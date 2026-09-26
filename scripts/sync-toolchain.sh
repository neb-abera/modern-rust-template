#!/usr/bin/env bash
#
# sync-toolchain.sh — move rust-toolchain.toml and Cargo.toml to the Rust
# version the Dockerfile's base image names.
#
#   scripts/sync-toolchain.sh              rewrite the two files, then run
#                                          scripts/check-toolchain.sh
#   scripts/sync-toolchain.sh --self-test  prove the rewrite makes a
#                                          mismatched tree pass the check
#
# The toolchain is pinned in three places and scripts/check-toolchain.sh
# fails when they differ. Dependabot's docker ecosystem bumps only the
# Dockerfile, so every Rust release arrived as a red pull request that could
# not auto-merge (rust #28, casefile #3, 2026-09-26). The Dependabot
# toolchain workflow runs this script on Dependabot's docker pull requests
# and commits what it changed.
#
# What it writes:
#   rust-toolchain.toml  channel = "<X.Y.Z>", the Dockerfile's version.
#   Cargo.toml           rust-version = "<X.Y>", its major and minor. CI
#                        builds and tests on the pinned toolchain only, so an
#                        older minimum would be a claim nothing checks. A
#                        patch release moves the channel and leaves
#                        rust-version alone, which check-toolchain.sh accepts
#                        ("1.98" matches "1.98.1").
#
# Exit 0 means the three pins agree after the rewrite.

set -euo pipefail
cd "$(dirname "$0")/.."

# sync <dir>: rewrite the pins under <dir>, then run that tree's check. A
# subshell, so --self-test can run it against several trees.
sync() (
  cd "$1"
  # The same expression check-toolchain.sh reads the Dockerfile with.
  ver=$(sed -n 's/^FROM rust:\([0-9][^-@ ]*\).*/\1/p' Dockerfile)
  case "$ver" in
    *[!0-9.]* | '' | .* | *.)
      echo "error: no 'FROM rust:<X.Y.Z>' line in the Dockerfile to sync to (read '${ver:-<missing>}')" >&2
      exit 1
      ;;
  esac
  case "$ver" in
    *.*.*) minor=${ver%.*} ;;
    *.*) minor=$ver ;;
    *)
      echo "error: the Dockerfile's rust version '$ver' has no minor part" >&2
      exit 1
      ;;
  esac
  sed -i.bak "s/^channel = \".*\"$/channel = \"$ver\"/" rust-toolchain.toml
  sed -i.bak "s/^rust-version = \".*\"$/rust-version = \"$minor\"/" Cargo.toml
  rm -f rust-toolchain.toml.bak Cargo.toml.bak
  echo "synced to rust:$ver: channel = \"$ver\", rust-version = \"$minor\""
  ./scripts/check-toolchain.sh
)

if [ "${1:-}" = "--self-test" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  # plant <name> <dockerfile-sed>: a copy of the pinned files with the
  # Dockerfile's rust line edited.
  plant() {
    rm -rf "${tmp:?}/$1"
    mkdir -p "$tmp/$1/scripts"
    cp Dockerfile rust-toolchain.toml Cargo.toml "$tmp/$1/"
    cp scripts/check-toolchain.sh scripts/sync-toolchain.sh "$tmp/$1/scripts/"
    sed -i.bak "$2" "$tmp/$1/Dockerfile"
    rm -f "$tmp/$1/Dockerfile.bak"
  }
  fail() { echo "self-test FAILED: $*" >&2; exit 1; }

  cur=$(sed -n 's/^FROM rust:\([0-9][^-@ ]*\).*/\1/p' Dockerfile)
  msrv=$(sed -n 's/^rust-version = "\(.*\)"$/\1/p' Cargo.toml)
  major=${cur%%.*}
  rest=${cur#*.}
  minor=${rest%%.*}
  patch=${rest#*.}
  next_patch="$major.$minor.$((patch + 1))"
  next_minor="$major.$((minor + 1)).0"

  # 1. The tree as committed: nothing to change, and the check passes.
  plant same ''
  sync "$tmp/same" > /dev/null || fail "the committed pins do not pass after a sync"
  for f in Dockerfile rust-toolchain.toml Cargo.toml; do
    cmp -s "$f" "$tmp/same/$f" || fail "a sync of agreeing pins changed $f"
  done

  # 2. A patch release: the check fails before, passes after, and
  # rust-version stays on its minor.
  plant patch "s/^FROM rust:$cur-/FROM rust:$next_patch-/"
  if "$tmp/patch/scripts/check-toolchain.sh" > /dev/null 2>&1; then
    fail "the planted patch bump (rust:$next_patch) passed the check before the sync"
  fi
  sync "$tmp/patch" > /dev/null || fail "the check still fails after syncing to rust:$next_patch"
  grep -qx "channel = \"$next_patch\"" "$tmp/patch/rust-toolchain.toml" || fail "channel is not $next_patch"
  grep -qx "rust-version = \"$msrv\"" "$tmp/patch/Cargo.toml" || fail "a patch bump moved rust-version off $msrv"

  # 3. A minor release: rust-version moves to the new minor.
  plant minor "s/^FROM rust:$cur-/FROM rust:$next_minor-/"
  if "$tmp/minor/scripts/check-toolchain.sh" > /dev/null 2>&1; then
    fail "the planted minor bump (rust:$next_minor) passed the check before the sync"
  fi
  sync "$tmp/minor" > /dev/null || fail "the check still fails after syncing to rust:$next_minor"
  grep -qx "channel = \"$next_minor\"" "$tmp/minor/rust-toolchain.toml" || fail "channel is not $next_minor"
  grep -qx "rust-version = \"${next_minor%.*}\"" "$tmp/minor/Cargo.toml" || fail "rust-version is not ${next_minor%.*}"

  # 4. No rust FROM line: the sync fails and writes nothing.
  plant none "s/^FROM rust:$cur-slim/FROM debian:stable-slim/"
  if sync "$tmp/none" > /dev/null 2>&1; then
    fail "a Dockerfile with no rust FROM line synced"
  fi
  cmp -s rust-toolchain.toml "$tmp/none/rust-toolchain.toml" || fail "a failed sync changed rust-toolchain.toml"

  echo "self-test passed: rust:$next_patch and rust:$next_minor fail the check and pass after a sync, agreeing pins stay byte-identical (rust:$cur, rust-version $msrv), a missing rust line fails"
  exit 0
fi

sync .
