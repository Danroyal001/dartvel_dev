// flutter/impeller/geometry/round_superellipse_param.h,
// round_superellipse_param.cc
//
// The table constants upstream writes as double literals into `Scalar`
// arrays are converted the same way here (`f64 as f32`), not parsed as f32
// literals, which could round differently.

use crate::constants::kEhCloseEnough;
use crate::cxx::{self, Num};
use crate::matrix::Matrix;
use crate::path_source::PathReceiver;
use crate::point::Point;
use crate::rect::Rect;
use crate::rounding_radii::RoundingRadii;
use crate::scalar::{Radians, Scalar};
use crate::size::Size;
use crate::vector::Vector3;

/// A structure that describes the shape of a rounded superellipse.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RoundSuperellipseParam {
    pub top_right: Quadrant,
    pub bottom_right: Quadrant,
    pub bottom_left: Quadrant,
    pub top_left: Quadrant,
    /// If true, all corners are the same and only top_right is computed.
    pub all_corners_same: bool,
    /// The coordinates of the boundaries between the quadrants.
    pub top_split: Scalar,
    pub bottom_split: Scalar,
    pub left_split: Scalar,
    pub right_split: Scalar,
}

/// The parameters for an octant, which is the region of a quadrant between
/// the x=y axis and the X or Y axis.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Octant {
    /// The offset of the square-like rounded superellipse's center from the
    /// origin.
    pub offset: Point,
    /// The radius of the superellipse in the octant, i.e. the half side
    /// length.
    pub se_a: Scalar,
    /// The degree of the superellipse.
    pub se_n: Scalar,
    /// The range of the parameter "theta" used to define the superellipse
    /// curve.
    pub se_max_theta: Scalar,
    /// The coordinate of the point that connects the superellipse curve and
    /// the circular arc.
    pub circle_start: Point,
    /// The center of the circular arc.
    pub circle_center: Point,
    /// The angular span of the circular arc.
    pub circle_max_angle: Radians,
    /// The radius of the circular arc.
    pub circle_radius: Scalar,
}

/// The parameters for a quadrant.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Quadrant {
    /// The offset of the quadrant's center relative to the origin.
    pub offset: Point,
    /// The scaling factor and its sign applied to the normalized quadrant.
    pub signed_scale: Point,
    /// The parameters for the top octant.
    pub top: Octant,
    /// The parameters for the right octant.
    pub right: Octant,
}

impl RoundSuperellipseParam {
    /// 1-cos(pi/4)
    pub const kGapFactor: Scalar = 0.29289321881;

    /// Create a param for a rounded superellipse with the specific bounds
    /// and radii.
    pub fn make_bounds_radii(bounds: &Rect, radii: &RoundingRadii) -> RoundSuperellipseParam {
        if radii.are_all_corners_same() && !radii.top_left.is_empty() {
            // Having four empty corners indicate a rectangle, which needs
            // special treatment on border containment and therefore is not
            // `all_corners_same`.
            return RoundSuperellipseParam {
                top_right: compute_quadrant(
                    bounds.get_center(),
                    bounds.get_right_top(),
                    radii.top_right,
                    Size::new(-1.0, 1.0),
                ),
                all_corners_same: true,
                top_split: bounds.get_center().x,
                bottom_split: bounds.get_center().x,
                left_split: bounds.get_center().y,
                right_split: bounds.get_center().y,
                ..Default::default()
            };
        }

        let top_split =
            split(bounds.get_left(), bounds.get_right(), radii.top_left.width, radii.top_right.width);
        let right_split =
            split(bounds.get_top(), bounds.get_bottom(), radii.top_right.height, radii.bottom_right.height);
        let bottom_split =
            split(bounds.get_left(), bounds.get_right(), radii.bottom_left.width, radii.bottom_right.width);
        let left_split =
            split(bounds.get_top(), bounds.get_bottom(), radii.top_left.height, radii.bottom_left.height);

        RoundSuperellipseParam {
            top_right: compute_quadrant(
                Point::new(top_split, right_split),
                bounds.get_right_top(),
                radii.top_right,
                Size::new(1.0, -1.0),
            ),
            bottom_right: compute_quadrant(
                Point::new(bottom_split, right_split),
                bounds.get_right_bottom(),
                radii.bottom_right,
                Size::new(1.0, 1.0),
            ),
            bottom_left: compute_quadrant(
                Point::new(bottom_split, left_split),
                bounds.get_left_bottom(),
                radii.bottom_left,
                Size::new(-1.0, 1.0),
            ),
            top_left: compute_quadrant(
                Point::new(top_split, left_split),
                bounds.get_left_top(),
                radii.top_left,
                Size::new(-1.0, -1.0),
            ),
            all_corners_same: false,
            top_split,
            bottom_split,
            left_split,
            right_split,
        }
    }

