// flutter/impeller/geometry/point.h (point.cc is empty)
//
// `TPoint<T>` keeps upstream's template: `Point` (float), `IPoint`
// (int64_t), `IPoint32` (int32_t) and `UintPoint32` (uint32_t). Arithmetic
// follows C++'s conversions through `crate::cxx::Num`: `p * scale` computes
// `x * scale` in the common type of `Type` and the scale and converts back,
// while `p *= scale` converts the scale to `Type` first, as upstream does.

use std::fmt;
use std::ops::{
    Add, AddAssign, Div, DivAssign, Mul, MulAssign, Neg, Sub, SubAssign,
};

use crate::cxx::{self, Num, Op, conv};
use crate::scalar::{Radians, Scalar};
use crate::size::TSize;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
#[repr(C)]
pub struct TPoint<T> {
    pub x: T,
    pub y: T,
}

pub type Point = TPoint<Scalar>;
pub type IPoint = TPoint<i64>;
pub type IPoint32 = TPoint<i32>;
pub type UintPoint32 = TPoint<u32>;
pub type Vector2 = Point;
pub type Quad = [Point; 4];

pub const kQuadrantAxes: [Vector2; 4] = [
    Point::new(1.0, 0.0),
    Point::new(0.0, 1.0),
    Point::new(-1.0, 0.0),
    Point::new(0.0, -1.0),
];

impl<T: Num> TPoint<T> {
    pub const fn new(x: T, y: T) -> Self {
        TPoint { x, y }
    }

    /// `explicit TPoint(const TPoint<U>&)`.
    pub fn from_point<U: Num>(other: TPoint<U>) -> Self {
        TPoint { x: conv(other.x), y: conv(other.y) }
    }

    /// `explicit TPoint(const TSize<U>&)`.
    pub fn from_size<U: Num>(other: TSize<U>) -> Self {
        TPoint { x: conv(other.width), y: conv(other.height) }
    }

    pub const fn make_xy(x: T, y: T) -> Self {
        TPoint { x, y }
    }

    /// `static TPoint Round(const TPoint<U>&)`.
    pub fn round_from<U: Num>(other: TPoint<U>) -> Self {
        TPoint { x: cxx::round_to(other.x), y: cxx::round_to(other.y) }
    }

    /// Computed in `double` from differences taken in `Type`, and returned as
    /// `Type`.
    pub fn get_distance_squared(&self, p: &Self) -> T {
        let dx: f64 = p.x.sub(self.x).to_f64();
        let dy: f64 = p.y.sub(self.y).to_f64();
        T::from_f64(dx * dx + dy * dy)
    }

    pub fn min(&self, p: &Self) -> Self {
        TPoint { x: cxx::min(self.x, p.x), y: cxx::min(self.y, p.y) }
    }

    pub fn max(&self, p: &Self) -> Self {
        TPoint { x: cxx::max(self.x, p.x), y: cxx::max(self.y, p.y) }
    }

    pub fn floor(&self) -> Self {
        TPoint { x: self.x.floor(), y: self.y.floor() }
    }

    pub fn ceil(&self) -> Self {
        TPoint { x: self.x.ceil(), y: self.y.ceil() }
    }

    pub fn round(&self) -> Self {
        TPoint { x: self.x.round(), y: self.y.round() }
    }

    pub fn get_distance(&self, p: &Self) -> T {
        self.get_distance_squared(p).sqrt_t()
    }

    pub fn get_length_squared(&self) -> Scalar {
        let (x, y) = (self.x.to_f64(), self.y.to_f64());
        (x * x + y * y) as Scalar
    }

    pub fn get_length(&self) -> Scalar {
        self.get_length_squared().sqrt()
    }

    /// Returns the distance (squared) from this point to the closest point on
    /// the line segment p0 -> p1.
    pub fn get_distance_to_segment_squared(&self, p0: Self, p1: Self) -> T {
        // Compute relative vectors to one endpoint of the segment (p0)
        let u = p1 - p0;
        let v = *self - p0;

        // Compute the projection of (this point) onto p0->p1.
        let dot: Scalar = u.dot(&v).to_f32();
        if dot <= 0.0 {
            // The projection lands outside the segment on the p0 side.
            return T::from_f32(v.get_length_squared());
        }

        let uLengthSquared: Scalar = u.get_length_squared();
        if dot >= uLengthSquared {
            // The projection lands outside the segment on the p1 side.
            return self.get_distance_squared(&p1);
        }

        let cross: Scalar = u.cross(&v).to_f32();
        // We reorder the equation slightly to avoid infinities:
        T::from_f32((cross / uLengthSquared) * cross)
    }

