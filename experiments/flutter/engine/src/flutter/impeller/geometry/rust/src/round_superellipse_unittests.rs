// flutter/impeller/geometry/round_superellipse_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

macro_rules! CHECK_POINT_WITH_OFFSET {
  ($rr:expr, $p:expr, $outward_offset:expr) => {{
 
  expect_true!($rr.contains(&$p));                         
  expect_false!($rr.contains(&($p + $outward_offset)));
  }};
}

// The anonymous-namespace SpyPathReceiver: forwards the segments it is given
// to the closures set with spy_line_to, spy_cubic_to and spy_conic_to.
#[derive(Default)]
struct SpyPathReceiver {
  line_to_: Option<Box<dyn Fn(&Point)>>,
  cubic_to_: Option<Box<dyn Fn(&Point, &Point, &Point)>>,
  conic_to_: Option<Box<dyn Fn(&Point, &Point, Scalar)>>,
}

impl SpyPathReceiver {
  fn spy_line_to(&mut self, line_to: impl Fn(&Point) + 'static) {
    self.line_to_ = Some(Box::new(line_to));
  }
  fn spy_cubic_to(&mut self, cubic_to: impl Fn(&Point, &Point, &Point) + 'static) {
    self.cubic_to_ = Some(Box::new(cubic_to));
  }
  fn spy_conic_to(&mut self, conic_to: impl Fn(&Point, &Point, Scalar) + 'static) {
    self.conic_to_ = Some(Box::new(conic_to));
  }
}

impl PathReceiver for SpyPathReceiver {
  fn move_to(&mut self, _p2: &Point, _will_be_closed: bool) {}
  fn line_to(&mut self, p2: &Point) {
    if let Some(f) = &self.line_to_ {
      f(p2);
    }
  }
  fn quad_to(&mut self, _cp: &Point, _p2: &Point) {}
  fn cubic_to(&mut self, cp1: &Point, cp2: &Point, p2: &Point) {
    if let Some(f) = &self.cubic_to_ {
      f(cp1, cp2, p2);
    }
  }
  fn conic_to(&mut self, cp: &Point, p2: &Point, weight: Scalar) -> bool {
    if let Some(f) = &self.conic_to_ {
      f(cp, p2, weight);
      return true;
    }
    false
  }
  fn close(&mut self) {}
}

#[test]
fn empty_declaration() {
  let mut rse = RoundSuperellipse::default();

  expect_true!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_true!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::default());
  expect_eq!(rse.get_bounds().get_left(), 0.0f32);
  expect_eq!(rse.get_bounds().get_top(), 0.0f32);
  expect_eq!(rse.get_bounds().get_right(), 0.0f32);
  expect_eq!(rse.get_bounds().get_bottom(), 0.0f32);
  expect_eq!(rse.get_radii().top_left, Size::default());
  expect_eq!(rse.get_radii().top_right, Size::default());
  expect_eq!(rse.get_radii().bottom_left, Size::default());
  expect_eq!(rse.get_radii().bottom_right, Size::default());
  expect_eq!(rse.get_radii().top_left.width, 0.0f32);
  expect_eq!(rse.get_radii().top_left.height, 0.0f32);
  expect_eq!(rse.get_radii().top_right.width, 0.0f32);
  expect_eq!(rse.get_radii().top_right.height, 0.0f32);
  expect_eq!(rse.get_radii().bottom_left.width, 0.0f32);
  expect_eq!(rse.get_radii().bottom_left.height, 0.0f32);
  expect_eq!(rse.get_radii().bottom_right.width, 0.0f32);
  expect_eq!(rse.get_radii().bottom_right.height, 0.0f32);
}

#[test]
fn default_constructor() {
  let mut rse = RoundSuperellipse::default();

  expect_true!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_true!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::default());
  expect_eq!(rse.get_radii().top_left, Size::default());
  expect_eq!(rse.get_radii().top_right, Size::default());
  expect_eq!(rse.get_radii().bottom_left, Size::default());
  expect_eq!(rse.get_radii().bottom_right, Size::default());
}

#[test]
fn empty_rect_construction() {
  let mut rse = RoundSuperellipse::make_rect(&Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32));

  expect_true!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_true!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::default());
  expect_eq!(rse.get_radii().top_right, Size::default());
  expect_eq!(rse.get_radii().bottom_left, Size::default());
  expect_eq!(rse.get_radii().bottom_right, Size::default());
}