    /// Create a param for a rounded superellipse with the specific bounds
    /// and a uniform radius.
    pub fn make_bounds_radius(bounds: &Rect, radius: Scalar) -> RoundSuperellipseParam {
        RoundSuperellipseParam {
            top_right: compute_quadrant(
                bounds.get_center(),
                bounds.get_right_top(),
                Size::new(radius, radius),
                Size::new(-1.0, 1.0),
            ),
            all_corners_same: true,
            ..Default::default()
        }
    }

    /// Returns whether this rounded superellipse contains the point.
    pub fn contains(&self, point: &Point) -> bool {
        if self.all_corners_same {
            return corner_contains(&self.top_right, point, false);
        }
        corner_contains(&self.top_right, point, true)
            && corner_contains(&self.bottom_right, point, true)
            && corner_contains(&self.bottom_left, point, true)
            && corner_contains(&self.top_left, point, true)
    }

    /// Dispatch the path operations of this rounded superellipse to the
    /// receiver.
    pub fn dispatch(&self, path_receiver: &mut dyn PathReceiver) {
        let start = self.top_right.offset
            + self.top_right.signed_scale
                * (self.top_right.top.offset + Point::new(0.0, self.top_right.top.se_a));
        path_receiver.move_to(&start, true);

        {
            let mut builder = RoundSuperellipseBuilder { receiver_: &mut *path_receiver };
            if self.all_corners_same {
                builder.add_quadrant(&self.top_right, false, Point::new(1.0, 1.0));
                builder.add_quadrant(&self.top_right, true, Point::new(1.0, -1.0));
                builder.add_quadrant(&self.top_right, false, Point::new(-1.0, -1.0));
                builder.add_quadrant(&self.top_right, true, Point::new(-1.0, 1.0));
            } else {
                builder.add_quadrant(&self.top_right, false, Point::new(1.0, 1.0));
                builder.add_quadrant(&self.bottom_right, true, Point::new(1.0, 1.0));
                builder.add_quadrant(&self.bottom_left, false, Point::new(1.0, 1.0));
                builder.add_quadrant(&self.top_left, true, Point::new(1.0, 1.0));
            }
        }

        path_receiver.line_to(&start);
        path_receiver.close();
    }
}

// Return the value that splits the range from `left` to `right` into two
// portions whose ratio equals to `ratio_left` : `ratio_right`.
fn split(left: Scalar, right: Scalar, ratio_left: Scalar, ratio_right: Scalar) -> Scalar {
    if ratio_left == 0.0 && ratio_right == 0.0 {
        return (left + right) / 2.0;
    }
    (left * ratio_right + right * ratio_left) / (ratio_left + ratio_right)
}

// Return the same Point, but each NaN coordinate is replaced by that of
// `default_size`.
#[inline]
fn replance_nan_with_default(in_: Point, default_size: Size) -> Point {
    Point::new(
        if in_.x.is_nan() { default_size.width } else { in_.x },
        if in_.y.is_nan() { default_size.height } else { in_.y },
    )
}

// Swap the x and y coordinate of a point.
//
// Effectively mirrors the point by the y=x line.
#[inline]
fn flip(a: Point) -> Point {
    Point::new(a.y, a.x)
}

