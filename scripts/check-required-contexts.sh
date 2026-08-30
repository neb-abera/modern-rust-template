#!/usr/bin/env bash
#
# check-required-contexts.sh — the branch-protection contexts setup.sh
# requires and the check names CI actually reports must agree, and this
# check (run by verify.sh) is what lets the list live in setup.sh without
# relying on anyone's memory:
#
#   scripts/setup.sh          "contexts": [...]   — what merges are gated on
#   .github/workflows/ci.yml      job names        — what CI reports on a PR
#   .github/workflows/codeql.yml  job names        — what CodeQL reports on a PR
#
# A job added to a workflow but not to setup.sh would run without gating
# merges; a context in setup.sh with no job behind it would block every
# merge forever. Both directions fail.
#
# The workflows are parsed by convention, not by a YAML engine: every job in
# ci.yml and codeql.yml runs on pull requests (both trigger on unfiltered
# pull_request, and the only job-level `if:` conditions are
# `github.event_name == 'pull_request'`), the job-level `name:` sits at
# four-space indent, and matrix names use a single `${{ matrix.<var> }}`
# whose values are either a flow list (`os: [a, b, c]`) or include entries
# (`- language: rust`). A job that breaks these conventions shows up here as
# a mismatch, which is the point.
#
# Exit code 0 means the lists agree.

set -eu

cd "$(dirname "$0")/.."

# The contexts setup.sh will require: the quoted strings of its JSON
# "contexts" array (quote-delimited, so names may contain commas).
setup_contexts() {
  sed -n '/"contexts": \[/,/\]/p' scripts/setup.sh \
    | grep -o '"[^"]*"' | sed 's/^"//; s/"$//' | grep -vx 'contexts'
}

# The check names one workflow reports on a PR: each job's `name:` (the job
# id when unnamed), with `${{ matrix.<var> }}` expanded from the matrix.
# shellcheck disable=SC2016  # the single-quoted ${{ }} is literal YAML text
workflow_contexts() {
  file=$1
  jobs=$(sed -n '/^jobs:/,$p' "$file" | sed -n 's/^  \([A-Za-z0-9_-]*\):[[:space:]]*$/\1/p')
  for job in $jobs; do
    block=$(sed -n "/^  $job:[[:space:]]*\$/,/^  [A-Za-z0-9_-]*:[[:space:]]*\$/p" "$file")
    name=$(printf '%s\n' "$block" | sed -n 's/^    name: //p' | head -1)
    [ -n "$name" ] || name=$job
    case $name in
      *'${{ matrix.'*)
        var=${name#*'${{ matrix.'}
        var=${var%%' }}'*}
        # Matrix values: a flow list first, include entries otherwise.
        vals=$(printf '%s\n' "$block" \
          | sed -n "s/^ *$var: \[\(.*\)\]\$/\1/p" | head -1 \
          | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true)
        if [ -z "$vals" ]; then
          vals=$(printf '%s\n' "$block" | sed -n "s/^ *- $var: //p")
        fi
        if [ -z "$vals" ]; then
          echo "error: cannot expand \${{ matrix.$var }} in $file job '$job'" >&2
          exit 1
        fi
        pattern='${{ matrix.'$var' }}'
        printf '%s\n' "$vals" | while IFS= read -r val; do
          printf '%s\n' "${name/"$pattern"/$val}"
        done
        ;;
      *) printf '%s\n' "$name" ;;
    esac
  done
}

required=$(setup_contexts | sort)
reported=$( (workflow_contexts .github/workflows/ci.yml
             workflow_contexts .github/workflows/codeql.yml) | sort)

if [ -z "$required" ] || [ -z "$reported" ]; then
  echo "error: could not read the context lists" >&2
  echo "  setup.sh contexts:  $(printf '%s' "$required" | grep -c . || true)" >&2
  echo "  workflow job names: $(printf '%s' "$reported" | grep -c . || true)" >&2
  exit 1
fi

status=0

missing=$(comm -13 <(printf '%s\n' "$required") <(printf '%s\n' "$reported"))
if [ -n "$missing" ]; then
  echo "error: CI reports these checks on every PR, but setup.sh does not require them:" >&2
  printf '%s\n' "$missing" | sed 's/^/  - /' >&2
  status=1
fi

stray=$(comm -23 <(printf '%s\n' "$required") <(printf '%s\n' "$reported"))
if [ -n "$stray" ]; then
  echo "error: setup.sh requires these contexts, but no PR-triggered job reports them (they would block every merge):" >&2
  printf '%s\n' "$stray" | sed 's/^/  - /' >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  count=$(printf '%s\n' "$required" | grep -c .)
  echo "required contexts agree: setup.sh and the workflows both list the same $count checks"
fi
exit "$status"