    pub fn get_distance_to_segment(&self, p0: Self, p1: Self) -> T {
        self.get_distance_to_segment_squared(p0, p1).sqrt_t()
    }

    pub fn normalize(&self) -> Self {
        let length = self.get_length();
        if length == 0.0 {
            return TPoint { x: conv(1), y: conv(0) };
        }
        TPoint { x: self.x.op(Op::Div, length), y: self.y.op(Op::Div, length) }
    }

    pub fn abs(&self) -> Self {
        TPoint { x: self.x.fabs(), y: self.y.fabs() }
    }

    pub fn cross(&self, p: &Self) -> T {
        self.x.mul(p.y).sub(self.y.mul(p.x))
    }

    /// Equivalent to ((p1 - p0).Cross(p2 - p0)).
    pub fn cross3(p0: &Self, p1: &Self, p2: &Self) -> T {
        (*p1 - *p0).cross(&(*p2 - *p0))
    }

    pub fn dot(&self, p: &Self) -> T {
        self.x.mul(p.x).add(self.y.mul(p.y))
    }

    pub fn reflect(&self, axis: &Self) -> Self {
        *self - *axis * self.dot(axis) * 2i32
    }

    pub fn rotate(&self, angle: &Radians) -> Self {
        let cos_a = angle.radians.cos();
        let sin_a = angle.radians.sin();
        TPoint {
            x: self.x.op(Op::Mul, cos_a).op(Op::Sub, self.y.op(Op::Mul, sin_a).to_f32()),
            y: self.x.op(Op::Mul, sin_a).op(Op::Add, self.y.op(Op::Mul, cos_a).to_f32()),
        }
    }

    pub fn perpendicular_right(&self) -> Self {
        TPoint { x: self.y.neg(), y: self.x }
    }

    pub fn perpendicular_left(&self) -> Self {
        TPoint { x: self.y, y: self.x.neg() }
    }

    pub fn angle_to(&self, p: &Self) -> Radians {
        Radians { radians: atan2_t(self.cross(p), self.dot(p)) }
    }

    pub fn lerp(&self, p: &Self, t: Scalar) -> Self {
        *self + (*p - *self) * t
    }

    pub fn is_zero(&self) -> bool {
        self.x == T::zero() && self.y == T::zero()
    }

    pub fn is_finite(&self) -> bool {
        self.x.is_finite_t() && self.y.is_finite_t()
    }
}

/// `std::atan2` of two `Type`s, as a Scalar (Radians holds one).
fn atan2_t<T: Num>(y: T, x: T) -> Scalar {
    if T::KIND == cxx::Kind::F32 {
        y.to_f32().atan2(x.to_f32())
    } else {
        y.to_f64().atan2(x.to_f64()) as Scalar
    }
}

// ----------------------------------------------------- compound assignment --

impl<T: Num, U: Num> AddAssign<TPoint<U>> for TPoint<T> {
    fn add_assign(&mut self, p: TPoint<U>) {
        self.x = self.x.add(conv(p.x));
        self.y = self.y.add(conv(p.y));
    }
}

impl<T: Num, U: Num> AddAssign<TSize<U>> for TPoint<T> {
    fn add_assign(&mut self, s: TSize<U>) {
        self.x = self.x.add(conv(s.width));
        self.y = self.y.add(conv(s.height));
    }
}

impl<T: Num, U: Num> SubAssign<TPoint<U>> for TPoint<T> {
    fn sub_assign(&mut self, p: TPoint<U>) {
        self.x = self.x.sub(conv(p.x));
        self.y = self.y.sub(conv(p.y));
    }
}

impl<T: Num, U: Num> SubAssign<TSize<U>> for TPoint<T> {
    fn sub_assign(&mut self, s: TSize<U>) {
        self.x = self.x.sub(conv(s.width));
        self.y = self.y.sub(conv(s.height));
    }
}

impl<T: Num, U: Num> MulAssign<TPoint<U>> for TPoint<T> {
    fn mul_assign(&mut self, p: TPoint<U>) {
        self.x = self.x.mul(conv(p.x));
        self.y = self.y.mul(conv(p.y));
    }
}

impl<T: Num, U: Num> MulAssign<TSize<U>> for TPoint<T> {
    fn mul_assign(&mut self, s: TSize<U>) {
        self.x = self.x.mul(conv(s.width));
        self.y = self.y.mul(conv(s.height));
    }
}

