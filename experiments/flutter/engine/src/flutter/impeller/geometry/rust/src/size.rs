// flutter/impeller/geometry/size.h (size.cc is empty)

use std::fmt;
use std::ops::{Add, Div, Mul, MulAssign, Neg, Sub};

use crate::cxx::{self, Num, Op, conv};
use crate::scalar::Scalar;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
#[repr(C)]
pub struct TSize<T> {
    pub width: T,
    pub height: T,
}

pub type Size = TSize<Scalar>;
pub type ISize32 = TSize<i32>;
pub type ISize64 = TSize<i64>;
pub type ISize = ISize64;

const _: () = assert!(std::mem::size_of::<Size>() == 2 * std::mem::size_of::<Scalar>());

impl<T: Num> TSize<T> {
    pub const fn new(width: T, height: T) -> Self {
        TSize { width, height }
    }

    /// `explicit TSize(Type dimension)`.
    pub const fn splat(dimension: T) -> Self {
        TSize { width: dimension, height: dimension }
    }

    /// `explicit TSize(const TSize<U>&)`: each dimension `static_cast`.
    pub fn from_size<U: Num>(other: TSize<U>) -> Self {
        TSize { width: conv(other.width), height: conv(other.height) }
    }

    pub const fn make_wh(width: T, height: T) -> Self {
        TSize { width, height }
    }

    pub fn infinite() -> Self {
        TSize { width: T::MAX, height: T::MAX }
    }

    pub fn min(&self, o: &Self) -> Self {
        TSize { width: cxx::min(self.width, o.width), height: cxx::min(self.height, o.height) }
    }

    pub fn max(&self, o: &Self) -> Self {
        TSize { width: cxx::max(self.width, o.width), height: cxx::max(self.height, o.height) }
    }

    pub fn min_dimension(&self) -> T {
        cxx::min(self.width, self.height)
    }

    pub fn max_dimension(&self) -> T {
        cxx::max(self.width, self.height)
    }

    pub fn abs(&self) -> Self {
        TSize { width: self.width.fabs(), height: self.height.fabs() }
    }

    pub fn floor(&self) -> Self {
        TSize { width: self.width.floor(), height: self.height.floor() }
    }

    pub fn ceil(&self) -> Self {
        TSize { width: self.width.ceil(), height: self.height.ceil() }
    }

    pub fn round(&self) -> Self {
        TSize { width: self.width.round(), height: self.height.round() }
    }

    pub fn area(&self) -> T {
        self.width.mul(self.height)
    }

    /// Returns true if either of the width or height are 0, negative, or NaN.
    pub fn is_empty(&self) -> bool {
        !(self.width > T::zero() && self.height > T::zero())
    }

    pub fn is_finite(&self) -> bool {
        self.width.is_finite_t() && self.height.is_finite_t()
    }

    pub fn is_square(&self) -> bool {
        self.width == self.height
    }

    /// `static TSize Ceil(const TSize<U>&)`.
    pub fn ceil_from<U: Num>(other: TSize<U>) -> Self {
        TSize { width: cxx::ceil_to(other.width), height: cxx::ceil_to(other.height) }
    }

    /// Return the mip count of the texture.
    pub fn mip_count(&self) -> usize {
        const minimum_mip: usize = 1;
        if self.is_empty() || self.width <= T::zero() || self.height <= T::zero() {
            return minimum_mip;
        }
        // log2 of a float is log2f; of an integer, log2 of a double. The
        // smaller is converted to size_t.
        let result: usize = if T::KIND == cxx::Kind::F32 {
            cxx::min(self.width.to_f32().log2(), self.height.to_f32().log2()) as usize
        } else {
            cxx::min(self.width.to_f64().log2(), self.height.to_f64().log2()) as usize
        };
        cxx::max(result, minimum_mip)
    }
}

/// `TSize operator*(Scalar scale)`.
impl<T: Num> Mul<Scalar> for TSize<T> {
    type Output = TSize<T>;
    fn mul(self, scale: Scalar) -> TSize<T> {
        TSize { width: self.width.op(Op::Mul, scale), height: self.height.op(Op::Mul, scale) }
    }
}

/// `TSize operator*=(U scale)`: the scale is converted to `Type` first.
impl<T: Num, U: Num> MulAssign<U> for TSize<T> {
    fn mul_assign(&mut self, scale: U) {
        self.width = self.width.mul(conv(scale));
        self.height = self.height.mul(conv(scale));
    }
}

/// `TSize operator/(Scalar scale)`: computed in `Scalar`.
impl<T: Num> Div<Scalar> for TSize<T> {
    type Output = TSize<T>;
    fn div(self, scale: Scalar) -> TSize<T> {
        TSize { width: conv(self.width.to_f32() / scale), height: conv(self.height.to_f32() / scale) }
    }
}

impl<T: Num> Div<TSize<T>> for TSize<T> {
    type Output = TSize<T>;
    fn div(self, s: TSize<T>) -> TSize<T> {
        TSize { width: self.width.div(s.width), height: self.height.div(s.height) }
    }
}

impl<T: Num> Add for TSize<T> {
    type Output = TSize<T>;
    fn add(self, s: TSize<T>) -> TSize<T> {
        TSize { width: self.width.add(s.width), height: self.height.add(s.height) }
    }
}

impl<T: Num> Sub for TSize<T> {
    type Output = TSize<T>;
    fn sub(self, s: TSize<T>) -> TSize<T> {
        TSize { width: self.width.sub(s.width), height: self.height.sub(s.height) }
    }
}

impl<T: Num> Neg for TSize<T> {
    type Output = TSize<T>;
    fn neg(self) -> TSize<T> {
        TSize { width: self.width.neg(), height: self.height.neg() }
    }
}

macro_rules! scalar_lhs {
    ($($u:ty),*) => {$(
        /// `operator*(U s, const TSize<T>& p)`: `p * s`, whose only
        /// overload takes a `Scalar`.
        impl<T: Num> Mul<TSize<T>> for $u {
            type Output = TSize<T>;
            fn mul(self, p: TSize<T>) -> TSize<T> {
                p * (self as Scalar)
            }
        }
        /// `operator/(U s, const TSize<T>& p)`.
        impl<T: Num> Div<TSize<T>> for $u {
            type Output = TSize<T>;
            fn div(self, p: TSize<T>) -> TSize<T> {
                let s: T = conv(self);
                TSize { width: s.div(p.width), height: s.div(p.height) }
            }
        }
    )*};
}
scalar_lhs!(f32, f64, i32, i64, u32);

impl<T: Num> fmt::Display for TSize<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({}, {})", self.width.cxx_fmt(), self.height.cxx_fmt())
    }
}
