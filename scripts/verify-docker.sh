#!/usr/bin/env bash
#
# verify-docker.sh — run the full verification suite (scripts/verify.sh)
# inside the project's Docker toolchain image instead of on the host, so
# results do not depend on locally installed toolchains or cargo tools.
#
# The source tree is mounted read-only and copied to a container-local
# directory before building, so the host checkout is never modified and no
# root-owned build artifacts are left behind.

set -eu

cd "$(dirname "$0")/.."

# Image/container names derive from the checkout directory, so projects
# generated from this template need no edits here.
NAME="$(basename "$PWD" | tr '[:upper:]' '[:lower:]')"
IMAGE="$NAME:latest"
CONTAINER="$NAME-verify"

echo "== Building toolchain image $IMAGE (cached after the first run) =="
docker build -t "$IMAGE" .

echo
echo "== Running verification in container $CONTAINER =="
docker rm -f "$CONTAINER" 2> /dev/null || true
# GITHUB_REPOSITORY: check-template-parity.sh asks git for this repository's
# name. In a worktree .git is a file naming a host path the container does
# not have, so git fails there and the name is passed in from the host.
REPO_SLUG=$(git remote get-url origin 2> /dev/null \
  | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##' || true)
docker run --rm --name "$CONTAINER" -v "$PWD":/src:ro -e GITHUB_REPOSITORY="$REPO_SLUG" "$IMAGE" bash -c '
  set -eu
  mkdir "$HOME/project"
  # Host build artifacts are excluded: they were produced by a different
  # platform/toolchain and would only poison the cache.
  tar -C /src --exclude=./target --exclude=./fuzz/target -cf - . \
    | tar -xf - -C "$HOME/project"
  cd "$HOME/project"
  ./scripts/verify.sh
'
