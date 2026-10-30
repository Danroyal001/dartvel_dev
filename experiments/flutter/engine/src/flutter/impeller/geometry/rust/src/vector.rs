// flutter/impeller/geometry/vector.h (vector.cc is empty)
//
// Upstream's unions (`x, y, z` over `e[3]`) are a struct with `e()` and
// indexing. Operators taking an arithmetic `U` compute `x * scale` in the
// common type and narrow back to Scalar, as upstream's
// `Vector3(x * scale, ...)` does.

use std::fmt;
use std::ops::{
    Add, AddAssign, Div, DivAssign, Index, IndexMut, Mul, MulAssign, Neg, Sub, SubAssign,
};

use crate::color::Color;
use crate::cxx::{self, Num, Op};
use crate::point::{Point, Vector2};
use crate::scalar::Scalar;
use crate::size::Size;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
#[repr(C)]
pub struct Vector3 {
    pub x: Scalar,
    pub y: Scalar,
    pub z: Scalar,
}

const _: () = assert!(std::mem::size_of::<Vector3>() == 3 * std::mem::size_of::<Scalar>());
const _: () = assert!(std::mem::size_of::<Vector4>() == 4 * std::mem::size_of::<Scalar>());

impl From<Color> for Vector3 {
    fn from(c: Color) -> Vector3 {
        Vector3 { x: c.red, y: c.green, z: c.blue }
    }
}

impl From<Point> for Vector3 {
    fn from(p: Point) -> Vector3 {
        Vector3 { x: p.x, y: p.y, z: 0.0 }
    }
}

impl From<Size> for Vector3 {
    fn from(s: Size) -> Vector3 {
        Vector3 { x: s.width, y: s.height, z: 0.0 }
    }
}

impl Vector3 {
    pub const fn new(x: Scalar, y: Scalar, z: Scalar) -> Vector3 {
        Vector3 { x, y, z }
    }

    /// `Vector3(Scalar x, Scalar y)`.
    pub const fn new2(x: Scalar, y: Scalar) -> Vector3 {
        Vector3 { x, y, z: 0.0 }
    }

    pub const fn e(&self) -> [Scalar; 3] {
        [self.x, self.y, self.z]
    }

    /// The length (or magnitude of the vector).
    pub fn get_length(&self) -> Scalar {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }

    pub fn normalize(&self) -> Vector3 {
        let len = self.get_length();
        Vector3 { x: self.x / len, y: self.y / len, z: self.z / len }
    }

    pub fn dot(&self, other: &Vector3) -> Scalar {
        (self.x * other.x) + (self.y * other.y) + (self.z * other.z)
    }

    pub fn abs(&self) -> Vector3 {
        Vector3 { x: self.x.abs(), y: self.y.abs(), z: self.z.abs() }
    }

    pub fn cross(&self, other: &Vector3) -> Vector3 {
        Vector3 {
            x: (self.y * other.z) - (self.z * other.y),
            y: (self.z * other.x) - (self.x * other.z),
            z: (self.x * other.y) - (self.y * other.x),
        }
    }

    pub fn min(&self, p: &Vector3) -> Vector3 {
        Vector3 { x: cxx::min(self.x, p.x), y: cxx::min(self.y, p.y), z: cxx::min(self.z, p.z) }
    }

    pub fn max(&self, p: &Vector3) -> Vector3 {
        Vector3 { x: cxx::max(self.x, p.x), y: cxx::max(self.y, p.y), z: cxx::max(self.z, p.z) }
    }

    pub fn floor(&self) -> Vector3 {
        Vector3 { x: self.x.floor(), y: self.y.floor(), z: self.z.floor() }
    }

    pub fn ceil(&self) -> Vector3 {
        Vector3 { x: self.x.ceil(), y: self.y.ceil(), z: self.z.ceil() }
    }

    pub fn round(&self) -> Vector3 {
        Vector3 { x: self.x.round(), y: self.y.round(), z: self.z.round() }
    }

    pub fn lerp(&self, v: &Vector3, t: Scalar) -> Vector3 {
        *self + (*v - *self) * t
    }

    /// Make a linear combination of two vectors and return the result.
    pub fn combine(a: &Vector3, aScale: Scalar, b: &Vector3, bScale: Scalar) -> Vector3 {
        Vector3 {
            x: aScale * a.x + bScale * b.x,
            y: aScale * a.y + bScale * b.y,
            z: aScale * a.z + bScale * b.z,
        }
    }
}

impl Index<usize> for Vector3 {
    type Output = Scalar;
    fn index(&self, i: usize) -> &Scalar {
        match i {
            0 => &self.x,
            1 => &self.y,
            2 => &self.z,
            _ => panic!("Vector3 index {i} out of range"),
        }
    }
}

impl IndexMut<usize> for Vector3 {
    fn index_mut(&mut self, i: usize) -> &mut Scalar {
        match i {
            0 => &mut self.x,
            1 => &mut self.y,
            2 => &mut self.z,
            _ => panic!("Vector3 index {i} out of range"),
        }
    }
}

