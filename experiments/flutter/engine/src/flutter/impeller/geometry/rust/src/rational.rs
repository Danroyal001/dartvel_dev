// flutter/impeller/geometry/rational.h, rational.cc

use std::cmp::Ordering;

use crate::scalar::Scalar;

#[derive(Clone, Copy, Debug)]
pub struct Rational {
    num_: i32,
    den_: u32,
}

fn abs_to_unsigned(x: i32) -> u32 {
    // std::abs(INT_MIN) is undefined upstream; it wraps here.
    x.wrapping_abs() as u32
}

/// `std::gcd` of two unsigned values (libc++'s binary algorithm gives the
/// same value as Euclid's).
fn gcd(mut a: u64, mut b: u64) -> u64 {
    while b != 0 {
        let t = a % b;
        a = b;
        b = t;
    }
    a
}

impl Rational {
    #[inline]
    /// `explicit Rational(int32_t num)`.
    pub const fn from_int(num: i32) -> Rational {
        Rational { num_: num, den_: 1 }
    }

    #[inline]
    pub const fn new(num: i32, den: u32) -> Rational {
        Rational { num_: num, den_: den }
    }

    #[inline]
    pub fn get_numerator(&self) -> i32 {
        self.num_
    }

    #[inline]
    pub fn get_denominator(&self) -> u32 {
        self.den_
    }

    pub fn get_hash(&self) -> u64 {
        if self.num_ == 0 {
            return 0;
        }
        // std::gcd(int32_t, uint32_t) works on the magnitudes in the common
        // type, uint32_t.
        let g: u64 = gcd(abs_to_unsigned(self.num_) as u64, self.den_ as u64);
        // num_ / gcd: num_ is converted to uint64_t (sign-extended) first.
        (((self.num_ as i64 as u64) / g) << 32) | (self.den_ as u64 / g)
    }

    #[inline]
    /// `explicit operator Scalar()`.
    pub fn to_scalar(&self) -> Scalar {
        self.num_ as f32 / self.den_ as f32
    }

    pub fn invert(&self) -> Rational {
        if self.num_ >= 0 {
            Rational::new(self.den_ as i32, self.num_ as u32)
        } else {
            Rational::new((-1i32).wrapping_mul(self.den_ as i32), self.num_.wrapping_abs() as u32)
        }
    }
}

impl PartialEq for Rational {
    #[inline]
    fn eq(&self, that: &Rational) -> bool {
        if self.den_ == that.den_ {
            self.num_ == that.num_
        } else if (self.num_ >= 0) != (that.num_ >= 0) {
            false
        } else {
            abs_to_unsigned(self.num_).wrapping_mul(that.den_)
                == abs_to_unsigned(that.num_).wrapping_mul(self.den_)
        }
    }
}

impl Rational {
    #[inline]
    /// `operator<`.
    pub fn lt(&self, that: &Rational) -> bool {
        if self.den_ == that.den_ {
            self.num_ < that.num_
        } else if (self.num_ >= 0) != (that.num_ >= 0) {
            self.num_ < that.num_
        } else {
            abs_to_unsigned(self.num_).wrapping_mul(that.den_)
                < abs_to_unsigned(that.num_).wrapping_mul(self.den_)
        }
    }
}

/// Only `operator<` and `operator==` exist upstream; this ordering is built
/// from them for callers that sort.
impl PartialOrd for Rational {
    #[inline]
    fn partial_cmp(&self, other: &Rational) -> Option<Ordering> {
        if self.lt(other) {
            Some(Ordering::Less)
        } else if self == other {
            Some(Ordering::Equal)
        } else {
            Some(Ordering::Greater)
        }
    }
}
