[![Actions Status](https://github.com/neb-abera/modern-rust-template/workflows/CI/badge.svg)](https://github.com/neb-abera/modern-rust-template/actions)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/neb-abera/modern-rust-template/badge)](https://scorecard.dev/viewer/?uri=github.com/neb-abera/modern-rust-template)

# Modern Rust Template

A template for modern Rust projects, aimed to be an easy to use starting
point that is highly performant, secure by design and works out of the box —
the Rust sibling of
[modern-cpp-template](https://github.com/neb-abera/modern-cpp-template).

## Features

* **A pinned toolchain everywhere** — `rust-toolchain.toml` pins the exact
stable compiler and rustup installs it automatically on every machine and CI
runner; the Docker toolchain image and the crate's declared MSRV are held in
lockstep with it by a CI gate (`scripts/check-toolchain.sh`), so the three
can never drift apart silently,

* **Performance defaults** — release builds use whole-program LTO and a
single codegen unit, and a **Criterion benchmark harness** (`benches/`,
`make bench`) is wired in so performance work starts with measurements, not
guesses,

* **Secure by design** — `unsafe_code = "forbid"`, integer-overflow checks
kept on in release builds, panicking `unwrap` linted against in library
code, and placeholder code that models returning errors instead of crashing
on untrusted input,

* **Static analysis as a gate** — **clippy** with the pedantic set (the
Rust API Guidelines material) configured once in `Cargo.toml [lints]` and
applied identically in editors, locally and in CI; warnings are promoted to
errors on every merge,

* **Miri** — the test suite runs under the
[Miri](https://github.com/rust-lang/miri) interpreter on every pull
request, flagging undefined behavior the moment any `unsafe` enters the
project,

* **Supply-chain gate** — [cargo-deny](https://github.com/EmbarkStudios/cargo-deny)
checks every pull request for RustSec advisories, license-allowlist
violations, duplicate crates and non-crates.io sources (`deny.toml`), with
`--locked` builds everywhere so the committed `Cargo.lock` is the only
resolution CI accepts — plus a **weekly scheduled audit** that re-checks
advisories against the lockfile and the latest release binary (`cargo
audit bin`, via the embedded cargo-auditable data) and fails when the
pinned Miri/fuzzing nightly grows stale,

* **Fuzzing** — a [cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz)
(libFuzzer) harness in `fuzz/`, smoke-run in CI so it can never rot, ready
to point at your parsers and input paths,

* **Unit, integration and documentation tests** — the placeholder API ships
with all three, plus a **mutation canary** in the verification suite that
plants a bug and proves the tests catch it,

* **Code coverage** via
[cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov), with a line
coverage threshold enforced in the CI job itself (no external service
required) and an optional *Codecov* dashboard upload when a
`CODECOV_TOKEN` secret is present,

* **CI for Linux, macOS and Windows** as a single matrix using *GitHub
Actions* — with clippy, rustfmt, docs, Miri, cargo-deny, fuzz-smoke,
coverage and toolchain-pin jobs alongside, so a green run means the change
built cleanly on all three platforms and passed every gate before it can
merge. **CodeQL** scans the Rust sources and the workflows themselves;
**OpenSSF Scorecard** watches the supply-chain posture,

* **An automated release workflow** — pushing a `v*` tag builds and tests
on all three platforms and publishes packaged binaries to a GitHub Release
with **SLSA build provenance attestations** and an **SPDX SBOM**,

* **Dockerized development environment** — a toolchain image pinning the
compiler (by digest), the Miri/fuzzing nightly and every cargo tool the
project uses, with `make shell` for day-to-day development inside the
container and `make verify-docker` for a full host-independent verification
run,

* **Dependabot on every ecosystem** (cargo, the fuzz crate, GitHub Actions,
Docker) with patch/minor updates grouped and an auto-merge workflow, so
staying current costs no attention until a major lands or a check goes red,

* **.md templates** for *README*, *Contributing Guidelines*, *Issues* and
*Pull Requests*, and a **permissive license** — the template is licensed under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0), with
attribution traveling in the NOTICE file.

## Getting started

Generate a repository from this template on GitHub, clone it, then:

```bash
make shell          # toolchain shell: edit on the host, build in the container
```

```bash
make verify-docker  # the full verification suite (what CI runs)
```

`make help` lists everything else (`test`, `miri`, `fuzz`, `bench`, `docs`).

### Prerequisites

**The intended development environment is the project's Docker container.**
Every tool the project needs — the pinned stable Rust, the pinned nightly
with Miri, clippy, rustfmt, cargo-deny, cargo-llvm-cov and cargo-fuzz — is
pinned in the [`Dockerfile`](Dockerfile), so every developer (and CI) builds
with the same toolchain and "works on my machine" dependency drift between
workstations and deployment servers disappears. For that workflow you only
need:

* **Docker** - found at [https://www.docker.com/](https://www.docker.com/)
* **git**

If you prefer to develop directly on your machine instead, you only need
[**rustup**](https://rustup.rs) — it reads `rust-toolchain.toml` and
installs the pinned toolchain automatically on first use. The optional
tools (`cargo-deny`, `cargo-llvm-cov`, `cargo-fuzz`) install with
`cargo install --locked <tool>`; the verification suite skips their checks
with a `[SKIP]` when they are missing rather than failing.

## Project layout

```
src/              the library (unit tests inline) and optional binary entry point
tests/            integration tests exercising the public API
benches/          Criterion benchmark harness (`make bench`)
fuzz/             cargo-fuzz (libFuzzer) harness, smoke-run in CI
scripts/          verify.sh / verify-docker.sh / setup.sh and the check-*.sh gates
Dockerfile        the pinned toolchain image CI and `make shell` share
.github/          CI, CodeQL, Audit, Scorecard and Release workflows (SHA-pinned), Dependabot
```

## Development workflow

1. Write a failing test — unit, integration or doc test, whichever layer
   owns the behavior.
2. `make shell` and implement until it passes.
3. `make verify-docker` before pushing — CI gates on the identical suite, so
   a local green run predicts the PR gate.
4. When a milestone is confirmed working, tag it (`git tag v1.2.0 && git
   push origin v1.2.0`) to publish provenance-attested binaries and an SBOM
   to a GitHub Release ([SemVer](http://semver.org/)).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the pull-request process.

## Building and testing

Cargo is the build system; the pinned toolchain comes from
`rust-toolchain.toml` automatically:

```bash
cargo build --release
cargo run --release
```

The release profile is configured in `Cargo.toml` for maximum runtime
performance (LTO, one codegen unit) with overflow checks retained.

### Dependencies

Add dependencies with `cargo add <crate>` (they resolve against the
committed `Cargo.lock`). Every new dependency must clear the
[cargo-deny](deny.toml) gate: no known vulnerabilities, a license on the
allowlist and crates.io as its source.

## Running the tests

The placeholder API ships with unit tests (in `src/lib.rs`), integration
tests exercising the public API (`tests/`) and documentation tests (the
examples in the rustdoc comments):

```bash
cargo test
```

To run the tests under Miri, or the fuzzer, or the benchmarks:

```bash
make miri      # undefined-behavior detection (pinned nightly, auto-derived)
make fuzz      # libFuzzer, 60 seconds of coverage-guided input
make bench     # Criterion benchmarks, report in target/criterion/
```

To run the **full verification suite** — toolchain-pin consistency, the
required-checks list in `scripts/setup.sh` matching the CI job names, a
clean release build with warnings-as-errors and the full test suite,
clippy, the rustdoc gate, Miri, cargo-deny, a fuzz smoke run, an executable
smoke test, package purity, a mutation canary proving the tests catch
planted bugs, and a rustfmt check — with a running pass/fail tally and a
final summary:

```bash
make verify        # or directly: ./scripts/verify.sh
```

To run the same suite **inside a Docker container** — so results do not
depend on the toolchains or cargo tools installed on your machine — use the
project's toolchain image (built automatically from the
[`Dockerfile`](Dockerfile) on first run; the source tree is mounted
read-only, so your checkout is never touched):

```bash
make verify-docker # or directly: ./scripts/verify-docker.sh
```

## Generating the documentation

```bash
make docs          # builds rustdoc HTML and opens it in your browser
```

The documentation gate in CI builds with `RUSTDOCFLAGS="-D warnings"`, so
missing documentation on public items and broken intra-doc links fail the
build rather than accumulating.

## Where the practices come from

The canon this template enforces, and the gate that enforces it — advice
that is not a failing check decays, so each source is wired to one:

* **The Rust API Guidelines** and **Effective Rust** — clippy's `pedantic`
  set plus the configured lints in `Cargo.toml [lints]`, gated in CI,
  warnings as errors,
* **The Rustonomicon** (the semantics `unsafe` code must uphold) —
  `unsafe_code = "forbid"` at the compiler level, and the **Miri** gate
  interpreting the test suite on every PR for the day that changes,
* **The RustSec Advisory Database** and **OpenSSF supply-chain
  guidance** — the `cargo-deny` gate (advisories, licenses, bans,
  sources), `--locked` builds, SHA-pinned actions, digest-pinned base
  images and Scorecard,
* **ANSSI's Secure Rust Guidelines** — overflow checks in release,
  `unwrap_used` linted in library code, errors returned instead of
  panicking on untrusted input,
* **fuzzing as standard practice** (cargo-fuzz/libFuzzer) — a harness CI
  smoke-runs on every PR, ready for real parsers and input paths,
* **API stability and test honesty as gates** — releases run
  **cargo-semver-checks** against the previous tag (undeclared breaking API
  changes fail the release), pull requests run **cargo-mutants** over the
  diff (changed code nothing tests fails the PR), and release binaries are
  built with **cargo-auditable** so `cargo audit bin` can scan shipped
  artifacts for CVEs without their source.

What a linter cannot check — naming things well, small functions, honest
tests (*Code Complete*, *Clean Code*, *Refactoring*) — is what the mutation
canary, the test-first workflow and code review are for.

## After generating from this template

One command finishes the setup — it
renames the crate after your repository (the package name, both lockfiles,
the fuzz crate, every `use` path and the README badge/links) and enables
the repo-level GitHub settings templates cannot carry over (secret
scanning, push protection, private vulnerability reporting, Dependabot
alerts + security updates, and branch protection requiring the sixteen CI
checks):

```bash
./scripts/setup.sh
```

It needs the [GitHub CLI](https://cli.github.com) authenticated as a repo
admin, and it is safe to re-run.

Optionally, add a `CODECOV_TOKEN` repository secret to feed the Codecov
dashboard. The token is not required: the coverage gate itself is enforced
inside the CI job, and the upload step simply skips when the secret is
absent.

## License

This project is licensed under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) — see the
[LICENSE](LICENSE) file. Keep the [NOTICE](NOTICE) file's attribution with
any copies.
