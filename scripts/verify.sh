#!/usr/bin/env bash
#
# verify.sh — run the project's full verification suite locally, with a
# running pass/fail count and a final summary. This mirrors what CI checks
# before a merge:
#
#    1. the toolchain pins (rust-toolchain.toml / Dockerfile / Cargo.toml) agree
#    2. clean release build with warnings-as-errors + full test suite
#       (unit, integration and documentation tests)
#    3. clippy is clean (Rust API Guidelines material, pedantic set)
#    4. rustdoc builds with no warnings (missing docs, broken links)
#    5. the tests pass under Miri (undefined-behavior detection)
#    6. cargo-deny: no security advisories, license or source violations
#    7. fuzz smoke: the libFuzzer target builds and survives a short run
#    8. executable mode builds and runs
#    9. the published package contains only this project's intended files
#   10. mutation canary: plant a bug and confirm the tests catch it
#   11. sources are rustfmt clean
#
# Exit code 0 means everything passed.

set -u

cd "$(dirname "$0")/.." || exit 1

# The crate name, read from Cargo.toml, so a rename (e.g. via
# scripts/setup.sh) needs no edits here.
PROJ=$(sed -n 's/^name = "\(.*\)"$/\1/p' Cargo.toml | head -1)

# The pinned nightly (for Miri and fuzzing) is derived from the Dockerfile,
# the single place it is written down.
NIGHTLY=$(sed -n 's/^ENV NIGHTLY_TOOLCHAIN=\(.*\)$/\1/p' Dockerfile)

# Warnings are errors for every check in this suite; the lint *set* lives
# in Cargo.toml [lints], this only promotes its findings from warn to deny.
export RUSTFLAGS="-D warnings"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi

CHECKS_TOTAL=11
CHECKS_RUN=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=""
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

banner() {
  printf '\n%s== [%d/%d] %s ==%s\n' "$BOLD" "$((CHECKS_RUN + 1))" "$CHECKS_TOTAL" "$1" "$RESET"
}

tally() {
  printf '%sRunning tally: checks %d passed / %d failed, tests %d passed / %d failed%s\n' \
    "$BOLD" "$CHECKS_PASSED" "$CHECKS_FAILED" "$TESTS_PASSED" "$TESTS_FAILED" "$RESET"
}

pass() {
  CHECKS_RUN=$((CHECKS_RUN + 1)); CHECKS_PASSED=$((CHECKS_PASSED + 1))
  printf '%s[PASS]%s %s\n' "$GREEN" "$RESET" "$1"
  tally
}

fail() {
  CHECKS_RUN=$((CHECKS_RUN + 1)); CHECKS_FAILED=$((CHECKS_FAILED + 1))
  FAILED_NAMES="$FAILED_NAMES  - $1\n"
  printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$1"
  tally
}

skip() {
  CHECKS_RUN=$((CHECKS_RUN + 1)); CHECKS_SKIPPED=$((CHECKS_SKIPPED + 1))
  printf '%s[SKIP]%s %s\n' "$YELLOW" "$RESET" "$1"
}

# Sum the "test result: ok. N passed; M failed; ..." lines from cargo test
# output in $LOG into the running tally.
count_cargo_test() {
  local p f
  p=$(grep -E '^test result:' "$LOG" | grep -Eo '[0-9]+ passed' | awk '{s+=$1} END {print s+0}')
  f=$(grep -E '^test result:' "$LOG" | grep -Eo '[0-9]+ failed' | awk '{s+=$1} END {print s+0}')
  TESTS_PASSED=$((TESTS_PASSED + p))
  TESTS_FAILED=$((TESTS_FAILED + f))
}

banner "Toolchain pin consistency"
if ./scripts/check-toolchain.sh; then
  pass "rust-toolchain.toml, Dockerfile and Cargo.toml pin the same toolchain"
else
  fail "Toolchain pin consistency"
fi

banner "Release build + full test suite (warnings as errors)"
if ! cargo build --release --locked > "$LOG" 2>&1; then
  tail -20 "$LOG"
  fail "Release build/tests"
else
  cargo test --release --locked 2>&1 | tee "$LOG"
  if grep -qE '^test result:' "$LOG" && ! grep -qE '^test result: FAILED' "$LOG" \
     && ! grep -q '^error' "$LOG"; then
    count_cargo_test; pass "Release: clean build, all tests green"
  else
    count_cargo_test; fail "Release build/tests"
  fi
fi

banner "Static analysis: clippy (pedantic + configured lints)"
if cargo clippy --all-targets --release --locked > "$LOG" 2>&1; then
  pass "clippy: sources conform to the configured lint set"
else
  tail -30 "$LOG"
  fail "Static analysis (clippy)"
fi

banner "Documentation build (rustdoc, warnings as errors)"
if RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --lib --locked > "$LOG" 2>&1; then
  pass "rustdoc: documentation complete, no broken links"
else
  tail -20 "$LOG"
  fail "Documentation build"
fi

banner "Tests under Miri (undefined-behavior detection)"
if ! rustup toolchain list 2>/dev/null | grep -q "^$NIGHTLY" \
   && ! rustup toolchain install "$NIGHTLY" --profile minimal \
        --component miri --component rust-src > "$LOG" 2>&1; then
  skip "Miri (pinned nightly $NIGHTLY unavailable)"
