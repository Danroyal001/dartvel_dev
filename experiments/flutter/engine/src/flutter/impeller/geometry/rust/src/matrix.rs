// flutter/impeller/geometry/matrix.h, matrix.cc
//
// A 4x4 matrix using column-major storage. Upstream's union of `m[16]`,
// `e[4][4]` and `vec[4]` is the array `m`, with `e(i, j)` (`m[i * 4 + j]`)
// and `vec(i)`.

use std::fmt;
use std::ops::{Add, Mul, Sub};

use crate::constants::kEhCloseEnough;
use crate::cxx::{self, Num};
use crate::matrix_decomposition::MatrixDecomposition;
use crate::point::{Point, Quad, Vector2};
use crate::quaternion::Quaternion;
use crate::scalar::{Radians, Scalar, scalar_nearly_equal_tol, scalar_nearly_zero, scalar_nearly_zero_tol};
use crate::size::TSize;
use crate::vector::{Vector3, Vector4};

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct Matrix {
    pub m: [Scalar; 16],
}

const _: () = assert!(
    std::mem::size_of::<Matrix>() == std::mem::size_of::<Scalar>() * 16,
    "The matrix must be of consistent size."
);

impl Default for Matrix {
    /// Constructs a default identity matrix.
    fn default() -> Matrix {
        Matrix::IDENTITY
    }
}

impl Matrix {
    pub const IDENTITY: Matrix = Matrix::new(
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    );

    #[allow(clippy::too_many_arguments)]
    #[rustfmt::skip]
    pub const fn new(
        m0: Scalar, m1: Scalar, m2: Scalar, m3: Scalar,
        m4: Scalar, m5: Scalar, m6: Scalar, m7: Scalar,
        m8: Scalar, m9: Scalar, m10: Scalar, m11: Scalar,
        m12: Scalar, m13: Scalar, m14: Scalar, m15: Scalar,
    ) -> Matrix {
        Matrix { m: [m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15] }
    }

    pub const fn from_array(m: [Scalar; 16]) -> Matrix {
        Matrix { m }
    }

    #[inline(always)]
    pub const fn e(&self, i: usize, j: usize) -> Scalar {
        self.m[i * 4 + j]
    }

    #[inline(always)]
    pub fn e_mut(&mut self, i: usize, j: usize) -> &mut Scalar {
        &mut self.m[i * 4 + j]
    }

    #[inline(always)]
    pub const fn vec(&self, i: usize) -> Vector4 {
        Vector4::new(self.m[i * 4], self.m[i * 4 + 1], self.m[i * 4 + 2], self.m[i * 4 + 3])
    }

    /// `explicit Matrix(const MatrixDecomposition& decomposition)`.
    pub fn from_decomposition(d: &MatrixDecomposition) -> Matrix {
        let mut this = Matrix::default();
        // Apply perspective.
        let p = d.perspective;
        for i in 0..4 {
            *this.e_mut(i, 3) = p[i];
        }

        // Apply translation.
        let t = d.translation;
        for i in 0..3 {
            for j in 0..3 {
                *this.e_mut(3, i) += t[j] * this.e(j, i);
            }
        }

        // Apply rotation.
        let mut rotation = Matrix::default();

        let x = -d.rotation.x;
        let y = -d.rotation.y;
        let z = -d.rotation.z;
        let w = d.rotation.w;

        // Construct a composite rotation matrix from the quaternion values.
        *rotation.e_mut(0, 0) = (1.0 - 2.0 * (y * y + z * z) as f64) as Scalar;
        *rotation.e_mut(0, 1) = (2.0 * (x * y - z * w) as f64) as Scalar;
        *rotation.e_mut(0, 2) = (2.0 * (x * z + y * w) as f64) as Scalar;
        *rotation.e_mut(1, 0) = (2.0 * (x * y + z * w) as f64) as Scalar;
        *rotation.e_mut(1, 1) = (1.0 - 2.0 * (x * x + z * z) as f64) as Scalar;
        *rotation.e_mut(1, 2) = (2.0 * (y * z - x * w) as f64) as Scalar;
        *rotation.e_mut(2, 0) = (2.0 * (x * z - y * w) as f64) as Scalar;
        *rotation.e_mut(2, 1) = (2.0 * (y * z + x * w) as f64) as Scalar;
        *rotation.e_mut(2, 2) = (1.0 - 2.0 * (x * x + y * y) as f64) as Scalar;

        this = this * rotation;

        // Apply shear.
        let mut shear = Matrix::default();
        let s = d.shear.e();

        if s[2] != 0.0 {
            *shear.e_mut(2, 1) = s[2] as Scalar;
            this = this * shear;
        }

        if s[1] != 0.0 {
            *shear.e_mut(2, 1) = 0.0;
            *shear.e_mut(2, 0) = s[1] as Scalar;
            this = this * shear;
        }

        if s[0] != 0.0 {
            *shear.e_mut(2, 0) = 0.0;
            *shear.e_mut(1, 0) = s[0] as Scalar;
            this = this * shear;
        }

        // Apply scale.
        let sc = d.scale;
        for i in 0..3 {
            for j in 0..3 {
                *this.e_mut(i, j) *= sc[i];
            }
        }
        this
    }

