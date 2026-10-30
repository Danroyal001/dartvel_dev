// flutter/impeller/geometry/rounding_radii.h, rounding_radii.cc

use std::fmt;
use std::ops::Mul;

use crate::constants::kEhCloseEnough;
use crate::cxx;
use crate::rect::Rect;
use crate::scalar::{Scalar, scalar_nearly_equal, scalar_nearly_equal_tol};
use crate::size::Size;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RoundingRadii {
    pub top_left: Size,
    pub top_right: Size,
    pub bottom_left: Size,
    pub bottom_right: Size,
}

impl RoundingRadii {
    pub fn make_radius(radius: Scalar) -> RoundingRadii {
        let s = Size::splat(radius);
        RoundingRadii { top_left: s, top_right: s, bottom_left: s, bottom_right: s }
    }

    pub fn make_radii(radii: Size) -> RoundingRadii {
        RoundingRadii { top_left: radii, top_right: radii, bottom_left: radii, bottom_right: radii }
    }

    pub fn make_nine_patch(left: Scalar, top: Scalar, right: Scalar, bottom: Scalar) -> RoundingRadii {
        RoundingRadii {
            top_left: Size::new(left, top),
            top_right: Size::new(right, top),
            bottom_left: Size::new(left, bottom),
            bottom_right: Size::new(right, bottom),
        }
    }

    pub fn is_finite(&self) -> bool {
        self.top_left.is_finite()
            && self.top_right.is_finite()
            && self.bottom_left.is_finite()
            && self.bottom_right.is_finite()
    }

    pub fn are_all_corners_empty(&self) -> bool {
        self.top_left.is_empty()
            && self.top_right.is_empty()
            && self.bottom_left.is_empty()
            && self.bottom_right.is_empty()
    }

    pub fn are_all_corners_same(&self) -> bool {
        self.are_all_corners_same_tol(kEhCloseEnough)
    }

    pub fn are_all_corners_same_tol(&self, tolerance: Scalar) -> bool {
        let tl = self.top_left;
        scalar_nearly_equal_tol(tl.width, self.top_right.width, tolerance)
            && scalar_nearly_equal_tol(tl.width, self.bottom_right.width, tolerance)
            && scalar_nearly_equal_tol(tl.width, self.bottom_left.width, tolerance)
            && scalar_nearly_equal_tol(tl.height, self.top_right.height, tolerance)
            && scalar_nearly_equal_tol(tl.height, self.bottom_right.height, tolerance)
            && scalar_nearly_equal_tol(tl.height, self.bottom_left.height, tolerance)
    }

    pub fn are_all_corners_circular(&self) -> bool {
        scalar_nearly_equal(self.top_left.width, self.top_left.height)
            && scalar_nearly_equal(self.top_right.width, self.top_right.height)
            && scalar_nearly_equal(self.bottom_left.width, self.bottom_left.height)
            && scalar_nearly_equal(self.bottom_right.width, self.bottom_right.height)
    }

    /// Returns a scaled copy of this object, ensuring that the sum of the
    /// corner radii on each side does not exceed the width or height of the
    /// given bounds.
    ///
    /// See the [Skia scaling
    /// implementation](https://github.com/google/skia/blob/main/src/core/SkRRect.cpp)
    /// for more details.
    pub fn scaled(&self, in_bounds: &Rect) -> RoundingRadii {
        let bounds = in_bounds.get_positive();
        if bounds.is_empty() || self.are_all_corners_empty() || !self.is_finite() {
            // Normalize empty radii.
            return RoundingRadii::default();
        }

        // Copy the incoming radii so that we can work on normalizing them to
        // the particular rectangle they are paired with without disturbing
        // the caller.
        let mut radii = *self;

        // If any corner is flat or has a negative value, normalize it to
        // zeros. We do this first so that the unnecessary non-flat part of
        // that radius does not contribute to the global scaling below.
        normalize_empty_to_zero(&mut radii.top_left);
        normalize_empty_to_zero(&mut radii.top_right);
        normalize_empty_to_zero(&mut radii.bottom_left);
        normalize_empty_to_zero(&mut radii.bottom_right);

        // Now determine a global scale to apply to all of the radii to ensure
        // that none of the adjacent pairs of radius values sum to larger than
        // the corresponding dimension of the rectangle.
        let size = bounds.get_size();
        let mut scale: Scalar = 1.0;
        // clang-format off
        adjust_scale(radii.top_left.width, radii.top_right.width, size.width, &mut scale);
        adjust_scale(radii.bottom_left.width, radii.bottom_right.width, size.width, &mut scale);
        adjust_scale(radii.top_left.height, radii.bottom_left.height, size.height, &mut scale);
        adjust_scale(radii.top_right.height, radii.bottom_right.height, size.height, &mut scale);
        // clang-format on
        if scale < 1.0 {
            radii = radii * scale;
        }

        radii
    }
}

#[inline]
fn normalize_empty_to_zero(radii: &mut Size) {
    if radii.is_empty() {
        *radii = Size::default();
    }
}

#[inline]
fn adjust_scale(radius1: Scalar, radius2: Scalar, dimension: Scalar, scale: &mut Scalar) {
    fml::fml_dcheck_at!(
        "flutter/impeller/geometry/rounding_radii.cc",
        19,
        "radius1 >= 0.0f && radius2 >= 0.0f",
        radius1 >= 0.0 && radius2 >= 0.0
    );
    fml::fml_dcheck_at!("flutter/impeller/geometry/rounding_radii.cc", 20, "dimension > 0.0f", dimension > 0.0);
    if radius1 + radius2 > dimension {
        *scale = cxx::min(*scale, dimension / (radius1 + radius2));
    }
}

impl Mul<Scalar> for RoundingRadii {
    type Output = RoundingRadii;
    fn mul(self, scale: Scalar) -> RoundingRadii {
        RoundingRadii {
            top_left: self.top_left * scale,
            top_right: self.top_right * scale,
            bottom_left: self.bottom_left * scale,
            bottom_right: self.bottom_right * scale,
        }
    }
}

impl fmt::Display for RoundingRadii {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "(ul: {}, ur: {}, ll: {}, lr: {})",
            self.top_left, self.top_right, self.bottom_left, self.bottom_right
        )
    }
}
