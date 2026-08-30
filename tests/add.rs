//! Integration tests: exercise the crate exactly as a downstream user
//! would, through its public API only. This is where TDD starts for
//! library changes — write the failing test here first.

#[test]
fn public_api_adds() {
    assert_eq!(project::add(2, 2), Some(4));
}

#[test]
fn public_api_reports_overflow() {
    assert_eq!(project::add(i64::MAX, i64::MAX), None);
}