    #[allow(clippy::too_many_arguments)]
    #[rustfmt::skip]
    pub const fn make_column(
        m0: Scalar, m1: Scalar, m2: Scalar, m3: Scalar,
        m4: Scalar, m5: Scalar, m6: Scalar, m7: Scalar,
        m8: Scalar, m9: Scalar, m10: Scalar, m11: Scalar,
        m12: Scalar, m13: Scalar, m14: Scalar, m15: Scalar,
    ) -> Matrix {
        Matrix::new(m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15)
    }

    #[allow(clippy::too_many_arguments)]
    #[rustfmt::skip]
    pub const fn make_row(
        m0: Scalar, m1: Scalar, m2: Scalar, m3: Scalar,
        m4: Scalar, m5: Scalar, m6: Scalar, m7: Scalar,
        m8: Scalar, m9: Scalar, m10: Scalar, m11: Scalar,
        m12: Scalar, m13: Scalar, m14: Scalar, m15: Scalar,
    ) -> Matrix {
        Matrix::new(m0, m4, m8, m12,
                    m1, m5, m9, m13,
                    m2, m6, m10, m14,
                    m3, m7, m11, m15)
    }

    #[rustfmt::skip]
    pub const fn make_translation(t: Vector3) -> Matrix {
        Matrix::new(1.0, 0.0, 0.0, 0.0,
                    0.0, 1.0, 0.0, 0.0,
                    0.0, 0.0, 1.0, 0.0,
                    t.x, t.y, t.z, 1.0)
    }

    #[rustfmt::skip]
    pub const fn make_scale(s: Vector3) -> Matrix {
        Matrix::new(s.x, 0.0, 0.0, 0.0,
                    0.0, s.y, 0.0, 0.0,
                    0.0, 0.0, s.z, 0.0,
                    0.0, 0.0, 0.0, 1.0)
    }

    #[rustfmt::skip]
    pub const fn make_translate_scale(s: Vector3, t: Vector3) -> Matrix {
        Matrix::new(s.x, 0.0, 0.0, 0.0,
                    0.0, s.y, 0.0, 0.0,
                    0.0, 0.0, s.z, 0.0,
                    t.x, t.y, t.z, 1.0)
    }

    /// `MakeScale(const Vector2& s)`.
    pub const fn make_scale2(s: Vector2) -> Matrix {
        Matrix::make_scale(Vector3::new(s.x, s.y, 1.0))
    }

    #[rustfmt::skip]
    pub const fn make_skew(sx: Scalar, sy: Scalar) -> Matrix {
        Matrix::new(1.0, sy, 0.0, 0.0,
                    sx, 1.0, 0.0, 0.0,
                    0.0, 0.0, 1.0, 0.0,
                    0.0, 0.0, 0.0, 1.0)
    }

    pub fn make_rotation(q: Quaternion) -> Matrix {
        Matrix::new(
            1.0 - 2.0 * q.y * q.y - 2.0 * q.z * q.z,
            2.0 * q.x * q.y + 2.0 * q.z * q.w,
            2.0 * q.x * q.z - 2.0 * q.y * q.w,
            0.0,
            2.0 * q.x * q.y - 2.0 * q.z * q.w,
            1.0 - 2.0 * q.x * q.x - 2.0 * q.z * q.z,
            2.0 * q.y * q.z + 2.0 * q.x * q.w,
            0.0,
            2.0 * q.x * q.z + 2.0 * q.y * q.w,
            2.0 * q.y * q.z - 2.0 * q.x * q.w,
            1.0 - 2.0 * q.x * q.x - 2.0 * q.y * q.y,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        )
    }

    /// `MakeRotation(Radians radians, const Vector4& r)`.
    pub fn make_rotation_axis(radians: Radians, r: &Vector4) -> Matrix {
        let v = r.normalize();

        let cos_sin = Matrix::cos_sin(radians);
        let cosine = cos_sin.x;
        let cosp = 1.0 - cosine;
        let sine = cos_sin.y;

        Matrix::new(
            cosine + cosp * v.x * v.x,
            cosp * v.x * v.y + v.z * sine,
            cosp * v.x * v.z - v.y * sine,
            0.0,
            cosp * v.x * v.y - v.z * sine,
            cosine + cosp * v.y * v.y,
            cosp * v.y * v.z + v.x * sine,
            0.0,
            cosp * v.x * v.z + v.y * sine,
            cosp * v.y * v.z - v.x * sine,
            cosine + cosp * v.z * v.z,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        )
    }

    #[rustfmt::skip]
    pub fn make_rotation_x(r: Radians) -> Matrix {
        let cos_sin = Matrix::cos_sin(r);
        let cosine = cos_sin.x;
        let sine = cos_sin.y;
        Matrix::new(
            1.0,  0.0,    0.0,    0.0,
            0.0,  cosine, sine,   0.0,
            0.0, -sine,   cosine, 0.0,
            0.0,  0.0,    0.0,    1.0,
        )
    }