// A look up table with precomputed variables.
//
// The columns represent the following variabls respectively:
//
//  * n
//  * k_xJ, which is defined as 1 / (1 - xJ / a)
//
// For definition of the variables, see ComputeOctant.
const kPrecomputedVariables: [[Scalar; 2]; 11] = [
    /*ratio=2.00*/ [2.00000000f64 as f32, 1.13276676f64 as f32],
    /*ratio=2.10*/ [2.18349805f64 as f32, 1.20311921f64 as f32],
    /*ratio=2.20*/ [2.33888662f64 as f32, 1.28698796f64 as f32],
    /*ratio=2.30*/ [2.48660575f64 as f32, 1.36351941f64 as f32],
    /*ratio=2.40*/ [2.62226596f64 as f32, 1.44717976f64 as f32],
    /*ratio=2.50*/ [2.75148990f64 as f32, 1.53385819f64 as f32],
    /*ratio=3.00*/ [3.36298265f64 as f32, 1.98288283f64 as f32],
    /*ratio=3.50*/ [4.08649929f64 as f32, 2.23811846f64 as f32],
    /*ratio=4.00*/ [4.85481134f64 as f32, 2.47563463f64 as f32],
    /*ratio=4.50*/ [5.62945551f64 as f32, 2.72948597f64 as f32],
    /*ratio=5.00*/ [6.43023796f64 as f32, 2.98020421f64 as f32],
];

const kMinRatio: Scalar = 2.00;

// The curve is split into 3 parts:
// * The first part uses a denser look up table.
// * The second part uses a sparser look up table.
// * The third part uses a straight line.
const kFirstStepInverse: Scalar = 10.0; // = 1 / 0.10
const kFirstMaxRatio: Scalar = 2.50;
const kFirstNumRecords: Scalar = 6.0;

const kSecondStepInverse: Scalar = 2.0; // = 1 / 0.50
const kSecondMaxRatio: Scalar = 5.00;

const kThirdNSlope: Scalar = 1.559599389f64 as f32;
const kThirdKxjSlope: Scalar = 0.522807185f64 as f32;

const kNumRecords: usize = kPrecomputedVariables.len();

// Compute the `n` and `xJ / a` for the given ratio.
fn compute_n_and_xj(mut ratio: Scalar) -> [Scalar; 2] {
    if ratio > kSecondMaxRatio {
        let n: Scalar =
            kThirdNSlope * (ratio - kSecondMaxRatio) + kPrecomputedVariables[kNumRecords - 1][0];
        let k_xJ: Scalar =
            kThirdKxjSlope * (ratio - kSecondMaxRatio) + kPrecomputedVariables[kNumRecords - 1][1];
        return [n, 1.0 - 1.0 / k_xJ];
    }
    ratio = cxx::clamp(ratio, kMinRatio, kSecondMaxRatio);
    let steps: Scalar = if ratio < kFirstMaxRatio {
        (ratio - kMinRatio) * kFirstStepInverse
    } else {
        (ratio - kFirstMaxRatio) * kSecondStepInverse + kFirstNumRecords - 1.0
    };

    let left: usize = cxx::clamp(steps.floor_c() as usize, 0, kNumRecords - 2);
    let frac: Scalar = steps - left as Scalar;

    let n: Scalar =
        (1.0 - frac) * kPrecomputedVariables[left][0] + frac * kPrecomputedVariables[left + 1][0];
    let k_xJ: Scalar =
        (1.0 - frac) * kPrecomputedVariables[left][1] + frac * kPrecomputedVariables[left + 1][1];
    [n, 1.0 - 1.0 / k_xJ]
}

