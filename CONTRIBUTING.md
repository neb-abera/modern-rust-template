# Contributing

The [README](README.md) covers what the project is. This file covers how
development works.

## Development environment

Development is Docker-first. The pinned Rust toolchain, the pinned nightly
(Miri, fuzzing) and every verification tool live in the project's toolchain
container, so the host needs Docker and git.

```bash
make verify-docker
```

builds the toolchain image and runs the full verification suite inside it,
the same environment CI uses. `make help` lists the other targets (tests,
Miri, fuzzing, coverage, prose).

Working on the host with rustup also works. `rust-toolchain.toml` pins the
toolchain, and `./scripts/verify.sh` runs the same suite. Checks that need
tools you do not have installed are skipped and say so.

## Tests come first

Write the test before or alongside the change, and check that it fails
without the change. The verify suite plants a bug on purpose (the mutation
canary) and CI mutates every line your PR touches (cargo-mutants). Code
whose tests notice nothing does not merge. Structure code so it can be unit
tested without scaffolding.

## The verify suite and required checks

`./scripts/verify.sh` is the local mirror of CI: consistency checks on the
toolchain pins, the required-contexts list and workflow concurrency, the
attribution and prose checks, build and tests with warnings as errors, line
coverage against the floor in `coverage-floor.txt`, clippy, rustdoc, Miri,
Kani, cargo-deny, cargo-vet, a fuzz smoke run, a benchmark smoke run, the
release size budget and its canary, package purity, the mutation canary and
rustfmt. The prose check runs Vale through Docker, so inside the
container it skips. `make prose` runs it on the host, and CI's `prose` job
runs it on every pull request.

Every pull request must pass the required CI checks before it can merge.
Branch protection enforces them, for admins too. There is no way to skip
them. `[skip ci]` in a commit message strands the PR with its required
checks missing forever. If a check is wrong rather than your change, open
an issue.

Some of those checks guard the gates themselves. actionlint and shellcheck
lint the workflows and scripts. `scripts/check-required-contexts.sh` fails
if a PR-gating job is added or renamed without updating
`.github/required-checks`, the list `scripts/setup.sh` sends to branch
protection. If you add a CI job, update that list in the same PR.
`scripts/check-template-parity.sh` fails if a file listed in
`.template-parity` differs from modern-webapp-template. Change those files
there first.

## Raising the size budget

The suite fails when the stripped release binary outgrows the byte budget
committed in [size-budget.txt](size-budget.txt). If the growth is intended,
raise the budget in the same pull request as the change that needs it. Take
the measured size from the failing check's message (`make verify-docker`),
set the budget to about 20% above it, and say in the pull request what the
bytes bought. Never raise it to get to green.

## Pull requests

* One PR per change. Keep the diff as small as the change allows.
* Fill in `.github/PULL_REQUEST_TEMPLATE.md`, in particular how the change
  was tested, with the commands you ran.
* `cargo fmt` before pushing. CI rejects unformatted code.
* Link the issue the PR addresses, if there is one.

## Licensing

This project is licensed under [Apache-2.0](LICENSE) (see also
[NOTICE](NOTICE)). There is no CLA. By submitting a contribution you agree
it is licensed under the same terms as the project (inbound = outbound), as
described in section 5 of the Apache License 2.0.

## Security issues

Do not open a public issue for a vulnerability. Use the private reporting
flow described in [SECURITY.md](SECURITY.md).