impl AddAssign for Vector3 {
    fn add_assign(&mut self, p: Vector3) {
        self.x += p.x;
        self.y += p.y;
        self.z += p.z;
    }
}

impl SubAssign for Vector3 {
    fn sub_assign(&mut self, p: Vector3) {
        self.x -= p.x;
        self.y -= p.y;
        self.z -= p.z;
    }
}

impl MulAssign<Vector3> for Vector3 {
    fn mul_assign(&mut self, p: Vector3) {
        self.x *= p.x;
        self.y *= p.y;
        self.z *= p.z;
    }
}

/// `x *= scale`: computed in the common type, narrowed to Scalar.
impl<U: Num> MulAssign<U> for Vector3 {
    fn mul_assign(&mut self, scale: U) {
        self.x = self.x.op(Op::Mul, scale);
        self.y = self.y.op(Op::Mul, scale);
        self.z = self.z.op(Op::Mul, scale);
    }
}

impl DivAssign<Vector3> for Vector3 {
    fn div_assign(&mut self, p: Vector3) {
        self.x /= p.x;
        self.y /= p.y;
        self.z /= p.z;
    }
}

impl<U: Num> DivAssign<U> for Vector3 {
    fn div_assign(&mut self, scale: U) {
        self.x = self.x.op(Op::Div, scale);
        self.y = self.y.op(Op::Div, scale);
        self.z = self.z.op(Op::Div, scale);
    }
}

impl Neg for Vector3 {
    type Output = Vector3;
    fn neg(self) -> Vector3 {
        Vector3::new(-self.x, -self.y, -self.z)
    }
}

impl Add<Vector3> for Vector3 {
    type Output = Vector3;
    fn add(self, v: Vector3) -> Vector3 {
        Vector3::new(self.x + v.x, self.y + v.y, self.z + v.z)
    }
}

impl Sub<Vector3> for Vector3 {
    type Output = Vector3;
    fn sub(self, v: Vector3) -> Vector3 {
        Vector3::new(self.x - v.x, self.y - v.y, self.z - v.z)
    }
}

/// `operator+(Scalar s)`.
impl Add<Scalar> for Vector3 {
    type Output = Vector3;
    fn add(self, s: Scalar) -> Vector3 {
        Vector3::new(self.x + s, self.y + s, self.z + s)
    }
}

/// `operator-(Scalar s)`.
impl Sub<Scalar> for Vector3 {
    type Output = Vector3;
    fn sub(self, s: Scalar) -> Vector3 {
        Vector3::new(self.x - s, self.y - s, self.z - s)
    }
}

impl Mul<Vector3> for Vector3 {
    type Output = Vector3;
    fn mul(self, v: Vector3) -> Vector3 {
        Vector3::new(self.x * v.x, self.y * v.y, self.z * v.z)
    }
}

impl<U: Num> Mul<U> for Vector3 {
    type Output = Vector3;
    fn mul(self, scale: U) -> Vector3 {
        Vector3::new(self.x.op(Op::Mul, scale), self.y.op(Op::Mul, scale), self.z.op(Op::Mul, scale))
    }
}

impl Div<Vector3> for Vector3 {
    type Output = Vector3;
    fn div(self, v: Vector3) -> Vector3 {
        Vector3::new(self.x / v.x, self.y / v.y, self.z / v.z)
    }
}

impl<U: Num> Div<U> for Vector3 {
    type Output = Vector3;
    fn div(self, scale: U) -> Vector3 {
        Vector3::new(self.x.op(Op::Div, scale), self.y.op(Op::Div, scale), self.z.op(Op::Div, scale))
    }
}

macro_rules! vector3_lhs {
    ($($u:ty),*) => {$(
        /// `operator*(U s, const Vector3& p)`: `p * s`.
        impl Mul<Vector3> for $u {
            type Output = Vector3;
            fn mul(self, p: Vector3) -> Vector3 {
                p * self
            }
        }
        /// `operator+(U s, const Vector3& p)`: `p + s` (s becomes a Scalar).
        impl Add<Vector3> for $u {
            type Output = Vector3;
            fn add(self, p: Vector3) -> Vector3 {
                p + self as Scalar
            }
        }
        /// `operator-(U s, const Vector3& p)`: `-p + s`.
        impl Sub<Vector3> for $u {
            type Output = Vector3;
            fn sub(self, p: Vector3) -> Vector3 {
                -p + self as Scalar
            }
        }
        /// `operator/(U s, const Vector3& p)`.
        impl Div<Vector3> for $u {
            type Output = Vector3;
            fn div(self, p: Vector3) -> Vector3 {
                let s = self as Scalar;
                Vector3::new(s / p.x, s / p.y, s / p.z)
            }
        }
    )*};
}
vector3_lhs!(f32, f64, i32, i64);