#[test]
fn rect_constructor() {
  let mut rse = RoundSuperellipse::make_rect(&Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));

  expect_false!(rse.is_empty());
  expect_true!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::default());
  expect_eq!(rse.get_radii().top_right, Size::default());
  expect_eq!(rse.get_radii().bottom_left, Size::default());
  expect_eq!(rse.get_radii().bottom_right, Size::default());
}

#[test]
fn inverted_rect_construction() {
  let mut rse = RoundSuperellipse::make_rect(&Rect::make_ltrb(20.0f32, 20.0f32, 10.0f32, 10.0f32));

  expect_false!(rse.is_empty());
  expect_true!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::default());
  expect_eq!(rse.get_radii().top_right, Size::default());
  expect_eq!(rse.get_radii().bottom_left, Size::default());
  expect_eq!(rse.get_radii().bottom_right, Size::default());
}

#[test]
fn empty_oval_construction() {
  let mut rse = RoundSuperellipse::make_rect_xy(
      &Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32), 10.0f32, 10.0f32);

  expect_true!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_true!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::default());
  expect_eq!(rse.get_radii().top_right, Size::default());
  expect_eq!(rse.get_radii().bottom_left, Size::default());
  expect_eq!(rse.get_radii().bottom_right, Size::default());
}

#[test]
fn oval_constructor() {
  let mut rse = RoundSuperellipse::make_oval(&Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_true!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(5.0f32, 5.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(5.0f32, 5.0f32));
}

#[test]
fn inverted_oval_construction() {
  let mut rse = RoundSuperellipse::make_rect_xy(
      &Rect::make_ltrb(20.0f32, 20.0f32, 10.0f32, 10.0f32), 10.0f32, 10.0f32);

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_true!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(5.0f32, 5.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(5.0f32, 5.0f32));
}

#[test]
fn rect_radius_constructor() {
  let mut rse = RoundSuperellipse::make_rect_radius(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32), 2.0f32);

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(2.0f32, 2.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(2.0f32, 2.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(2.0f32, 2.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(2.0f32, 2.0f32));
}

#[test]
fn rect_xy_constructor() {
  let mut rse = RoundSuperellipse::make_rect_xy(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32), 2.0f32, 3.0f32);

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(2.0f32, 3.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(2.0f32, 3.0f32));
}

#[test]
fn rect_size_constructor() {
  let mut rse = RoundSuperellipse::make_rect_xy_size(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32), Size::new(2.0f32, 3.0f32));

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(2.0f32, 3.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(2.0f32, 3.0f32));
}

#[test]
fn rect_radii_constructor() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0, 1.5),
          top_right: Size::new(2.0, 2.5f32),
          bottom_left: Size::new(3.0, 3.5f32),
          bottom_right: Size::new(4.0, 4.5f32),
        ..Default::default()
      });

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(1.0f32, 1.5f32));
  expect_eq!(rse.get_radii().top_right, Size::new(2.0f32, 2.5f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(3.0f32, 3.5f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(4.0f32, 4.5f32));
}

#[test]
fn rect_radii_overflow_width_constructor() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 6.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  // Largest sum of paired radii widths is the bottom edge which sums to 12
  // Rect is only 6 wide so all radii are scaled by half
  // Rect is 30 tall so no scaling should happen due to radii heights

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 16.0f32, 40.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(0.5f32, 1.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(1.5f32, 2.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(2.5f32, 3.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(3.5f32, 4.0f32));
}

#[test]
fn rect_radii_overflow_height_constructor() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 6.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  // Largest sum of paired radii heights is the right edge which sums to 12
  // Rect is only 6 tall so all radii are scaled by half
  // Rect is 30 wide so no scaling should happen due to radii widths

  expect_false!(rse.is_empty());
  expect_false!(rse.is_rect());
  expect_false!(rse.is_oval());
  expect_true!(rse.is_finite());
  expect_false!(rse.get_bounds().is_empty());
  expect_eq!(rse.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 40.0f32, 16.0f32));
  expect_eq!(rse.get_radii().top_left, Size::new(0.5f32, 1.0f32));
  expect_eq!(rse.get_radii().top_right, Size::new(1.5f32, 2.0f32));
  expect_eq!(rse.get_radii().bottom_left, Size::new(2.5f32, 3.0f32));
  expect_eq!(rse.get_radii().bottom_right, Size::new(3.5f32, 4.0f32));
}

