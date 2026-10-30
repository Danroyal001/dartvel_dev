// flutter/impeller/geometry/wangs_formula_unittests.cc

#![allow(unused_mut, unused_variables, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn cubic() {
  let mut p0 = Point::new(300.0, 0.0);
  let mut p1 = Point::new(0.0, 0.0);
  let mut p2 = Point::new(0.0, 0.0);
  let mut p3 = Point::new(0.0, 300.0);
  let mut result = compute_cubic_subdivisions(1.0, p0, p1, p2, p3);
  expect_float_eq!(result, 30.0f32);
}

#[test]
fn quadratic() {
  let mut p0 = Point::new(15.0, 0.0);
  let mut p1 = Point::new(0.0, 0.0);
  let mut p2 = Point::new(0.0, 20.0);
  let mut result = compute_quadradic_subdivisions(1.0, p0, p1, p2);
  expect_float_eq!(result, 5.0f32);
}

