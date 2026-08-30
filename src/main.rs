//! Executable entry point. Delete this file (and the smoke-test step in
//! `scripts/verify.sh`) if your project is a library only; delete
//! `src/lib.rs` and inline the code here if it is a binary only.

fn main() {
    // 1 + 2 cannot overflow, so the None arm is unreachable; expect() here
    // documents that reasoning rather than hiding an error path.
    let sum = project::add(1, 2).expect("1 + 2 does not overflow");
    println!("1 + 2 = {sum}");
}
