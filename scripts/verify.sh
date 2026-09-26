#!/usr/bin/env bash
#
# verify.sh — run the project's full verification suite locally, with a
# running pass/fail count and a final summary. This mirrors what CI checks
# before a merge:
#
#   - the toolchain pins (rust-toolchain.toml / Dockerfile / Cargo.toml) agree,
#     and scripts/sync-toolchain.sh proves it moves them after a base image bump
#   - .github/required-checks matches the pull-request job names (the
#     checker first proves it catches a renamed check and an unlisted job)
#   - template parity: every file .template-parity lists is byte-identical
#     to modern-webapp-template's default branch (the checker first proves
#     a drifted and a missing file are caught)
#   - no workflow cancels a run on the default branch
#   - no commit on this branch credits an AI (the checker proves it can fail)
#   - prose: every tracked Markdown file passes the writing rules in
#     .vale/styles/Abera (the checker first proves every rule fires on a
#     fixture and that clean prose passes; skipped if Docker is missing,
#     as inside the toolchain container, where CI's prose job covers it)
#   - clean release build with warnings-as-errors + full test suite
#     (unit, integration and documentation tests)
#   - line coverage: the same tests under cargo llvm-cov cover the crate
#     at or above the floor in coverage-floor.txt (skipped if
#     cargo-llvm-cov is missing)
#   - clippy is clean (Rust API Guidelines material, pedantic set)
#   - rustdoc builds with no warnings (missing docs, broken links)
#   - the tests pass under Miri (undefined-behavior detection)
#   - Kani proves the #[kani::proof] harnesses in src/lib.rs for every
#     input, not the sampled inputs the tests cover
#   - proof canary: plant a bug the unit tests cannot see and confirm the
#     tests pass while Kani fails, so the proofs are load-bearing rather
#     than vacuous
#   - cargo-deny: no security advisories, license or source violations
#   - cargo-vet: every dependency is audited by someone, or explicitly
#     exempted; and the gate proves it can fail
#   - fuzz smoke: the libFuzzer target builds and survives a short run
#   - executable mode builds and runs
#   - benchmark smoke: every Criterion benchmark builds and runs once, with
#     no timing read from it
#   - size budget: the stripped release binary fits the committed byte
#     budget (size-budget.txt)
#   - size-budget canary: the size gate fails one byte over budget, and
#     on a missing artifact or budget
#   - the published package contains only this project's intended files
#   - mutation canary: plant a bug and confirm the tests catch it
#   - sources are rustfmt clean
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

# The pinned Kani version, derived from the same place for the same reason.
KANI_VERSION=$(sed -n 's/^ENV KANI_VERSION=\(.*\)$/\1/p' Dockerfile)

# The line-coverage floor, in percent, read from coverage-floor.txt: the one
# place it is written down. CI's coverage job reads the same file, so the
# two gates cannot drift apart. Blank lines and `#` comments are ignored.
COVERAGE_FLOOR=$(grep -Ev '^[[:space:]]*(#|$)' coverage-floor.txt 2> /dev/null | tr -d '[:space:]')

# Warnings are errors for every check in this suite; the lint *set* lives
# in Cargo.toml [lints], this only promotes its findings from warn to deny.
export RUSTFLAGS="-D warnings"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi

# One check per banner line below, counted rather than typed, so adding a
# check cannot leave the total stale.
CHECKS_TOTAL=$(grep -c '^banner "' scripts/verify.sh)
CHECKS_RUN=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0
TESTS_PASSED=0
TESTS_FAILED=0
# Line-coverage percentage, e.g. "97.5%", set by the coverage check; the
# summary lines are omitted when it is empty (the check skipped or was not
# selected).
COVERAGE_PCT=""
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
if ./scripts/check-toolchain.sh && ./scripts/sync-toolchain.sh --self-test; then
  pass "rust-toolchain.toml, Dockerfile and Cargo.toml pin the same toolchain"
else
  fail "Toolchain pin consistency"
fi

banner "Required checks: .github/required-checks vs the pull-request jobs"
if ./scripts/check-required-contexts.sh --self-test > "$LOG" 2>&1 \
   && ./scripts/check-required-contexts.sh >> "$LOG" 2>&1; then
  grep -E '^self-test:|^required checks' "$LOG" || true
  pass ".github/required-checks matches the pull-request job names"
else
  tail -30 "$LOG"
  fail "Required checks (the list and the jobs disagree, or a broken self-test)"
fi

banner "Template parity: files shared with modern-webapp-template are byte-identical to it"
if ./scripts/check-template-parity.sh --self-test > "$LOG" 2>&1 \
   && ./scripts/check-template-parity.sh >> "$LOG" 2>&1; then
  grep -E '^self-test:' "$LOG" || true
  pass "Shared files match the template, and the checker caught a planted drift"