#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(C)]
pub struct Vector4 {
    pub x: Scalar,
    pub y: Scalar,
    pub z: Scalar,
    pub w: Scalar,
}

impl Default for Vector4 {
    fn default() -> Vector4 {
        Vector4 { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }
    }
}

impl From<Color> for Vector4 {
    fn from(c: Color) -> Vector4 {
        Vector4 { x: c.red, y: c.green, z: c.blue, w: c.alpha }
    }
}

/// `Vector4(const Vector3&)`: w keeps its default, 1.
impl From<Vector3> for Vector4 {
    fn from(v: Vector3) -> Vector4 {
        Vector4 { x: v.x, y: v.y, z: v.z, w: 1.0 }
    }
}

/// `Vector4(const Point&)`: z is 0 and w 1.
impl From<Point> for Vector4 {
    fn from(p: Point) -> Vector4 {
        Vector4 { x: p.x, y: p.y, z: 0.0, w: 1.0 }
    }
}

impl From<[Scalar; 4]> for Vector4 {
    fn from(values: [Scalar; 4]) -> Vector4 {
        Vector4 { x: values[0], y: values[1], z: values[2], w: values[3] }
    }
}

impl Vector4 {
    pub const fn new(x: Scalar, y: Scalar, z: Scalar, w: Scalar) -> Vector4 {
        Vector4 { x, y, z, w }
    }

    pub const fn e(&self) -> [Scalar; 4] {
        [self.x, self.y, self.z, self.w]
    }

    pub fn is_finite(&self) -> bool {
        self.x.is_finite() && self.y.is_finite() && self.z.is_finite() && self.w.is_finite()
    }

    pub fn normalize(&self) -> Vector4 {
        let inverse: Scalar =
            1.0 / (self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w).sqrt();
        Vector4::new(self.x * inverse, self.y * inverse, self.z * inverse, self.w * inverse)
    }

    pub fn min(&self, p: &Vector4) -> Vector4 {
        Vector4::new(
            cxx::min(self.x, p.x),
            cxx::min(self.y, p.y),
            cxx::min(self.z, p.z),
            cxx::min(self.w, p.w),
        )
    }

    pub fn max(&self, p: &Vector4) -> Vector4 {
        Vector4::new(
            cxx::max(self.x, p.x),
            cxx::max(self.y, p.y),
            cxx::max(self.z, p.z),
            cxx::max(self.w, p.w),
        )
    }

    pub fn floor(&self) -> Vector4 {
        Vector4::new(self.x.floor(), self.y.floor(), self.z.floor(), self.w.floor())
    }

    pub fn ceil(&self) -> Vector4 {
        Vector4::new(self.x.ceil(), self.y.ceil(), self.z.ceil(), self.w.ceil())
    }

    pub fn round(&self) -> Vector4 {
        Vector4::new(self.x.round(), self.y.round(), self.z.round(), self.w.round())
    }

    pub fn lerp(&self, v: &Vector4, t: Scalar) -> Vector4 {
        *self + (*v - *self) * t
    }

    pub fn xy(&self) -> Vector2 {
        Vector2::new(self.x, self.y)
    }
}

impl Index<usize> for Vector4 {
    type Output = Scalar;
    fn index(&self, i: usize) -> &Scalar {
        match i {
            0 => &self.x,
            1 => &self.y,
            2 => &self.z,
            3 => &self.w,
            _ => panic!("Vector4 index {i} out of range"),
        }
    }
}

impl IndexMut<usize> for Vector4 {
    fn index_mut(&mut self, i: usize) -> &mut Scalar {
        match i {
            0 => &mut self.x,
            1 => &mut self.y,
            2 => &mut self.z,
            3 => &mut self.w,
            _ => panic!("Vector4 index {i} out of range"),
        }
    }
}

impl Add for Vector4 {
    type Output = Vector4;
    fn add(self, v: Vector4) -> Vector4 {
        Vector4::new(self.x + v.x, self.y + v.y, self.z + v.z, self.w + v.w)
    }
}

impl Sub for Vector4 {
    type Output = Vector4;
    fn sub(self, v: Vector4) -> Vector4 {
        Vector4::new(self.x - v.x, self.y - v.y, self.z - v.z, self.w - v.w)
    }
}

impl Mul<Scalar> for Vector4 {
    type Output = Vector4;
    fn mul(self, f: Scalar) -> Vector4 {
        Vector4::new(self.x * f, self.y * f, self.z * f, self.w * f)
    }
}

impl Mul<Vector4> for Vector4 {
    type Output = Vector4;
    fn mul(self, v: Vector4) -> Vector4 {
        Vector4::new(self.x * v.x, self.y * v.y, self.z * v.z, self.w * v.w)
    }
}

impl fmt::Display for Vector3 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(f, "({}, {}, {})", g(self.x), g(self.y), g(self.z))
    }
}

impl fmt::Display for Vector4 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(f, "({}, {}, {}, {})", g(self.x), g(self.y), g(self.z), g(self.w))
    }
}
