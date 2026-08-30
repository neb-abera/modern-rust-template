# Toolchain image: every compiler and tool the project uses, pinned, so
# every developer and CI build with the same versions. `make shell` opens a
# development shell in it; `make verify-docker` runs the full verification
# suite in it.
#
# The base image tag must match the channel in rust-toolchain.toml and the
# rust-version in Cargo.toml — scripts/check-toolchain.sh (a verify.sh and
# CI gate) enforces the pairing, and Dependabot updates the digest.
FROM rust:1.98.0-slim@sha256:17d1ba895198f9934c6314ec5346a0d5115372f3243390c3d731e242f35c2f27

# The pinned nightly toolchain, used only where stable cannot go: Miri
# (undefined-behavior detection) and cargo-fuzz (libFuzzer). Scripts and CI
# derive the value from this line rather than repeating it.
ENV NIGHTLY_TOOLCHAIN=nightly-2026-08-25

# git for version control inside the container and g++ for libfuzzer-sys'
# C++ runtime; the rest of the build essentials (gcc, libc headers) ship
# with the base image.
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        git \
        g++ \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Run as a non-root user. The base image leaves RUSTUP_HOME and CARGO_HOME
# world-writable precisely so toolchains and tools can be managed without
# root.
RUN useradd --create-home --uid 1000 dev
USER dev
WORKDIR /home/dev

# Stable components beyond the defaults: llvm-tools for cargo-llvm-cov.
RUN rustup component add clippy rustfmt llvm-tools

# Nightly toolchain with Miri and the rust-src Miri needs to build its
# sysroot. The sysroot itself is deliberately NOT pre-built here: a
# sysroot cached at image-build time records different settings than a
# run-time build and Miri then refuses to use it, so the first `make miri`
# in a fresh container builds it once (~1 minute) instead.
RUN rustup toolchain install "$NIGHTLY_TOOLCHAIN" --profile minimal \
        --component miri --component rust-src

# Cargo subcommand tools, installed as prebuilt release binaries via
# cargo-binstall (which is itself built from source, from crates.io):
#   cargo-deny     — supply-chain gate: advisories, licenses, bans, sources
#   cargo-llvm-cov — code coverage
#   cargo-fuzz     — libFuzzer front end
RUN cargo install --locked cargo-binstall && \
    cargo binstall -y cargo-deny cargo-llvm-cov cargo-fuzz && \
    rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"
