// flutter/impeller/geometry/size_unittests.cc

#![allow(unused_mut, unused_variables, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn size_is_empty() {
  let mut nan = f32::NAN;

  // Non-empty
  expect_false!(Size::new(10.5, 7.2).is_empty());

  // Empty both width and height both 0 or negative, in all combinations
  expect_true!(Size::new(0.0, 0.0).is_empty());
  expect_true!(Size::new(-1.0, -1.0).is_empty());
  expect_true!(Size::new(-1.0, 0.0).is_empty());
  expect_true!(Size::new(0.0, -1.0).is_empty());

  // Empty for 0 or negative width or height (but not both at the same time)
  expect_true!(Size::new(10.5, 0.0).is_empty());
  expect_true!(Size::new(10.5, -1.0).is_empty());
  expect_true!(Size::new(0.0, 7.2).is_empty());
  expect_true!(Size::new(-1.0, 7.2).is_empty());

  // Empty for NaN in width or height or both
  expect_true!(Size::new(10.5, nan).is_empty());
  expect_true!(Size::new(nan, 7.2).is_empty());
  expect_true!(Size::new(nan, nan).is_empty());
}

#[test]
fn i_size_is_empty() {
  // Non-empty
  expect_false!(ISize::new(10, 7).is_empty());

  // Empty both width and height both 0 or negative, in all combinations
  expect_true!(ISize::new(0, 0).is_empty());
  expect_true!(ISize::new(-1, -1).is_empty());
  expect_true!(ISize::new(-1, 0).is_empty());
  expect_true!(ISize::new(0, -1).is_empty());

  // Empty for 0 or negative width or height (but not both at the same time)
  expect_true!(ISize::new(10, 0).is_empty());
  expect_true!(ISize::new(10, -1).is_empty());
  expect_true!(ISize::new(0, 7).is_empty());
  expect_true!(ISize::new(-1, 7).is_empty());
}

#[test]
fn is_square() {
  expect_true!(Size::new(20.0, 20.0).is_square());
  expect_false!(Size::new(20.0, 19.0).is_square());
  expect_false!(Size::new(19.0, 20.0).is_square());

  expect_true!(ISize::new(20, 20).is_square());
  expect_false!(ISize::new(20, 19).is_square());
  expect_false!(ISize::new(19, 20).is_square());
}

#[test]
fn max_dimension() {
  expect_eq!(Size::new(20.0, 20.0).max_dimension(), 20);
  expect_eq!(Size::new(20.0, 19.0).max_dimension(), 20);
  expect_eq!(Size::new(19.0, 20.0).max_dimension(), 20);
  expect_eq!(Size::new(20.0, 21.0).max_dimension(), 21);
  expect_eq!(Size::new(21.0, 20.0).max_dimension(), 21);

  expect_eq!(ISize::new(20, 20).max_dimension(), 20);
  expect_eq!(ISize::new(20, 19).max_dimension(), 20);
  expect_eq!(ISize::new(19, 20).max_dimension(), 20);
  expect_eq!(ISize::new(20, 21).max_dimension(), 21);
  expect_eq!(ISize::new(21, 20).max_dimension(), 21);
}

#[test]
fn negation_operator() {
  expect_eq!(-Size::new(10.0, 20.0), Size::new(-10.0, -20.0));
  expect_eq!(-Size::new(-10.0, 20.0), Size::new(10.0, -20.0));
  expect_eq!(-Size::new(10.0, -20.0), Size::new(-10.0, 20.0));
  expect_eq!(-Size::new(-10.0, -20.0), Size::new(10.0, 20.0));
}