// Find the center of the circle that passes the given two points and have
// the given radius.
fn find_circle_center(a: Point, b: Point, r: Scalar) -> Point {
    /* Denote the middle point of A and B as M. The key is to find the center
     * of the circle.
     *         A --__
     *          /  ⟍ `、
     *         /   M  ⟍\
     *        /       ⟋  B
     *       /     ⟋   ↗
     *      /   ⟋
     *     / ⟋    r
     *  C ᜱ  ↙
     */

    let a_to_b = b - a;
    let m = (a + b) / 2i32;
    let c_to_m = Point::new(-a_to_b.y, a_to_b.x);
    let distance_am: Scalar = a_to_b.get_length() / 2.0;
    let distance_cm: Scalar = (r * r - distance_am * distance_am).sqrt();
    m - distance_cm * c_to_m.normalize()
}

// Compute parameters for a square-like rounded superellipse with a
// symmetrical radius.
fn compute_octant(center: Point, a: Scalar, radius: Scalar) -> Octant {
    /* The following figure shows the first quadrant of a square-like rounded
     * superellipse.
     *
     *              superelipse
     *        A     ↓            circular arc
     *        ---------...._J   ↙
     *        |           /   `⟍ M (where x=y)
     *        |          /     ⟋ ⟍
     *        |         /   ⟋     \
     *        |        / ⟋         |
     *        |       ᜱD           |
     *        |     ⟋              |
     *        |  ⟋                 |
     *        |⟋                   |
     *        +--------------------| A'
     *       O
     *        ←-------- a ---------→
     */

    if radius <= kEhCloseEnough {
        return Octant {
            offset: center,
            se_a: a,
            se_n: 0.0,
            circle_start: Point::new(a, a),
            ..Default::default()
        };
    }

    let ratio: Scalar = a * 2.0 / radius;
    let g: Scalar = RoundSuperellipseParam::kGapFactor * radius;

    let precomputed_vars = compute_n_and_xj(ratio);
    let n: Scalar = precomputed_vars[0];
    let xJ: Scalar = precomputed_vars[1] * a;
    let yJ: Scalar = (1.0 - precomputed_vars[1].powf(n)).powf(1.0 / n) * a;
    let max_theta: Scalar = precomputed_vars[1].powf(n / 2.0).asin();

    let tan_phiJ: Scalar = (xJ / yJ).powf(n - 1.0);
    let d: Scalar = (xJ - tan_phiJ * yJ) / (1.0 - tan_phiJ);
    let R: Scalar = ((a - d - g) as f64 * 2f64.sqrt()) as Scalar;

    let pointM = Point::new(a - g, a - g);
    let pointJ = Point::new(xJ, yJ);
    let circle_center = if radius == 0.0 { pointM } else { find_circle_center(pointJ, pointM, R) };
    let circle_max_angle = if radius == 0.0 {
        Radians::new(0.0)
    } else {
        (pointM - circle_center).angle_to(&(pointJ - circle_center))
    };

    Octant {
        offset: center,
        se_a: a,
        se_n: n,
        se_max_theta: max_theta,
        circle_start: pointJ,
        circle_center,
        circle_max_angle,
        circle_radius: R,
    }
}

// Compute parameters for a quadrant of a rounded superellipse with
// asymmetrical radii.
//
// The `corner` is the coordinate of the corner point in the same coordinate
// space as `center`, which specifies both the half size of the bounding box
// and which quadrant the curve should be.
fn compute_quadrant(center: Point, corner: Point, in_radii: Size, sign: Size) -> Quadrant {
    let corner_vector = corner - center;
    let radii = Size::new(
        cxx::min(in_radii.width.abs(), corner_vector.x.abs()),
        cxx::min(in_radii.height.abs(), corner_vector.y.abs()),
    );

    // The prefix "norm" is short for "normalized".
    //
    // Be extra careful to avoid NaNs in cases that some coordinates of
    // `in_radii` or `corner_vector` are zero.
    let norm_radius: Scalar = radii.min_dimension();
    let forward_scale: Size = if norm_radius == 0.0 { Size::new(1.0, 1.0) } else { radii / norm_radius };
    let norm_half_size: Point = corner_vector.abs() / forward_scale;
    let signed_scale: Point = replance_nan_with_default(corner_vector / norm_half_size, sign);

    // Each quadrant curve is composed of two octant curves, each of which
    // belongs to a square-like rounded rectangle. For the two octants to
    // connect at the middle of the curve, the two squares must have the
    // same `norm_radius` but different heights.
    let c: Scalar = norm_half_size.x - norm_half_size.y;

    Quadrant {
        offset: center,
        signed_scale,
        top: compute_octant(Point::new(0.0, -c), norm_half_size.x, norm_radius),
        right: compute_octant(Point::new(c, 0.0), norm_half_size.y, norm_radius),
    }
}

