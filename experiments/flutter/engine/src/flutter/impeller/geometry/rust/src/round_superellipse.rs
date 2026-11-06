// flutter/impeller/geometry/round_superellipse.h, round_superellipse.cc

use std::fmt;

use crate::path_source::{FillType, PathReceiver, PathSource};
use crate::point::Point;
use crate::rect::Rect;
use crate::round_rect::RoundRect;
use crate::round_superellipse_param::RoundSuperellipseParam;
use crate::rounding_radii::RoundingRadii;
use crate::scalar::{Scalar, scalar_nearly_equal};
use crate::size::Size;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RoundSuperellipse {
    bounds_: Rect,
    radii_: RoundingRadii,
}

impl RoundSuperellipse {
    #[inline]
    pub fn make_rect(rect: &Rect) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(rect, &RoundingRadii::default())
    }

    #[inline]
    pub fn make_oval(rect: &Rect) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(rect, &RoundingRadii::make_radii(rect.get_size() * 0.5))
    }

    #[inline]
    pub fn make_rect_radius(rect: &Rect, radius: Scalar) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(rect, &RoundingRadii::make_radius(radius))
    }

    #[inline]
    pub fn make_rect_xy(rect: &Rect, x_radius: Scalar, y_radius: Scalar) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(rect, &RoundingRadii::make_radii(Size::new(x_radius, y_radius)))
    }

    #[inline]
    pub fn make_rect_xy_size(rect: &Rect, corner_radii: Size) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(rect, &RoundingRadii::make_radii(corner_radii))
    }

    pub fn make_rect_radii(in_bounds: &Rect, in_radii: &RoundingRadii) -> RoundSuperellipse {
        if !in_bounds.is_finite() {
            return RoundSuperellipse::default();
        }
        let bounds = in_bounds.get_positive();
        // RoundingRadii::Scaled might return an empty radii if bounds or
        // in_radii is empty, which is fine.
        RoundSuperellipse { bounds_: bounds, radii_: in_radii.scaled(&bounds) }
    }

    pub fn get_bounds(&self) -> &Rect {
        &self.bounds_
    }

    #[inline]
    pub fn get_radii(&self) -> &RoundingRadii {
        &self.radii_
    }

    #[inline]
    pub fn is_finite(&self) -> bool {
        self.bounds_.is_finite()
            && self.radii_.top_left.is_finite()
            && self.radii_.top_right.is_finite()
            && self.radii_.bottom_left.is_finite()
            && self.radii_.bottom_right.is_finite()
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.bounds_.is_empty()
    }

    #[inline]
    pub fn is_rect(&self) -> bool {
        !self.bounds_.is_empty() && self.radii_.are_all_corners_empty()
    }

    #[inline]
    pub fn is_oval(&self) -> bool {
        !self.bounds_.is_empty()
            && self.radii_.are_all_corners_same()
            && scalar_nearly_equal(self.radii_.top_left.width, self.bounds_.get_width() * 0.5)
            && scalar_nearly_equal(self.radii_.top_left.height, self.bounds_.get_height() * 0.5)
    }

    #[inline]
    /// Returns true iff the provided point |p| is inside the half-open
    /// interior of this rounded superellipse.
    pub fn contains(&self, p: &Point) -> bool {
        if !self.bounds_.contains(p) {
            return false;
        }
        let param = RoundSuperellipseParam::make_bounds_radii(&self.bounds_, &self.radii_);
        param.contains(p)
    }

    #[inline]
    pub fn shift(&self, dx: Scalar, dy: Scalar) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(&self.bounds_.shift(dx, dy), &self.radii_)
    }

    #[inline]
    pub fn expand_ltrb(&self, left: Scalar, top: Scalar, right: Scalar, bottom: Scalar) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(&self.bounds_.expand_ltrb(left, top, right, bottom), &self.radii_)
    }

    #[inline]
    pub fn expand_xy(&self, horizontal: Scalar, vertical: Scalar) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(&self.bounds_.expand_xy(horizontal, vertical), &self.radii_)
    }

    #[inline]
    pub fn expand(&self, amount: Scalar) -> RoundSuperellipse {
        RoundSuperellipse::make_rect_radii(&self.bounds_.expand(amount), &self.radii_)
    }

    /// Returns a rounded rectangle that approximates this rounded
    /// superellipse with the same bounds and radii.
    pub fn to_approximate_round_rect(&self) -> RoundRect {
        // Use the same radii, since the curves of rounded superellipses
        // touch the bounds at the same points as rounded rectangles.
        RoundRect::make_rect_radii(self.get_bounds(), self.get_radii())
    }
}

#[derive(Clone, Copy, Debug)]
pub struct RoundSuperellipsePathSource {
    round_superellipse_: RoundSuperellipse,
}

impl RoundSuperellipsePathSource {
    pub fn new(round_superellipse: &RoundSuperellipse) -> RoundSuperellipsePathSource {
        RoundSuperellipsePathSource { round_superellipse_: *round_superellipse }
    }

    #[inline]
    pub fn get_round_superellipse(&self) -> &RoundSuperellipse {
        &self.round_superellipse_
    }
}

impl PathSource for RoundSuperellipsePathSource {
    fn get_fill_type(&self) -> FillType {
        FillType::kNonZero
    }

    fn get_bounds(&self) -> Rect {
        *self.round_superellipse_.get_bounds()
    }

    fn is_convex(&self) -> bool {
        true
    }

    fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        let param = RoundSuperellipseParam::make_bounds_radii(
            self.round_superellipse_.get_bounds(),
            self.round_superellipse_.get_radii(),
        );
        param.dispatch(receiver);
    }
}

impl fmt::Display for RoundSuperellipse {
    #[inline]
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "(rect: {}, radii: {})", self.get_bounds(), self.get_radii())
    }
}
