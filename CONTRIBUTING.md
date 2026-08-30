# Contributing

Thank you for contributing to this project. This document covers how
development works here; the [README](README.md) covers what the project is.

## Development environment

Development is Docker-first: the pinned Rust toolchain, the pinned nightly
(Miri, fuzzing) and every verification tool live in the project's toolchain
container, so your host needs only Docker and git.

```bash
make verify-docker
```

builds the toolchain image and runs the full verification suite inside it —
the same environment CI uses. `make help` lists the other targets (tests,
Miri, fuzzing, coverage) individually.

You can also work on the host with rustup: `rust-toolchain.toml` pins the
toolchain, and `./scripts/verify.sh` runs the same suite (checks that need
tools you don't have installed are skipped and say so).

## Tests come first

Write the test before or alongside the change, and make sure it fails
without the change. The verify suite plants a bug on purpose (the mutation
canary) and CI mutates every line your PR touches (cargo-mutants); code
whose tests notice nothing does not merge. Structure code so it can be unit
tested without scaffolding.

## The verify suite and required checks

`./scripts/verify.sh` is the local mirror of CI: build and tests with
warnings as errors, clippy, rustdoc, Miri, cargo-deny, a fuzz smoke run,
package purity, the mutation canary, rustfmt, and consistency checks on the
toolchain pins and the required-contexts list.

Every pull request must pass the required CI checks before it can merge —
they are enforced by branch protection, for admins too. There is no way to
skip them: `[skip ci]` in a commit message only strands the PR with its
required checks missing forever. If a check seems wrong rather than your
change, open an issue.

Two of those checks guard the gates themselves: actionlint and shellcheck
lint the workflows and scripts, and `scripts/check-required-contexts.sh`
fails if a PR-gating job is added or renamed without updating the
branch-protection list in `scripts/setup.sh` — so if you add a CI job,
update that list in the same PR.

## Pull requests

* One PR per change; keep the diff as small as the change allows.
* Fill in `.github/PULL_REQUEST_TEMPLATE.md` — in particular how the change
  was tested, with the commands you ran.
* `cargo fmt` before pushing; CI rejects unformatted code.
* Link the issue the PR addresses, if there is one.

## Licensing

This project is licensed under [Apache-2.0](LICENSE) (see also
[NOTICE](NOTICE)). There is no CLA: by submitting a contribution you agree
it is licensed under the same terms as the project (inbound = outbound), as
described in section 5 of the Apache License 2.0.

## Security issues

Do not open a public issue for a vulnerability. Use the private reporting
flow described in [SECURITY.md](SECURITY.md).
