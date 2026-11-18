// flutter/impeller/geometry/separated_vector.h, separated_vector.cc

use crate::point::Vector2;
use crate::scalar::{Radians, Scalar};

/// A Vector2, broken down as a separate magnitude and direction. Assumes
/// that the direction given is normalized.
///
/// This is a simple convenience struct for handling polyline offset values
/// when generating polylines from paths.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SeparatedVector2 {
    pub direction: Vector2,
    pub magnitude: Scalar,
}

impl SeparatedVector2 {
    pub const fn new(direction: Vector2, magnitude: Scalar) -> SeparatedVector2 {
        SeparatedVector2 { direction, magnitude }
    }

    /// `explicit SeparatedVector2(Vector2 vector)`.
    pub fn from_vector(vector: Vector2) -> SeparatedVector2 {
        SeparatedVector2 { direction: vector.normalize(), magnitude: vector.get_length() }
    }

    /// Returns the vector representation of the vector.
    pub fn get_vector(&self) -> Vector2 {
        self.direction * self.magnitude
    }

    /// Returns the direction of the vector.
    pub fn get_direction(&self) -> Vector2 {
        self.direction
    }

    /// Returns the scalar alignment of the two vectors. In other words, the
    /// dot product of the two normalized vectors.
    ///
    /// Range: [-1, 1]
    /// A value of 1 indicates the directions are parallel and pointing in the
    /// same direction. A value of -1 indicates the vectors are parallel and
    /// pointing in opposite directions. A value of 0 indicates the vectors
    /// are perpendicular.
    pub fn get_alignment(&self, other: &SeparatedVector2) -> Scalar {
        self.direction.dot(&other.direction)
    }

    /// Returns the scalar angle between the two rays.
    pub fn angle_to(&self, other: &SeparatedVector2) -> Radians {
        self.direction.angle_to(&other.direction)
    }

    /// Returns the cross product of the two vectors.
    pub fn cross(&self, other: &SeparatedVector2) -> Scalar {
        self.direction.cross(&other.direction)
    }
}