    #[rustfmt::skip]
    pub fn make_rotation_y(r: Radians) -> Matrix {
        let cos_sin = Matrix::cos_sin(r);
        let cosine = cos_sin.x;
        let sine = cos_sin.y;
        Matrix::new(
            cosine, 0.0, -sine,  0.0,
            0.0,    1.0,  0.0,   0.0,
            sine,   0.0,  cosine, 0.0,
            0.0,    0.0,  0.0,   1.0,
        )
    }

    #[rustfmt::skip]
    pub fn make_rotation_z(r: Radians) -> Matrix {
        let cos_sin = Matrix::cos_sin(r);
        let cosine = cos_sin.x;
        let sine = cos_sin.y;
        Matrix::new(
            cosine, sine,   0.0, 0.0,
            -sine,  cosine, 0.0, 0.0,
            0.0,    0.0,    1.0, 0.0,
            0.0,    0.0,    0.0, 1.0,
        )
    }

    /// The Matrix without its `w` components (without translation).
    #[rustfmt::skip]
    pub const fn basis(&self) -> Matrix {
        let m = &self.m;
        Matrix::new(
            m[0], m[1], m[2],  0.0,
            m[4], m[5], m[6],  0.0,
            m[8], m[9], m[10], 0.0,
            0.0,  0.0,  0.0,   1.0,
        )
    }

    /// Returns the matrix without the Z components (the 3rd row and column).
    #[rustfmt::skip]
    pub const fn to3x3(&self) -> Matrix {
        let m = &self.m;
        Matrix::new(
            m[0],  m[1],  0.0, m[3],
            m[4],  m[5],  0.0, m[7],
            0.0,   0.0,   1.0, 0.0,
            m[12], m[13], 0.0, m[15],
        )
    }

    pub fn translate(&self, t: &Vector3) -> Matrix {
        let m = &self.m;
        Matrix::new(
            m[0], m[1], m[2], m[3],
            m[4], m[5], m[6], m[7],
            m[8], m[9], m[10], m[11],
            m[0] * t.x + m[4] * t.y + m[8] * t.z + m[12],
            m[1] * t.x + m[5] * t.y + m[9] * t.z + m[13],
            m[2] * t.x + m[6] * t.y + m[10] * t.z + m[14],
            m[3] * t.x + m[7] * t.y + m[11] * t.z + m[15],
        )
    }

    #[rustfmt::skip]
    pub fn scale(&self, s: &Vector3) -> Matrix {
        let m = &self.m;
        Matrix::new(m[0] * s.x, m[1] * s.x, m[2]  * s.x, m[3]  * s.x,
                    m[4] * s.y, m[5] * s.y, m[6]  * s.y, m[7]  * s.y,
                    m[8] * s.z, m[9] * s.z, m[10] * s.z, m[11] * s.z,
                    m[12],      m[13],      m[14],       m[15])
    }

    #[rustfmt::skip]
    pub fn multiply(&self, o: &Matrix) -> Matrix {
        let m = &self.m;
        let o = &o.m;
        Matrix::new(
            m[0] * o[0]  + m[4] * o[1]  + m[8]  * o[2]  + m[12] * o[3],
            m[1] * o[0]  + m[5] * o[1]  + m[9]  * o[2]  + m[13] * o[3],
            m[2] * o[0]  + m[6] * o[1]  + m[10] * o[2]  + m[14] * o[3],
            m[3] * o[0]  + m[7] * o[1]  + m[11] * o[2]  + m[15] * o[3],
            m[0] * o[4]  + m[4] * o[5]  + m[8]  * o[6]  + m[12] * o[7],
            m[1] * o[4]  + m[5] * o[5]  + m[9]  * o[6]  + m[13] * o[7],
            m[2] * o[4]  + m[6] * o[5]  + m[10] * o[6]  + m[14] * o[7],
            m[3] * o[4]  + m[7] * o[5]  + m[11] * o[6]  + m[15] * o[7],
            m[0] * o[8]  + m[4] * o[9]  + m[8]  * o[10] + m[12] * o[11],
            m[1] * o[8]  + m[5] * o[9]  + m[9]  * o[10] + m[13] * o[11],
            m[2] * o[8]  + m[6] * o[9]  + m[10] * o[10] + m[14] * o[11],
            m[3] * o[8]  + m[7] * o[9]  + m[11] * o[10] + m[15] * o[11],
            m[0] * o[12] + m[4] * o[13] + m[8]  * o[14] + m[12] * o[15],
            m[1] * o[12] + m[5] * o[13] + m[9]  * o[14] + m[13] * o[15],
            m[2] * o[12] + m[6] * o[13] + m[10] * o[14] + m[14] * o[15],
            m[3] * o[12] + m[7] * o[13] + m[11] * o[14] + m[15] * o[15])
    }

    #[rustfmt::skip]
    pub const fn transpose(&self) -> Matrix {
        let m = &self.m;
        Matrix::new(
            m[0], m[4], m[8],  m[12],
            m[1], m[5], m[9],  m[13],
            m[2], m[6], m[10], m[14],
            m[3], m[7], m[11], m[15],
        )
    }