else
  tail -30 "$LOG"
  fail "Template parity (a shared file drifted from the template, or a broken self-test)"
fi

banner "Concurrency: no workflow cancels a run on the default branch"
if ./scripts/check-concurrency.sh --self-test > "$LOG" 2>&1 \
   && ./scripts/check-concurrency.sh >> "$LOG" 2>&1; then
  cat "$LOG"
  pass "No workflow cancels a push, schedule or merge-queue run"
else
  cat "$LOG"
  fail "Concurrency (a workflow cancels runs outside a pull request, or a broken self-test)"
fi

banner "Attribution: no commit on this branch credits an AI"
# The commit-msg hook and the Claude PreToolUse gate both run on the machine
# making the commit, so neither sees one made anywhere they are not installed.
# This is the one that runs where the merge happens. The self-test first, as
# everywhere else: it plants a trailer and a generated-with line in throwaway
# repositories and requires both refused.
if ./scripts/check-attribution.sh --self-test > "$LOG" 2>&1 \
   && ./scripts/check-attribution.sh >> "$LOG" 2>&1; then
  grep -E '^check-attribution|^attribution:' "$LOG" || true
  pass "No commit on this branch credits an AI"
else
  tail -30 "$LOG"
  fail "Attribution (a commit carries an AI credit, or a broken self-test)"
fi

banner "Prose: every tracked Markdown file passes the writing rules"
# The rules run in the Vale image the Dockerfile pins (the `vale` stage), so
# this check needs Docker. Inside the toolchain container (make
# verify-docker) there is none and the check skips; CI's prose job runs it
# on the runner. The self-test runs first, every time: one fixture carries
# one violation per rule and every rule must fire on it, another is clean
# and must pass, so a rule that has stopped matching is caught here rather
# than trusted.
if ! command -v docker > /dev/null; then
  skip "Prose (docker not installed; CI's prose job runs this check on the runner)"
elif ./scripts/check-prose.sh --self-test > "$LOG" 2>&1 \
   && ./scripts/check-prose.sh >> "$LOG" 2>&1; then
  grep -E '^self-test' "$LOG" || true
  pass "Prose passes .vale/styles/Abera"
else
  tail -40 "$LOG"
  fail "Prose (a rule violation in a Markdown file, or a broken self-test)"
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

banner "Line coverage: test suite under cargo llvm-cov vs coverage-floor.txt"
if [ -z "$COVERAGE_FLOOR" ]; then
  fail "Line coverage (coverage-floor.txt is missing or holds no number)"
elif ! command -v cargo-llvm-cov > /dev/null; then
  skip "Line coverage (cargo-llvm-cov not installed; available in the Docker toolchain image)"
else
  # The same invocation as CI's coverage job, lcov report included; the
  # percentage is read back from that report (LH/LF sums) as CI's summary
  # does. A stale report is removed first so a failed build cannot be
  # mistaken for a coverage shortfall.
  rm -f lcov.info
  cargo llvm-cov --locked --fail-under-lines "$COVERAGE_FLOOR" --lcov --output-path lcov.info > "$LOG" 2>&1
  llvm_cov_status=$?
  count_cargo_test
  if [ -f lcov.info ]; then
    COVERAGE_PCT=$(awk -F: '/^LF:/ {lf+=$2} /^LH:/ {lh+=$2} END {if (lf > 0) printf "%.2f%%", 100*lh/lf}' lcov.info)
  fi
  if [ "$llvm_cov_status" -eq 0 ]; then
    pass "Line coverage: ${COVERAGE_PCT:-?} of lines, at or above the ${COVERAGE_FLOOR}% floor"
  elif [ -n "$COVERAGE_PCT" ]; then
    tail -20 "$LOG"
    fail "Line coverage (${COVERAGE_PCT} of lines, under the ${COVERAGE_FLOOR}% floor)"
  else
    tail -20 "$LOG"
    fail "Line coverage (coverage build/tests failed)"
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

banner "Proofs under Kani (bit-precise model checking, all inputs)"
# RUSTFLAGS is cleared for Kani for the same reason as for Miri: Kani is a
# rustc driver with its own sysroot, and the flag forces a rebuild of it.
# Warnings-as-errors is already gated by the build and clippy checks.
if ! command -v cargo-kani > /dev/null; then
  skip "Kani (not installed; available in the Docker toolchain image)"
# A proof is only as good as the solver that checked it, so the version is
# part of the result. An unpinned Kani is a different prover than the one
# this repository's proofs were verified against.
elif installed_kani=$(cargo kani --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1) \
     && [ "$installed_kani" != "$KANI_VERSION" ]; then
  echo "installed Kani $installed_kani, Dockerfile pins $KANI_VERSION"
  echo "install the pin with: cargo install --locked kani-verifier@$KANI_VERSION && cargo kani setup"
  fail "Kani version drift (proofs must be checked by the pinned prover)"
