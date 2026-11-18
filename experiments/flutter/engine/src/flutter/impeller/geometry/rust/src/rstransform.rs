// flutter/impeller/geometry/rstransform.h, rstransform.cc

use std::fmt;

use crate::matrix::Matrix;
use crate::point::{Point, Quad};
use crate::rect::Rect;
use crate::scalar::{Radians, Scalar};
use crate::size::Size;

/// A utility struct that stores a simple transform composed of a translation,
/// a rotation, and a uniform scale.
///
/// This transform is used by drawAtlas to transform the sprites. This
/// structure mirrors the Flutter RSTransform class.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RSTransform {
    pub scaled_cos: Scalar,
    pub scaled_sin: Scalar,
    pub translate_x: Scalar,
    pub translate_y: Scalar,
}

impl Default for RSTransform {
    #[inline]
    fn default() -> RSTransform {
        RSTransform { scaled_cos: 1.0, scaled_sin: 0.0, translate_x: 0.0, translate_y: 0.0 }
    }
}

impl RSTransform {
    #[inline]
    pub const fn new(
        scaled_cos: Scalar,
        scaled_sin: Scalar,
        translate_x: Scalar,
        translate_y: Scalar,
    ) -> RSTransform {
        RSTransform { scaled_cos, scaled_sin, translate_x, translate_y }
    }

    #[inline]
    pub fn make(origin: Point, scale: Scalar, radians: Radians) -> RSTransform {
        let scaled_cos_sin = Matrix::cos_sin(radians) * scale;
        RSTransform::new(scaled_cos_sin.x, scaled_cos_sin.y, origin.x, origin.y)
    }

    /// Returns true iff the resulting transformed quad will be aligned with
    /// the axes, even if rotated by a quadrant rotation.
    pub fn is_axis_aligned(&self) -> bool {
        self.scaled_cos == 0.0 || self.scaled_sin == 0.0
    }

    #[rustfmt::skip]
    pub fn get_matrix(&self) -> Matrix {
        Matrix::make_row(self.scaled_cos, -self.scaled_sin, 0.0, self.translate_x,
                         self.scaled_sin,  self.scaled_cos, 0.0, self.translate_y,
                         0.0,              0.0,             1.0, 0.0,
                         0.0,              0.0,             0.0, 1.0)
    }

    #[inline]
    /// Returns the 4 corner points of the transformed quad for a sub-image
    /// of the indicated size in the same order as Rect::GetPoints.
    pub fn get_quad_into(&self, width: Scalar, height: Scalar, quad: &mut Quad) {
        let origin = Point::new(self.translate_x, self.translate_y);
        let dx = width * Point::new(self.scaled_cos, self.scaled_sin);
        let dy = height * Point::new(-self.scaled_sin, self.scaled_cos);
        *quad = [origin, origin + dx, origin + dy, origin + dx + dy];
    }

    pub fn get_quad(&self, width: Scalar, height: Scalar) -> Quad {
        let mut quad = Quad::default();
        self.get_quad_into(width, height, &mut quad);
        quad
    }

    #[inline]
    pub fn get_quad_size(&self, size: Size) -> Quad {
        let mut quad = Quad::default();
        self.get_quad_into(size.width, size.height, &mut quad);
        quad
    }

    /// Returns the bounds of the 4 corner points of the transformed quad
    /// for a sub-image of the indicated size.
    pub fn get_bounds(&self, width: Scalar, height: Scalar) -> Option<Rect> {
        Rect::make_point_bounds(&self.get_quad(width, height))
    }

    #[inline]
    pub fn get_bounds_size(&self, size: Size) -> Option<Rect> {
        Rect::make_point_bounds(&self.get_quad_size(size))
    }
}

impl fmt::Display for RSTransform {
    #[inline]
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(
            f,
            "(scos: {}, ssin: {}, origin: ({}, {}))",
            g(self.scaled_cos),
            g(self.scaled_sin),
            g(self.translate_x),
            g(self.translate_y)
        )
    }
}
