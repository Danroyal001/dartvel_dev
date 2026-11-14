// flutter/impeller/geometry/wangs_formula.h, wangs_formula.cc
//
// Wang's formula estimates the number of line segments a curve needs to be
// flattened into within a given tolerance.

use crate::cxx;
use crate::point::{Point, Vector2};
use crate::scalar::Scalar;

// Don't allow linearized segments to be off by more than 1/4th of a pixel
// from the true curve.
const kPrecision: Scalar = 4.0;

/// Returns the minimum number of evenly spaced (in the parametric sense)
/// line segments that the cubic must be chopped into in order to guarantee
/// all lines stay within a distance of "1/intolerance" pixels from the true
/// curve.
pub fn compute_cubic_subdivisions(scale_factor: Scalar, p0: Point, p1: Point, p2: Point, p3: Point) -> Scalar {
    let k: Scalar = scale_factor * 0.75 * kPrecision;
    let a: Vector2 = p0 - p1 * 2i32 + p2;
    let b: Vector2 = p1 - p2 * 2i32 + p3;
    let max_len_sq = cxx::max(a.get_length_squared(), b.get_length_squared());
    (k * max_len_sq.sqrt()).sqrt()
}

/// Returns the minimum number of evenly spaced (in the parametric sense)
/// line segments that the quadratic must be chopped into.
pub fn compute_quadradic_subdivisions(scale_factor: Scalar, p0: Point, p1: Point, p2: Point) -> Scalar {
    let k: Scalar = scale_factor * 0.25 * kPrecision;
    (k * (p0 - p1 * 2i32 + p2).get_length()).sqrt()
}

/// Returns the minimum number of evenly spaced (in the parametric sense)
/// line segments that the conic must be chopped into.
pub fn compute_conic_subdivisions(
    scale_factor: Scalar,
    mut p0: Point,
    mut p1: Point,
    mut p2: Point,
    w: Scalar,
) -> Scalar {
    // Compute center of bounding box in projected space
    let C: Point = 0.5f32 * (p0.min(&p1).min(&p2) + p0.max(&p1).max(&p2));

    // Map control points into projected space, centered around C.
    p0 -= C;
    p1 -= C;
    p2 -= C;

    // Compute the maximum length of the 3 points in projected space
    let max_len: Scalar = cxx::max(p0.dot(&p0), cxx::max(p1.dot(&p1), p2.dot(&p2))).sqrt();

    // Compute forward differences
    let dp: Point = (-2.0 * w) * p1 + p0 + p2;
    let dw: Scalar = (-2.0 * w + 2.0).abs();

    // Compute the numerator and denominator, from the conic subdivision
    // reference.
    let k: Scalar = scale_factor * kPrecision;
    let rp_minus_1: Scalar = cxx::max(0.0, max_len * k - 1.0);
    let numer: Scalar = dp.dot(&dp).sqrt() * k + rp_minus_1 * dw;
    let denom: Scalar = 4.0 * cxx::min(w, 1.0);
    (numer / denom).sqrt()
}