elif env -u RUSTFLAGS cargo kani > "$LOG" 2>&1; then
  harnesses=$(grep -Eo '[0-9]+ successfully verified harnesses' "$LOG" | grep -Eo '^[0-9]+' | head -1)
  checks=$(grep -Eo 'Complete - .*' "$LOG" | head -1)
  echo "${checks:-proof summary unavailable}"
  pass "Kani $KANI_VERSION: ${harnesses:-?} proof harnesses verified for every input"
else
  grep -E 'Status: FAILURE|Failed Checks|VERIFICATION' "$LOG" | head -20 || tail -20 "$LOG"
  fail "Kani proofs"
fi

banner "Proof canary: are the proofs load-bearing, or vacuous?"
# A proof whose assumptions are too strong proves nothing and still reports
# success, which is the standard way verification goes wrong. So plant a bug
# that the unit tests CANNOT see (a wrong answer at one arbitrary input they
# never sample) and require two things: the tests still pass, and Kani fails.
# The first half is the demonstration that proof buys something tests do not.
# Backed up and restored by file copy, as the mutation canary is, so this
# works in containers and source exports with no git metadata.
if ! command -v cargo-kani > /dev/null; then
  skip "Proof canary (Kani not installed)"
else
  PROOF_BACKUP="$(mktemp)"
  cp src/lib.rs "$PROOF_BACKUP"
  restore_proof_canary() { cp "$PROOF_BACKUP" src/lib.rs; rm -f "$PROOF_BACKUP"; }
  perl -pi -e 's/^    lhs\.checked_add\(rhs\)$/    if lhs == 0x5EED_BEEF { None } else { lhs.checked_add(rhs) }/' src/lib.rs
  cargo test --release --locked --no-fail-fast > "$LOG" 2>&1
  # A canary must tell three outcomes apart, and the exit code alone cannot:
  # a compile error and a failing test both exit non-zero. Counting the
  # reported test results distinguishes them, so a mutation that does not
  # build can never be mistaken for one the tests caught.
  proof_ran=$(grep -cE '^test result:' "$LOG" || true)
  proof_caught=$(grep -E '^test result:' "$LOG" | grep -Eo '[0-9]+ failed' | awk '{s+=$1} END {print s+0}')
  if cmp -s src/lib.rs "$PROOF_BACKUP"; then
    restore_proof_canary
    skip "Proof canary (could not plant the bug; src/lib.rs changed?)"
  elif [ "$proof_ran" -eq 0 ]; then
    restore_proof_canary
    tail -20 "$LOG"
    fail "Proof canary (the planted bug did not compile, so nothing was measured)"
  elif [ "$proof_caught" -ne 0 ]; then
    restore_proof_canary
    fail "Proof canary ($proof_caught unit tests caught the planted bug, so it does not demonstrate what proof adds; pick an input the tests do not sample)"
  elif env -u RUSTFLAGS cargo kani > "$LOG" 2>&1; then
    restore_proof_canary
    fail "Proof canary (Kani did NOT fail on the planted bug! The proofs are vacuous or not reached.)"
  else
    failed=$(grep -c 'Status: FAILURE' "$LOG" || true)
    restore_proof_canary
    echo "planted a wrong answer at lhs == 0x5EED_BEEF: the unit tests passed, Kani reported $failed failing checks, then restored"
    pass "Proof canary: tests missed the bug, Kani caught it"
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

banner "Supply chain: cargo-vet (has anyone read this dependency?)"
# cargo-deny above judges advisories, licences and sources. This judges
# whether the code was read. The self-test runs first: a config that accepted
# everything would report success forever, so the gate proves it can fail
# before its result is believed.
if ! command -v cargo-vet > /dev/null; then
  skip "cargo-vet (not installed; available in the Docker toolchain image)"
elif ./scripts/check-vet.sh --self-test > "$LOG" 2>&1 \
     && ./scripts/check-vet.sh >> "$LOG" 2>&1; then
  grep -E '^self-test|Vetting Succeeded' "$LOG" || true
  pass "cargo-vet: every dependency accounted for, and the gate caught a removed exemption"
else
  tail -25 "$LOG"
  fail "cargo-vet (an unaudited dependency, or a broken self-test)"
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

banner "Benchmark smoke: every Criterion benchmark builds and runs once"
# Criterion's test mode (what `cargo test --benches` runs) executes each
# benchmark once and prints `Success`. A build-and-run gate, never a timing
# gate: nothing here reads a number. Zero `Success` lines means no
# benchmark ran, which fails rather than passing empty.
if cargo test --benches --release --locked > "$LOG" 2>&1; then
  benches=$(grep -c '^Success' "$LOG" || true)
  if [ "$benches" -gt 0 ]; then
    pass "Benchmark smoke: $benches benchmarks ran once"
  else
    tail -20 "$LOG"
    fail "Benchmark smoke (no benchmark ran)"
  fi
