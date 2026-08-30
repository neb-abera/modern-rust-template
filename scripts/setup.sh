#!/usr/bin/env bash
#
# setup.sh — one-command setup for a repository generated from this template:
#
#   ./scripts/setup.sh
#
# What it does:
#   1. renames the crate after your repository: the package name in
#      Cargo.toml (and both lockfiles), the fuzz crate, every
#      `use project::` path in sources, tests, benches and fuzz targets,
#      and the README/SECURITY.md badge and links — then pushes the change
#   2. enables the GitHub security settings templates cannot carry over:
#      secret scanning, push protection, private vulnerability reporting,
#      Dependabot alerts and security updates
#   3. enables branch protection on the default branch requiring the
#      sixteen CI checks — plus required commit signatures, when this
#      machine is configured to sign
#
# Requirements: git, and the GitHub CLI (`gh`, https://cli.github.com)
# authenticated as an admin of the repository. Safe to re-run: every step is
# idempotent.

set -euo pipefail

cd "$(dirname "$0")/.."

TEMPLATE_CRATE="project"
TEMPLATE_OWNER_REPO="neb-abera/modern-rust-template"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi
step() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$1"; }
done_() { printf '%s  done:%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s  note:%s %s\n' "$YELLOW" "$RESET" "$1"; }

#
# Detect the repository
#

origin=$(git remote get-url origin 2> /dev/null || true)
if [ -z "$origin" ]; then
  echo "error: no git remote named 'origin'. Clone your generated repository first." >&2
  exit 1
fi
owner_repo=$(printf '%s' "$origin" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
repo=${owner_repo##*/}

# Crate name: the repository name lowercased and sanitized to what
# crates.io accepts; the module path used in code swaps dashes for
# underscores, exactly as cargo does.
name=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]/-/g; s/^([0-9])/n\1/')
name_snake=$(printf '%s' "$name" | tr '-' '_')

if ! command -v gh > /dev/null; then
  echo "error: the GitHub CLI (gh) is required — https://cli.github.com — and must be authenticated (gh auth login)." >&2
  exit 1
fi
default_branch=$(gh api "repos/$owner_repo" --jq .default_branch)

step "Setting up $owner_repo (crate name: $name, default branch: $default_branch)"

#
# 1. Rename the crate after the repository
#

if [ "$owner_repo" = "$TEMPLATE_OWNER_REPO" ]; then
  warn "this is the template itself; skipping the rename"
else
  step "Renaming crate \"$TEMPLATE_CRATE\" to \"$name\""

  NEW=$name perl -pi -e 's/^name = "project"$/name = "$ENV{NEW}"/' Cargo.toml Cargo.lock fuzz/Cargo.lock
  NEW=$name perl -pi -e 's/"project-fuzz"/"$ENV{NEW}-fuzz"/' fuzz/Cargo.toml fuzz/Cargo.lock
  # the fuzz lockfile also lists the parent crate as a dependency entry
  NEW=$name perl -pi -e 's/^ "project"(,?)$/ "$ENV{NEW}"$1/' fuzz/Cargo.lock
  NEW=$name perl -pi -e 's/^\[dependencies\.project\]$/[dependencies.$ENV{NEW}]/' fuzz/Cargo.toml
  NEW=$name_snake perl -pi -e 's/\bproject::/$ENV{NEW}::/g' \
    src/*.rs tests/*.rs benches/*.rs fuzz/fuzz_targets/*.rs

  NEW_REPO="$owner_repo" perl -pi -e 's#\Qneb-abera/modern-rust-template\E#$ENV{NEW_REPO}#g' \
    README.md Cargo.toml SECURITY.md .github/ISSUE_TEMPLATE/config.yml
  NEW=$repo perl -pi -e 's/\QModern Rust Template\E/$ENV{NEW}/' README.md

  if git diff --quiet && git diff --cached --quiet; then
    done_ "already renamed"
  else
    git add -u
    git commit -q -m "Rename crate after repository ($name) via scripts/setup.sh"
    if git push -q origin "HEAD:$default_branch" 2> /dev/null; then
      done_ "renamed and pushed to $default_branch"
    else
      warn "push to $default_branch was rejected (branch protection already on?); open a PR with the local commit"
    fi
  fi
fi

#
# 2. Repo security settings
#

step "Enabling security settings"
gh api -X PATCH "repos/$owner_repo" \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  -f 'security_and_analysis[dependabot_security_updates][status]=enabled' > /dev/null
done_ "secret scanning, push protection, Dependabot security updates"
gh api -X PUT "repos/$owner_repo/private-vulnerability-reporting" > /dev/null
done_ "private vulnerability reporting"
gh api -X PUT "repos/$owner_repo/vulnerability-alerts" > /dev/null
done_ "Dependabot alerts"

#
# 3. Branch protection requiring the sixteen CI checks
#
# The list must match the PR-triggered job names in ci.yml and codeql.yml;
# scripts/check-required-contexts.sh (a verify.sh gate) enforces the pairing.

step "Enabling branch protection on $default_branch"
gh api -X PUT "repos/$owner_repo/branches/$default_branch/protection" --input - > /dev/null <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "ubuntu-latest", "macos-latest", "windows-latest",
      "clippy", "rustfmt", "docs", "miri", "cargo-deny",
      "fuzz smoke", "coverage", "toolchain pins",
      "dependency review",
      "mutation testing (cargo-mutants, diff only)",
      "lint workflows and scripts",
      "analyze (rust)", "analyze (actions)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
done_ "sixteen CI checks required, strict, enforced for admins"

# Required commit signatures are a separate sub-resource of branch
# protection with their own endpoint, not a field of the PUT above, so they
# are enabled here explicitly (idempotent: POSTing to an already-enabled
# branch succeeds). Guarded like the webapp template: a branch that demands
# signatures from a machine that cannot produce them would lock its own
# adopter out on day one, so this only turns on when this clone is already
# configured to sign its commits.
if [ "$(git config --get commit.gpgsign || true)" = "true" ]; then
  gh api -X POST "repos/$owner_repo/branches/$default_branch/protection/required_signatures" > /dev/null
  done_ "$default_branch accepts only Verified (signed) commits"
else
  warn "commit signing is not configured (commit.gpgsign is not true); $default_branch does NOT require signatures"
  warn "configure signing, then run: gh api -X POST repos/$owner_repo/branches/$default_branch/protection/required_signatures"
fi

printf '\n%sSetup complete.%s Every future change now goes through a PR gated on the
sixteen CI checks. Verify the renamed project with: make verify-docker

Optional: add a CODECOV_TOKEN repository secret to feed the Codecov
dashboard. The coverage gate itself runs in CI and needs no token.\n' "$BOLD" "$RESET"
