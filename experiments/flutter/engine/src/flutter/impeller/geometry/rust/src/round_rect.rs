// flutter/impeller/geometry/round_rect.h, round_rect.cc

use std::fmt;

use crate::constants::kSqrt2Over2;
use crate::path_source::{FillType, PathReceiver, PathSource};
use crate::point::Point;
use crate::rect::Rect;
use crate::rounding_radii::RoundingRadii;
use crate::scalar::{Scalar, scalar_nearly_equal};
use crate::size::Size;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RoundRect {
    bounds_: Rect,
    radii_: RoundingRadii,
}

impl RoundRect {
    pub fn make_rect(rect: &Rect) -> RoundRect {
        RoundRect::make_rect_radii(rect, &RoundingRadii::default())
    }

    pub fn make_oval(rect: &Rect) -> RoundRect {
        RoundRect::make_rect_radii(rect, &RoundingRadii::make_radii(rect.get_size() * 0.5))
    }

    pub fn make_rect_radius(rect: &Rect, radius: Scalar) -> RoundRect {
        RoundRect::make_rect_radii(rect, &RoundingRadii::make_radius(radius))
    }

    pub fn make_rect_xy(rect: &Rect, x_radius: Scalar, y_radius: Scalar) -> RoundRect {
        RoundRect::make_rect_radii(rect, &RoundingRadii::make_radii(Size::new(x_radius, y_radius)))
    }

    pub fn make_rect_xy_size(rect: &Rect, corner_radii: Size) -> RoundRect {
        RoundRect::make_rect_radii(rect, &RoundingRadii::make_radii(corner_radii))
    }

    pub fn make_nine_patch(rect: &Rect, left: Scalar, top: Scalar, right: Scalar, bottom: Scalar) -> RoundRect {
        RoundRect::make_rect_radii(rect, &RoundingRadii::make_nine_patch(left, top, right, bottom))
    }

    pub fn make_rect_radii(in_bounds: &Rect, in_radii: &RoundingRadii) -> RoundRect {
        if !in_bounds.is_finite() {
            return RoundRect::default();
        }
        let bounds = in_bounds.get_positive();
        // RoundingRadii::Scaled might return an empty radii if bounds or
        // in_radii is empty, which is fine.
        RoundRect { bounds_: bounds, radii_: in_radii.scaled(&bounds) }
    }

    pub fn get_bounds(&self) -> &Rect {
        &self.bounds_
    }

    pub fn get_radii(&self) -> &RoundingRadii {
        &self.radii_
    }

    pub fn is_finite(&self) -> bool {
        self.bounds_.is_finite()
            && self.radii_.top_left.is_finite()
            && self.radii_.top_right.is_finite()
            && self.radii_.bottom_left.is_finite()
            && self.radii_.bottom_right.is_finite()
    }

    pub fn is_empty(&self) -> bool {
        self.bounds_.is_empty()
    }

    pub fn is_rect(&self) -> bool {
        !self.bounds_.is_empty() && self.radii_.are_all_corners_empty()
    }

    pub fn is_oval(&self) -> bool {
        !self.bounds_.is_empty()
            && self.radii_.are_all_corners_same()
            && scalar_nearly_equal(self.radii_.top_left.width, self.bounds_.get_width() * 0.5)
            && scalar_nearly_equal(self.radii_.top_left.height, self.bounds_.get_height() * 0.5)
    }

    /// Returns true iff the provided point |p| is inside the half-open
    /// interior of this rectangle.
    ///
    /// For purposes of containment, a rectangle contains points along the
    /// top and left edges but not points along the right and bottom edges
    /// so that a point is only ever considered inside one of two abutting
    /// rectangles.
    pub fn contains(&self, p: &Point) -> bool {
        if !self.bounds_.contains(p) {
            return false;
        }
        if !corner_contains(p, &self.bounds_.get_left_top(), &kUpperLeftDirection, &self.radii_.top_left)
            || !corner_contains(p, &self.bounds_.get_right_top(), &kUpperRightDirection, &self.radii_.top_right)
            || !corner_contains(p, &self.bounds_.get_left_bottom(), &kLowerLeftDirection, &self.radii_.bottom_left)
            || !corner_contains(
                p,
                &self.bounds_.get_right_bottom(),
                &kLowerRightDirection,
                &self.radii_.bottom_right,
            )
        {
            return false;
        }
        true
    }

    /// Returns a new round rectangle translated by the given offset.
    pub fn shift(&self, dx: Scalar, dy: Scalar) -> RoundRect {
        // Just in case, use the factory rather than the internal constructor
        // as shifting the rectangle may increase/decrease its bit precision
        // so we should re-validate the radii to the newly located rectangle.
        RoundRect::make_rect_radii(&self.bounds_.shift(dx, dy), &self.radii_)
    }

