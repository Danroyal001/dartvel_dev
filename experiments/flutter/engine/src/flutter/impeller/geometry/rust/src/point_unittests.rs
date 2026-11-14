// flutter/impeller/geometry/point_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn length() {
  for i in 0..21 {
    let i = i as f32;
    expect_eq!(Point::new(i, 0.0).get_length_squared(), i * i);
    expect_eq!(Point::new(0.0, i).get_length_squared(), i * i);
    expect_eq!(Point::new(-i, 0.0).get_length_squared(), i * i);
    expect_eq!(Point::new(0.0, -i).get_length_squared(), i * i);

    expect_eq!(Point::new(i, 0.0).get_length(), i);
    expect_eq!(Point::new(0.0, i).get_length(), i);
    expect_eq!(Point::new(-i, 0.0).get_length(), i);
    expect_eq!(Point::new(0.0, -i).get_length(), i);

    expect_eq!(Point::new(i, i).get_length_squared(), 2.0 * i * i);
    expect_eq!(Point::new(-i, i).get_length_squared(), 2.0 * i * i);
    expect_eq!(Point::new(i, -i).get_length_squared(), 2.0 * i * i);
    expect_eq!(Point::new(-i, -i).get_length_squared(), 2.0 * i * i);

    expect_float_eq!(Point::new(i, i).get_length(), kSqrt2 * i);
    expect_float_eq!(Point::new(-i, i).get_length(), kSqrt2 * i);
    expect_float_eq!(Point::new(i, -i).get_length(), kSqrt2 * i);
    expect_float_eq!(Point::new(-i, -i).get_length(), kSqrt2 * i);
  }
}

#[test]
fn distance() {
  for j in 0..21 {
    for i in 0..21 {
      let (i, j) = (i as f32, j as f32);
      {
        let mut d = i - j;

        expect_eq!(Point::new(i, 0.0).get_distance_squared(&Point::new(j, 0.0)), d * d);
        expect_eq!(Point::new(0.0, i).get_distance_squared(&Point::new(0.0, j)), d * d);
        expect_eq!(Point::new(j, 0.0).get_distance_squared(&Point::new(i, 0.0)), d * d);
        expect_eq!(Point::new(0.0, j).get_distance_squared(&Point::new(0.0, i)), d * d);

        expect_eq!(Point::new(i, 0.0).get_distance(&Point::new(j, 0.0)), d.abs());
        expect_eq!(Point::new(0.0, i).get_distance(&Point::new(0.0, j)), d.abs());
        expect_eq!(Point::new(j, 0.0).get_distance(&Point::new(i, 0.0)), d.abs());
        expect_eq!(Point::new(0.0, j).get_distance(&Point::new(0.0, i)), d.abs());
      }

      {
        let mut d_squared = i * i + j * j;

        expect_eq!(Point::new(i, 0.0).get_distance_squared(&Point::new(0.0, j)), d_squared);
        expect_eq!(Point::new(-i, 0.0).get_distance_squared(&Point::new(0.0, j)), d_squared);
        expect_eq!(Point::new(i, 0.0).get_distance_squared(&Point::new(0.0, -j)), d_squared);
        expect_eq!(Point::new(-i, 0.0).get_distance_squared(&Point::new(0.0, -j)), d_squared);

        let mut d = d_squared.sqrt();

        expect_float_eq!(Point::new(i, 0.0).get_distance(&Point::new(0.0, j)), d);
        expect_float_eq!(Point::new(-i, 0.0).get_distance(&Point::new(0.0, j)), d);
        expect_float_eq!(Point::new(i, 0.0).get_distance(&Point::new(0.0, -j)), d);
        expect_float_eq!(Point::new(-i, 0.0).get_distance(&Point::new(0.0, -j)), d);
      }
    }
  }
}

#[test]
fn perpendicular_left() {
  expect_eq!(Point::new(1.0, 0.0).perpendicular_left(), Point::new(0.0, -1.0));
  expect_eq!(Point::new(0.0, 1.0).perpendicular_left(), Point::new(1.0, 0.0));
  expect_eq!(Point::new(-1.0, 0.0).perpendicular_left(), Point::new(0.0, 1.0));
  expect_eq!(Point::new(0.0, -1.0).perpendicular_left(), Point::new(-1.0, 0.0));

  expect_eq!(Point::new(1.0, 1.0).perpendicular_left(), Point::new(1.0, -1.0));
  expect_eq!(Point::new(-1.0, 1.0).perpendicular_left(), Point::new(1.0, 1.0));
  expect_eq!(Point::new(-1.0, -1.0).perpendicular_left(), Point::new(-1.0, 1.0));
  expect_eq!(Point::new(1.0, -1.0).perpendicular_left(), Point::new(-1.0, -1.0));
}

