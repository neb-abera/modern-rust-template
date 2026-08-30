//! Fuzz target: proves `add` never panics — not even on overflow — for any
//! pair of inputs. In a real project, point targets like this at your
//! parsers and every function that touches untrusted input.

#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|pair: (i64, i64)| {
    let _ = project::add(pair.0, pair.1);
});
