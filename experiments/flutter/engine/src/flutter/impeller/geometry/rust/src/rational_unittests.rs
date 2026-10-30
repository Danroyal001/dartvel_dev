// flutter/impeller/geometry/rational_unittests.cc

#![allow(unused_mut, unused_variables, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn make() {
  let mut value = Rational::new(1, 2);
  expect_eq!(value.get_numerator(), 1);
  expect_eq!(value.get_denominator(), 2u32);
}

#[test]
fn equals_same_den() {
  expect_true!(Rational::new(1, 2) == Rational::new(1, 2));
}

#[test]
fn not_equals_same_den() {
  expect_false!(Rational::new(3, 2) == Rational::new(1, 2));
}

#[test]
fn equals_different_den() {
  expect_true!(Rational::new(1, 2) == Rational::new(2, 4));
}

#[test]
fn negation_not_equals() {
  expect_false!(Rational::new(1, 2) == Rational::new(-1, 2));
}

#[test]
fn less_than_same_den() {
  expect_true!(Rational::new(1, 2) < Rational::new(2, 2));
}

#[test]
fn less_than_negation() {
  expect_true!(Rational::new(-1, 2) < Rational::new(2, 23));
}

#[test]
fn less_than_different_den() {
  expect_true!(Rational::new(1, 2) < Rational::new(25, 23));
}

#[test]
fn not_less_than_different_den() {
  expect_false!(Rational::new(25, 23) < Rational::new(1, 2));
}

#[test]
fn same_hashes() {
  expect_eq!(Rational::new(1, 2).get_hash(), Rational::new(2, 4).get_hash());
}

#[test]
fn different_hashes() {
  expect_ne!(Rational::new(2, 2).get_hash(), Rational::new(2, 4).get_hash());
}

