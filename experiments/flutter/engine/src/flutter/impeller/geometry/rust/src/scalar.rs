// flutter/impeller/geometry/scalar.h

use std::fmt;
use std::ops::{Add, Neg, Sub};

use crate::constants::{kEhCloseEnough, kPi};

pub type Scalar = f32;

/// `Absolute<T>`: `val >= T{} ? val : -val` for arithmetic types, and
/// `fabsf` for `Scalar` (upstream's specialization). So `Absolute(-0.0)` of
/// a double is -0.0 and of a NaN double is the negated NaN, while the
/// `Scalar` form clears the sign bit.
pub trait Absolute: Copy {
    fn absolute(self) -> Self;
}

impl Absolute for f32 {
    #[inline(always)]
    fn absolute(self) -> f32 {
        self.abs()
    }
}

impl Absolute for f64 {
    #[inline(always)]
    fn absolute(self) -> f64 {
        if self >= 0.0 { self } else { -self }
    }
}

macro_rules! absolute_int {
    ($($t:ty),*) => {$(
        impl Absolute for $t {
            #[inline(always)]
            fn absolute(self) -> $t {
                // INT_MIN negates to itself (undefined upstream; wraps here).
                if self >= 0 { self } else { self.wrapping_neg() }
            }
        }
    )*};
}
absolute_int!(i8, i16, i32, i64);

#[inline(always)]
pub fn absolute<T: Absolute>(val: T) -> T {
    val.absolute()
}

#[inline(always)]
pub fn scalar_nearly_zero(x: Scalar) -> bool {
    scalar_nearly_zero_tol(x, kEhCloseEnough)
}

#[inline(always)]
pub fn scalar_nearly_zero_tol(x: Scalar, tolerance: Scalar) -> bool {
    absolute(x) <= tolerance
}

#[inline(always)]
pub fn scalar_nearly_equal(x: Scalar, y: Scalar) -> bool {
    scalar_nearly_zero(x - y)
}

#[inline(always)]
pub fn scalar_nearly_equal_tol(x: Scalar, y: Scalar, tolerance: Scalar) -> bool {
    scalar_nearly_zero_tol(x - y, tolerance)
}

#[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
pub struct Radians {
    pub radians: Scalar,
}

impl Radians {
    #[inline]
    pub const fn new(p_radians: Scalar) -> Radians {
        Radians { radians: p_radians }
    }

    #[inline]
    pub fn is_finite(&self) -> bool {
        self.radians.is_finite()
    }
}

impl Neg for Radians {
    type Output = Radians;
    #[inline]
    fn neg(self) -> Radians {
        Radians { radians: -self.radians }
    }
}

impl Add for Radians {
    type Output = Radians;
    #[inline]
    fn add(self, r: Radians) -> Radians {
        Radians { radians: self.radians + r.radians }
    }
}

impl Sub for Radians {
    type Output = Radians;
    #[inline]
    fn sub(self, r: Radians) -> Radians {
        Radians { radians: self.radians - r.radians }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
pub struct Degrees {
    pub degrees: Scalar,
}

impl Degrees {
    #[inline]
    pub const fn new(p_degrees: Scalar) -> Degrees {
        Degrees { degrees: p_degrees }
    }

    #[inline]
    pub fn is_finite(&self) -> bool {
        self.degrees.is_finite()
    }

    #[inline]
    pub fn get_positive(&self) -> Degrees {
        let mut deg = self.degrees % 360.0;
        if deg < 0.0 {
            deg += 360.0;
        }
        Degrees { degrees: deg }
    }
}

/// `Degrees::operator Radians()`.
impl From<Degrees> for Radians {
    #[inline(always)]
    fn from(d: Degrees) -> Radians {
        Radians { radians: d.degrees * kPi / 180.0 }
    }
}

impl Neg for Degrees {
    type Output = Degrees;
    #[inline]
    fn neg(self) -> Degrees {
        Degrees { degrees: -self.degrees }
    }
}

impl Add for Degrees {
    type Output = Degrees;
    #[inline]
    fn add(self, d: Degrees) -> Degrees {
        Degrees { degrees: self.degrees + d.degrees }
    }
}

impl Sub for Degrees {
    type Output = Degrees;
    #[inline]
    fn sub(self, d: Degrees) -> Degrees {
        Degrees { degrees: self.degrees - d.degrees }
    }
}

impl fmt::Display for Degrees {
    #[inline]
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Degrees({})", crate::print::g(self.degrees))
    }
}

impl fmt::Display for Radians {
    #[inline]
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Radians({})", crate::print::g(self.radians))
    }
}
