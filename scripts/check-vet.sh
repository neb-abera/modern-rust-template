#!/usr/bin/env bash
#
# check-vet.sh — cargo-vet: has anyone read this dependency's code?
#
# cargo-deny (deny.toml) answers a different question: known advisories,
# licence compliance, banned crates, untrusted sources. Neither subsumes the
# other, so both are gates.
#
#   scripts/check-vet.sh              run the gate
#   scripts/check-vet.sh --self-test  prove the gate can fail
#
# --self-test deletes one exemption from supply-chain/config.toml and requires
# cargo vet to fail on the now-unaccounted crate, then requires it to pass
# again once the file is restored. Without that, a config that silently
# accepted everything would report success forever.
#
# --locked is deliberate. The [imports] in supply-chain/config.toml are four
# third-party URLs; reading supply-chain/imports.lock instead makes the gate
# deterministic and keeps a pull request from depending on someone else's
# repository being up. Refresh the lock deliberately with `make vet-update`.

set -eu

cd "$(dirname "$0")/.."

run_vet() { cargo vet --locked; }

self_test() {
  local backup victim
  backup="$(mktemp)"
  cp supply-chain/config.toml "$backup"
  # Restore by file copy, never git checkout: this has to work in containers
  # and source exports with no git metadata, and must touch nothing else.
  # shellcheck disable=SC2064
  trap "cp '$backup' supply-chain/config.toml; rm -f '$backup'" EXIT

  victim=$(grep -m1 '^\[\[exemptions\.' supply-chain/config.toml | sed 's/^\[\[exemptions\.//; s/\]\]$//')
  if [ -z "$victim" ]; then
    echo "self-test: no exemption to remove; has supply-chain/config.toml changed?" >&2
    return 1
  fi

  # Delete the stanza: its header and the lines up to the next blank line.
  perl -0pi -e "s/\\Q[[exemptions.$victim]]\\E\\n(?:[^\\n]*\\n)*?\\n//" supply-chain/config.toml
  if cmp -s supply-chain/config.toml "$backup"; then
    echo "self-test: could not remove the exemption for $victim" >&2
    return 1
  fi

  if run_vet > /dev/null 2>&1; then
    echo "self-test: cargo vet passed with $victim unaccounted for. The gate is not judging anything." >&2
    return 1
  fi
  echo "self-test: cargo vet failed with the exemption for $victim removed, as it must"

  cp "$backup" supply-chain/config.toml
  if ! run_vet > /dev/null 2>&1; then
    echo "self-test: cargo vet still fails after restoring the config" >&2
    return 1
  fi
  echo "self-test: cargo vet passes again once the config is restored"
}

if ! command -v cargo-vet > /dev/null; then
  echo "error: cargo-vet not found (it ships in the Docker toolchain image)" >&2
  exit 1
fi

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  run_vet
fi
