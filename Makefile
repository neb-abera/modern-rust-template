.PHONY: test lint format docs coverage miri kani vet vet-update fuzz bench verify verify-docker setup-self-test shell install prose help
.DEFAULT_GOAL := help

define PRINT_HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
	match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
	if match:
		target, help = match.groups()
		print("%-20s %s" % (target, help))
endef
export PRINT_HELP_PYSCRIPT

# Docker image/container names derive from the checkout directory, so
# projects generated from this template need no edits here.
IMAGE := $(shell basename "$(CURDIR)" | tr '[:upper:]' '[:lower:]')
# `make shell` runs as the user who owns the checkout. The image's own user
# (uid 1000) can neither read a tree left at rw-rw---- by a umask of 007 nor
# leave behind files the owner can delete. HOME points somewhere writable,
# and KANI_HOME at the Kani bundle the image installed under that user.
HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)
export HOST_UID
export HOST_GID
# The pinned nightly (Miri, fuzzing) is derived from the Dockerfile, the
# single place it is written down.
NIGHTLY := $(shell sed -n 's/^ENV NIGHTLY_TOOLCHAIN=\(.*\)$$/\1/p' Dockerfile)

help:
	@python3 -c "$$PRINT_HELP_PYSCRIPT" < $(MAKEFILE_LIST)

test: ## build and run the full test suite (unit, integration, doc)
	cargo test --locked

lint: ## run clippy over every target with the configured lint set
	cargo clippy --all-targets --locked

format: ## format the project sources
	cargo fmt

docs: ## build and open the API documentation
	cargo doc --no-deps --lib --open

coverage: ## measure test coverage with cargo-llvm-cov
	cargo llvm-cov --locked

miri: ## run the test suite under Miri (undefined-behavior detection)
	cargo +$(NIGHTLY) miri test --locked

# Kani is a rustc driver with its own sysroot, so RUSTFLAGS is cleared here
# for the same reason it is for Miri.
kani: ## prove the #[kani::proof] harnesses in src/lib.rs for every input
	env -u RUSTFLAGS cargo kani

vet: ## cargo-vet: has anyone read this dependency? (reads imports.lock)
	./scripts/check-vet.sh --self-test
	./scripts/check-vet.sh

# Fetches the four third-party audit files, rewrites imports.lock and drops
# any exemption the refreshed imports now cover. Review the diff: it changes
# what the gate accepts.
vet-update: ## refresh supply-chain/imports.lock and prune covered exemptions
	cargo vet regenerate imports
	cargo vet prune
	cargo vet

# The fuzz target triple is passed explicitly: a prebuilt cargo-fuzz binary
# otherwise defaults to the triple *it* was compiled for (often musl).
fuzz: ## fuzz the libFuzzer target for 60 seconds (Ctrl-C safe)
	cargo +$(NIGHTLY) fuzz run add --target "$$(rustc +$(NIGHTLY) -vV | sed -n 's/^host: //p')" -- -max_total_time=60

bench: ## run the Criterion benchmarks (report in target/criterion/)
	cargo bench

verify: ## run the full verification suite with a pass/fail tally
	./scripts/verify.sh

verify-docker: ## run the full verification suite inside the Docker toolchain image
	./scripts/verify-docker.sh

setup-self-test: ## run scripts/setup.sh on a copy under a fake name, then build and test it
	./scripts/setup.sh --self-test

shell: ## open a development shell inside the Docker toolchain image
	docker build -t $(IMAGE):latest .
	docker rm -f $(IMAGE)-dev 2>/dev/null || true
	docker run --rm -it --name $(IMAGE)-dev --user $(HOST_UID):$(HOST_GID) \
		-e HOME=/tmp -e KANI_HOME=/home/dev/.kani \
		-v $(CURDIR):/work -w /work $(IMAGE):latest bash

install: ## install the release binary into ~/.cargo/bin
	cargo install --path . --locked

prose: ## lint every tracked Markdown file against the writing rules (.vale/styles/Abera)
	./scripts/check-prose.sh --self-test
	./scripts/check-prose.sh
