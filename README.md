[![Actions Status](https://github.com/neb-abera/modern-rust-template/workflows/CI/badge.svg)](https://github.com/neb-abera/modern-rust-template/actions)
[![Coverage](https://codecov.io/gh/neb-abera/modern-rust-template/graph/badge.svg)](https://codecov.io/gh/neb-abera/modern-rust-template)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/neb-abera/modern-rust-template/badge)](https://scorecard.dev/viewer/?uri=github.com/neb-abera/modern-rust-template)

# Modern Rust Template

A starting point for Rust projects: a pinned toolchain, release builds tuned
for performance, secure by design, the Rust sibling of
[modern-cpp-template](https://github.com/neb-abera/modern-cpp-template).

## Features

* **A pinned toolchain everywhere.** `rust-toolchain.toml` pins the stable
  compiler and rustup installs it on every machine and CI runner. The Docker
  toolchain image and the crate's declared MSRV are held in lockstep with it
  by a CI gate (`scripts/check-toolchain.sh`).

* **Performance defaults.** Release builds use whole-program LTO and a
  single codegen unit. A Criterion benchmark harness (`benches/`,
  `make bench`) is wired in so performance work starts with measurements.
  CI and the verification suite run each benchmark once in test mode, so
  the harness cannot rot. No gate reads a timing.

* **Secure by design.** `unsafe_code = "forbid"`, integer-overflow checks
  kept on in release builds, panicking `unwrap` linted against in library
  code, and placeholder code that returns errors on untrusted input instead
  of crashing.

* **Static analysis as a gate.** clippy with the pedantic set (the Rust API
  Guidelines material) configured once in `Cargo.toml [lints]` and applied
  identically in editors, locally and in CI. Warnings are errors on every
  merge.

* **A release size budget.** The stripped release binary is measured in
  bytes against the committed [`size-budget.txt`](size-budget.txt), with a
  canary that proves the gate fails one byte over. Growth is a reviewed
  change to the budget.

* **Miri.** The test suite runs under the
  [Miri](https://github.com/rust-lang/miri) interpreter on every pull
  request, flagging undefined behavior the moment any `unsafe` enters the
  project.

* **Proofs.** The `#[kani::proof]` harnesses in
  [`src/lib.rs`](src/lib.rs) are settled by
  [Kani](https://github.com/model-checking/kani), a bit-precise model
  checker, on every pull request. A test samples inputs. A proof covers all
  of them: `add` is proved total, commutative, and equal to exact `i128`
  arithmetic for every one of the 2^128 input pairs. Kani also proves the
  absence of panics, arithmetic overflow and out-of-bounds indexing on every
  path a harness reaches, which is why a harness with no assertion still
  earns its place.

  The gate ships with a canary, because the way verification fails is
  silence: a harness whose `kani::assume` is too strong reports success and
  proves nothing. So CI plants a wrong answer at one input the unit tests
  never sample, then requires the tests to pass and Kani to fail. The first
  half is the measurement of what proof adds over tests. The second is proof
  that the proofs are load-bearing.

  Kani ships its own rustc driver, so it is a third toolchain alongside the
  pinned stable and the pinned nightly. Its version is pinned in the
  Dockerfile (`KANI_VERSION`) and derived from there by the Makefile, the
  verification suite and CI. `make verify` fails on a version mismatch: a
  proof is only as good as the solver that checked it.

* **Supply-chain gate.** [cargo-deny](https://github.com/EmbarkStudios/cargo-deny)
  checks every pull request for RustSec advisories, license-allowlist
  violations, duplicate crates and sources other than crates.io
  (`deny.toml`). `--locked` builds everywhere, so the committed `Cargo.lock`
  is the only resolution CI accepts. A weekly scheduled audit re-checks
  advisories against the lockfile and the latest release binary
  (`cargo audit bin`, through the embedded cargo-auditable data) and fails
  when the pinned Miri and fuzzing nightly grows stale.

* **Dependency audits.** [cargo-vet](https://github.com/mozilla/cargo-vet)
  answers a question cargo-deny does not: has anyone read this dependency's
  code. Audits are imported from Google, Mozilla, the Bytecode Alliance and
  Zcash, which covers 17 of the 74 crates in the tree. The remaining 57 are
  `[[exemptions]]` written by `cargo vet init`, the dependency set as it stood
  when the gate landed. What the gate buys is the next dependency: a crate
  that is neither exempted nor covered by an import fails, and the pull
  request adding it has to say why it is trusted. CI runs `--locked` against
  the committed `supply-chain/imports.lock`, so the gate never depends on four
  third-party repositories being reachable. `make vet-update` refreshes the
  lock and prunes exemptions the imports now cover. The gate self-tests first:
  remove one exemption and `cargo vet` must fail.

* **Fuzzing.** A [cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz)
  (libFuzzer) harness in `fuzz/`, smoke-run in CI so it cannot rot, ready to
  point at your parsers and input paths.

* **Unit, integration and documentation tests.** The placeholder API ships
  with all three, plus a mutation canary in the verification suite that
  plants a bug and proves the tests catch it.

* **Code coverage** through
  [cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov), with a line
  coverage floor (`coverage-floor.txt`) enforced by the verification suite
  and the CI job alike, and an optional Codecov dashboard upload when a
  `CODECOV_TOKEN` secret is present.

* **One verification suite.** `make verify` runs every check with a
  pass/fail tally: the toolchain pins, the required-contexts list, workflow
  concurrency, the attribution and prose checks, a release build and tests
  with warnings as errors, line coverage against the floor, clippy, rustdoc,
  Miri, the Kani proofs and the proof canary, cargo-deny, cargo-vet, a fuzz
  smoke run, an executable smoke test, a benchmark smoke run, the release
  size budget and its canary, package purity, the mutation canary and
  rustfmt. The list is at the top of
  [scripts/verify.sh](scripts/verify.sh).

* **CI for Linux, macOS and Windows** as one GitHub Actions matrix, with
  clippy, rustfmt, docs, Miri, Kani, cargo-deny, cargo-vet, fuzz smoke,
  coverage, prose, toolchain-pin, setup self-test and template parity jobs
  alongside. Branch protection requires the checks in
  `.github/required-checks`. A green
  run means the change built on all three platforms and passed every gate.
  CodeQL scans the Rust sources and the workflows. Trivy scans the toolchain
  image for HIGH and CRITICAL CVEs on every pull request and weekly. OpenSSF
  Scorecard watches the supply-chain posture.

* **Releases from tags.** Pushing `v*` builds and tests on Linux, macOS and
  Windows, plus a static musl binary for scratch and distroless containers
  and Alpine, and publishes packaged, debug-info-stripped binaries to a
  GitHub Release with SLSA build provenance attestations and an SPDX SBOM.

* **Docker-first.** A toolchain image pins the compiler (by digest), the
  Miri and fuzzing nightly and every cargo tool the project uses.
  `make shell` opens a development shell in the container.
  `make verify-docker` runs the full suite in it.

* **Prose is linted.** `make prose` runs Vale with the rules in
  `.vale/styles/Abera` over every Markdown file, and the verification
  suite runs the same check.

* **Kept current by Dependabot** on every ecosystem (cargo, the fuzz crate,
  GitHub Actions, Docker), patch and minor grouped, with an auto-merge
  workflow. Staying current costs no attention until a major lands or a
  check goes red.

* **Templates** for README, contributing guidelines, issues and pull
  requests, under the
  [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0), with
  attribution in the NOTICE file.

## Getting started

Generate a repository from this template on GitHub, clone it, then:

```bash
make shell          # toolchain shell: edit on the host, build in the container
```

```bash
make verify-docker  # the full verification suite (what CI runs)
```

`make help` lists the rest (`test`, `miri`, `kani`, `vet`, `fuzz`, `bench`,
`docs`, `prose`).

### Prerequisites

* **Docker**, from [docker.com](https://www.docker.com/)
* **git**

Every tool the project needs is pinned in the [`Dockerfile`](Dockerfile):
the stable Rust, the nightly with Miri, the pinned Kani with its solvers,
clippy, rustfmt, cargo-deny, cargo-llvm-cov and cargo-fuzz. Every developer
and CI build with the same toolchain.

Developing on the host instead needs [rustup](https://rustup.rs) alone. It
reads `rust-toolchain.toml` and installs the pinned toolchain on first use.
The optional tools (`cargo-deny`, `cargo-llvm-cov`, `cargo-fuzz`) install
with `cargo install --locked <tool>`. The verification suite skips their
checks with a `[SKIP]` when they are missing.

## Project layout

```
src/              the library (unit tests inline) and optional binary entry point
tests/            integration tests exercising the public API
benches/          Criterion benchmark harness (`make bench`)
fuzz/             cargo-fuzz (libFuzzer) harness, smoke-run in CI
scripts/          verify.sh / verify-docker.sh / setup.sh and the check-*.sh gates
.vale/            the writing rules (styles/Abera) and their self-test fixtures
Dockerfile        the pinned toolchain image CI and `make shell` share, and the prose linter stage
.github/          CI, CodeQL, Security scan, Audit, Scorecard and Release workflows (SHA-pinned), Dependabot
```

## Development workflow

1. Write a failing test, unit, integration or doc test, whichever layer
   owns the behavior.
2. `make shell` and implement until it passes.
3. `make verify-docker` before pushing. CI gates on the identical suite.
4. When a milestone works, tag it (`git tag v1.2.0 && git push origin
   v1.2.0`) to publish provenance-attested binaries and an SBOM to a GitHub
   Release ([SemVer](http://semver.org/)).

[CONTRIBUTING.md](CONTRIBUTING.md) has the pull-request process.

## Building and testing

Cargo is the build system. The pinned toolchain comes from
`rust-toolchain.toml`:

```bash
cargo build --release
cargo run --release
```

The release profile in `Cargo.toml` is set for runtime performance (LTO,
one codegen unit) with overflow checks retained.

### Dependencies

Add dependencies with `cargo add <crate>`. They resolve against the
committed `Cargo.lock`. Every new dependency must clear the
[cargo-deny](deny.toml) gate: no known vulnerabilities, a license on the
allowlist and crates.io as its source.

## Running the tests

The placeholder API ships with unit tests (in `src/lib.rs`), integration
tests of the public API (`tests/`) and documentation tests (the examples in
the rustdoc comments):

```bash
cargo test
```

Under Miri, the prover, the fuzzer, or the benchmarks:

```bash
make miri      # undefined-behavior detection (pinned nightly, auto-derived)
make kani      # prove the harnesses in src/lib.rs for every input
make vet       # cargo-vet: has anyone read this dependency?
make fuzz      # libFuzzer, 60 seconds of coverage-guided input
make bench     # Criterion benchmarks, report in target/criterion/
```

The full verification suite, with a running pass/fail tally and a final
summary:

```bash
make verify        # or directly: ./scripts/verify.sh
```

The same suite inside the toolchain image, built from the
[`Dockerfile`](Dockerfile) on first run, so results do not depend on the
tools installed on your machine. The source tree is mounted read-only, so
the checkout is never touched:

```bash
make verify-docker # or directly: ./scripts/verify-docker.sh
```

## Generating the documentation

```bash
make docs          # builds rustdoc HTML and opens it in your browser
```

The documentation gate in CI builds with `RUSTDOCFLAGS="-D warnings"`, so
missing documentation on public items and broken intra-doc links fail the
build.

## Where the practices come from

Each source below is wired to a failing check.

* **The Rust API Guidelines** and **Effective Rust.** clippy's `pedantic`
  set plus the configured lints in `Cargo.toml [lints]`, gated in CI,
  warnings as errors.
* **The Rustonomicon** (the semantics `unsafe` code must uphold).
  `unsafe_code = "forbid"` at the compiler level, and the Miri gate
  interpreting the test suite on every PR for the day that changes.
* **The RustSec Advisory Database** and **OpenSSF supply-chain guidance.**
  The `cargo-deny` gate (advisories, licenses, bans, sources), `--locked`
  builds, SHA-pinned actions, digest-pinned base images and Scorecard.
* **ANSSI's Secure Rust Guidelines.** Overflow checks in release,
  `unwrap_used` linted in library code, errors returned instead of panicking
  on untrusted input.
* **Size budgets.** The stripped release binary against a committed byte
  budget ([size-budget.txt](size-budget.txt)), the sibling of the web
  template's bundle budget. Bytes are deterministic on shared runners, so
  this one is a gate, and its canary proves it fails.
* **Fuzzing as standard practice** (cargo-fuzz, libFuzzer). A harness CI
  smoke-runs on every PR, ready for real parsers and input paths.
* **API stability and test honesty as gates.** Releases run
  cargo-semver-checks against the previous tag, so an undeclared breaking
  API change fails the release. Pull requests run cargo-mutants over the
  diff, so changed code nothing tests fails the PR. Release binaries are
  built with cargo-auditable, so `cargo audit bin` can scan shipped
  artifacts for CVEs without their source.

The web template's held-majors check has no counterpart here. It catches a
dependency major Dependabot stays silent about: an npm peer conflict or a
NuGet framework floor. Cargo has no peer ranges and Dependabot does not
consult `rust-version`, so a crate major it offers that needs a newer
toolchain fails the pull request red rather than never arriving. The
`--locked` builds and the MSRV check are where that lands.

Naming, small functions and honest tests (*Code Complete*, *Clean Code*,
*Refactoring*) are what the mutation canary, the test-first workflow and
code review are for.

## After generating from this template

One command renames the crate after your repository (the package name, both
lockfiles, the fuzz crate, every `use` path, the README badge and links,
and NOTICE) and enables the repository settings templates cannot carry
over: secret scanning, push protection, private vulnerability reporting,
Dependabot alerts and security updates, the Update branch button,
auto-merge, and branch protection requiring every CI check.

```bash
./scripts/setup.sh
```

It needs the [GitHub CLI](https://cli.github.com) authenticated as a repo
admin, and it is safe to re-run.

A `CODECOV_TOKEN` repository secret feeds the Codecov dashboard. The token
is optional. The coverage gate is enforced by the verification suite and
the CI job, the upload step skips when the secret is absent, and the
coverage badge reads "unknown" until the token is added.

## License

[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). See
[LICENSE](LICENSE), and keep the [NOTICE](NOTICE) attribution with any
copies.