    pub fn invert(&self) -> Matrix {
        let m = &self.m;
        let tmp: [Scalar; 16] = [
      m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
          m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10],
      -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
          m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10],
      m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
          m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6],
      -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
          m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6],
      -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
          m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10],
      m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
          m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10],
      -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
          m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6],
      m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
          m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6],
      m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
          m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9],
      -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
          m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9],
      m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
          m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5],
      -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
          m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5],
      -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
          m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9],
      m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
          m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9],
      -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
          m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5],
      m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
          m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5],
        ];

        let mut det: Scalar = m[0] * tmp[0] + m[1] * tmp[4] + m[2] * tmp[8] + m[3] * tmp[12];

        if det == 0.0 {
            return Matrix::default();
        }

        det = (1.0 / det as f64) as Scalar;

        Matrix::from_array(tmp.map(|t| t * det))
    }

    pub fn get_determinant(&self) -> Scalar {
        let a00 = self.e(0, 0);
        let a01 = self.e(0, 1);
        let a02 = self.e(0, 2);
        let a03 = self.e(0, 3);
        let a10 = self.e(1, 0);
        let a11 = self.e(1, 1);
        let a12 = self.e(1, 2);
        let a13 = self.e(1, 3);
        let a20 = self.e(2, 0);
        let a21 = self.e(2, 1);
        let a22 = self.e(2, 2);
        let a23 = self.e(2, 3);
        let a30 = self.e(3, 0);
        let a31 = self.e(3, 1);
        let a32 = self.e(3, 2);
        let a33 = self.e(3, 3);

        let b00 = a00 * a11 - a01 * a10;
        let b01 = a00 * a12 - a02 * a10;
        let b02 = a00 * a13 - a03 * a10;
        let b03 = a01 * a12 - a02 * a11;
        let b04 = a01 * a13 - a03 * a11;
        let b05 = a02 * a13 - a03 * a12;
        let b06 = a20 * a31 - a21 * a30;
        let b07 = a20 * a32 - a22 * a30;
        let b08 = a20 * a33 - a23 * a30;
        let b09 = a21 * a32 - a22 * a31;
        let b10 = a21 * a33 - a23 * a31;
        let b11 = a22 * a33 - a23 * a32;

        b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
    }

    pub fn is_invertible(&self) -> bool {
        self.get_determinant() != 0.0
    }

    pub fn get_max_basis_length_xy(&self) -> Scalar {
        // The full basis computation requires computing the squared scaling
        // factor for translate/scale only matrices. This substantially limits
        // the range of precision for small and large scales. Instead, check
        // for the common cases and directly return the max scaling factor.
        if self.e(0, 1) == 0.0 && self.e(1, 0) == 0.0 {
            return cxx::max(self.e(0, 0).abs(), self.e(1, 1).abs());
        }
        cxx::max(
            self.e(0, 0) * self.e(0, 0) + self.e(0, 1) * self.e(0, 1),
            self.e(1, 0) * self.e(1, 0) + self.e(1, 1) * self.e(1, 1),
        )
        .sqrt()
    }

    /// Return the smaller of the two non-negative scales that will be
    /// applied to 2D coordinates by this matrix.
    pub fn get_min_scale_2d(&self) -> Option<Scalar> {
        let scales = self.get_scales_2d()?;
        Some(cxx::min(scales.0, scales.1))
    }

    /// Return the larger of the two non-negative scales.
    pub fn get_max_scale_2d(&self) -> Option<Scalar> {
        let scales = self.get_scales_2d()?;
        Some(cxx::max(scales.0, scales.1))
    }

    pub const fn get_basis_x(&self) -> Vector3 {
        Vector3::new(self.m[0], self.m[1], self.m[2])
    }

    pub const fn get_basis_y(&self) -> Vector3 {
        Vector3::new(self.m[4], self.m[5], self.m[6])
    }

    pub const fn get_basis_z(&self) -> Vector3 {
        Vector3::new(self.m[8], self.m[9], self.m[10])
    }

    pub fn get_scale(&self) -> Vector3 {
        Vector3::new(
            self.get_basis_x().get_length(),
            self.get_basis_y().get_length(),
            self.get_basis_z().get_length(),
        )
    }

    pub const fn get_basis_x_2d(&self) -> Vector2 {
        Vector2::new(self.m[0], self.m[1])
    }

    pub const fn get_basis_y_2d(&self) -> Vector2 {
        Vector2::new(self.m[4], self.m[5])
    }

    /// Return the 2D lengths of the X and Y basis vectors.
    pub fn get_basis_scale_xy(&self) -> Vector2 {
        Vector2::new(self.get_basis_x_2d().get_length(), self.get_basis_y_2d().get_length())
    }

    /// The size, in local coordinates, of a single device pixel.
    pub fn get_transformed_pixel_size(&self) -> Vector2 {
        let m = &self.m;
        if m[1] == 0.0 && m[4] == 0.0 {
            if m[0] == 0.0 || m[5] == 0.0 {
                return Vector2::default();
            }
            return Vector2::new(1.0 / m[0].abs(), 1.0 / m[5].abs());
        }
        let det: Scalar = m[0] * m[5] - m[1] * m[4];
        if scalar_nearly_zero(det) {
            return Vector2::default();
        }
        let abs_det = det.abs();
        Vector2::new(
            self.get_basis_y_2d().get_length() / abs_det,
            self.get_basis_x_2d().get_length() / abs_det,
        )
    }

    pub fn get_direction_scale(&self, direction: Vector3) -> Scalar {
        1.0 / (self.basis().invert() * direction.normalize()).get_length() * direction.get_length()
    }

    pub fn is_finite(&self) -> bool {
        self.vec(0).is_finite() && self.vec(1).is_finite() && self.vec(2).is_finite() && self.vec(3).is_finite()
    }

    pub fn is_affine(&self) -> bool {
        let m = &self.m;
        m[2] == 0.0
            && m[3] == 0.0
            && m[6] == 0.0
            && m[7] == 0.0
            && m[8] == 0.0
            && m[9] == 0.0
            && m[10] == 1.0
            && m[11] == 0.0
            && m[14] == 0.0
            && m[15] == 1.0
    }

    pub fn has_perspective_2d(&self) -> bool {
        self.m[3] != 0.0 || self.m[7] != 0.0 || self.m[15] != 1.0
    }

    pub fn has_perspective(&self) -> bool {
        self.m[3] != 0.0 || self.m[7] != 0.0 || self.m[11] != 0.0 || self.m[15] != 1.0
    }

    pub fn has_translation(&self) -> bool {
        self.m[12] != 0.0 || self.m[13] != 0.0
    }

    pub fn is_aligned_2d(&self) -> bool {
        self.is_aligned_2d_tol(0.0)
    }

    pub fn is_aligned_2d_tol(&self, tolerance: Scalar) -> bool {
        if self.has_perspective_2d() {
            return false;
        }
        let m = &self.m;
        if scalar_nearly_zero_tol(m[1], tolerance) && scalar_nearly_zero_tol(m[4], tolerance) {
            return true;
        }
        if scalar_nearly_zero_tol(m[0], tolerance) && scalar_nearly_zero_tol(m[5], tolerance) {
            return true;
        }
        false
    }

    pub fn is_aligned(&self) -> bool {
        self.is_aligned_tol(0.0)
    }

    pub fn is_aligned_tol(&self, tolerance: Scalar) -> bool {
        if self.has_perspective() {
            return false;
        }
        let m = &self.m;
        let nz = |v: Scalar| !scalar_nearly_zero_tol(v, tolerance) as i32;
        let v = [nz(m[0]), nz(m[1]), nz(m[2]), nz(m[4]), nz(m[5]), nz(m[6]), nz(m[8]), nz(m[9]), nz(m[10])];
        // Check if all three basis vectors are aligned to an axis.
        if v[0] + v[1] + v[2] != 1 || v[3] + v[4] + v[5] != 1 || v[6] + v[7] + v[8] != 1 {
            return false;
        }
        // Ensure that none of the basis vectors overlap.
        if v[0] + v[3] + v[6] != 1 || v[1] + v[4] + v[7] != 1 || v[2] + v[5] + v[8] != 1 {
            return false;
        }
        true
    }

    pub fn is_identity(&self) -> bool {
        let m = &self.m;
        m[0] == 1.0 && m[1] == 0.0 && m[2] == 0.0 && m[3] == 0.0
            && m[4] == 0.0 && m[5] == 1.0 && m[6] == 0.0 && m[7] == 0.0
            && m[8] == 0.0 && m[9] == 0.0 && m[10] == 1.0 && m[11] == 0.0
            && m[12] == 0.0 && m[13] == 0.0 && m[14] == 0.0 && m[15] == 1.0
    }

    /// Returns true if the matrix has no entries other than translation
    /// components. Note that an identity matrix meets this criteria.
    pub fn is_translation_only(&self) -> bool {
        let m = &self.m;
        m[0] == 1.0 && m[1] == 0.0 && m[2] == 0.0 && m[3] == 0.0
            && m[4] == 0.0 && m[5] == 1.0 && m[6] == 0.0 && m[7] == 0.0
            && m[8] == 0.0 && m[9] == 0.0 && m[10] == 1.0 && m[11] == 0.0
            && m[15] == 1.0
    }

    /// Returns true if the matrix has a scale-only basis and is
    /// non-projective. Note that an identity matrix meets this criteria.
    pub fn is_translation_scale_only(&self) -> bool {
        let m = &self.m;
        m[0] != 0.0 && m[1] == 0.0 && m[2] == 0.0 && m[3] == 0.0
            && m[4] == 0.0 && m[5] != 0.0 && m[6] == 0.0 && m[7] == 0.0
            && m[8] == 0.0 && m[9] == 0.0 && m[10] != 0.0 && m[11] == 0.0
            && m[15] == 1.0
    }

    /// Adapted for Impeller from Graphics Gems:
    /// http://www.realtimerendering.com/resources/GraphicsGems/gemsii/unmatrix.c
    pub fn decompose(&self) -> Option<MatrixDecomposition> {
        // Normalize the matrix.
        let mut self_ = *self;

        if self_.e(3, 3) == 0.0 {
            return None;
        }

        for i in 0..4 {
            for j in 0..4 {
                let d = self_.e(3, 3);
                *self_.e_mut(i, j) /= d;
            }
        }

        // `perspectiveMatrix` is used to solve for perspective, but it also
        // provides an easy way to test for singularity of the upper 3x3
        // component.
        let mut perpectiveMatrix = self_;
        for i in 0..3 {
            *perpectiveMatrix.e_mut(i, 3) = 0.0;
        }

        *perpectiveMatrix.e_mut(3, 3) = 1.0;

        if !perpectiveMatrix.is_invertible() {
            return None;
        }

        let mut result = MatrixDecomposition::default();

        // First, isolate perspective.
        if self_.e(0, 3) != 0.0 || self_.e(1, 3) != 0.0 || self_.e(2, 3) != 0.0 {
            // prhs is the right hand side of the equation.
            let rightHandSide =
                Vector4::new(self_.e(0, 3), self_.e(1, 3), self_.e(2, 3), self_.e(3, 3));

            // Solve the equation by inverting `perspectiveMatrix` and
            // multiplying prhs by the inverse.
            result.perspective = perpectiveMatrix.invert().transpose() * rightHandSide;

            // Clear the perspective partition.
            *self_.e_mut(0, 3) = 0.0;
            *self_.e_mut(1, 3) = 0.0;
            *self_.e_mut(2, 3) = 0.0;
            *self_.e_mut(3, 3) = 1.0;
        }

        // Next, the translation.
        result.translation = Vector3::new(self_.e(3, 0), self_.e(3, 1), self_.e(3, 2));
        *self_.e_mut(3, 0) = 0.0;
        *self_.e_mut(3, 1) = 0.0;
        *self_.e_mut(3, 2) = 0.0;

        // Next, the scale and shear.
        let mut row = [Vector3::default(); 3];
        for (i, r) in row.iter_mut().enumerate() {
            r.x = self_.e(i, 0);
            r.y = self_.e(i, 1);
            r.z = self_.e(i, 2);
        }

        // Compute X scale factor and normalize first row.
        result.scale.x = row[0].get_length();
        row[0] = row[0].normalize();

        // Compute XY shear factor and make 2nd row orthogonal to 1st.
        result.shear.xy = row[0].dot(&row[1]) as f64;
        row[1] = Vector3::combine(&row[1], 1.0, &row[0], -result.shear.xy as Scalar);

        // Compute Y scale and normalize 2nd row.
        result.scale.y = row[1].get_length();
        row[1] = row[1].normalize();
        result.shear.xy /= result.scale.y as f64;

        // Compute XZ and YZ shears, orthogonalize 3rd row.
        result.shear.xz = row[0].dot(&row[2]) as f64;
        row[2] = Vector3::combine(&row[2], 1.0, &row[0], -result.shear.xz as Scalar);
        result.shear.yz = row[1].dot(&row[2]) as f64;
        row[2] = Vector3::combine(&row[2], 1.0, &row[1], -result.shear.yz as Scalar);

        // Next, get Z scale and normalize 3rd row.
        result.scale.z = row[2].get_length();
        row[2] = row[2].normalize();

        result.shear.xz /= result.scale.z as f64;
        result.shear.yz /= result.scale.z as f64;

        // At this point, the matrix (in rows[]) is orthonormal. Check for a
        // coordinate system flip. If the determinant is -1, then negate the
        // matrix and the scaling factors.
        if row[0].dot(&row[1].cross(&row[2])) < 0.0 {
            result.scale.x *= -1.0;
            result.scale.y *= -1.0;
            result.scale.z *= -1.0;

            for r in row.iter_mut() {
                r.x *= -1.0;
                r.y *= -1.0;
                r.z *= -1.0;
            }
        }

        // Finally, get the rotations out.
        let q = |v: f64| (0.5 * v.max_cxx_fmax(0.0).sqrt()) as Scalar;
        result.rotation.x = q(1.0 + row[0].x as f64 - row[1].y as f64 - row[2].z as f64);
        result.rotation.y = q(1.0 - row[0].x as f64 + row[1].y as f64 - row[2].z as f64);
        result.rotation.z = q(1.0 - row[0].x as f64 - row[1].y as f64 + row[2].z as f64);
        result.rotation.w = q(1.0 + row[0].x as f64 + row[1].y as f64 + row[2].z as f64);

        if row[2].y > row[1].z {
            result.rotation.x = -result.rotation.x;
        }
        if row[0].z > row[2].x {
            result.rotation.y = -result.rotation.y;
        }
        if row[1].x > row[0].y {
            result.rotation.z = -result.rotation.z;
        }

        Some(result)
    }

    /// Computed in double, as upstream does.
    pub fn get_scales_2d(&self) -> Option<(Scalar, Scalar)> {
        if self.has_perspective_2d() {
            return None;
        }

        // We only operate on the uppermost 2x2 matrix since those are the only
        // values that can induce a scale on 2D coordinates.
        // [a b]
        // [c d]
        let a: f64 = self.m[0] as f64;
        let b: f64 = self.m[1] as f64;
        let c: f64 = self.m[4] as f64;
        let d: f64 = self.m[5] as f64;

        if b == 0.0 && c == 0.0 {
            return Some((a.abs() as Scalar, d.abs() as Scalar));
        }

        if a == 0.0 && d == 0.0 {
            return Some((b.abs() as Scalar, c.abs() as Scalar));
        }

        // Compute eigenvalues for the matrix (transpose(A) * A):
        // [a2 b2] == [a b] [a c] == [aa + bb   ac + bd]
        // [c2 d2]    [c d] [b d]    [ac + bd   cc + dd]
        // (note the reverse order of the 2 matrix multiplications)
        let a2 = a * a + b * b;
        let b2 = a * c + b * d;
        let c2 = b2;
        let d2 = c * c + d * d;

        // quadratic equation: A = 1, B = -(a2 + d2), C = a2 d2 - b2 c2.
        let minus_B = a2 + d2;
        let C = a2 * d2 - b2 * c2;
        let B_squared_minus_4AC = minus_B * minus_B - (4.0f32 * 1.0f32) as f64 * C;

        let quadratic_sqrt: f64;
        if B_squared_minus_4AC <= 0.0 {
            // This test should never fail, but we might be slightly negative
            fml::fml_dcheck_at!(
                "flutter/impeller/geometry/matrix.cc",
                417,
                "B_squared_minus_4AC + kEhCloseEnough >= 0.0f",
                B_squared_minus_4AC + kEhCloseEnough as f64 >= 0.0
            );
            // Uniform scales (possibly rotated) would tend to end up here
            // in which case both eigenvalues are identical
            quadratic_sqrt = 0.0;
        } else {
            quadratic_sqrt = B_squared_minus_4AC.sqrt();
        }

        // Since this is iterating on transpose(A) * A, the eigenvalues are
        // the squares of the scales in the matrix.
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/matrix.cc",
            427,
            "minus_B - quadratic_sqrt >= 0.0f",
            minus_B - quadratic_sqrt >= 0.0
        );
        fml::fml_dcheck_at!(
            "flutter/impeller/geometry/matrix.cc",
            428,
            "minus_B + quadratic_sqrt >= 0.0f",
            minus_B + quadratic_sqrt >= 0.0
        );
        Some((
            ((minus_B - quadratic_sqrt) / 2.0).sqrt() as Scalar,
            ((minus_B + quadratic_sqrt) / 2.0).sqrt() as Scalar,
        ))
    }

    pub fn equals(&self, matrix: &Matrix) -> bool {
        self.equals_eps(matrix, 1e-5)
    }

    pub fn equals_eps(&self, matrix: &Matrix, epsilon: Scalar) -> bool {
        let (a, b) = (&self.m, &matrix.m);
        (0..16).all(|i| scalar_nearly_equal_tol(a[i], b[i], epsilon))
    }

    pub fn transform_homogenous(&self, v: &Point) -> Vector3 {
        let m = &self.m;
        Vector3::new(
            v.x * m[0] + v.y * m[4] + m[12],
            v.x * m[1] + v.y * m[5] + m[13],
            v.x * m[3] + v.y * m[7] + m[15],
        )
    }

    pub fn transform_direction4(&self, v: &Vector4) -> Vector4 {
        let m = &self.m;
        Vector4::new(
            v.x * m[0] + v.y * m[4] + v.z * m[8],
            v.x * m[1] + v.y * m[5] + v.z * m[9],
            v.x * m[2] + v.y * m[6] + v.z * m[10],
            v.w,
        )
    }

    pub fn transform_direction3(&self, v: &Vector3) -> Vector3 {
        let m = &self.m;
        Vector3::new(
            v.x * m[0] + v.y * m[4] + v.z * m[8],
            v.x * m[1] + v.y * m[5] + v.z * m[9],
            v.x * m[2] + v.y * m[6] + v.z * m[10],
        )
    }

    pub fn transform_direction2(&self, v: &Vector2) -> Vector2 {
        let m = &self.m;
        Vector2::new(v.x * m[0] + v.y * m[4], v.x * m[1] + v.y * m[5])
    }

    pub fn transform(&self, quad: &Quad) -> Quad {
        [*self * quad[0], *self * quad[1], *self * quad[2], *self * quad[3]]
    }

    pub fn make_orthographic<T: Num>(size: TSize<T>) -> Matrix {
        // Per assumptions about NDC documented above.
        let scale = Matrix::make_scale(Vector3::new(
            2.0 / size.width.to_f32(),
            -2.0 / size.height.to_f32(),
            0.0,
        ));
        let translate = Matrix::make_translation(Vector3::new(-1.0, 1.0, 0.5));
        translate * scale
    }

    #[rustfmt::skip]
    pub fn make_perspective(fov_y: Radians, aspect_ratio: Scalar, z_near: Scalar, z_far: Scalar) -> Matrix {
        let height: Scalar = (fov_y.radians * 0.5).tan();
        let width: Scalar = height * aspect_ratio;

        Matrix::new(
            1.0 / width, 0.0,          0.0,                               0.0,
            0.0,         1.0 / height, 0.0,                               0.0,
            0.0,         0.0,          z_far / (z_far - z_near),          1.0,
            0.0,         0.0,          -(z_far * z_near) / (z_far - z_near), 0.0,
        )
    }

    pub fn make_perspective_size<T: Num>(fov_y: Radians, size: TSize<T>, z_near: Scalar, z_far: Scalar) -> Matrix {
        let aspect: Scalar = size.width.to_f32().op(crate::cxx::Op::Div, size.height);
        Matrix::make_perspective(fov_y, aspect, z_near, z_far)
    }

    #[rustfmt::skip]
    pub fn make_look_at(position: Vector3, target: Vector3, mut up: Vector3) -> Matrix {
        let forward = (target - position).normalize();
        let right = up.cross(&forward);
        up = forward.cross(&right);

        Matrix::new(
             right.x,               up.x,               forward.x,               0.0,
             right.y,               up.y,               forward.y,               0.0,
             right.z,               up.z,               forward.z,               0.0,
            -right.dot(&position), -up.dot(&position), -forward.dot(&position), 1.0,
        )
    }

    pub fn cos_sin(radians: Radians) -> Vector2 {
        let sin = radians.radians.sin();
        if sin.abs() == 1.0 {
            // When sin is exactly 1 or -1, cos is exactly 0.
            Vector2::new(0.0, sin)
        } else {
            let cos = radians.radians.cos();
            if cos.abs() == 1.0 {
                // When cos is exactly 1 or -1, sin is exactly 0.
                return Vector2::new(cos, 0.0);
            }
            Vector2::new(cos, sin)
        }
    }
}

