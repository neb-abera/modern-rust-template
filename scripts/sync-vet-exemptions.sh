#!/usr/bin/env bash
#
# sync-vet-exemptions.sh: move cargo-vet exemptions to the versions a
# dependency update locked, and refuse when the update brings a new crate.
#
#   scripts/sync-vet-exemptions.sh              regenerate the exemptions in
#                                               supply-chain/config.toml
#   scripts/sync-vet-exemptions.sh --self-test  prove a version-only move
#                                               passes and a new crate fails
#
# A Dependabot cargo update moves exempted crates to versions nobody
# exempted, so scripts/check-vet.sh fails on every one (the template's #40,
# 2026-09-27: 19 crates). `cargo vet regenerate exemptions` fixes that, and
# it would also exempt a crate the project has never seen. So this script
# compares the exempted crate names before and after. A name that appears is
# a new crate: the script puts supply-chain/config.toml back as it was and
# exits 1, and the vet gate stays red until a human audits or exempts it.
# Versions moving, and names disappearing with a dropped dependency, pass.
# The Dependabot toolchain workflow runs this on Dependabot's cargo pull
# requests and commits the moved file.
#
# Exit 0: the exemptions name no crate they did not name before.
# Exit 1: a new crate, or regenerate failed. The file is unchanged.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=supply-chain/config.toml
# --locked reads supply-chain/imports.lock, as scripts/check-vet.sh does,
# so imported audits count exactly as they do in the gate.
REGENERATE="${REGENERATE:-cargo vet regenerate exemptions}"

# names <file>: the exempted crate names, one per line, sorted.
names() { sed -n 's/^\[\[exemptions\.\(.*\)\]\]$/\1/p' "$1" | sort -u; }

# sync <dir>: regenerate under <dir> and judge the result. A subshell, so
# --self-test can run it against a copy.
sync() (
  cd "$1"
  local before added
  before="$(mktemp)"
  cp "$CONFIG" "$before"
  # shellcheck disable=SC2064 # expand now: the path is fixed
  trap "rm -f '$before'" EXIT
  if ! $REGENERATE; then
    cp "$before" "$CONFIG"
    echo "error: '$REGENERATE' failed; $CONFIG is unchanged" >&2
    return 1
  fi
  added="$(comm -13 <(names "$before") <(names "$CONFIG"))"
  if [ -n "$added" ]; then
    cp "$before" "$CONFIG"
    echo "error: the update brings crates with no audit and no exemption:" >&2
    # shellcheck disable=SC2086 # one name per word
    printf '  %s\n' $added >&2
    echo "$CONFIG is unchanged. Audit them (cargo vet certify) or exempt them by hand." >&2
    return 1
  fi
  if cmp -s "$before" "$CONFIG"; then
    echo "exemptions already match the lockfile"
  else
    echo "exemptions moved to the locked versions; no new crate"
  fi
)

SELF_TEST_FAILED=0
# expect <exit> <text> <label> <stub>: run sync on a fresh copy with <stub>
# standing in for cargo vet, and check the exit code and the output.
expect() {
  local want="$1" needle="$2" label="$3" stub="$4" code=0 out
  rm -rf "$DIR/repo"
  mkdir -p "$DIR/repo/supply-chain"
  cp "$CONFIG" "$DIR/repo/$CONFIG"
  out="$(REGENERATE="$stub" sync "$DIR/repo" 2>&1)" || code=$?
  if [ "$code" -eq "$want" ] && grep -qF -- "$needle" <<< "$out"; then
    echo "self-test: ok: $label (exit $code)"
  else
    echo "self-test FAILED: $label: wanted exit $want and '$needle', got exit $code:" >&2
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    SELF_TEST_FAILED=1
  fi
}

self_test() {
  local first
  DIR="$(mktemp -d)"
  # shellcheck disable=SC2064 # expand now: the directory name is fixed
  trap "rm -rf '$DIR'" EXIT
  first="$(names "$CONFIG" | head -1)"
  if [ -z "$first" ]; then
    echo "self-test FAILED: $CONFIG has no exemption to plant against" >&2
    return 1
  fi

  # Stubs for `cargo vet regenerate exemptions`, run in the copy's root.
  cat > "$DIR/bump" << EOF
#!/usr/bin/env bash
perl -0pi -e 's/(\[\[exemptions\.\Q$first\E\]\]\nversion = ")[^"]*"/\${1}999.0.0"/' $CONFIG
EOF
  cat > "$DIR/add" << EOF
#!/usr/bin/env bash
printf '\n[[exemptions.planted-new-crate]]\nversion = "1.0.0"\ncriteria = "safe-to-run"\n' >> $CONFIG
EOF
  cat > "$DIR/both" << EOF
#!/usr/bin/env bash
"$DIR/bump" && "$DIR/add"
EOF
  cat > "$DIR/drop" << EOF
#!/usr/bin/env bash
perl -0pi -e 's/\[\[exemptions\.\Q$first\E\]\]\n(?:[^\n]*\n)*?\n//' $CONFIG
EOF
  cat > "$DIR/broken" << 'EOF'
#!/usr/bin/env bash
echo "junk" >> supply-chain/config.toml
exit 3
EOF
  chmod +x "$DIR/bump" "$DIR/add" "$DIR/both" "$DIR/drop" "$DIR/broken"

  expect 0 "no new crate" "a version-only bump of $first passes" "$DIR/bump"
  if grep -q '999.0.0' "$DIR/repo/$CONFIG"; then
    echo "self-test: ok: the moved version is kept in the file"
  else
    echo "self-test FAILED: the version-only bump was not kept" >&2
    SELF_TEST_FAILED=1
  fi
  expect 0 "already match" "an unchanged file passes" true
  expect 0 "no new crate" "a dropped crate passes" "$DIR/drop"
  expect 1 "planted-new-crate" "a planted new crate fails" "$DIR/add"
  if cmp -s "$CONFIG" "$DIR/repo/$CONFIG"; then
    echo "self-test: ok: the file is back as it was after the new crate"
  else
    echo "self-test FAILED: the new crate left $CONFIG changed" >&2
    SELF_TEST_FAILED=1
  fi
  expect 1 "planted-new-crate" "a new crate beside a version bump fails" "$DIR/both"
  if cmp -s "$CONFIG" "$DIR/repo/$CONFIG"; then
    echo "self-test: ok: none of the mixed change was kept"
  else
    echo "self-test FAILED: the mixed change left $CONFIG changed" >&2
    SELF_TEST_FAILED=1
  fi
  expect 1 "is unchanged" "a failed regenerate fails and restores the file" "$DIR/broken"
  if cmp -s "$CONFIG" "$DIR/repo/$CONFIG"; then
    echo "self-test: ok: the file is back as it was after the failed regenerate"
  else
    echo "self-test FAILED: the failed regenerate left $CONFIG changed" >&2
    SELF_TEST_FAILED=1
  fi
  if [ "$SELF_TEST_FAILED" -eq 0 ]; then
    echo "self-test: every planted case behaved; new crates never pass"
  fi
  return "$SELF_TEST_FAILED"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  sync .
fi
