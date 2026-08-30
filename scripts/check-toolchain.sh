#!/usr/bin/env bash
#
# check-toolchain.sh — the toolchain version is pinned in three places that
# must agree, and this check (run by verify.sh and CI) is what lets them be
# three places without relying on anyone's memory:
#
#   rust-toolchain.toml  channel        — what rustup installs everywhere
#   Dockerfile           FROM rust:<v>  — what the toolchain image ships
#   Cargo.toml           rust-version   — the MSRV consumers see
#
# Exit code 0 means all three agree.

set -eu

cd "$(dirname "$0")/.."

channel=$(sed -n 's/^channel = "\(.*\)"$/\1/p' rust-toolchain.toml)
docker_ver=$(sed -n 's/^FROM rust:\([0-9][^-@ ]*\).*/\1/p' Dockerfile)
msrv=$(sed -n 's/^rust-version = "\(.*\)"$/\1/p' Cargo.toml)

status=0

if [ -z "$channel" ] || [ -z "$docker_ver" ] || [ -z "$msrv" ]; then
  echo "error: could not read all three pins" >&2
  echo "  rust-toolchain.toml channel: '${channel:-<missing>}'" >&2
  echo "  Dockerfile rust version:     '${docker_ver:-<missing>}'" >&2
  echo "  Cargo.toml rust-version:     '${msrv:-<missing>}'" >&2
  exit 1
fi

if [ "$channel" != "$docker_ver" ]; then
  echo "error: rust-toolchain.toml pins $channel but the Dockerfile base image is rust:$docker_ver" >&2
  status=1
fi

case "$channel" in
  "$msrv" | "$msrv".*) ;;
  *)
    echo "error: Cargo.toml rust-version ($msrv) does not match the pinned toolchain ($channel)" >&2
    status=1
    ;;
esac

if [ "$status" -eq 0 ]; then
  echo "toolchain pins agree: channel=$channel, Dockerfile=rust:$docker_ver, rust-version=$msrv"
fi
exit "$status"
