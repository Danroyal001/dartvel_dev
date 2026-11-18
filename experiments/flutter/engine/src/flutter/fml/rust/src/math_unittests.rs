// Port of flutter/fml/math_unittests.cc.

use super::math::*;

fn expect_float_eq(a: f32, b: f32) {
    // gtest's EXPECT_FLOAT_EQ: within 4 ULPs.
    let ulps = (a.to_bits() as i64 - b.to_bits() as i64).abs();
    assert!(ulps <= 4, "{a} vs {b}");
}

#[test]
fn constants() {
    // Don't use the constants in cmath as those aren't portable.
    expect_float_eq(kE.log2(), kLog2E);
    expect_float_eq(kE.log10(), kLog10E);
    expect_float_eq(2.0f32.ln(), kLogE2);
    expect_float_eq(kPi / 2.0, kPiOver2);
    expect_float_eq(kPi / 4.0, kPiOver4);
    expect_float_eq(1.0 / kPi, k1OverPi);
    expect_float_eq(2.0 / kPi, k2OverPi);
    expect_float_eq(2.0f32.sqrt(), kSqrt2);
    expect_float_eq(1.0 / 2.0f32.sqrt(), k1OverSqrt2);
}