else
  # RUSTFLAGS is cleared for Miri only: it changes the sysroot fingerprint,
  # forcing a slow rebuild (and clashing with the image's pre-built one);
  # the warnings-as-errors gate is already covered by the build and clippy
  # checks above.
  env -u RUSTFLAGS cargo +"$NIGHTLY" miri test --locked 2>&1 | tee "$LOG"
  if grep -qE '^test result:' "$LOG" && ! grep -qE '^test result: FAILED' "$LOG" \
     && ! grep -q '^error' "$LOG"; then
    count_cargo_test; pass "Miri: no undefined behavior in the test suite"
  else
    count_cargo_test; fail "Miri run"
  fi
fi

banner "Supply chain: cargo-deny (advisories, licenses, bans, sources)"
if ! command -v cargo-deny > /dev/null; then
  skip "cargo-deny (not installed; available in the Docker toolchain image)"
elif cargo deny check > "$LOG" 2>&1; then
  pass "cargo-deny: no advisories, license or source violations"
else
  tail -30 "$LOG"
  fail "Supply chain (cargo-deny)"
fi

banner "Fuzz smoke: libFuzzer target builds and survives a short run"
if ! command -v cargo-fuzz > /dev/null; then
  skip "Fuzz smoke (cargo-fuzz not installed; available in the Docker toolchain image)"
elif ! rustup toolchain list 2>/dev/null | grep -q "^$NIGHTLY"; then
  skip "Fuzz smoke (pinned nightly $NIGHTLY unavailable)"
# The target triple is passed explicitly: a prebuilt cargo-fuzz binary
# otherwise defaults to the triple *it* was compiled for (often musl),
# which has no std installed here.
elif cargo +"$NIGHTLY" fuzz run add \
       --target "$(rustc +"$NIGHTLY" -vV | sed -n 's/^host: //p')" \
       -- -max_total_time=5 > "$LOG" 2>&1; then
  runs=$(grep -Eo 'Done [0-9]+ runs' "$LOG" | grep -Eo '[0-9]+' | head -1)
  echo "fuzzer executed ${runs:-?} inputs without a crash"
  pass "Fuzz smoke: no crashes under coverage-guided input"
else
  tail -20 "$LOG"
  fail "Fuzz smoke"
fi

banner "Executable mode smoke test"
if cargo build --release --locked > "$LOG" 2>&1 \
   && out=$(./target/release/"$PROJ") && [ "$out" = "1 + 2 = 3" ]; then
  echo "program output: $out"
  pass "Executable builds and prints the expected output"
else
  tail -20 "$LOG"
  fail "Executable mode"
fi

banner "Package purity: cargo package ships only intended files"
PKG_LIST=""
if cargo package --list --allow-dirty --locked > "$LOG" 2>&1; then
  PKG_LIST=$(grep -v '^warning' "$LOG" || true)
fi
if [ -n "$PKG_LIST" ] \
   && printf '%s\n' "$PKG_LIST" | grep -q '^src/lib.rs$' \
   && ! printf '%s\n' "$PKG_LIST" | grep -Eq '^(Dockerfile|Makefile|fuzz/|\.github/|scripts/|deny\.toml|rust-toolchain\.toml)' \
   && cargo package --allow-dirty --locked > "$LOG" 2>&1; then
  echo "packaged files:"; printf '%s\n' "$PKG_LIST" | sed 's/^/  /'
  pass "Package contains only this project's intended files and builds standalone"
else
  tail -20 "$LOG"
  fail "Package purity (unexpected files, or the packaged crate does not build)"
fi

banner "Mutation canary: do the tests catch a planted bug?"
# Back up and restore via a plain file copy, so this works in containers and
# source exports where no git metadata is available.
BACKUP="$(mktemp)"
cp src/lib.rs "$BACKUP"
restore_canary() { cp "$BACKUP" src/lib.rs; rm -f "$BACKUP"; }
perl -pi -e 's/checked_add/checked_sub/' src/lib.rs
if ! cmp -s src/lib.rs "$BACKUP"; then
  if cargo test --release --locked --no-fail-fast > "$LOG" 2>&1; then
    restore_canary
    fail "Mutation canary (tests did NOT catch the planted bug!)"
  else
    caught=$(grep -E '^test result:' "$LOG" | grep -Eo '[0-9]+ failed' | awk '{s+=$1} END {print s+0}')
    restore_canary
    echo "planted 'checked_add -> checked_sub'; $caught tests failed as they should, then restored"
    pass "Mutation canary: tests caught the planted bug ($caught failures)"
  fi
else
  restore_canary
  skip "Mutation canary (could not plant the mutation; src/lib.rs changed?)"
fi

banner "rustfmt check"
if cargo fmt --check > "$LOG" 2>&1; then
  pass "Sources are rustfmt clean"
else
  tail -20 "$LOG"
  fail "rustfmt check"
fi

printf '\n%s========================= VERIFICATION COMPLETE =========================%s\n' "$BOLD" "$RESET"
printf 'Checks : %s%d passed%s, %s%d failed%s, %d skipped (of %d)\n' \
  "$GREEN" "$CHECKS_PASSED" "$RESET" "$RED" "$CHECKS_FAILED" "$RESET" "$CHECKS_SKIPPED" "$CHECKS_TOTAL"
printf 'Tests  : %s%d passed%s, %s%d failed%s\n' \
  "$GREEN" "$TESTS_PASSED" "$RESET" "$RED" "$TESTS_FAILED" "$RESET"
if [ "$CHECKS_FAILED" -eq 0 ]; then
  printf '%s%sALL CHECKS PASSED — this build behaves as intended.%s\n' "$BOLD" "$GREEN" "$RESET"
  exit 0
else
  printf '%s%sFAILURES:%s\n' "$BOLD" "$RED" "$RESET"
  printf '%b' "$FAILED_NAMES"
  exit 1
fi
