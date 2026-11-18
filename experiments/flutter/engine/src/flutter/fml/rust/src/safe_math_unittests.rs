// Port of flutter/fml/safe_math_unittests.cc.

use super::safe_math::SafeMath;

#[test]
fn multiply_size_t() {
    // Multiplication with no overflow.
    let mut safe1 = SafeMath::new();
    assert_eq!(safe1.mul(1000, 2000), 2000000);
    assert!(!safe1.overflow_detected());

    // Overflow detection when multiplying size_t values at or near the maximum.
    let mut safe2 = SafeMath::new();
    safe2.mul(usize::MAX, usize::MAX);
    assert!(safe2.overflow_detected());

    let mut safe3 = SafeMath::new();
    safe3.mul(usize::MAX >> 2, 5);
    assert!(safe3.overflow_detected());

    // Overflow detection for a result that slightly exceeds the range of a
    // uint64_t.
    if std::mem::size_of::<usize>() == std::mem::size_of::<u64>() {
        let mut safe4 = SafeMath::new();
        safe4.mul(1usize << 32, 1usize << 32);
        assert!(safe4.overflow_detected());
    }
}