else
  tail -20 "$LOG"
  fail "Benchmark smoke (a benchmark does not build or panics)"
fi

# The release artifact the size checks measure: the binary cargo names after
# the crate, so a rename (e.g. via scripts/setup.sh) needs no edits here.
ARTIFACT="target/release/$PROJ"

banner "Size budget: stripped release binary vs size-budget.txt"
if [ "$(uname -s)" != "Linux" ]; then
  skip "Size budget (the budget is set for the Linux toolchain container; use make verify-docker)"
elif ./scripts/check-size-budget.sh "$ARTIFACT" size-budget.txt > "$LOG" 2>&1; then
  cat "$LOG"
  pass "Size budget: the stripped release binary fits the committed budget"
else
  cat "$LOG"
  fail "Size budget (artifact over budget, or artifact/budget missing)"
fi

banner "Size-budget canary: does the size gate fail when it should?"
if ./scripts/check-size-budget.sh --self-test "$ARTIFACT" > "$LOG" 2>&1; then
  cat "$LOG"
  pass "Size-budget canary: one byte over, a missing artifact and a missing budget all fail"
else
  cat "$LOG"
  fail "Size-budget canary (the size gate did NOT fail when it should, or there was no artifact to test it on)"
fi

banner "Package purity: cargo package ships only intended files"
PKG_LIST=""
if cargo package --list --allow-dirty --locked > "$LOG" 2>&1; then
  PKG_LIST=$(grep -v '^warning' "$LOG" || true)
fi
if [ -n "$PKG_LIST" ] \
   && printf '%s\n' "$PKG_LIST" | grep -q '^src/lib.rs$' \
   && ! printf '%s\n' "$PKG_LIST" | grep -Eq '^(Dockerfile|Makefile|fuzz/|proof/|supply-chain/|\.github/|scripts/|deny\.toml|rust-toolchain\.toml)' \
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
  cargo test --release --locked --no-fail-fast > "$LOG" 2>&1
  # As in the proof canary: the exit code cannot tell a compile error from a
  # failing test, and a mutation that does not build measures nothing. Count
  # the reported results instead. Before this, a broken build passed this
  # check with "0 tests failed as they should".
  ran=$(grep -cE '^test result:' "$LOG" || true)
  caught=$(grep -E '^test result:' "$LOG" | grep -Eo '[0-9]+ failed' | awk '{s+=$1} END {print s+0}')
  if [ "$ran" -eq 0 ]; then
    restore_canary
    tail -20 "$LOG"
    fail "Mutation canary (the planted bug did not compile, so the tests were never run)"
  elif [ "$caught" -eq 0 ]; then
    restore_canary
    fail "Mutation canary (tests did NOT catch the planted bug!)"
  else
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
if [ -n "$COVERAGE_PCT" ]; then
  printf 'Lines  : %s covered (floor %s%%)\n' "$COVERAGE_PCT" "$COVERAGE_FLOOR"
fi

# CI parity: when running as a GitHub Actions step (GITHUB_STEP_SUMMARY is
# set), append the same tallies as a markdown job summary — plus the line
# coverage measured by the coverage check. Local runs (env var unset) are
# unchanged.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '### Verification suite\n\n'
    printf '| Checks passed | Checks failed | Checks skipped | Tests passed | Tests failed |\n'
    printf '| ---: | ---: | ---: | ---: | ---: |\n'
    printf '| %d of %d | %d | %d | %d | %d |\n' \
      "$CHECKS_PASSED" "$CHECKS_TOTAL" "$CHECKS_FAILED" "$CHECKS_SKIPPED" \
      "$TESTS_PASSED" "$TESTS_FAILED"
    if [ -n "$COVERAGE_PCT" ]; then
      printf '\nLine coverage: %s (gate: >= %s%%)\n' "$COVERAGE_PCT" "$COVERAGE_FLOOR"
    fi
    if [ "$CHECKS_FAILED" -gt 0 ]; then
      printf '\nFailed checks:\n\n'
      printf '%b' "$FAILED_NAMES" | sed 's/^  - /- /'
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$CHECKS_FAILED" -eq 0 ]; then
  printf '%s%sALL CHECKS PASSED — this build behaves as intended.%s\n' "$BOLD" "$GREEN" "$RESET"
  exit 0
else
  printf '%s%sFAILURES:%s\n' "$BOLD" "$RED" "$RESET"
  printf '%b' "$FAILED_NAMES"
  exit 1
fi