#[test]
fn shift() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut shifted = rse.shift(5.0, 6.0);

  expect_false!(shifted.is_empty());
  expect_false!(shifted.is_rect());
  expect_false!(shifted.is_oval());
  expect_true!(shifted.is_finite());
  expect_false!(shifted.get_bounds().is_empty());
  expect_eq!(shifted.get_bounds(), Rect::make_ltrb(15.0f32, 16.0f32, 45.0f32, 46.0f32));
  expect_eq!(shifted.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(shifted.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(shifted.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(shifted.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(shifted, RoundSuperellipse::make_rect_radii(
                         &Rect::make_xywh(15.0f32, 16.0f32, 30.0f32, 30.0f32),
                         &RoundingRadii {
                             top_left: Size::new(1.0f32, 2.0f32),
                             top_right: Size::new(3.0f32, 4.0f32),
                             bottom_left: Size::new(5.0f32, 6.0f32),
                             bottom_right: Size::new(7.0f32, 8.0f32),
                           ..Default::default()
                         }));
}

#[test]
fn expand_scalar() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand(5.0);

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(5.0f32, 5.0f32, 45.0f32, 45.0f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(5.0f32, 5.0f32, 40.0f32, 40.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn expand_two_scalars() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand_xy(5.0, 6.0);

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(5.0f32, 4.0f32, 45.0f32, 46.0f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(5.0f32, 4.0f32, 40.0f32, 42.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn expand_four_scalars() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand_ltrb(5.0, 6.0, 7.0, 8.0);

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(5.0f32, 4.0f32, 47.0f32, 48.0f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(5.0f32, 4.0f32, 42.0f32, 44.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn contract_scalar() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand(-2.0);

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(12.0f32, 12.0f32, 38.0f32, 38.0f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(12.0f32, 12.0f32, 26.0f32, 26.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn contract_two_scalars() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand_xy(-1.0, -2.0);

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(11.0f32, 12.0f32, 39.0f32, 38.0f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(11.0f32, 12.0f32, 28.0f32, 26.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn contract_four_scalars() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand_ltrb(-1.0, -1.5, -2.0, -2.5);

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(11.0f32, 11.5f32, 38.0f32, 37.5f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(1.0f32, 2.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(3.0f32, 4.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(7.0f32, 8.0f32));

  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(11.0f32, 11.5f32, 27.0f32, 26.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn contract_and_require_radii_adjustment() {
  let mut rse = RoundSuperellipse::make_rect_radii(
      &Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
      &RoundingRadii {
          top_left: Size::new(1.0f32, 2.0f32),
          top_right: Size::new(3.0f32, 4.0f32),
          bottom_left: Size::new(5.0f32, 6.0f32),
          bottom_right: Size::new(7.0f32, 8.0f32),
        ..Default::default()
      });
  let mut expanded = rse.expand(-12.0);
  // Largest sum of paired radii sizes are the bottom and right edges
  // both of which sum to 12
  // Rect was 30x30 reduced by 12 on all sides leaving only 6x6, so all
  // radii are scaled by half to avoid overflowing the contracted rect

  expect_false!(expanded.is_empty());
  expect_false!(expanded.is_rect());
  expect_false!(expanded.is_oval());
  expect_true!(expanded.is_finite());
  expect_false!(expanded.get_bounds().is_empty());
  expect_eq!(expanded.get_bounds(), Rect::make_ltrb(22.0f32, 22.0f32, 28.0f32, 28.0f32));
  expect_eq!(expanded.get_radii().top_left, Size::new(0.5f32, 1.0f32));
  expect_eq!(expanded.get_radii().top_right, Size::new(1.5f32, 2.0f32));
  expect_eq!(expanded.get_radii().bottom_left, Size::new(2.5f32, 3.0f32));
  expect_eq!(expanded.get_radii().bottom_right, Size::new(3.5f32, 4.0f32));

  // In this test, the MakeRectRadii constructor will make the same
  // adjustment to the radii that the Expand method applied.
  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(22.0f32, 22.0f32, 6.0f32, 6.0f32),
                          &RoundingRadii {
                              top_left: Size::new(1.0f32, 2.0f32),
                              top_right: Size::new(3.0f32, 4.0f32),
                              bottom_left: Size::new(5.0f32, 6.0f32),
                              bottom_right: Size::new(7.0f32, 8.0f32),
                            ..Default::default()
                          }));

  // In this test, the arguments to the constructor supply the correctly
  // adjusted radii (though there is no real way to tell other than
  // the result is the same).
  expect_eq!(expanded, RoundSuperellipse::make_rect_radii(
                          &Rect::make_xywh(22.0f32, 22.0f32, 6.0f32, 6.0f32),
                          &RoundingRadii {
                              top_left: Size::new(0.5f32, 1.0f32),
                              top_right: Size::new(1.5f32, 2.0f32),
                              bottom_left: Size::new(2.5f32, 3.0f32),
                              bottom_right: Size::new(3.5f32, 4.0f32),
                            ..Default::default()
                          }));
}

#[test]
fn no_corner_round_superellipse_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  // Rounded superellipses of bounds with no corners contains corners just
  // barely.
  let mut no_corners = RoundSuperellipse::make_rect_radii(
      &bounds, &RoundingRadii::make_radii(Size::new(0.0, 0.0)));

  expect_true!(no_corners.contains(&Point::new(-50.0, -50.0)));
  // Rectangles have half-in, half-out containment so we need
  // to be careful about testing containment of right/bottom corners.
  expect_true!(no_corners.contains(&Point::new(-50.0, 49.99)));
  expect_true!(no_corners.contains(&Point::new(49.99, -50.0)));
  expect_true!(no_corners.contains(&Point::new(49.99, 49.99)));
  expect_false!(no_corners.contains(&Point::new(-50.01, -50.0)));
  expect_false!(no_corners.contains(&Point::new(-50.0, -50.01)));
  expect_false!(no_corners.contains(&Point::new(-50.01, 50.0)));
  expect_false!(no_corners.contains(&Point::new(-50.0, 50.01)));
  expect_false!(no_corners.contains(&Point::new(50.01, -50.0)));
  expect_false!(no_corners.contains(&Point::new(50.0, -50.01)));
  expect_false!(no_corners.contains(&Point::new(50.01, 50.0)));
  expect_false!(no_corners.contains(&Point::new(50.0, 50.01)));
}

#[test]
fn tiny_corner_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  // Rounded superellipses of bounds with even the tiniest corners does not
  // contain corners.
  let mut tiny_corners = RoundSuperellipse::make_rect_radii(
      &bounds, &RoundingRadii::make_radii(Size::new(0.01, 0.01)));

  expect_false!(tiny_corners.contains(&Point::new(-50.0, -50.0)));
  expect_false!(tiny_corners.contains(&Point::new(-50.0, 50.0)));
  expect_false!(tiny_corners.contains(&Point::new(50.0, -50.0)));
  expect_false!(tiny_corners.contains(&Point::new(50.0, 50.0)));
}

#[test]
fn uniform_square_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  let mut rr = RoundSuperellipse::make_rect_radii(
      &bounds, &RoundingRadii::make_radii(Size::new(5.0, 5.0)));

macro_rules! CHECK_POINT_AND_MIRRORS {
  ($p:expr) => {{
                                     
  CHECK_POINT_WITH_OFFSET!(rr, ($p), Point::new(0.02, 0.02));                 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(1.0, -1.0), Point::new(0.02, -0.02)); 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(-1.0, 1.0), Point::new(-0.02, 0.02)); 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(-1.0, -1.0), Point::new(-0.02, -0.02));
  }};
}

  CHECK_POINT_AND_MIRRORS!(Point::new(0.0, 49.995));      // Top
  CHECK_POINT_AND_MIRRORS!(Point::new(44.245, 49.95));  // Top curve start
  CHECK_POINT_AND_MIRRORS!(Point::new(45.72, 49.87));   // Top joint
  CHECK_POINT_AND_MIRRORS!(Point::new(48.53, 48.53));   // Circular arc mid
  CHECK_POINT_AND_MIRRORS!(Point::new(49.87, 45.72));   // Right joint
  CHECK_POINT_AND_MIRRORS!(Point::new(49.95, 44.245));  // Right curve start
  CHECK_POINT_AND_MIRRORS!(Point::new(49.995, 0.0));      // Right
}

#[test]
fn uniform_elliptical_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  let mut rr = RoundSuperellipse::make_rect_radii(
      &bounds, &RoundingRadii::make_radii(Size::new(5.0, 10.0)));

macro_rules! CHECK_POINT_AND_MIRRORS {
  ($p:expr) => {{
                                     
  CHECK_POINT_WITH_OFFSET!(rr, ($p), Point::new(0.02, 0.02));                 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(1.0, -1.0), Point::new(0.02, -0.02)); 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(-1.0, 1.0), Point::new(-0.02, 0.02)); 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(-1.0, -1.0), Point::new(-0.02, -0.02));
  }};
}

  CHECK_POINT_AND_MIRRORS!(Point::new(0.0, 49.995));       // Top
  CHECK_POINT_AND_MIRRORS!(Point::new(44.245, 49.911));  // Top curve start
  CHECK_POINT_AND_MIRRORS!(Point::new(45.72, 49.75));    // Top joint
  CHECK_POINT_AND_MIRRORS!(Point::new(48.51, 47.07));    // Circular arc mid
  CHECK_POINT_AND_MIRRORS!(Point::new(49.87, 41.44));    // Right joint
  CHECK_POINT_AND_MIRRORS!(Point::new(49.95, 38.49));    // Right curve start
  CHECK_POINT_AND_MIRRORS!(Point::new(49.995, 0.0));       // Right
}

#[test]
fn uniform_rectangular_contains() {
  // The bounds is not centered at the origin and has unequal height and width.
  let mut bounds = Rect::make_ltrb(0.0f32, 0.0f32, 50.0f32, 100.0f32);
  let mut rr = RoundSuperellipse::make_rect_radii(
      &bounds, &RoundingRadii::make_radii(Size::new(23.0, 30.0)));

  let mut center = bounds.get_center();
macro_rules! CHECK_POINT_AND_MIRRORS {
  ($p:expr) => {{
                                   
  CHECK_POINT_WITH_OFFSET!(rr, (($p - center) * Point::new(1.0, 1.0) + center),   
                          Point::new(0.02, 0.02));                        
  CHECK_POINT_WITH_OFFSET!(rr, (($p - center) * Point::new(1.0, -1.0) + center),  
                          Point::new(0.02, -0.02));                       
  CHECK_POINT_WITH_OFFSET!(rr, (($p - center) * Point::new(-1.0, 1.0) + center),  
                          Point::new(-0.02, 0.02));                       
  CHECK_POINT_WITH_OFFSET!(rr, (($p - center) * Point::new(-1.0, -1.0) + center), 
                          Point::new(-0.02, -0.02));
  }};
}

  CHECK_POINT_AND_MIRRORS!(Point::new(24.99, 99.99));  // Bottom mid edge
  CHECK_POINT_AND_MIRRORS!(Point::new(29.99, 99.64));
  CHECK_POINT_AND_MIRRORS!(Point::new(34.99, 98.06));
  CHECK_POINT_AND_MIRRORS!(Point::new(39.99, 94.73));
  CHECK_POINT_AND_MIRRORS!(Point::new(44.13, 89.99));
  CHECK_POINT_AND_MIRRORS!(Point::new(48.46, 79.99));
  CHECK_POINT_AND_MIRRORS!(Point::new(49.70, 69.99));
  CHECK_POINT_AND_MIRRORS!(Point::new(49.97, 59.99));
  CHECK_POINT_AND_MIRRORS!(Point::new(49.99, 49.99));  // Right mid edge

}

#[test]
fn slim_diagonal_contains() {
  // This shape has large radii on one diagonal and tiny radii on the other,
  // resulting in a almond-like shape placed diagonally (NW to SE).
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  let mut rr = RoundSuperellipse::make_rect_radii(
      &bounds, &RoundingRadii {
                  top_left: Size::new(1.0, 1.0),
                  top_right: Size::new(99.0, 99.0),
                  bottom_left: Size::new(99.0, 99.0),
                  bottom_right: Size::new(1.0, 1.0),
                ..Default::default()
              });

  expect_true!(rr.contains(&Point::new(0.0, 0.0)));
  expect_false!(rr.contains(&Point::new(-49.999, -49.999)));
  expect_false!(rr.contains(&Point::new(-49.999, 49.999)));
  expect_false!(rr.contains(&Point::new(49.999, 49.999)));
  expect_false!(rr.contains(&Point::new(49.999, -49.999)));

  // The pointy ends at the NE and SW corners
  CHECK_POINT_WITH_OFFSET!(rr, Point::new(-49.70, -49.70), Point::new(-0.02, -0.02));
  CHECK_POINT_WITH_OFFSET!(rr, Point::new(49.70, 49.70), Point::new(0.02, 0.02));

macro_rules! CHECK_DIAGONAL_POINTS {
  ($p:expr) => {{
                        
  CHECK_POINT_WITH_OFFSET!(rr, ($p), Point::new(0.02, -0.02)); 
  CHECK_POINT_WITH_OFFSET!(rr, ($p) * Point::new(-1.0, -1.0), Point::new(-0.02, 0.02));
  }};
}

  // A few other points along the edge
  CHECK_DIAGONAL_POINTS!(Point::new(-40.0, -49.59));
  CHECK_DIAGONAL_POINTS!(Point::new(-20.0, -45.64));
  CHECK_DIAGONAL_POINTS!(Point::new(0.0, -37.01));
  CHECK_DIAGONAL_POINTS!(Point::new(20.0, -21.96));
  CHECK_DIAGONAL_POINTS!(Point::new(21.05, -20.92));
  CHECK_DIAGONAL_POINTS!(Point::new(40.0, 5.68));
}

#[test]
fn points_outside_of_sharp_corner() {
  let mut bounds = Rect::make_ltrb(196.0f32, 0.0f32, 294.0f32, 28.0f32);
  // Regression test for a case where RoundSuperellipseParam::Contains
  // previously failed. Although the bounding rect filter of
  // `RoundSuperellipse::Contains` would reject this point, this test ensures
  // the internal logic of RoundSuperellipseParam::Contains is now correct.
  let mut rr = RoundSuperellipseParam::make_bounds_radii(
      &bounds, &RoundingRadii {
                  top_left: Size::new(0.0, 0.0),
                  top_right: Size::new(3.0, 3.0),
                  bottom_left: Size::new(0.0, 0.0),
                  bottom_right: Size::new(3.0, 3.0),
                ..Default::default()
              });

  expect_false!(rr.contains(&Point::new(147.0, 14.0)));
}

#[test]
fn path_for_rectangular_rse_with_shape_corners_should_be_within_bounds() {
  let mut bounds = Rect::make_ltrb(34.0f32, 242.0f32, 766.0f32, 358.0f32);
  // Regression test for https://github.com/flutter/flutter/issues/170593.
  // The issue was caused by incorrect calculation when building paths for
  // rounded superellipses with sharp corners and unequal width and height.
  // Since the most obvious symptom of the issue is some points being
  // incorrectly placed out of bounds, this test case simply verifies that all
  // points are within the bounds.

  let mut rr = RoundSuperellipseParam::make_bounds_radii(
      &bounds, &RoundingRadii {
                  top_left: Size::new(14.0, 14.0),
                  top_right: Size::new(14.0, 14.0),
                  bottom_left: Size::new(0.0, 0.0),
                  bottom_right: Size::new(0.0, 0.0),
                ..Default::default()
              });
  let mut receiver = SpyPathReceiver::default();
  receiver.spy_line_to(
      move |p2: &Point| { expect_true!(bounds.contains_inclusive(p2)); });
  receiver.spy_cubic_to(move |cp1: &Point, cp2: &Point, p2: &Point| {
    expect_true!(bounds.contains_inclusive(p2));
  });

  rr.dispatch(&mut receiver);
}

#[test]
fn path_for_long_rse_should_be_correct() {
  let mut bounds = Rect::make_ltrb(0.0, 0.0, 300.0, 100000.0);
  // Regression test for https://github.com/flutter/flutter/issues/179875.

  let mut rr = RoundSuperellipseParam::make_bounds_radius(&bounds, 100.0);
  let mut receiver = SpyPathReceiver::default();
  receiver.spy_line_to(
      move |p2: &Point| { expect_true!(bounds.contains_inclusive(p2)); });
  receiver.spy_cubic_to(move |cp1: &Point, cp2: &Point, p2: &Point| {
    expect_true!(bounds.contains_inclusive(cp1));
    expect_true!(bounds.contains_inclusive(cp2));
    expect_true!(bounds.contains_inclusive(p2));
  });
  receiver.spy_conic_to(move |cp: &Point, p2: &Point, weight: Scalar| {
    expect_true!(bounds.contains_inclusive(cp));
    expect_true!(bounds.contains_inclusive(p2));
  });

  rr.dispatch(&mut receiver);
}


// Not upstream's: a corner with no rounding contains its top and left edges
// but not its right and bottom ones, as Rect::Contains does.
#[test]
fn rectangular_corner_excludes_right_edge() {
  let bounds = Rect::make_ltrb(0.0, 0.0, 10.0, 10.0);
  let param = RoundSuperellipseParam::make_bounds_radius(&bounds, 0.0);
  expect_false!(param.contains(&Point::new(10.0, 5.0)));
  expect_true!(param.contains(&Point::new(9.99, 5.0)));
}
