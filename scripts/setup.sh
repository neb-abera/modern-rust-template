#!/usr/bin/env bash
#
# setup.sh — one-command setup for a repository generated from this template:
#
#   ./scripts/setup.sh              set up the repository this clone points at
#   ./scripts/setup.sh --self-test  run the whole setup against a copy under a
#                                   fake name and a stubbed GitHub CLI, then
#                                   build and test the result
#
# What it does:
#   1. renames the crate after your repository: the package name in
#      Cargo.toml (and both lockfiles), the fuzz crate, every
#      `use project::` path in sources, tests, benches and fuzz targets,
#      the README/SECURITY.md badge and links, and NOTICE, then pushes the
#      change
#   2. enables the GitHub settings templates cannot carry over: secret
#      scanning, push protection, private vulnerability reporting,
#      Dependabot alerts and security updates, deleting merged branches,
#      the Update branch button and auto-merge
#   3. enables branch protection on the default branch requiring every
#      check CI reports on a pull request, plus required commit signatures
#      when this machine is configured to sign
#
# Requirements: git, and the GitHub CLI (`gh`, https://cli.github.com)
# authenticated as an admin of the repository. Safe to re-run: every step is
# idempotent.
#
# The self-test copies the tracked tree, names the copy
# example-owner/Fake-Widget_2 and runs this script in it with `gh` replaced
# by a stub that records every call. It fails if any template name survives
# the rename (NOTICE included), if the settings calls lose a field, or if the
# renamed project does not build and pass its tests. It then plants a
# leftover name and requires the scan to report it, so the scan is known to
# be able to fail.

set -euo pipefail

cd "$(dirname "$0")/.."

TEMPLATE_CRATE="project"
TEMPLATE_OWNER_REPO="neb-abera/modern-rust-template"
TEMPLATE_TITLE="Modern Rust Template"
TEMPLATE_YEAR="2026"
TEMPLATE_HOLDER="Nebyou Abera"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi
step() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$1"; }
done_() { printf '%s  done:%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s  note:%s %s\n' "$YELLOW" "$RESET" "$1"; }

# Every template name the rename must remove, as one extended regex: the
# repository slug, the README title, the crate name in each place Cargo
# writes it, and the module path in code.
LEFTOVER_PATTERN="${TEMPLATE_OWNER_REPO#*/}|$TEMPLATE_TITLE|^name = \"$TEMPLATE_CRATE\"\$|\"$TEMPLATE_CRATE-fuzz\"|^ \"$TEMPLATE_CRATE\",?\$|^\[dependencies\.$TEMPLATE_CRATE\]\$|\b$TEMPLATE_CRATE::"

# leftovers <dir>: print every template name still in the tree at <dir>,
# as path:line:text. Two places are exempt: this script, which has to name
# what it replaces, and NOTICE below its first blank line, where the rename
# records the template it came from (Apache-2.0 section 4(d) keeps that
# attribution with every derived work). NOTICE's own header is scanned.
leftovers() (
  cd "$1"
  grep -rnE --exclude-dir=.git --exclude-dir=target \
    --exclude=setup.sh --exclude=NOTICE "$LEFTOVER_PATTERN" . || true
  sed '/^$/q' NOTICE | grep -nE "$LEFTOVER_PATTERN" | sed 's#^#./NOTICE:#' || true
)

if [ "${1:-}" = "--self-test" ]; then
  # A repository already renamed from the template has no template names
  # left to test the rename against.
  if ! grep -qx "name = \"$TEMPLATE_CRATE\"" Cargo.toml; then
    echo "self-test skipped: this repository has already been renamed from the template"
    exit 0
  fi
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  work="$tmp/Fake-Widget_2"
  mkdir -p "$work" "$tmp/bin"
  git ls-files -z --cached --others --exclude-standard \
    | tar --null -T - -cf - | tar -xf - -C "$work"

  # A GitHub CLI that records each call and its input and answers the two
  # questions setup asks: the default branch and the owner's display name.
  cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_LOG"
case " $* " in *" --input - "*) cat >> "$GH_LOG" ;; esac
case "$*" in
  *"--jq .default_branch"*) echo main ;;
  "api users/"*) echo "Example Owner" ;;
