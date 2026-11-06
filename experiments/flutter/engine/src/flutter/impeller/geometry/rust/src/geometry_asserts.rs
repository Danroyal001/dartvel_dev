// flutter/impeller/geometry/geometry_asserts.h, plus the gtest assertions
// the ported tests use.
//
// gtest's EXPECT_*/ASSERT_* become the `expect_*!` macros below (an ASSERT
// stops the test where an EXPECT would continue; both panic here, which
// stops it). `expect_eq!` compares as C++'s `==` does, converting mixed
// arithmetic operands to their common type (`EXPECT_EQ(rect.GetLeft(), 80)`).

#![cfg(test)]

use crate::color::Color;
use crate::cxx::{Kind, Num};
use crate::matrix::Matrix;
use crate::point::Point;
use crate::quaternion::Quaternion;
use crate::rect::Rect;
use crate::size::Size;
use crate::vector::{Vector3, Vector4};

/// `a == b` as C++ evaluates it.
pub trait TestEq<Rhs: ?Sized = Self> {
    fn test_eq(&self, other: &Rhs) -> bool;
}

macro_rules! same_eq {
    ($($t:ty),*) => {$(
        impl TestEq for $t {
            fn test_eq(&self, other: &$t) -> bool { self == other }
        }
    )*};
}

macro_rules! num_eq {
    ($($a:ty),*) => {
        num_eq!(@outer [$($a),*] [$($a),*]);
    };
    (@outer [$($a:ty),*] $b:tt) => {
        $( num_eq!(@inner $a $b); )*
    };
    (@inner $a:ty [$($b:ty),*]) => {
        $(
            impl TestEq<$b> for $a {
                fn test_eq(&self, other: &$b) -> bool {
                    match Kind::common(<$a as Num>::KIND, <$b as Num>::KIND) {
                        Kind::F64 => self.to_f64() == other.to_f64(),
                        Kind::F32 => self.to_f32() == other.to_f32(),
                        k => k.wrap(self.to_i128()) == k.wrap(other.to_i128()),
                    }
                }
            }
        )*
    };
}
num_eq!(f32, f64, i8, i16, i32, i64, u8, u16, u32, u64);

impl TestEq<usize> for usize {
    fn test_eq(&self, other: &usize) -> bool {
        self == other
    }
}
impl TestEq<i32> for usize {
    fn test_eq(&self, other: &i32) -> bool {
        *self as u64 == *other as u64
    }
}
impl TestEq<u32> for usize {
    fn test_eq(&self, other: &u32) -> bool {
        *self as u64 == *other as u64
    }
}

same_eq!(bool, String);

impl TestEq for str {
    fn test_eq(&self, other: &str) -> bool {
        self == other
    }
}

impl TestEq<&str> for str {
    fn test_eq(&self, other: &&str) -> bool {
        self == *other
    }
}

impl TestEq<&str> for String {
    fn test_eq(&self, other: &&str) -> bool {
        self == other
    }
}

/// A reference compares as what it refers to.
impl<T: TestEq<U> + ?Sized, U> TestEq<U> for &T {
    fn test_eq(&self, other: &U) -> bool {
        (**self).test_eq(other)
    }
}

impl<T: TestEq<U>, U> TestEq<Option<U>> for Option<T> {
    fn test_eq(&self, other: &Option<U>) -> bool {
        match (self, other) {
            (Some(a), Some(b)) => a.test_eq(b),
            (None, None) => true,
            _ => false,
        }
    }
}

impl<T: TestEq<U>, U, const N: usize> TestEq<[U; N]> for [T; N] {
    fn test_eq(&self, other: &[U; N]) -> bool {
        self.iter().zip(other.iter()).all(|(a, b)| a.test_eq(b))
    }
}

impl<T: TestEq<U>, U> TestEq<Vec<U>> for Vec<T> {
    fn test_eq(&self, other: &Vec<U>) -> bool {
        self.len() == other.len() && self.iter().zip(other.iter()).all(|(a, b)| a.test_eq(b))
    }
}

/// Every other type compares with its own `operator==`.
macro_rules! partial_eq {
    ($($t:ty),*) => {$(
        impl TestEq for $t {
            fn test_eq(&self, other: &$t) -> bool { self == other }
        }
    )*};
}
partial_eq!(
    crate::point::TPoint<f32>,
    crate::point::TPoint<i64>,
    crate::point::TPoint<i32>,
    crate::point::TPoint<u32>,
    crate::size::TSize<f32>,
    crate::size::TSize<i64>,
    crate::size::TSize<i32>,
    crate::rect::TRect<f32>,
    crate::rect::TRect<i64>,
    crate::rect::TRect<i32>,
    crate::matrix::Matrix,
    crate::vector::Vector3,
    crate::vector::Vector4,
    crate::color::Color,
    crate::color::BlendMode,
    crate::quaternion::Quaternion,
    crate::scalar::Degrees,
    crate::scalar::Radians,
    crate::rational::Rational,
    crate::rounding_radii::RoundingRadii,
    crate::round_rect::RoundRect,
    crate::round_superellipse::RoundSuperellipse,
    crate::rstransform::RSTransform,
    crate::half::Half,
    crate::half::HalfVector2,
    crate::half::HalfVector3,
    crate::half::HalfVector4,
    crate::path_source::FillType,
    crate::arc::Quadrant,
    crate::sigma::Sigma,
    crate::sigma::Radius,
    crate::shear::Shear
);

