// flutter/impeller/geometry/quaternion.h, quaternion.cc

use std::fmt;
use std::ops::{Add, Mul, Sub};

use crate::scalar::Scalar;
use crate::vector::Vector3;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Quaternion {
    pub x: Scalar,
    pub y: Scalar,
    pub z: Scalar,
    pub w: Scalar,
}

impl Default for Quaternion {
    fn default() -> Quaternion {
        Quaternion { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }
    }
}

impl Quaternion {
    pub const fn new(px: Scalar, py: Scalar, pz: Scalar, pw: Scalar) -> Quaternion {
        Quaternion { x: px, y: py, z: pz, w: pw }
    }

    /// `Quaternion(const Vector3& axis, Scalar angle)`.
    pub fn from_axis_angle(axis: &Vector3, angle: Scalar) -> Quaternion {
        let sine = (angle * 0.5).sin();
        Quaternion { x: sine * axis.x, y: sine * axis.y, z: sine * axis.z, w: (angle * 0.5).cos() }
    }

    pub const fn e(&self) -> [Scalar; 4] {
        [self.x, self.y, self.z, self.w]
    }

    pub fn dot(&self, q: &Quaternion) -> Scalar {
        self.x * q.x + self.y * q.y + self.z * q.z + self.w * q.w
    }

    pub fn length(&self) -> Scalar {
        (self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w).sqrt()
    }

    pub fn normalize(&self) -> Quaternion {
        let m = 1.0 / self.length();
        Quaternion::new(self.x * m, self.y * m, self.z * m, self.w * m)
    }

    pub fn invert(&self) -> Quaternion {
        Quaternion::new(-self.x, -self.y, -self.z, self.w)
    }

    /// Computed in double; the coefficients are narrowed to Scalar by
    /// `operator*(Scalar)`.
    pub fn slerp(&self, to: &Quaternion, time: f64) -> Quaternion {
        let cosine: f64 = self.dot(to) as f64;
        if cosine.abs() < 1.0 - 1e-3 /* epsilon */ {
            // Spherical Interpolation.
            let sine = (1.0 - cosine * cosine).sqrt();
            let angle = sine.atan2(cosine);
            let sineInverse = 1.0 / sine;
            let c0 = ((1.0 - time) * angle).sin() * sineInverse;
            let c1 = (time * angle).sin() * sineInverse;
            *self * c0 as Scalar + *to * c1 as Scalar
        } else {
            // Linear Interpolation.
            (*self * (1.0 - time) as Scalar + *to * time as Scalar).normalize()
        }
    }
}

impl Mul<Quaternion> for Quaternion {
    type Output = Quaternion;
    fn mul(self, o: Quaternion) -> Quaternion {
        let (x, y, z, w) = (self.x, self.y, self.z, self.w);
        Quaternion::new(
            w * o.x + x * o.w + y * o.z - z * o.y,
            w * o.y + y * o.w + z * o.x - x * o.z,
            w * o.z + z * o.w + x * o.y - y * o.x,
            w * o.w - x * o.x - y * o.y - z * o.z,
        )
    }
}

impl Mul<Scalar> for Quaternion {
    type Output = Quaternion;
    fn mul(self, scale: Scalar) -> Quaternion {
        Quaternion::new(scale * self.x, scale * self.y, scale * self.z, scale * self.w)
    }
}

impl Mul<Vector3> for Quaternion {
    type Output = Vector3;
    fn mul(self, vector: Vector3) -> Vector3 {
        let v = Vector3::new(self.x, self.y, self.z);
        v * v.dot(&vector) * 2i32
            + vector * (self.w * self.w - v.dot(&v))
            + v.cross(&vector) * 2i32 * self.w
    }
}

impl Add for Quaternion {
    type Output = Quaternion;
    fn add(self, o: Quaternion) -> Quaternion {
        Quaternion::new(self.x + o.x, self.y + o.y, self.z + o.z, self.w + o.w)
    }
}

impl Sub for Quaternion {
    type Output = Quaternion;
    fn sub(self, o: Quaternion) -> Quaternion {
        Quaternion::new(self.x - o.x, self.y - o.y, self.z - o.z, self.w - o.w)
    }
}

impl fmt::Display for Quaternion {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(f, "({}, {}, {}, {})", g(self.x), g(self.y), g(self.z), g(self.w))
    }
}
