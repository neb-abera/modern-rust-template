//! A template library crate.
//!
//! Replace this module documentation with a description of your project.
//! The `add` function below is placeholder code demonstrating the shape a
//! real API should take here: documented, with a doctest, unit tests, an
//! integration test entry point (`tests/`), a benchmark (`benches/`) and a
//! fuzz target (`fuzz/`) all exercising it.

/// Adds two integers, returning `None` if the sum would overflow.
///
/// Overflow is reported to the caller rather than wrapping silently or
/// panicking, so untrusted inputs cannot take the program down.
///
/// # Examples
///
/// ```
/// assert_eq!(project::add(1, 2), Some(3));
/// assert_eq!(project::add(i64::MAX, 1), None);
/// ```
#[must_use]
pub fn add(lhs: i64, rhs: i64) -> Option<i64> {
    lhs.checked_add(rhs)
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds_small_numbers() {
        assert_eq!(add(1, 2), Some(3));
    }

    #[test]
    fn adds_negative_numbers() {
        assert_eq!(add(-2, -3), Some(-5));
    }

    #[test]
    fn reports_overflow_instead_of_wrapping() {
        assert_eq!(add(i64::MAX, 1), None);
        assert_eq!(add(i64::MIN, -1), None);
    }
}