#[macro_export]
#[doc(hidden)]
macro_rules! expect_eq {
    ($a:expr, $b:expr $(,)?) => {{
        let (a, b) = (&$a, &$b);
        assert!(
            $crate::geometry_asserts::TestEq::test_eq(a, b),
            "expected {} == {}\n  left: {:?}\n right: {:?}",
            stringify!($a),
            stringify!($b),
            a,
            b
        );
    }};
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_ne {
    ($a:expr, $b:expr $(,)?) => {{
        let (a, b) = (&$a, &$b);
        assert!(
            !$crate::geometry_asserts::TestEq::test_eq(a, b),
            "expected {} != {}\n  left: {:?}\n right: {:?}",
            stringify!($a),
            stringify!($b),
            a,
            b
        );
    }};
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_true {
    ($a:expr $(,)?) => {
        assert!($a, "expected {} to be true", stringify!($a))
    };
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_false {
    ($a:expr $(,)?) => {
        assert!(!($a), "expected {} to be false", stringify!($a))
    };
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_lt {
    ($a:expr, $b:expr $(,)?) => {
        assert!($a < $b, "expected {} < {}: {:?} {:?}", stringify!($a), stringify!($b), $a, $b)
    };
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_gt {
    ($a:expr, $b:expr $(,)?) => {
        assert!($a > $b, "expected {} > {}: {:?} {:?}", stringify!($a), stringify!($b), $a, $b)
    };
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_ge {
    ($a:expr, $b:expr $(,)?) => {
        assert!($a >= $b, "expected {} >= {}: {:?} {:?}", stringify!($a), stringify!($b), $a, $b)
    };
}

/// gtest's `EXPECT_FLOAT_EQ`: within 4 units in the last place.
pub fn float_eq(a: f32, b: f32) -> bool {
    if a.is_nan() || b.is_nan() {
        return false;
    }
    fn biased(f: f32) -> u32 {
        let bits = f.to_bits();
        if bits & 0x8000_0000 != 0 { (!bits).wrapping_add(1) } else { bits | 0x8000_0000 }
    }
    let (x, y) = (biased(a), biased(b));
    (if x >= y { x - y } else { y - x }) <= 4
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_float_eq {
    ($a:expr, $b:expr $(,)?) => {{
        let (a, b): (f32, f32) = ($a as f32, $b as f32);
        assert!(
            $crate::geometry_asserts::float_eq(a, b),
            "expected {} ~= {}: {:?} {:?}",
            stringify!($a),
            stringify!($b),
            a,
            b
        );
    }};
}

#[macro_export]
#[doc(hidden)]
macro_rules! expect_near {
    ($a:expr, $b:expr, $e:expr $(,)?) => {{
        let (a, b, e): (f64, f64, f64) = ($a as f64, $b as f64, $e as f64);
        assert!((a - b).abs() <= e, "expected |{} - {}| <= {}: {} {}", stringify!($a), stringify!($b), e, a, b);
    }};
}

/// `std::nexttowardf(x, y)`.
fn nexttowardf(x: f32, y: f64) -> f32 {
    if x.is_nan() || y.is_nan() {
        return (x as f64 + y) as f32;
    }
    if x as f64 == y {
        return y as f32;
    }
    if x == 0.0 {
        let tiny = f32::from_bits(1);
        return if y > 0.0 { tiny } else { -tiny };
    }
    let bits = x.to_bits();
    let up = (y > x as f64) == (x > 0.0);
    f32::from_bits(if up { bits + 1 } else { bits - 1 })
}

pub fn number_near(a: f64, b: f64) -> bool {
    if a == b {
        return true;
    }
    if a.is_nan() || b.is_nan() {
        return false;
    }

    // We used to compare based on an absolute difference of 1e-3 which would
    // allow up to 10 bits of mantissa difference in a float (leaving 14 bits
    // of accuracy being tested). Some of our tests began failing, though,
    // when using FMA instructions. This test accepts up to 32 ULPs.
    const kImpellerTestingMaxULP: f32 = 32.0;
    // Some of the tests compute values near 0, so we need a tiny step.
    const kMinimumULPStep: f32 = 1.0 / (1 << 24) as f32;

    let adjust_step =
        |v: f32| -> f32 { if v.abs() < kMinimumULPStep { kMinimumULPStep.copysign(v) } else { v } };

    let step_ab = adjust_step((a - nexttowardf(a as f32, b) as f64) as f32);
    let step_ba = adjust_step((b - nexttowardf(b as f32, a) as f64) as f32);

    let ab_ulps = ((a - b) / step_ab as f64) as f32;
    let ba_ulps = ((b - a) / step_ba as f64) as f32;
    assert!(ab_ulps >= 0.0 && ba_ulps >= 0.0, "Check failed: ab_ulps >= 0 && ba_ulps >= 0");

    crate::cxx::min(ab_ulps, ba_ulps) < kImpellerTestingMaxULP
}

pub fn matrix_near(a: Matrix, b: Matrix) -> bool {
    (0..16).all(|i| number_near(a.m[i] as f64, b.m[i] as f64))
}

pub fn quaternion_near(a: Quaternion, b: Quaternion) -> bool {
    number_near(a.x as f64, b.x as f64)
        && number_near(a.y as f64, b.y as f64)
        && number_near(a.z as f64, b.z as f64)
        && number_near(a.w as f64, b.w as f64)
}

pub fn rect_near(a: Rect, b: Rect) -> bool {
    number_near(a.get_left() as f64, b.get_left() as f64)
        && number_near(a.get_top() as f64, b.get_top() as f64)
        && number_near(a.get_right() as f64, b.get_right() as f64)
        && number_near(a.get_bottom() as f64, b.get_bottom() as f64)
}

pub fn color_near(a: Color, b: Color) -> bool {
    number_near(a.red as f64, b.red as f64)
        && number_near(a.green as f64, b.green as f64)
        && number_near(a.blue as f64, b.blue as f64)
        && number_near(a.alpha as f64, b.alpha as f64)
}

pub fn point_near(a: Point, b: Point) -> bool {
    number_near(a.x as f64, b.x as f64) && number_near(a.y as f64, b.y as f64)
}

pub fn vector3_near(a: Vector3, b: Vector3) -> bool {
    number_near(a.x as f64, b.x as f64)
        && number_near(a.y as f64, b.y as f64)
        && number_near(a.z as f64, b.z as f64)
}

pub fn vector4_near(a: Vector4, b: Vector4) -> bool {
    number_near(a.x as f64, b.x as f64)
        && number_near(a.y as f64, b.y as f64)
        && number_near(a.z as f64, b.z as f64)
        && number_near(a.w as f64, b.w as f64)
}

pub fn size_near(a: Size, b: Size) -> bool {
    number_near(a.width as f64, b.width as f64) && number_near(a.height as f64, b.height as f64)
}

pub fn array4_near(a: [u8; 4], b: [u8; 4]) -> bool {
    (0..4).all(|i| number_near(a[i] as f64, b[i] as f64))
}

/// Upstream's ColorBufferNear builds a failure for unequal colors and
/// discards it, so only a length mismatch fails (kept).
pub fn color_buffer_near(a: Vec<u8>, b: Vec<Color>) -> bool {
    if a.len() != b.len() * 4 {
        return false;
    }
    true
}

/// Upstream's ColorsNear discards its per-color failures too (kept).
pub fn colors_near(a: Vec<Color>, b: Vec<Color>) -> bool {
    a.len() == b.len()
}

/// `ASSERT_PRED2(&::Pred, a, b)`.
#[macro_export]
#[doc(hidden)]
macro_rules! expect_pred2 {
    ($f:ident, $a:expr, $b:expr) => {{
        let (a, b) = ($a, $b);
        assert!(
            $crate::geometry_asserts::$f(a.clone(), b.clone()),
            "{}({}, {}) failed: {:?} vs {:?}",
            stringify!($f),
            stringify!($a),
            stringify!($b),
            a,
            b
        );
    }};
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_matrix_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(matrix_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_quaternion_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(quaternion_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_rect_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(rect_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_color_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(color_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_point_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(point_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_vector3_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(vector3_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_vector4_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(vector4_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_size_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(size_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_array4_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(array4_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_color_buffer_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(color_buffer_near, $a, $b)
    };
}
#[macro_export]
#[doc(hidden)]
macro_rules! expect_colors_near {
    ($a:expr, $b:expr $(,)?) => {
        $crate::expect_pred2!(colors_near, $a, $b)
    };
}

/// `std::optional<T> == T`.
macro_rules! optional_eq {
    ($($t:ty),*) => {$(
        impl TestEq<$t> for Option<$t> {
            fn test_eq(&self, other: &$t) -> bool {
                self.as_ref().is_some_and(|v| v == other)
            }
        }
    )*};
}
optional_eq!(
    crate::rect::TRect<f32>,
    crate::rect::TRect<i64>,
    crate::rect::TRect<i32>,
    crate::point::TPoint<f32>,
    f32
);