// Checks whether the given point is contained in the first octant of the
// given square-like rounded superellipse.
//
// The first octant refers to the region that spans from 0 to pi/4 starting
// from positive Y axis clockwise.
//
// If the point is not within this octant at all, then this function always
// returns true. Otherwise this function returns whether the point is
// contained within the rounded superellipse.
//
// The `param.offset` is ignored. The input point should have been
// transformed to the coordinate space where the rounded superellipse is
// centered at the origin.
fn octant_contains(param: &Octant, p: &Point) -> bool {
    // Check whether the point is within the octant.
    if p.x < 0.0 || p.y < 0.0 || p.y < p.x {
        return true;
    }
    // Check if the point is within the superellipsoid segment.
    if p.x <= param.circle_start.x {
        let p_se = *p / param.se_a;
        return p_se.x.powf(param.se_n) + p_se.y.powf(param.se_n) <= 1.0;
    }
    let circle_radius: Scalar = param.circle_start.get_distance_squared(&param.circle_center);
    let p_circle = *p - param.circle_center;
    p_circle.get_distance_squared(&Point::default()) < circle_radius
}

// Determine if p is inside the corner curve defined by the indicated corner
// param.
//
// The coordinates of p should be within the same coordinate space with
// `param.offset`.
//
// If `check_quadrant` is true, then this function first checks if the point
// is within the quadrant of given corner. If not, this function returns
// true.
//
// If `check_quadrant` is false, then the first step above is skipped, and
// the function checks whether the absolute (relative to the center) point
// is contained within the rounded superellipse.
fn corner_contains(param: &Quadrant, p: &Point, check_quadrant: bool) -> bool {
    let mut norm_point = (*p - param.offset) / param.signed_scale;
    if check_quadrant {
        if norm_point.x < 0.0 || norm_point.y < 0.0 {
            return true;
        }
    } else {
        norm_point = norm_point.abs();
    }
    if param.top.se_n < 2.0 || param.right.se_n < 2.0 {
        // A rectangular corner. The top and left sides contain the borders
        // while the bottom and right sides don't (see `Rect.contains`).
        let x_delta: Scalar = param.right.offset.x + param.right.se_a - norm_point.x;
        let y_delta: Scalar = param.top.offset.y + param.top.se_a - norm_point.y;
        let x_within = x_delta > 0.0 || (x_delta == 0.0 && param.signed_scale.x < 0.0);
        let y_within = y_delta > 0.0 || (y_delta == 0.0 && param.signed_scale.y < 0.0);
        return x_within && y_within;
    }
    octant_contains(&param.top, &(norm_point - param.top.offset))
        && octant_contains(&param.right, &flip(norm_point - param.right.offset))
}

struct ConicParam {
    p1: Point,
    c: Point,
    p2: Point,
    weight: Scalar,
}

struct RoundSuperellipseBuilder<'a> {
    receiver_: &'a mut dyn PathReceiver,
}

#[rustfmt::skip]
const kFlip: Matrix = Matrix::new(
    0.0, 1.0, 0.0, 0.0,
    1.0, 0.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0);