esac
STUB
  chmod +x "$tmp/bin/gh"

  # The copy is its own repository. Its origin is the fake GitHub URL setup
  # parses the name from. Pushes go to a local bare repository instead.
  git init -q --bare -b main "$tmp/remote.git"
  (
    cd "$work"
    git init -q -b main
    git config user.name "setup self-test"
    git config user.email "setup-self-test@example.invalid"
    git config commit.gpgsign false
    git remote add origin https://github.com/example-owner/Fake-Widget_2.git
    git config remote.origin.pushurl "$tmp/remote.git"
    git add -A
    git commit -q --no-verify -m "template as generated"
  )

  failed=0
  fail() { echo "self-test FAILED: $1" >&2; failed=1; }

  echo "== setup.sh in a copy named example-owner/Fake-Widget_2 =="
  if ! (cd "$work" && GH_LOG="$tmp/gh.log" PATH="$tmp/bin:$PATH" ./scripts/setup.sh); then
    fail "setup.sh exited non-zero"
  fi

  found=$(leftovers "$work")
  if [ -n "$found" ]; then
    fail "the rename left template names behind:"
    printf '%s\n' "$found" | sed 's/^/  /' >&2
  fi
  [ "$(head -1 "$work/NOTICE")" = "Fake-Widget_2" ] \
    || fail "NOTICE does not name the new project on its first line"
  git -C "$tmp/remote.git" log -1 --format=%s main 2> /dev/null | grep -q '^Rename crate' \
    || fail "the rename commit was not pushed to the default branch"

  # The settings a strict branch policy depends on. Without the Update
  # branch button a pull request that falls behind can never merge, and
  # auto-merge stays armed on it forever.
  for field in delete_branch_on_merge=true allow_update_branch=true allow_auto_merge=true; do
    grep -q -- "$field" "$tmp/gh.log" || fail "no gh api call sets $field"
  done
  grep -q '"strict": true' "$tmp/gh.log" || fail "branch protection is not strict"
  want=$(./scripts/check-required-contexts.sh --json)
  grep -qF "\"contexts\": $want" "$tmp/gh.log" \
    || fail "branch protection did not require exactly .github/required-checks"

  # The scan must be able to fail. Plant a leftover in a source file, then
  # put the template's NOTICE back, and require each to be reported.
  cp "$work/src/main.rs" "$tmp/main.rs"
  echo "// ${TEMPLATE_OWNER_REPO#*/}" >> "$work/src/main.rs"
  leftovers "$work" | grep -q '^./src/main.rs:' \
    || fail "a planted leftover in src/main.rs was not reported"
  cp "$tmp/main.rs" "$work/src/main.rs"
  cp "$work/NOTICE" "$tmp/NOTICE"
  git show HEAD:NOTICE > "$work/NOTICE" 2> /dev/null || cp NOTICE "$work/NOTICE"
  leftovers "$work" | grep -q '^./NOTICE:' \
    || fail "the template's own NOTICE was not reported"
  cp "$tmp/NOTICE" "$work/NOTICE"
  [ -z "$(leftovers "$work")" ] || fail "restoring the planted files did not clear the scan"

  # The renamed project builds and its tests run and pass. The count of
  # test result lines is read, as the canaries do: a build that produced no
  # tests would otherwise pass.
  echo "== build and test the renamed project =="
  if (cd "$work" && cargo build --locked --all-targets \
        && cargo metadata --locked --format-version 1 --manifest-path fuzz/Cargo.toml > /dev/null \
        && cargo test --locked 2>&1 | tee "$tmp/test.log"); then
    ran=$(grep -cE '^test result:' "$tmp/test.log" || true)
    bad=$(grep -E '^test result:' "$tmp/test.log" | grep -Eo '[0-9]+ failed' | awk '{s+=$1} END {print s+0}')
    [ "$ran" -gt 0 ] || fail "the renamed project ran no tests"
    [ "$bad" -eq 0 ] || fail "$bad tests failed in the renamed project"
  else
    fail "the renamed project does not build or its tests fail"
  fi

  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
  echo "self-test passed: the rename left no template name, the settings calls are complete, the scan caught two planted leftovers, and the renamed project builds and passes its tests"
  exit 0
fi

#
# Detect the repository
#

origin=$(git remote get-url origin 2> /dev/null || true)
if [ -z "$origin" ]; then
  echo "error: no git remote named 'origin'. Clone your generated repository first." >&2
  exit 1
fi
owner_repo=$(printf '%s' "$origin" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
owner=${owner_repo%%/*}
repo=${owner_repo##*/}

# Crate name: the repository name lowercased and sanitized to what
# crates.io accepts; the module path used in code swaps dashes for
# underscores, exactly as cargo does.
name=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]/-/g; s/^([0-9])/n\1/')
name_snake=$(printf '%s' "$name" | tr '-' '_')

if ! command -v gh > /dev/null; then
  echo "error: the GitHub CLI (gh) is required — https://cli.github.com — and must be authenticated (gh auth login)." >&2
  exit 1
fi
default_branch=$(gh api "repos/$owner_repo" --jq .default_branch)

step "Setting up $owner_repo (crate name: $name, default branch: $default_branch)"

#
# 1. Rename the crate after the repository
#

if [ "$owner_repo" = "$TEMPLATE_OWNER_REPO" ]; then
  warn "this is the template itself; skipping the rename"