impl<T: Num, U: Num> MulAssign<U> for TPoint<T> {
    fn mul_assign(&mut self, scale: U) {
        self.x = self.x.mul(conv(scale));
        self.y = self.y.mul(conv(scale));
    }
}

impl<T: Num, U: Num> DivAssign<TPoint<U>> for TPoint<T> {
    fn div_assign(&mut self, p: TPoint<U>) {
        self.x = self.x.div(conv(p.x));
        self.y = self.y.div(conv(p.y));
    }
}

impl<T: Num, U: Num> DivAssign<TSize<U>> for TPoint<T> {
    fn div_assign(&mut self, s: TSize<U>) {
        self.x = self.x.div(conv(s.width));
        self.y = self.y.div(conv(s.height));
    }
}

impl<T: Num, U: Num> DivAssign<U> for TPoint<T> {
    fn div_assign(&mut self, scale: U) {
        self.x = self.x.div(conv(scale));
        self.y = self.y.div(conv(scale));
    }
}

// --------------------------------------------------------------- operators --

impl<T: Num> Neg for TPoint<T> {
    type Output = TPoint<T>;
    fn neg(self) -> TPoint<T> {
        TPoint { x: self.x.neg(), y: self.y.neg() }
    }
}

impl<T: Num> Add<TPoint<T>> for TPoint<T> {
    type Output = TPoint<T>;
    fn add(self, p: TPoint<T>) -> TPoint<T> {
        TPoint { x: self.x.add(p.x), y: self.y.add(p.y) }
    }
}

impl<T: Num, U: Num> Add<TSize<U>> for TPoint<T> {
    type Output = TPoint<T>;
    fn add(self, s: TSize<U>) -> TPoint<T> {
        TPoint { x: self.x.add(conv(s.width)), y: self.y.add(conv(s.height)) }
    }
}

impl<T: Num> Sub<TPoint<T>> for TPoint<T> {
    type Output = TPoint<T>;
    fn sub(self, p: TPoint<T>) -> TPoint<T> {
        TPoint { x: self.x.sub(p.x), y: self.y.sub(p.y) }
    }
}

impl<T: Num, U: Num> Sub<TSize<U>> for TPoint<T> {
    type Output = TPoint<T>;
    fn sub(self, s: TSize<U>) -> TPoint<T> {
        TPoint { x: self.x.sub(conv(s.width)), y: self.y.sub(conv(s.height)) }
    }
}

/// `operator*(U scale)`: `static_cast<Type>(x * scale)`.
impl<T: Num, U: Num> Mul<U> for TPoint<T> {
    type Output = TPoint<T>;
    fn mul(self, scale: U) -> TPoint<T> {
        TPoint { x: self.x.op(Op::Mul, scale), y: self.y.op(Op::Mul, scale) }
    }
}

impl<T: Num> Mul<TPoint<T>> for TPoint<T> {
    type Output = TPoint<T>;
    fn mul(self, p: TPoint<T>) -> TPoint<T> {
        TPoint { x: self.x.mul(p.x), y: self.y.mul(p.y) }
    }
}

impl<T: Num, U: Num> Mul<TSize<U>> for TPoint<T> {
    type Output = TPoint<T>;
    fn mul(self, s: TSize<U>) -> TPoint<T> {
        TPoint { x: self.x.mul(conv(s.width)), y: self.y.mul(conv(s.height)) }
    }
}

/// `operator/(U d)`: `static_cast<Type>(x / d)`.
impl<T: Num, U: Num> Div<U> for TPoint<T> {
    type Output = TPoint<T>;
    fn div(self, d: U) -> TPoint<T> {
        TPoint { x: self.x.op(Op::Div, d), y: self.y.op(Op::Div, d) }
    }
}

impl<T: Num> Div<TPoint<T>> for TPoint<T> {
    type Output = TPoint<T>;
    fn div(self, p: TPoint<T>) -> TPoint<T> {
        TPoint { x: self.x.div(p.x), y: self.y.div(p.y) }
    }
}

impl<T: Num, U: Num> Div<TSize<U>> for TPoint<T> {
    type Output = TPoint<T>;
    fn div(self, s: TSize<U>) -> TPoint<T> {
        TPoint { x: self.x.div(conv(s.width)), y: self.y.div(conv(s.height)) }
    }
}

// ------------------------------------------------- mixed-type operators ----
//
// `MixedOp<F, I>`: a floating point point with an integral one gives the
// floating point type.