impl RoundSuperellipseBuilder<'_> {
    // Draws an arc representing the top right quadrant of a rounded
    // superellipse, transformed by `scale_sign` and the quadrant's own
    // offset and signed scale.
    //
    // If `reverse` is false, the resulting arc spans from 0 to pi/2,
    // clockwise starting from the positive Y-axis. Otherwise it spans from
    // pi/2 to 0.
    fn add_quadrant(&mut self, param: &Quadrant, reverse: bool, scale_sign: Point) {
        let transform = Matrix::make_translate_scale(
            Vector3::from(param.signed_scale * scale_sign),
            Vector3::from(param.offset),
        );
        if param.top.se_n < 2.0 || param.right.se_n < 2.0 {
            self.receiver_.line_to(
                &(transform * (param.top.offset + Point::new(param.top.se_a, param.top.se_a))),
            );
            if !reverse {
                self.receiver_
                    .line_to(&(transform * (param.right.offset + Point::new(param.right.se_a, 0.0))));
            } else {
                self.receiver_.line_to(&(transform * (param.top.offset + Point::new(0.0, param.top.se_a))));
            }
            return;
        }
        if !reverse {
            self.add_octant(&param.top, /*reverse=*/ false, /*flip=*/ false, &transform);
            self.add_octant(&param.right, /*reverse=*/ true, /*flip=*/ true, &transform);
        } else {
            self.add_octant(&param.right, /*reverse=*/ false, /*flip=*/ true, &transform);
            self.add_octant(&param.top, /*reverse=*/ true, /*flip=*/ false, &transform);
        }
    }

    // Return the points for the two conics that approximate the
    // superellipse curve of an octant (from point A to point J).
    fn superellipse_arc_points(&self, param: &Octant) -> (ConicParam, ConicParam) {
        let A = Point::new(0.0, param.se_a);
        let J = param.circle_start;
        let factors =
            superellipse_bezier_factors(param.se_n, J.x / param.se_a, J.y / param.se_a);
        let weight1: Scalar = factors.0;
        let weight2: Scalar = factors.1;
        let yHOverA: Scalar = factors.2;

        let H = Point::new(
            (1.0 - yHOverA.powf(param.se_n)).powf(1.0 / param.se_n) * param.se_a,
            yHOverA * param.se_a,
        );
        let kA: Scalar = 0.0;
        let kJ: Scalar = -(J.x / J.y).powf(param.se_n - 1.0);
        let kH: Scalar = -(H.x / H.y).powf(param.se_n - 1.0);

        (
            ConicParam { p1: A, c: intersection(A, kA, H, kH), p2: H, weight: weight1 },
            ConicParam { p1: H, c: intersection(H, kH, J, kJ), p2: J, weight: weight2 },
        )
    }

    // Return the points for the cubic Bézier curve that approximates the
    // circular arc of an octant (from point J to point M).
    fn circular_arc_points(&self, param: &Octant) -> [Point; 4] {
        let start_vector = param.circle_start - param.circle_center;
        let end_vector = start_vector.rotate(&Radians::new(-param.circle_max_angle.radians));
        let circle_end = param.circle_center + end_vector;
        let start_tangent = Point::new(start_vector.y, -start_vector.x).normalize();
        let end_tangent = Point::new(-end_vector.y, end_vector.x).normalize();
        let bezier_factor: Scalar = (param.circle_max_angle.radians / 4.0).tan() * 4.0 / 3.0;
        let radius: Scalar = start_vector.get_length();

        [
            param.circle_start,
            param.circle_start + start_tangent * bezier_factor * radius,
            circle_end + end_tangent * bezier_factor * radius,
            circle_end,
        ]
    }

    // Draws an arc representing an octant of a square-like rounded
    // superellipse.
    fn add_octant(&mut self, param: &Octant, reverse: bool, flip: bool, external_transform: &Matrix) {
        let mut transform = *external_transform * Matrix::make_translation(Vector3::from(param.offset));
        if flip {
            transform = transform * kFlip;
        }

        let circle_points = self.circular_arc_points(param);
        let se_conics = self.superellipse_arc_points(param);

        if !reverse {
            self.receiver_.conic_to(&(transform * se_conics.0.c), &(transform * se_conics.0.p2), se_conics.0.weight);
            self.receiver_.conic_to(&(transform * se_conics.1.c), &(transform * se_conics.1.p2), se_conics.1.weight);
            self.receiver_.cubic_to(
                &(transform * circle_points[1]),
                &(transform * circle_points[2]),
                &(transform * circle_points[3]),
            );
        } else {
            self.receiver_.cubic_to(
                &(transform * circle_points[2]),
                &(transform * circle_points[1]),
                &(transform * circle_points[0]),
            );
            self.receiver_.conic_to(&(transform * se_conics.1.c), &(transform * se_conics.1.p1), se_conics.1.weight);
            self.receiver_.conic_to(&(transform * se_conics.0.c), &(transform * se_conics.0.p1), se_conics.0.weight);
        }
    }
}

