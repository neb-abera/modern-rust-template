#!/usr/bin/env bash
#
# check-concurrency.sh — no workflow cancels a run on the default branch.
#
#   scripts/check-concurrency.sh              check .github/workflows/*.yml
#   scripts/check-concurrency.sh --self-test  prove the check can fail
#
# `cancel-in-progress: true` in a workflow that runs on push, a schedule, a
# tag or a merge queue means two merges minutes apart cancel the first
# merge's runs, and that merge commit is left with no checks. On a pull
# request a newer push does make the running check obsolete, so the rule
# is `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`, and
# a release uses a fixed group with cancel off. A workflow triggered by
# pull_request alone may cancel.

set -euo pipefail
cd "$(dirname "$0")/.."

# check <dir>: print each offending workflow under <dir>; exit 1 if any.
check() (
  status=0
  for wf in "$1"/*.yml; do
    [ -f "$wf" ] || continue
    grep -Eq '^[[:space:]]*cancel-in-progress:[[:space:]]*true[[:space:]]*$' "$wf" || continue
    # Triggers: the on: block, flow form (`on: pull_request`, `on: [a, b]`)
    # or block form (the keys indented under `on:`).
    triggers=$(sed -n 's/^on:[[:space:]]*\[*\([^]#]*\)\]*.*$/\1/p' "$wf" | tr ',' '\n')
    triggers="$triggers
$(sed -n '/^on:[[:space:]]*$/,/^[^[:space:]#]/s/^  \([a-z_]*\):.*$/\1/p' "$wf")"
    others=$(printf '%s\n' "$triggers" | tr -d ' ' | grep -v '^$' | grep -vx 'pull_request' || true)
    if [ -n "$others" ]; then
      echo "error: $wf sets cancel-in-progress: true and also runs on: $(printf '%s' "$others" | tr '\n' ' ')" >&2
      status=1
    fi
  done
  exit "$status"
)

if [ "${1:-}" = "--self-test" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  cp .github/workflows/*.yml "$tmp/"
  check "$tmp" || { echo "self-test FAILED: the unmodified workflows do not pass" >&2; exit 1; }
  printf 'on:\n  push:\n    branches: [main]\n  pull_request:\nconcurrency:\n  group: x\n  cancel-in-progress: true\n' > "$tmp/planted-push.yml"
  if check "$tmp" 2> /dev/null; then
    echo "self-test FAILED: a push workflow that cancels in progress passed" >&2
    exit 1
  fi
  rm "$tmp/planted-push.yml"
  printf 'on: pull_request\nconcurrency:\n  group: x\n  cancel-in-progress: true\n' > "$tmp/planted-pr.yml"
  check "$tmp" || { echo "self-test FAILED: a pull_request-only workflow that cancels was refused" >&2; exit 1; }
  echo "self-test passed: a push workflow that cancels fails, a pull_request-only one passes"
  exit 0
fi

check .github/workflows
echo "concurrency: no workflow cancels a run outside a pull request"