#[test]
fn perpendicular_right() {
  expect_eq!(Point::new(1.0, 0.0).perpendicular_right(), Point::new(0.0, 1.0));
  expect_eq!(Point::new(0.0, 1.0).perpendicular_right(), Point::new(-1.0, 0.0));
  expect_eq!(Point::new(-1.0, 0.0).perpendicular_right(), Point::new(0.0, -1.0));
  expect_eq!(Point::new(0.0, -1.0).perpendicular_right(), Point::new(1.0, 0.0));

  expect_eq!(Point::new(1.0, 1.0).perpendicular_right(), Point::new(-1.0, 1.0));
  expect_eq!(Point::new(-1.0, 1.0).perpendicular_right(), Point::new(-1.0, -1.0));
  expect_eq!(Point::new(-1.0, -1.0).perpendicular_right(), Point::new(1.0, -1.0));
  expect_eq!(Point::new(1.0, -1.0).perpendicular_right(), Point::new(1.0, 1.0));
}

fn test_point_to_segment_group(
    segment0: Point,
    segment1: Point,
    mut p0: Point,
    delta: Point,
    count: i32,
    calc_distance: impl Fn(Point) -> (Scalar, Scalar),
) {
  for _ in 0..count {
    let (distance, squared) = calc_distance(p0);
    expect_float_eq!(p0.get_distance_to_segment_squared(segment0, segment1), squared);
    expect_float_eq!(p0.get_distance_to_segment_squared(segment1, segment0), squared);
    expect_float_eq!(p0.get_distance_to_segment(segment0, segment1), distance);
    expect_float_eq!(p0.get_distance_to_segment(segment1, segment0), distance);
    p0 += delta;
  }
}

fn pt(x: Scalar, y: Scalar) -> Point {
  Point::new(x, y)
}

#[test]
fn point_to_segment() {
  // Horizontal segment and points to the left of it on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 10.0),
      // Starting point, delta, count ({0,10} through {10,10})
      pt(0.0, 10.0), pt(1.0, 0.0), 11,
      // Distance computation
      |p: Point| { let d: Scalar = 10.0 - p.x; (d, d * d) });

  // Horizontal segment and points on the segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 10.0),
      // Starting point, delta, count ({11,10} through pt(19.0, 10.0))
      pt(11.0, 10.0), pt(1.0, 0.0), 9,
      // Distance computation
      |p: Point| (0.0f32, 0.0f32));

  // Horizontal segment and points to the right of it on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 10.0),
      // Starting point, delta, count ({20,10} through {30,10})
      pt(20.0, 10.0), pt(1.0, 0.0), 11,
      // Distance computation
      |p: Point| { let d: Scalar = p.x - 20.0; (d, d * d) });

  // Vertical segment and points above the top of it on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(10.0, 20.0),
      // Starting point, delta, count ({10,0} through {10,10})
      pt(10.0, 0.0), pt(0.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d: Scalar = 10.0 - p.y; (d, d * d) });

  // Vertical segment and points on the segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(10.0, 20.0),
      // Starting point, delta, count ({10,11} through pt(10.0, 19.0))
      pt(10.0, 11.0), pt(0.0, 1.0), 9,
      // Distance computation
      |p: Point| (0.0f32, 0.0f32));

  // Vertical segment and points below the bottom of it on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(10.0, 20.0),
      // Starting point, delta, count ({10,20} through {10,30})
      pt(10.0, 20.0), pt(0.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d: Scalar = p.y - 20.0; (d, d * d) });

  // Horizontal segment and points 5 pixels above and to the left of it
  // on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 10.0),
      // Starting point, delta, count ({0,5} through {10,5})
      pt(0.0, 5.0), pt(1.0, 0.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = (10.0 - p.x) * (10.0 - p.x) + 25.0; (d_sq.sqrt(), d_sq) });

  // Horizontal segment and points 5 pixels directly above the segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 10.0),
      // Starting point, delta, count ({11,5} through pt(19.0, 5.0))
      pt(11.0, 5.0), pt(1.0, 0.0), 9,
      // Distance computation
      |p: Point| (5.0f32, 25.0f32));

  // Horizontal segment and points 5 pixels above and to the right of it
  // on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 10.0),
      // Starting point, delta, count ({20,5} through {30,5})
      pt(20.0, 5.0), pt(1.0, 0.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = (p.x - 20.0) * (p.x - 20.0) + 25.0; (d_sq.sqrt(), d_sq) });

  // Vertical segment and points 5 pixels to the left and above the segment
  // on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(10.0, 20.0),
      // Starting point, delta, count ({5,0} through {5,10})
      pt(5.0, 0.0), pt(0.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = 25.0 + (10.0 - p.y) * (10.0 - p.y); (d_sq.sqrt(), d_sq) });

  // Vertical segment and points 5 pixels directly to the left of the segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(10.0, 20.0),
      // Starting point, delta, count ({5,11} through {5,19,})
      pt(5.0, 11.0), pt(0.0, 1.0), 9,
      // Distance computation
      |p: Point| (5.0f32, 25.0f32));

  // Vertical segment and points 5 pixels to the left and below the segment
  // on the same line.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(10.0, 20.0),
      // Starting point, delta, count ({20,5} through {30,5})
      pt(5.0, 20.0), pt(0.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = 25.0 + (p.y - 20.0) * (p.y - 20.0); (d_sq.sqrt(), d_sq) });

  // Diagonal segment and points up and to the right of the top of the segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 20.0),
      // Starting point, delta, count ({5,-5} through {15,5})
      pt(5.0, -5.0), pt(1.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = (p.x - 10.0) * (p.x - 10.0) + (p.y - 10.0) * (p.y - 10.0); (d_sq.sqrt(), d_sq) });

  // Diagonal segment and points up and to the right of the segment itself.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 20.0),
      // Starting point, delta, count ({15,5} through {24,14})
      pt(15.0, 5.0), pt(1.0, 1.0), 9,
      // Distance computation
      |p: Point| { let d_sq: Scalar = 50.0f32; (d_sq.sqrt(), d_sq) });

  // Diagonal segment and points up and to the right of the bottom of the
  // segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 20.0),
      // Starting point, delta, count ({25,15} through {35,25})
      pt(25.0, 15.0), pt(1.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = (p.x - 20.0) * (p.x - 20.0) + (p.y - 20.0) * (p.y - 20.0); (d_sq.sqrt(), d_sq) });

  // Diagonal segment and points down and to the left of the top of the segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 20.0),
      // Starting point, delta, count ({-5,5} through {5,15})
      pt(-5.0, 5.0), pt(1.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = (p.x - 10.0) * (p.x - 10.0) + (p.y - 10.0) * (p.y - 10.0); (d_sq.sqrt(), d_sq) });

  // Diagonal segment and points down and to the left of the segment itself.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 20.0),
      // Starting point, delta, count ({5,15} through {14,24})
      pt(5.0, 15.0), pt(1.0, 1.0), 9,
      // Distance computation
      |p: Point| { let d_sq: Scalar = 50.0f32; (d_sq.sqrt(), d_sq) });

  // Diagonal segment and points down and to the left of the bottom of the
  // segment.
  test_point_to_segment_group(
      // Segment
      pt(10.0, 10.0), pt(20.0, 20.0),
      // Starting point, delta, count ({15,25} through {25,35})
      pt(15.0, 25.0), pt(1.0, 1.0), 11,
      // Distance computation
      |p: Point| { let d_sq: Scalar = (p.x - 20.0) * (p.x - 20.0) + (p.y - 20.0) * (p.y - 20.0); (d_sq.sqrt(), d_sq) });
}

