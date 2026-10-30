// flutter/impeller/geometry/path_source.h, path_source.cc
//
// Upstream's virtual `PathReceiver` and `PathSource` are traits; a receiver
// is passed as `&mut dyn PathReceiver`.

use crate::constants::kSqrt2Over2;
use crate::matrix::Matrix;
use crate::point::Point;
use crate::rect::Rect;
use crate::scalar::Scalar;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FillType {
    /// The default winding order.
    #[default]
    kNonZero,
    kOdd,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Convexity {
    #[default]
    kUnknown,
    kConvex,
}

/// Collection of functions to receive path segments from the underlying
/// path representation via the DlPath::Dispatch method.
///
/// The conic_to function is optional. If the receiver understands rational
/// quadratic Bezier curve forms then it should accept the curve parameters
/// and return true, otherwise it can return false and the dispatcher will
/// provide the path segment in a different form via the other methods.
///
/// The dispatcher might not call the close method if the path is not
/// explicitly closed. It is not guaranteed that the path ends where it
/// started (the dispatcher might not provide the final line segment); the
/// receiver must handle these cases implicitly.
pub trait PathReceiver {
    fn move_to(&mut self, p2: &Point, will_be_closed: bool);
    fn line_to(&mut self, p2: &Point);
    fn quad_to(&mut self, cp: &Point, p2: &Point);
    fn conic_to(&mut self, _cp: &Point, _p2: &Point, _weight: Scalar) -> bool {
        false
    }
    fn cubic_to(&mut self, cp1: &Point, cp2: &Point, p2: &Point);
    fn close(&mut self);
}

pub trait PathSource {
    fn get_fill_type(&self) -> FillType;
    fn get_bounds(&self) -> Rect;
    fn is_convex(&self) -> bool;
    fn dispatch(&self, receiver: &mut dyn PathReceiver);
}

/// A PathSource object that provides path iteration for any TRect.
#[derive(Clone, Copy, Debug)]
pub struct RectPathSource {
    rect_: Rect,
}

impl RectPathSource {
    pub fn new(r: &Rect) -> RectPathSource {
        RectPathSource { rect_: *r }
    }
}

impl PathSource for RectPathSource {
    /// |PathSource|
    fn get_fill_type(&self) -> FillType {
        FillType::kNonZero
    }

    /// |PathSource|
    fn get_bounds(&self) -> Rect {
        self.rect_
    }

    /// |PathSource|
    fn is_convex(&self) -> bool {
        true
    }

    /// |PathSource|
    fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        receiver.move_to(&self.rect_.get_left_top(), true);
        receiver.line_to(&self.rect_.get_right_top());
        receiver.line_to(&self.rect_.get_right_bottom());
        receiver.line_to(&self.rect_.get_left_bottom());
        receiver.line_to(&self.rect_.get_left_top());
        receiver.close();
    }
}

/// A PathSource object that provides path iteration for any ellipse
/// inscribed within a Rect bounds.
#[derive(Clone, Copy, Debug)]
pub struct EllipsePathSource {
    bounds_: Rect,
}

impl EllipsePathSource {
    pub fn new(bounds: &Rect) -> EllipsePathSource {
        EllipsePathSource { bounds_: *bounds }
    }
}

impl PathSource for EllipsePathSource {
    fn get_fill_type(&self) -> FillType {
        FillType::kNonZero
    }

    fn get_bounds(&self) -> Rect {
        self.bounds_
    }

    fn is_convex(&self) -> bool {
        true
    }

    fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        let left = self.bounds_.get_left();
        let right = self.bounds_.get_right();
        let top = self.bounds_.get_top();
        let bottom = self.bounds_.get_bottom();
        let center = self.bounds_.get_center();

        receiver.move_to(&Point::new(left, center.y), true);
        receiver.conic_to(&Point::new(left, top), &Point::new(center.x, top), kSqrt2Over2);
        receiver.conic_to(&Point::new(right, top), &Point::new(right, center.y), kSqrt2Over2);
        receiver.conic_to(&Point::new(right, bottom), &Point::new(center.x, bottom), kSqrt2Over2);
        receiver.conic_to(&Point::new(left, bottom), &Point::new(left, center.y), kSqrt2Over2);
        receiver.close();
    }
}

/// A utility class to receive path segments from a source, transform them by
/// a matrix, and pass them along to a subsequent receiver.
pub struct PathTransformer<'a> {
    receiver_: &'a mut dyn PathReceiver,
    matrix_: &'a Matrix,
}

impl<'a> PathTransformer<'a> {
    pub fn new(receiver: &'a mut dyn PathReceiver, matrix: &'a Matrix) -> PathTransformer<'a> {
        PathTransformer { receiver_: receiver, matrix_: matrix }
    }
}

impl PathReceiver for PathTransformer<'_> {
    fn move_to(&mut self, p2: &Point, will_be_closed: bool) {
        self.receiver_.move_to(&(*self.matrix_ * *p2), will_be_closed);
    }

    fn line_to(&mut self, p2: &Point) {
        self.receiver_.line_to(&(*self.matrix_ * *p2));
    }

    fn quad_to(&mut self, cp: &Point, p2: &Point) {
        self.receiver_.quad_to(&(*self.matrix_ * *cp), &(*self.matrix_ * *p2));
    }

    fn conic_to(&mut self, cp: &Point, p2: &Point, weight: Scalar) -> bool {
        self.receiver_.conic_to(&(*self.matrix_ * *cp), &(*self.matrix_ * *p2), weight)
    }

    fn cubic_to(&mut self, cp1: &Point, cp2: &Point, p2: &Point) {
        self.receiver_.cubic_to(&(*self.matrix_ * *cp1), &(*self.matrix_ * *cp2), &(*self.matrix_ * *p2));
    }

    fn close(&mut self) {
        self.receiver_.close();
    }
}
