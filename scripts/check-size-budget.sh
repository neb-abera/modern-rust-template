#!/usr/bin/env bash
#
# check-size-budget.sh — the release artifact's size budget. Measures the
# stripped size of a built artifact in bytes and fails when it exceeds the
# committed budget, so size growth is a deliberate, reviewed change to the
# budget file instead of something that accumulates unnoticed. Bytes are
# deterministic for a pinned toolchain; this is a size gate, never a timing
# gate.
#
#   check-size-budget.sh <artifact> <budget-file>
#   check-size-budget.sh --self-test <artifact>
#
# The artifact itself is never modified: a temporary copy is stripped and
# measured. The budget file holds one integer (bytes); blank lines and
# `#` comments are ignored. The caller (verify.sh, CI) resolves the artifact
# path from the project name, so a renamed project needs no edits here.
#
# --self-test is the gate's own canary: it runs this script against the
# given artifact with a budget of exactly its size (must pass), one byte
# under (must fail and name artifact, size and budget), a missing artifact
# and a missing or unreadable budget (must each fail, distinctly).
#
# Exit codes: 0 = within budget (or self-test passed), 1 = over budget (or
# self-test failed), 2 = artifact missing, 3 = budget missing or unreadable,
# 4 = the artifact could not be stripped, 64 = usage.

set -eu

usage() {
  echo "usage: $0 <artifact> <budget-file> | --self-test <artifact>" >&2
  exit 64
}

# Print the stripped size of "$1" in bytes. GNU strip first (Linux, the
# toolchain container), BSD strip (macOS) as fallback.
stripped_size() {
  local tmp
  tmp=$(mktemp)
  cp "$1" "$tmp"
  if strip --strip-unneeded "$tmp" 2> /dev/null || strip -x "$tmp" 2> /dev/null; then
    wc -c < "$tmp" | tr -d '[:space:]'
    rm -f "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

check() {
  local artifact="$1" budget_file="$2" name budget size
  name=$(basename "$artifact")

  if [ ! -f "$artifact" ]; then
    echo "size-budget: ERROR: artifact not found: $artifact (build the release artifact first)" >&2
    return 2
  fi
  if [ ! -f "$budget_file" ]; then
    echo "size-budget: ERROR: budget file not found: $budget_file" >&2
    return 3
  fi
  budget=$(grep -Ev '^[[:space:]]*(#|$)' "$budget_file" | tr -d '[:space:]')
  case "$budget" in
    '' | *[!0-9]*)
      echo "size-budget: ERROR: $budget_file must hold one integer (bytes), got '${budget}'" >&2
      return 3
      ;;
  esac
  if ! size=$(stripped_size "$artifact"); then
    echo "size-budget: ERROR: could not strip a copy of $artifact (is strip installed?)" >&2
    return 4
  fi

  if [ "$size" -gt "$budget" ]; then
    echo "size-budget: FAIL: $name is $size bytes stripped, $((size - budget)) over the budget of $budget bytes ($budget_file)" >&2
    echo "size-budget: shrink the artifact, or raise the budget deliberately (see CONTRIBUTING.md)" >&2
    return 1
  fi
  echo "size-budget: ok: $name is $size bytes stripped, within the budget of $budget bytes ($((budget - size)) to spare)"
}

# Run this script as a child with the given arguments and require an exact
# exit code plus a pattern in its combined output.
expect() {
  local want="$1" pattern="$2" label="$3" out code
  shift 3
  code=0
  out=$("$0" "$@" 2>&1) || code=$?
  if [ "$code" -eq "$want" ] && printf '%s\n' "$out" | grep -Eq -- "$pattern"; then
    echo "  ok: $label (exit $code)"
    printf '%s\n' "$out" | sed 's/^/      /'
  else
    echo "  NOT ok: $label: wanted exit $want matching /$pattern/, got exit $code:" >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    SELF_TEST_FAILED=1
  fi
}

self_test() {
  local artifact="$1" name size dir
  name=$(basename "$artifact")
  if [ ! -f "$artifact" ]; then
    echo "size-budget self-test: ERROR: artifact not found: $artifact" >&2
    return 2
  fi
  if ! size=$(stripped_size "$artifact"); then
    echo "size-budget self-test: ERROR: could not strip a copy of $artifact" >&2
    return 4
  fi
  dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$dir'" EXIT
  echo "$size" > "$dir/exact"
  echo "$((size - 1))" > "$dir/one-under"
  echo "not-a-number" > "$dir/garbage"

  SELF_TEST_FAILED=0
  expect 0 "ok: $name is $size bytes" "a budget of exactly the size passes" \
    "$artifact" "$dir/exact"
  expect 1 "FAIL: $name is $size bytes stripped, 1 over the budget of $((size - 1)) bytes" \
    "one byte over the budget fails" "$artifact" "$dir/one-under"
  expect 2 "artifact not found" "a missing artifact fails, it does not pass" \
    "$dir/no-such-artifact" "$dir/exact"
  expect 3 "budget file not found" "a missing budget fails, it does not pass" \
    "$artifact" "$dir/no-such-budget"
  expect 3 "must hold one integer" "an unreadable budget fails" \
    "$artifact" "$dir/garbage"
  return "$SELF_TEST_FAILED"
}

[ $# -eq 2 ] || usage
if [ "$1" = "--self-test" ]; then
  self_test "$2"
else
  check "$1" "$2"
fi