// Get the Bezier factor for the superellipse arc in a rounded superellipse.
//
// The result will be assigned to the weights of the two conics, and the y
// over a ratio of the junction point H.
fn superellipse_bezier_factors(mut n: Scalar, xJOverA: Scalar, yJOverA: Scalar) -> (Scalar, Scalar, Scalar) {
    const kPrecomputedVariables: [[Scalar; 2]; 13] = [
        /*n= 2.0*/ [0.7078f64 as f32, 8.3194f64 as f32],
        /*n= 3.0*/ [0.7895f64 as f32, 2.4523f64 as f32],
        /*n= 4.0*/ [0.8379f64 as f32, 1.8528f64 as f32],
        /*n= 5.0*/ [0.8701f64 as f32, 1.6891f64 as f32],
        /*n= 6.0*/ [0.8932f64 as f32, 1.5806f64 as f32],
        /*n= 7.0*/ [0.9107f64 as f32, 1.5043f64 as f32],
        /*n= 8.0*/ [0.9244f64 as f32, 1.4470f64 as f32],
        /*n= 9.0*/ [0.9355f64 as f32, 1.4037f64 as f32],
        /*n=10.0*/ [0.9448f64 as f32, 1.3701f64 as f32],
        /*n=11.0*/ [0.9526f64 as f32, 1.3431f64 as f32],
        /*n=12.0*/ [0.9594f64 as f32, 1.3212f64 as f32],
        /*n=13.0*/ [0.9653f64 as f32, 1.3032f64 as f32],
        /*n=14.0*/ [0.9705f64 as f32, 1.2880f64 as f32],
    ];
    const kNumRecords: usize = kPrecomputedVariables.len();
    const kStep: Scalar = 1.00;
    const kMinN: Scalar = 2.00;
    const kMaxN: Scalar = kMinN + (kNumRecords - 1) as Scalar * kStep;

    if n >= kMaxN {
        // Heuristic formula derived from fitting.
        n = kMaxN;
    }

    let steps: Scalar = cxx::clamp((n - kMinN) / kStep, 0.0, (kNumRecords - 1) as Scalar);
    let left: usize = cxx::clamp(steps.floor_c() as usize, 0, kNumRecords - 2);
    let frac: Scalar = steps - left as Scalar;

    let weight1: Scalar = (1.0 - frac) * kPrecomputedVariables[left][0]
        + frac * kPrecomputedVariables[left + 1][0] * n.sqrt();
    let weight2: Scalar = (1.0 - frac) * kPrecomputedVariables[left][1]
        + frac * kPrecomputedVariables[left + 1][1] * xJOverA;

    let yH_proportion: Scalar = n.sqrt();
    const yAOverA: Scalar = 1.0;
    let yHOverA: Scalar = (yAOverA * yH_proportion + yJOverA) / (yH_proportion + 1.0);

    (weight1, weight2, yHOverA)
}

// Find the intersection of two lines, each defined by a point and a slope.
fn intersection(p1: Point, k1: Scalar, p2: Point, k2: Scalar) -> Point {
    if (k1 - k2).abs() < kEhCloseEnough {
        return (p1 + p2) / 2i32;
    }
    let x: Scalar = (k1 * p1.x - k2 * p2.x + p2.y - p1.y) / (k1 - k2);
    let y: Scalar = k1 * (x - p1.x) + p1.y;
    Point::new(x, y)
}
