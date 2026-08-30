#!/usr/bin/env bash
#
# check-nightly-age.sh — the pinned nightly toolchain (Miri, fuzzing) is an
# ENV string in the Dockerfile, so Dependabot cannot see it and nothing
# updates it automatically. This check (run by the scheduled audit workflow)
# fails once the pin is older than the age limit, so staleness surfaces as
# a red run instead of silently accumulating.
#
# Exit code 0 means the pin is fresh enough.

set -eu

cd "$(dirname "$0")/.."

MAX_AGE_DAYS=90

# The pinned nightly is derived from the Dockerfile, the single place it is
# written down.
nightly=$(sed -n 's/^ENV NIGHTLY_TOOLCHAIN=\(.*\)$/\1/p' Dockerfile)
pin_date=${nightly#nightly-}

case $pin_date in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *)
    echo "error: could not read a nightly-YYYY-MM-DD pin from the Dockerfile (got '${nightly:-<missing>}')" >&2
    exit 1
    ;;
esac

# Date arithmetic: GNU date (Linux, CI) first, BSD date (macOS) as fallback.
if pin_epoch=$(date -d "$pin_date" +%s 2>/dev/null); then
  :
else
  pin_epoch=$(date -j -f '%Y-%m-%d' "$pin_date" +%s)
fi
age_days=$(( ($(date +%s) - pin_epoch) / 86400 ))

if [ "$age_days" -gt "$MAX_AGE_DAYS" ]; then
  echo "error: the pinned nightly ($nightly) is $age_days days old (limit: $MAX_AGE_DAYS)." >&2
  echo "Bump ENV NIGHTLY_TOOLCHAIN in the Dockerfile to a recent nightly, then run" >&2
  echo "'make verify-docker' — the Miri and fuzz checks prove the new pin works." >&2
  exit 1
fi

echo "nightly pin is fresh: $nightly is $age_days days old (limit: $MAX_AGE_DAYS)"
