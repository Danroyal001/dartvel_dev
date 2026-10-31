// flutter/impeller/geometry/stroke_parameters.h (stroke_parameters.cc is
// empty)

use crate::scalar::Scalar;

/// An enum that describes ways to decorate the end of a path contour.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Cap {
    #[default]
    kButt,
    kRound,
    kSquare,
}

/// An enum that describes ways to join two segments of a path.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Join {
    #[default]
    kMiter,
    kRound,
    kBevel,
}

/// A structure to store all of the parameters related to stroking a path
/// or basic geometry object.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StrokeParameters {
    pub width: Scalar,
    pub cap: Cap,
    pub join: Join,
    pub miter_limit: Scalar,
}

impl Default for StrokeParameters {
    #[inline]
    fn default() -> StrokeParameters {
        StrokeParameters { width: 0.0, cap: Cap::kButt, join: Join::kMiter, miter_limit: 4.0 }
    }
}
