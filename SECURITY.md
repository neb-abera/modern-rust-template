# Security Policy

## Supported Versions

Only the latest release (and the default branch) receives security updates.

## Reporting a Vulnerability

Please report vulnerabilities privately via
[GitHub's private vulnerability reporting](../../security/advisories/new)
rather than opening a public issue. You should receive a response within a
week. Please include a proof of concept or reproduction steps where possible.

## Hardening in this template

Projects generated from this template ship with:

* `unsafe_code = "forbid"` — the compiler proves the crate contains no
  unsafe Rust; if a project relaxes it to `deny` with per-site allows, the
  Miri CI gate interprets the test suite and flags undefined behavior,
* integer-overflow checks kept on in release builds
  (`overflow-checks = true` in `Cargo.toml`), so an overflow is a clean
  panic instead of a silent wrap,
* a cargo-deny gate on every pull request: RustSec security advisories,
  license allowlist, duplicate/wildcard bans and a crates.io-only source
  policy (`deny.toml`),
* `--locked` builds everywhere — the committed `Cargo.lock` is the only
  dependency resolution CI will accept,
* CodeQL static analysis of the Rust sources and the workflow files on
  every pull request and weekly,
* GitHub Actions pinned to full commit SHAs and the Docker base image
  pinned to its digest, kept current by Dependabot,
* least-privilege workflow tokens (`contents: read` except where releasing
  requires write),
* releases with SLSA build provenance attestations and an SPDX SBOM,
* a non-root user in the development container.