    /// Returns a round rectangle with expanded edges. Negative expansion
    /// results in shrinking.
    pub fn expand_ltrb(&self, left: Scalar, top: Scalar, right: Scalar, bottom: Scalar) -> RoundRect {
        // Use the factory rather than the internal constructor as the changing
        // size of the rectangle requires that we re-validate the radii to the
        // newly sized rectangle.
        RoundRect::make_rect_radii(&self.bounds_.expand_ltrb(left, top, right, bottom), &self.radii_)
    }

    pub fn expand_xy(&self, horizontal: Scalar, vertical: Scalar) -> RoundRect {
        RoundRect::make_rect_radii(&self.bounds_.expand_xy(horizontal, vertical), &self.radii_)
    }

    pub fn expand(&self, amount: Scalar) -> RoundRect {
        RoundRect::make_rect_radii(&self.bounds_.expand(amount), &self.radii_)
    }

    pub(crate) fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        let left = self.bounds_.get_left();
        let top = self.bounds_.get_top();
        let right = self.bounds_.get_right();
        let bottom = self.bounds_.get_bottom();
        let radii = &self.radii_;

        receiver.move_to(&Point::new(left + radii.top_left.width, top), true);
        receiver.line_to(&Point::new(right - radii.top_right.width, top));
        receiver.conic_to(&Point::new(right, top), &Point::new(right, top + radii.top_right.height), kSqrt2Over2);
        receiver.line_to(&Point::new(right, bottom - radii.bottom_right.height));
        receiver.conic_to(
            &Point::new(right, bottom),
            &Point::new(right - radii.bottom_right.width, bottom),
            kSqrt2Over2,
        );
        receiver.line_to(&Point::new(left + radii.bottom_left.width, bottom));
        receiver.conic_to(
            &Point::new(left, bottom),
            &Point::new(left, bottom - radii.bottom_left.height),
            kSqrt2Over2,
        );
        receiver.line_to(&Point::new(left, top + radii.top_left.height));
        receiver.conic_to(&Point::new(left, top), &Point::new(left + radii.top_left.width, top), kSqrt2Over2);
        receiver.close();
    }
}

fn corner_contains(p: &Point, corner: &Point, direction: &Point, radii: &Size) -> bool {
    fml::fml_dcheck_at!(
        "flutter/impeller/geometry/round_rect.cc",
        34,
        "radii.width >= 0.0f && radii.height >= 0.0f",
        radii.width >= 0.0 && radii.height >= 0.0
    );
    if radii.is_empty() {
        return true;
    }
    let corner_relative = (*corner - *p) * *direction;
    let quadrant_relative = *radii - corner_relative;
    if quadrant_relative.x <= 0.0 || quadrant_relative.y <= 0.0 {
        return true;
    }
    let quadrant_unit_circle_point = quadrant_relative / *radii;
    quadrant_unit_circle_point.get_length_squared() as f64 <= 1.0
}

const kUpperLeftDirection: Point = Point::new(-1.0, -1.0);
const kUpperRightDirection: Point = Point::new(1.0, -1.0);
const kLowerLeftDirection: Point = Point::new(-1.0, 1.0);
const kLowerRightDirection: Point = Point::new(1.0, 1.0);

#[derive(Clone, Copy, Debug)]
pub struct RoundRectPathSource {
    round_rect_: RoundRect,
}

impl RoundRectPathSource {
    pub fn new(round_rect: &RoundRect) -> RoundRectPathSource {
        RoundRectPathSource { round_rect_: *round_rect }
    }

    pub fn get_round_rect(&self) -> &RoundRect {
        &self.round_rect_
    }
}

impl PathSource for RoundRectPathSource {
    fn get_fill_type(&self) -> FillType {
        FillType::kNonZero
    }

    fn get_bounds(&self) -> Rect {
        *self.round_rect_.get_bounds()
    }

    fn is_convex(&self) -> bool {
        true
    }

    fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        self.round_rect_.dispatch(receiver);
    }
}

#[derive(Clone, Copy, Debug)]
pub struct DiffRoundRectPathSource {
    outer_: RoundRect,
    inner_: RoundRect,
}

impl DiffRoundRectPathSource {
    pub fn new(outer: &RoundRect, inner: &RoundRect) -> DiffRoundRectPathSource {
        DiffRoundRectPathSource { outer_: *outer, inner_: *inner }
    }

    pub fn get_outer(&self) -> &RoundRect {
        &self.outer_
    }

    pub fn get_inner(&self) -> &RoundRect {
        &self.inner_
    }
}

impl PathSource for DiffRoundRectPathSource {
    fn get_fill_type(&self) -> FillType {
        FillType::kOdd
    }

    fn get_bounds(&self) -> Rect {
        *self.outer_.get_bounds()
    }

    fn is_convex(&self) -> bool {
        false
    }

    fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        self.outer_.dispatch(receiver);
        self.inner_.dispatch(receiver);
    }
}

impl fmt::Display for RoundRect {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "(rect: {}, radii: {})", self.get_bounds(), self.get_radii())
    }
}
