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

// Proof harnesses, compiled only under `cargo kani` (the `kani` cfg is set by
// the Kani driver, not by cargo, so nothing here affects a normal build).
//
// The difference between this module and the `tests` module above is the
// quantifier. `adds_small_numbers` checks one pair. `add_matches_wider_oracle`
// checks all 2^128 pairs, by handing the property to an SMT solver instead of
// running the function. Kani also proves the absence of panics, arithmetic
// overflow and out-of-bounds indexing on every path the harness reaches, which
// is why a harness with no explicit assertion is still worth writing.
//
// Cost on this crate is milliseconds. On a real API it grows with the state
// space, and `kani::assume` is how you bound it: an assumption narrows the
// inputs the solver considers, so an over-strong one makes the proof vacuous.
// The canary in scripts/verify.sh exists to catch exactly that.
#[cfg(kani)]
mod proofs {
    use super::add;

    /// `add` is total: no input pair panics, overflows or aborts.
    ///
    /// Nothing is asserted. Kani inserts a check at every operation that could
    /// fail and proves each unreachable, so the harness body is the whole
    /// specification.
    #[kani::proof]
    fn add_never_panics() {
        let _ = add(kani::any(), kani::any());
    }

    /// `add` agrees with exact arithmetic in a wider type, for every input.
    ///
    /// `i128` is the oracle: the true sum always fits it, so the property is
    /// "return `Some(sum)` when the sum is representable in `i64`, and `None`
    /// exactly otherwise". This is functional correctness, not just absence of
    /// panics, and it is the property the four unit tests sample at four
    /// points.
    #[kani::proof]
    fn add_matches_wider_oracle() {
        let lhs: i64 = kani::any();
        let rhs: i64 = kani::any();
        let exact = i128::from(lhs) + i128::from(rhs);
        let fits = exact >= i128::from(i64::MIN) && exact <= i128::from(i64::MAX);

        match add(lhs, rhs) {
            Some(sum) => {
                assert!(fits, "returned Some for a sum that does not fit i64");
                assert!(i128::from(sum) == exact, "returned the wrong sum");
            }
            None => assert!(!fits, "returned None for a sum that fits i64"),
        }
    }

    /// `add` is commutative, including on the overflow paths.
    #[kani::proof]
    fn add_is_commutative() {
        let lhs: i64 = kani::any();
        let rhs: i64 = kani::any();
        assert!(add(lhs, rhs) == add(rhs, lhs));
    }
}