macro_rules! mixed {
    ($f:ty, $($i:ty),*) => {$(
        impl Add<TPoint<$i>> for TPoint<$f> {
            type Output = TPoint<$f>;
            fn add(self, p2: TPoint<$i>) -> TPoint<$f> {
                TPoint { x: self.x + p2.x as $f, y: self.y + p2.y as $f }
            }
        }
        impl Add<TPoint<$f>> for TPoint<$i> {
            type Output = TPoint<$f>;
            fn add(self, p2: TPoint<$f>) -> TPoint<$f> {
                p2 + self
            }
        }
        impl Sub<TPoint<$i>> for TPoint<$f> {
            type Output = TPoint<$f>;
            fn sub(self, p2: TPoint<$i>) -> TPoint<$f> {
                TPoint { x: self.x - p2.x as $f, y: self.y - p2.y as $f }
            }
        }
        impl Sub<TPoint<$f>> for TPoint<$i> {
            type Output = TPoint<$f>;
            fn sub(self, p2: TPoint<$f>) -> TPoint<$f> {
                TPoint { x: self.x as $f - p2.x, y: self.y as $f - p2.y }
            }
        }
        impl Mul<TPoint<$i>> for TPoint<$f> {
            type Output = TPoint<$f>;
            fn mul(self, p2: TPoint<$i>) -> TPoint<$f> {
                TPoint { x: self.x * p2.x as $f, y: self.y * p2.y as $f }
            }
        }
        impl Mul<TPoint<$f>> for TPoint<$i> {
            type Output = TPoint<$f>;
            fn mul(self, p2: TPoint<$f>) -> TPoint<$f> {
                p2 * self
            }
        }
        impl Div<TPoint<$i>> for TPoint<$f> {
            type Output = TPoint<$f>;
            fn div(self, p2: TPoint<$i>) -> TPoint<$f> {
                TPoint { x: self.x / p2.x as $f, y: self.y / p2.y as $f }
            }
        }
        impl Div<TPoint<$f>> for TPoint<$i> {
            type Output = TPoint<$f>;
            fn div(self, p2: TPoint<$f>) -> TPoint<$f> {
                TPoint { x: self.x as $f / p2.x, y: self.y as $f / p2.y }
            }
        }
    )*};
}
mixed!(f32, i32, i64, u32);

// ---------------------------------------- scalar and size on the left ----

macro_rules! scalar_lhs {
    ($($u:ty),*) => {$(
        /// `operator*(U s, const TPoint<T>& p)`: `p * s`.
        impl<T: Num> Mul<TPoint<T>> for $u {
            type Output = TPoint<T>;
            fn mul(self, p: TPoint<T>) -> TPoint<T> {
                p * self
            }
        }
        /// `operator/(U s, const TPoint<T>& p)`.
        impl<T: Num> Div<TPoint<T>> for $u {
            type Output = TPoint<T>;
            fn div(self, p: TPoint<T>) -> TPoint<T> {
                let s: T = conv(self);
                TPoint { x: s.div(p.x), y: s.div(p.y) }
            }
        }
    )*};
}
scalar_lhs!(f32, f64, i32, i64, u32);

impl<T: Num, U: Num> Add<TPoint<T>> for TSize<U> {
    type Output = TPoint<T>;
    fn add(self, p: TPoint<T>) -> TPoint<T> {
        p + self
    }
}

impl<T: Num, U: Num> Sub<TPoint<T>> for TSize<U> {
    type Output = TPoint<T>;
    fn sub(self, p: TPoint<T>) -> TPoint<T> {
        TPoint { x: conv::<U, T>(self.width).sub(p.x), y: conv::<U, T>(self.height).sub(p.y) }
    }
}

impl<T: Num, U: Num> Mul<TPoint<T>> for TSize<U> {
    type Output = TPoint<T>;
    fn mul(self, p: TPoint<T>) -> TPoint<T> {
        p * self
    }
}

impl<T: Num, U: Num> Div<TPoint<T>> for TSize<U> {
    type Output = TPoint<T>;
    fn div(self, p: TPoint<T>) -> TPoint<T> {
        TPoint { x: conv::<U, T>(self.width).div(p.x), y: conv::<U, T>(self.height).div(p.y) }
    }
}

impl<T: Num> TPoint<T> {
    /// `operator-(const TPoint<T>& p, T v)`.
    pub fn sub_value(self, v: T) -> TPoint<T> {
        TPoint { x: self.x.sub(v), y: self.y.sub(v) }
    }
}

impl<T: Num> fmt::Display for TPoint<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({}, {})", self.x.cxx_fmt(), self.y.cxx_fmt())
    }
}
