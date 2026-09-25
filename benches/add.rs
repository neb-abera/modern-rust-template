//! Criterion benchmark. `make bench` (or `cargo bench`) measures it and
//! writes an HTML report under `target/criterion/`. CI and `make verify`
//! run it once in Criterion's test mode (`cargo test --benches`), which
//! proves it builds and runs and measures nothing. Timing on shared CI
//! runners is noise, so no gate reads a number from it.

use std::hint::black_box;

use criterion::{Criterion, criterion_group, criterion_main};

fn bench_add(c: &mut Criterion) {
    c.bench_function("add", |b| {
        b.iter(|| project::add(black_box(1), black_box(2)));
    });
}

criterion_group!(benches, bench_add);
criterion_main!(benches);