/// `fmax` (not `std::max`): a NaN argument yields the other one.
trait CxxFmax {
    fn max_cxx_fmax(self, o: f64) -> f64;
}
impl CxxFmax for f64 {
    #[inline(always)]
    fn max_cxx_fmax(self, o: f64) -> f64 {
        self.max(o)
    }
}

impl PartialEq for Matrix {
    fn eq(&self, m: &Matrix) -> bool {
        self.vec(0) == m.vec(0) && self.vec(1) == m.vec(1) && self.vec(2) == m.vec(2) && self.vec(3) == m.vec(3)
    }
}

/// `operator+(const Vector3& t)`: Translate(t).
impl Add<Vector3> for Matrix {
    type Output = Matrix;
    fn add(self, t: Vector3) -> Matrix {
        self.translate(&t)
    }
}

/// `operator-(const Vector3& t)`: Translate(-t).
impl Sub<Vector3> for Matrix {
    type Output = Matrix;
    fn sub(self, t: Vector3) -> Matrix {
        self.translate(&-t)
    }
}

impl Mul<Matrix> for Matrix {
    type Output = Matrix;
    fn mul(self, m: Matrix) -> Matrix {
        self.multiply(&m)
    }
}

impl Add<Matrix> for Matrix {
    type Output = Matrix;
    fn add(self, o: Matrix) -> Matrix {
        let (m, o) = (&self.m, &o.m);
        Matrix::from_array(std::array::from_fn(|i| m[i] + o[i]))
    }
}