else
  step "Renaming crate \"$TEMPLATE_CRATE\" to \"$name\""

  NEW=$name perl -pi -e 's/^name = "project"$/name = "$ENV{NEW}"/' Cargo.toml Cargo.lock fuzz/Cargo.lock
  NEW=$name perl -pi -e 's/"project-fuzz"/"$ENV{NEW}-fuzz"/' fuzz/Cargo.toml fuzz/Cargo.lock
  # the fuzz lockfile also lists the parent crate as a dependency entry
  NEW=$name perl -pi -e 's/^ "project"(,?)$/ "$ENV{NEW}"$1/' fuzz/Cargo.lock
  NEW=$name perl -pi -e 's/^\[dependencies\.project\]$/[dependencies.$ENV{NEW}]/' fuzz/Cargo.toml
  NEW=$name_snake perl -pi -e 's/\bproject::/$ENV{NEW}::/g' \
    src/*.rs tests/*.rs benches/*.rs fuzz/fuzz_targets/*.rs
  # The two comment lines that explain the placeholder name go with it.
  perl -ni -e 'print unless /^# The package is named "project" as a placeholder/ || /^# it \(and every `use project::` path\) after your repository/' Cargo.toml

  NEW_REPO="$owner_repo" perl -pi -e 's#\Qneb-abera/modern-rust-template\E#$ENV{NEW_REPO}#g' \
    README.md Cargo.toml SECURITY.md .github/ISSUE_TEMPLATE/config.yml
  NEW=$repo perl -pi -e 's/\QModern Rust Template\E/$ENV{NEW}/' README.md

  # NOTICE names this project and its copyright holder, and keeps the
  # template's attribution below, as Apache-2.0 section 4(d) requires.
  # Rewritten only while it is still the template's, so a re-run in a later
  # year leaves the date alone.
  if [ "$(head -1 NOTICE)" = "${TEMPLATE_OWNER_REPO#*/}" ]; then
    holder=$(gh api "users/$owner" --jq '.name // .login' 2> /dev/null || true)
    cat > NOTICE <<NOTICE
$repo
Copyright $(date +%Y) ${holder:-$owner}

This project was generated from ${TEMPLATE_OWNER_REPO#*/}
(https://github.com/$TEMPLATE_OWNER_REPO),
Copyright $TEMPLATE_YEAR $TEMPLATE_HOLDER, under the Apache License 2.0.
NOTICE
  fi

  if git diff --quiet && git diff --cached --quiet; then
    done_ "already renamed"
  else
    git add -u
    git commit -q -m "Rename crate after repository ($name) via scripts/setup.sh"
    if git push -q origin "HEAD:$default_branch" 2> /dev/null; then
      done_ "renamed and pushed to $default_branch"
    else
      warn "push to $default_branch was rejected (branch protection already on?); open a PR with the local commit"
    fi
  fi
fi

#
# 2. Repo security settings
#

step "Enabling security settings"
gh api -X PATCH "repos/$owner_repo" \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  -f 'security_and_analysis[dependabot_security_updates][status]=enabled' > /dev/null
done_ "secret scanning, push protection, Dependabot security updates"
gh api -X PUT "repos/$owner_repo/private-vulnerability-reporting" > /dev/null
done_ "private vulnerability reporting"
gh api -X PUT "repos/$owner_repo/vulnerability-alerts" > /dev/null
done_ "Dependabot alerts"
# Merged PR branches delete themselves; without this every merged PR leaves
# a dead branch behind, and the branch list turns to noise within a few
# dozen PRs. Branch protection below is strict (a PR must be up to date
# with the default branch), so the Update branch button has to exist or a
# Dependabot PR that falls behind can never become mergeable. Auto-merge is
# what dependabot-automerge.yml arms.
gh api -X PATCH "repos/$owner_repo" \
  -F delete_branch_on_merge=true \
  -F allow_update_branch=true \
  -F allow_auto_merge=true > /dev/null
done_ "merged PR branches are deleted, the Update branch button and auto-merge are on"

#
# 3. Branch protection requiring every check CI reports on a pull request
#
# The contexts are the `check` lines of .github/required-checks.
# scripts/check-required-contexts.sh (a verify.sh gate) fails when that list
# and the pull-request jobs disagree, and runs here first so a drifted list
# never reaches GitHub.

step "Enabling branch protection on $default_branch"
./scripts/check-required-contexts.sh > /dev/null
contexts=$(./scripts/check-required-contexts.sh --json)
gh api -X PUT "repos/$owner_repo/branches/$default_branch/protection" --input - > /dev/null <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": $contexts
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
done_ "every check in .github/required-checks required, strict, enforced for admins"

# Required commit signatures are a separate sub-resource of branch
# protection with their own endpoint, not a field of the PUT above, so they
# are enabled here explicitly (idempotent: POSTing to an already-enabled
# branch succeeds). Guarded like the webapp template: a branch that demands
# signatures from a machine that cannot produce them would lock its own
# adopter out on day one, so this only turns on when this clone is already
# configured to sign its commits.
if [ "$(git config --get commit.gpgsign || true)" = "true" ]; then
  gh api -X POST "repos/$owner_repo/branches/$default_branch/protection/required_signatures" > /dev/null
  done_ "$default_branch accepts only Verified (signed) commits"
else
  warn "commit signing is not configured (commit.gpgsign is not true); $default_branch does NOT require signatures"
  warn "configure signing, then run: gh api -X POST repos/$owner_repo/branches/$default_branch/protection/required_signatures"
fi

printf '\n%sSetup complete.%s Every future change now goes through a PR gated on
the CI checks. Verify the renamed project with: make verify-docker

Optional: add a CODECOV_TOKEN repository secret to feed the Codecov
dashboard. The coverage gate itself runs in CI and needs no token.\n' "$BOLD" "$RESET"
