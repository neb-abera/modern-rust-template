//! Criterion benchmark. `make bench` (or `cargo bench`) runs it and writes
//! an HTML report under `target/criterion/`. Benchmarks are compiled by CI
//! (so they cannot rot) but only run on demand — timing in shared CI
//! runners is noise.

use std::hint::black_box;

use criterion::{Criterion, criterion_group, criterion_main};

fn bench_add(c: &mut Criterion) {
    c.bench_function("add", |b| {
        b.iter(|| project::add(black_box(1), black_box(2)));
    });
}

criterion_group!(benches, bench_add);
criterion_main!(benches);
