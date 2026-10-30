// flutter/impeller/geometry/trig.h (trig.cc is empty)

use std::ops::{Mul, Neg};

use crate::point::Vector2;
use crate::scalar::{Radians, Scalar};
use crate::size::Size;

/// A structure to store the sine and cosine of an angle.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Trig {
    pub cos: f64,
    pub sin: f64,
}

impl Trig {
    #[inline]
    /// Construct a Trig object from a given angle in radians. The cosine
    /// and sine are those of the float (`cosf`, `sinf`), widened.
    pub fn from_radians(r: Radians) -> Trig {
        Trig { cos: r.radians.cos() as f64, sin: r.radians.sin() as f64 }
    }

    #[inline]
    /// Construct a Trig object from the given cosine and sine values.
    pub const fn new(cos: f64, sin: f64) -> Trig {
        Trig { cos, sin }
    }
}

impl Mul<Vector2> for Trig {
    type Output = Vector2;
    #[inline]
    fn mul(self, vector: Vector2) -> Vector2 {
        Vector2::new(
            (vector.x as f64 * self.cos - vector.y as f64 * self.sin) as Scalar,
            (vector.x as f64 * self.sin + vector.y as f64 * self.cos) as Scalar,
        )
    }
}

impl Neg for Trig {
    type Output = Trig;
    #[inline]
    fn neg(self) -> Trig {
        Trig::new(self.cos, -self.sin)
    }
}

impl Mul<f64> for Trig {
    type Output = Vector2;
    #[inline]
    fn mul(self, radius: f64) -> Vector2 {
        Vector2::new((self.cos * radius) as Scalar, (self.sin * radius) as Scalar)
    }
}

impl Mul<Size> for Trig {
    type Output = Vector2;
    #[inline]
    fn mul(self, ellipse_radii: Size) -> Vector2 {
        Vector2::new(
            (self.cos * ellipse_radii.width as f64) as Scalar,
            (self.sin * ellipse_radii.height as f64) as Scalar,
        )
    }
}