impl Mul<Vector4> for Matrix {
    type Output = Vector4;
    fn mul(self, v: Vector4) -> Vector4 {
        let m = &self.m;
        Vector4::new(
            v.x * m[0] + v.y * m[4] + v.z * m[8] + v.w * m[12],
            v.x * m[1] + v.y * m[5] + v.z * m[9] + v.w * m[13],
            v.x * m[2] + v.y * m[6] + v.z * m[10] + v.w * m[14],
            v.x * m[3] + v.y * m[7] + v.z * m[11] + v.w * m[15],
        )
    }
}

impl Mul<Vector3> for Matrix {
    type Output = Vector3;
    fn mul(self, v: Vector3) -> Vector3 {
        let m = &self.m;
        let mut w: Scalar = v.x * m[3] + v.y * m[7] + v.z * m[11] + m[15];
        let result = Vector3::new(
            v.x * m[0] + v.y * m[4] + v.z * m[8] + m[12],
            v.x * m[1] + v.y * m[5] + v.z * m[9] + m[13],
            v.x * m[2] + v.y * m[6] + v.z * m[10] + m[14],
        );

        // This is Skia's behavior, but it may be reasonable to allow UB for
        // the w=0 case.
        if w != 0.0 {
            w = 1.0 / w;
        }
        result * w
    }
}

impl Mul<Point> for Matrix {
    type Output = Point;
    fn mul(self, v: Point) -> Point {
        let m = &self.m;
        let mut w: Scalar = v.x * m[3] + v.y * m[7] + m[15];
        let result = Point::new(v.x * m[0] + v.y * m[4] + m[12], v.x * m[1] + v.y * m[5] + m[13]);

        // This is Skia's behavior, but it may be reasonable to allow UB for
        // the w=0 case.
        if w != 0.0 {
            w = 1.0 / w;
        }
        result * w
    }
}

/// `out << matrix`: `std::fixed`, each entry `std::setw(15)`, rows of the
/// transposed array.
impl fmt::Display for Matrix {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "(")?;
        for i in 0..4 {
            for j in 0..4 {
                write!(f, "{:>15},", crate::print::fixed(self.e(j, i)))?;
            }
            writeln!(f)?;
        }
        write!(f, ")")
    }
}
