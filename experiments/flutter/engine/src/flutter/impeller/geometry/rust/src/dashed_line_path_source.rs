// flutter/impeller/geometry/dashed_line_path_source.h,
// dashed_line_path_source.cc

use crate::path_source::{FillType, PathReceiver, PathSource};
use crate::point::Point;
use crate::rect::Rect;
use crate::scalar::Scalar;

/// A PathSource that generates the various segments of a dashed line.
#[derive(Clone, Copy, Debug)]
pub struct DashedLinePathSource {
    p0_: Point,
    p1_: Point,
    on_length_: Scalar,
    off_length_: Scalar,
}

impl DashedLinePathSource {
    pub fn new(p0: Point, p1: Point, on_length: Scalar, off_length: Scalar) -> Self {
        DashedLinePathSource { p0_: p0, p1_: p1, on_length_: on_length, off_length_: off_length }
    }
}

impl PathSource for DashedLinePathSource {
    fn get_fill_type(&self) -> FillType {
        FillType::kNonZero
    }

    fn get_bounds(&self) -> Rect {
        Rect::make_ltrb(self.p0_.x, self.p0_.y, self.p1_.x, self.p1_.y).get_positive()
    }

    fn is_convex(&self) -> bool {
        false
    }

    fn dispatch(&self, receiver: &mut dyn PathReceiver) {
        let length: Scalar = self.p0_.get_distance(&self.p1_);
        if length > 0.0 && self.on_length_ >= 0.0 && self.off_length_ > 0.0 {
            let delta: Point = (self.p1_ - self.p0_) / length; // length > 0 already verified
            let mut consumed: Scalar = 0.0;
            while consumed < length {
                receiver.move_to(&(self.p0_ + delta * consumed), false);

                let dash_end: Scalar = consumed + self.on_length_;
                if dash_end < length {
                    receiver.line_to(&(self.p0_ + delta * dash_end));
                } else {
                    receiver.line_to(&self.p1_);
                    // Once we draw the last dash, we're done.
                    break;
                }

                consumed = dash_end + self.off_length_;
            }
        } else {
            receiver.move_to(&self.p0_, false);
            receiver.line_to(&self.p1_);
        }
    }
}