#[test]
fn cross_product_three_points() {
  // Colinear
  expect_float_eq!(Point::cross3(&Point::new(-1.0, 0.0), &Point::new(0.0, 0.0), &Point::new(1.0, 0.0)), 0);
  expect_float_eq!(Point::cross3(&Point::new(1.0, 0.0), &Point::new(0.0, 0.0), &Point::new(-1.0, 0.0)), 0);

  // Right turn
  expect_float_eq!(Point::cross3(&Point::new(-1.0, 0.0), &Point::new(0.0, 0.0), &Point::new(0.0, 1.0)), 1);
  expect_float_eq!(Point::cross3(&Point::new(-2.0, 0.0), &Point::new(0.0, 0.0), &Point::new(0.0, 2.0)), 4);

  // Left turn
  expect_float_eq!(Point::cross3(&Point::new(-1.0, 0.0), &Point::new(0.0, 0.0), &Point::new(0.0, -1.0)), -1);
  expect_float_eq!(Point::cross3(&Point::new(-2.0, 0.0), &Point::new(0.0, 0.0), &Point::new(0.0, -2.0)), -4);

  // Convenient values for a less obvious left turn.
  // p1 - p0 == (0, 0) - (3, -4) == (-3, 4)
  // p2 - p0 == (1, 2) - (3, -4) == (-2, 6)
  // product of the magnitude of the 2 legs and the sin of their angle
  // (||(-3, 4)||) * (||(-2, 6)||) * sin(angle)
  // 5 * sqrt(40) * sin(angle)
  // angle = arcsin(4 / 5) - arcsin(6 / sqrt(40)) ~= -18.4349
  // sin(angle) ~= -0.316227766
  // 5 * sqrt(40) * sin(angle) == -10
  // The math is cleaner with the cross product:
  // (-3 * 6) - (-2 * 4) == -18 - -8 == -10
  expect_float_eq!(Point::cross3(&Point::new(3.0, -4.0), &Point::new(0.0, 0.0), &Point::new(1.0, 2.0)), -10);
}


// Not upstream's: a zero vector normalizes to the X axis (no upstream test
// covers the zero-length branch; see README.md, Deliberate failures).
#[test]
fn normalize_of_zero_is_the_x_axis() {
  expect_eq!(Point::new(0.0, 0.0).normalize(), Point::new(1.0, 0.0));
  expect_eq!(Point::new(-0.0, 0.0).normalize(), Point::new(1.0, 0.0));
}
