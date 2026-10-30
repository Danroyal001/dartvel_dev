// flutter/impeller/geometry/half.h
//
// The non-Apple branch: `InternalHalf` is `uint16_t` and `ScalarToHalf` is
// `static_cast<uint16_t>(f)`, a truncating integer conversion (undefined
// upstream outside [0, 65536); it saturates here). Apple's `_Float16` branch
// and Windows' (which returns 0) are not this platform's.

use std::fmt;

use crate::color::Color;
use crate::point::Vector2;
use crate::scalar::Scalar;
use crate::vector::{Vector3, Vector4};

pub type InternalHalf = u16;

/// Convert a scalar to a half precision float.
#[inline(always)]
pub fn scalar_to_half(f: Scalar) -> InternalHalf {
    f as InternalHalf
}

/// A storage only class for half precision floating point.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Half {
    pub x: InternalHalf,
}

impl Half {
    pub fn from_f64(value: f64) -> Half {
        Half { x: scalar_to_half(value as Scalar) }
    }
    pub fn from_scalar(value: Scalar) -> Half {
        Half { x: scalar_to_half(value) }
    }
    pub fn from_int(value: i32) -> Half {
        Half { x: scalar_to_half(value as Scalar) }
    }
    pub const fn from_internal(x: InternalHalf) -> Half {
        Half { x }
    }
}

/// A storage only class for half precision floating point vector 4.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct HalfVector4 {
    pub x: InternalHalf,
    pub y: InternalHalf,
    pub z: InternalHalf,
    pub w: InternalHalf,
}

impl From<Color> for HalfVector4 {
    fn from(a: Color) -> HalfVector4 {
        HalfVector4 {
            x: scalar_to_half(a.red),
            y: scalar_to_half(a.green),
            z: scalar_to_half(a.blue),
            w: scalar_to_half(a.alpha),
        }
    }
}

impl From<Vector4> for HalfVector4 {
    fn from(a: Vector4) -> HalfVector4 {
        HalfVector4 {
            x: scalar_to_half(a.x),
            y: scalar_to_half(a.y),
            z: scalar_to_half(a.z),
            w: scalar_to_half(a.w),
        }
    }
}

impl HalfVector4 {
    pub const fn new(x: InternalHalf, y: InternalHalf, z: InternalHalf, w: InternalHalf) -> Self {
        HalfVector4 { x, y, z, w }
    }
    pub const fn e(&self) -> [InternalHalf; 4] {
        [self.x, self.y, self.z, self.w]
    }
}

/// A storage only class for half precision floating point vector 3.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct HalfVector3 {
    pub x: InternalHalf,
    pub y: InternalHalf,
    pub z: InternalHalf,
}

impl From<Vector3> for HalfVector3 {
    fn from(a: Vector3) -> HalfVector3 {
        HalfVector3 { x: scalar_to_half(a.x), y: scalar_to_half(a.y), z: scalar_to_half(a.z) }
    }
}

impl HalfVector3 {
    pub const fn new(x: InternalHalf, y: InternalHalf, z: InternalHalf) -> Self {
        HalfVector3 { x, y, z }
    }
    pub const fn e(&self) -> [InternalHalf; 3] {
        [self.x, self.y, self.z]
    }
}

/// A storage only class for half precision floating point vector 2.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct HalfVector2 {
    pub x: InternalHalf,
    pub y: InternalHalf,
}

impl From<Vector2> for HalfVector2 {
    fn from(a: Vector2) -> HalfVector2 {
        HalfVector2 { x: scalar_to_half(a.x), y: scalar_to_half(a.y) }
    }
}

impl HalfVector2 {
    pub const fn new(x: InternalHalf, y: InternalHalf) -> Self {
        HalfVector2 { x, y }
    }
    pub const fn e(&self) -> [InternalHalf; 2] {
        [self.x, self.y]
    }
}

const _: () = assert!(std::mem::size_of::<Half>() == std::mem::size_of::<u16>());
const _: () = assert!(std::mem::size_of::<HalfVector2>() == 2 * std::mem::size_of::<Half>());
const _: () = assert!(std::mem::size_of::<HalfVector3>() == 3 * std::mem::size_of::<Half>());
const _: () = assert!(std::mem::size_of::<HalfVector4>() == 4 * std::mem::size_of::<Half>());

impl fmt::Display for Half {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({})", crate::print::g(self.x as Scalar))
    }
}
impl fmt::Display for HalfVector2 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(f, "({}, {})", g(self.x as Scalar), g(self.y as Scalar))
    }
}
impl fmt::Display for HalfVector3 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(f, "({}, {}, {})", g(self.x as Scalar), g(self.y as Scalar), g(self.z as Scalar))
    }
}
impl fmt::Display for HalfVector4 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        let s = |v: InternalHalf| g(v as Scalar);
        write!(f, "({}, {}, {}, {})", s(self.x), s(self.y), s(self.z), s(self.w))
    }
}
