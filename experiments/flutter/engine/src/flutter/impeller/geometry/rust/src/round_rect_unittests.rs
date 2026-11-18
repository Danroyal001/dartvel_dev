// flutter/impeller/geometry/round_rect_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn empty_declaration() {
  let mut round_rect = RoundRect::default();

  expect_true!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_true!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::default());
  expect_eq!(round_rect.get_bounds().get_left(), 0.0f32);
  expect_eq!(round_rect.get_bounds().get_top(), 0.0f32);
  expect_eq!(round_rect.get_bounds().get_right(), 0.0f32);
  expect_eq!(round_rect.get_bounds().get_bottom(), 0.0f32);
  expect_eq!(round_rect.get_radii().top_left, Size::default());
  expect_eq!(round_rect.get_radii().top_right, Size::default());
  expect_eq!(round_rect.get_radii().bottom_left, Size::default());
  expect_eq!(round_rect.get_radii().bottom_right, Size::default());
  expect_eq!(round_rect.get_radii().top_left.width, 0.0f32);
  expect_eq!(round_rect.get_radii().top_left.height, 0.0f32);
  expect_eq!(round_rect.get_radii().top_right.width, 0.0f32);
  expect_eq!(round_rect.get_radii().top_right.height, 0.0f32);
  expect_eq!(round_rect.get_radii().bottom_left.width, 0.0f32);
  expect_eq!(round_rect.get_radii().bottom_left.height, 0.0f32);
  expect_eq!(round_rect.get_radii().bottom_right.width, 0.0f32);
  expect_eq!(round_rect.get_radii().bottom_right.height, 0.0f32);
}

#[test]
fn default_constructor() {
  let mut round_rect = RoundRect::default();

  expect_true!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_true!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::default());
  expect_eq!(round_rect.get_radii().top_left, Size::default());
  expect_eq!(round_rect.get_radii().top_right, Size::default());
  expect_eq!(round_rect.get_radii().bottom_left, Size::default());
  expect_eq!(round_rect.get_radii().bottom_right, Size::default());
}

#[test]
fn empty_rect_construction() {
  let mut round_rect = RoundRect::make_rect(&Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32));

  expect_true!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_true!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::default());
  expect_eq!(round_rect.get_radii().top_right, Size::default());
  expect_eq!(round_rect.get_radii().bottom_left, Size::default());
  expect_eq!(round_rect.get_radii().bottom_right, Size::default());
}

#[test]
fn rect_constructor() {
  let mut round_rect = RoundRect::make_rect(&Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));

  expect_false!(round_rect.is_empty());
  expect_true!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::default());
  expect_eq!(round_rect.get_radii().top_right, Size::default());
  expect_eq!(round_rect.get_radii().bottom_left, Size::default());
  expect_eq!(round_rect.get_radii().bottom_right, Size::default());
}

#[test]
fn inverted_rect_construction() {
  let mut round_rect = RoundRect::make_rect(&Rect::make_ltrb(20.0f32, 20.0f32, 10.0f32, 10.0f32));

  expect_false!(round_rect.is_empty());
  expect_true!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::default());
  expect_eq!(round_rect.get_radii().top_right, Size::default());
  expect_eq!(round_rect.get_radii().bottom_left, Size::default());
  expect_eq!(round_rect.get_radii().bottom_right, Size::default());
}

#[test]
fn empty_oval_construction() {
  let mut round_rect = RoundRect::make_rect_xy(
      &Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32), 10.0f32, 10.0f32);

  expect_true!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_true!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(20.0f32, 20.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::default());
  expect_eq!(round_rect.get_radii().top_right, Size::default());
  expect_eq!(round_rect.get_radii().bottom_left, Size::default());
  expect_eq!(round_rect.get_radii().bottom_right, Size::default());
}

#[test]
fn oval_constructor() {
  let mut round_rect = RoundRect::make_oval(&Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_true!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(5.0f32, 5.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(5.0f32, 5.0f32));
}

#[test]
fn inverted_oval_construction() {
  let mut round_rect = RoundRect::make_rect_xy(
      &Rect::make_ltrb(20.0f32, 20.0f32, 10.0f32, 10.0f32), 10.0f32, 10.0f32);

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_true!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(5.0f32, 5.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(5.0f32, 5.0f32));
}

#[test]
fn rect_radius_constructor() {
  let mut round_rect = RoundRect::make_rect_radius(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32), 2.0f32);

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(2.0f32, 2.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(2.0f32, 2.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(2.0f32, 2.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(2.0f32, 2.0f32));
}

#[test]
fn rect_xy_constructor() {
  let mut round_rect = RoundRect::make_rect_xy(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32), 2.0f32, 3.0f32);

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(2.0f32, 3.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(2.0f32, 3.0f32));
}

#[test]
fn rect_size_constructor() {
  let mut round_rect = RoundRect::make_rect_xy_size(
      &Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32), Size::new(2.0f32, 3.0f32));

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(2.0f32, 3.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(2.0f32, 3.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(2.0f32, 3.0f32));
}

#[test]
fn rect_radii_constructor() {
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0, 1.5),
                                   top_right: Size::new(2.0, 2.5f32),
                                   bottom_left: Size::new(3.0, 3.5f32),
                                   bottom_right: Size::new(4.0, 4.5f32),
                                 ..Default::default()
                               });

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 20.0f32, 20.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(1.0f32, 1.5f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(2.0f32, 2.5f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(3.0f32, 3.5f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(4.0f32, 4.5f32));
}

#[test]
fn rect_radii_overflow_width_constructor() {
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 6.0f32, 30.0f32),
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

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 16.0f32, 40.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(0.5f32, 1.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(1.5f32, 2.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(2.5f32, 3.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(3.5f32, 4.0f32));
}

#[test]
fn rect_radii_overflow_height_constructor() {
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 6.0f32),
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

  expect_false!(round_rect.is_empty());
  expect_false!(round_rect.is_rect());
  expect_false!(round_rect.is_oval());
  expect_true!(round_rect.is_finite());
  expect_false!(round_rect.get_bounds().is_empty());
  expect_eq!(round_rect.get_bounds(), Rect::make_ltrb(10.0f32, 10.0f32, 40.0f32, 16.0f32));
  expect_eq!(round_rect.get_radii().top_left, Size::new(0.5f32, 1.0f32));
  expect_eq!(round_rect.get_radii().top_right, Size::new(1.5f32, 2.0f32));
  expect_eq!(round_rect.get_radii().bottom_left, Size::new(2.5f32, 3.0f32));
  expect_eq!(round_rect.get_radii().bottom_right, Size::new(3.5f32, 4.0f32));
}

#[test]
fn shift() {
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut shifted = round_rect.shift(5.0, 6.0);

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

  expect_eq!(shifted,
            RoundRect::make_rect_radii(&Rect::make_xywh(15.0f32, 16.0f32, 30.0f32, 30.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand(5.0);

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

  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(5.0f32, 5.0f32, 40.0f32, 40.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand_xy(5.0, 6.0);

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

  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(5.0f32, 4.0f32, 40.0f32, 42.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand_ltrb(5.0, 6.0, 7.0, 8.0);

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

  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(5.0f32, 4.0f32, 42.0f32, 44.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand(-2.0);

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

  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(12.0f32, 12.0f32, 26.0f32, 26.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand_xy(-1.0, -2.0);

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

  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(11.0f32, 12.0f32, 28.0f32, 26.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand_ltrb(-1.0, -1.5, -2.0, -2.5);

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

  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(11.0f32, 11.5f32, 27.0f32, 26.0f32),
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
  let mut round_rect = RoundRect::make_rect_radii(&Rect::make_xywh(10.0f32, 10.0f32, 30.0f32, 30.0f32),
                               &RoundingRadii {
                                   top_left: Size::new(1.0f32, 2.0f32),
                                   top_right: Size::new(3.0f32, 4.0f32),
                                   bottom_left: Size::new(5.0f32, 6.0f32),
                                   bottom_right: Size::new(7.0f32, 8.0f32),
                                 ..Default::default()
                               });
  let mut expanded = round_rect.expand(-12.0);
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
  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(22.0f32, 22.0f32, 6.0f32, 6.0f32),
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
  expect_eq!(expanded,
            RoundRect::make_rect_radii(&Rect::make_xywh(22.0f32, 22.0f32, 6.0f32, 6.0f32),
                                     &RoundingRadii {
                                         top_left: Size::new(0.5f32, 1.0f32),
                                         top_right: Size::new(1.5f32, 2.0f32),
                                         bottom_left: Size::new(2.5f32, 3.0f32),
                                         bottom_right: Size::new(3.5f32, 4.0f32),
                                       ..Default::default()
                                     }));
}

#[test]
fn no_corner_round_rect_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  // RRect of bounds with no corners contains corners just barely
  let mut no_corners = RoundRect::make_rect_xy(&bounds, 0.0f32, 0.0f32);

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
fn tiny_corner_round_rect_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  // RRect of bounds with even the tiniest corners does not contain corners
  let mut tiny_corners = RoundRect::make_rect_xy(&bounds, 0.01f32, 0.01f32);

  expect_false!(tiny_corners.contains(&Point::new(-50.0, -50.0)));
  expect_false!(tiny_corners.contains(&Point::new(-50.0, 50.0)));
  expect_false!(tiny_corners.contains(&Point::new(50.0, -50.0)));
  expect_false!(tiny_corners.contains(&Point::new(50.0, 50.0)));
}

#[test]
fn uniform_circular_round_rect_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  let mut expanded_2_r_2 = RoundRect::make_rect_xy(&bounds.expand(2.0), 2.0f32, 2.0f32);

  // Expanded by 2.0 and then with a corner of 2.0 obviously still
  // contains the corners
  expect_true!(expanded_2_r_2.contains(&Point::new(-50.0, -50.0)));
  expect_true!(expanded_2_r_2.contains(&Point::new(-50.0, 50.0)));
  expect_true!(expanded_2_r_2.contains(&Point::new(50.0, -50.0)));
  expect_true!(expanded_2_r_2.contains(&Point::new(50.0, 50.0)));

  // Now we try to box in the corner containment to exactly where the
  // rounded corner of the expanded round rect with radii of 2.0 lies.
  // The 45-degree diagonal point of a circle of radius 2.0 lies at:
  //
  // (2 * sqrt(2) / 2, 2 * sqrt(2) / 2)
  // (sqrt(2), sqrt(2))
  //
  // So we test +/- (50 + sqrt(2) +/- epsilon)
  let mut coord_out = 50.0 + kSqrt2 + kEhCloseEnough;
  let mut coord_in = 50.0 + kSqrt2 - kEhCloseEnough;
  // Upper left corner
  expect_true!(expanded_2_r_2.contains(&Point::new(-coord_in, -coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(-coord_out, -coord_out)));
  // Upper right corner
  expect_true!(expanded_2_r_2.contains(&Point::new(coord_in, -coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(coord_out, -coord_out)));
  // Lower left corner
  expect_true!(expanded_2_r_2.contains(&Point::new(-coord_in, coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(-coord_out, coord_out)));
  // Lower right corner
  expect_true!(expanded_2_r_2.contains(&Point::new(coord_in, coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(coord_out, coord_out)));
}

#[test]
fn uniform_elliptical_round_rect_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  let mut expanded_2_r_2 = RoundRect::make_rect_xy(&bounds.expand(2.0), 2.0f32, 3.0f32);

  // Expanded by 2.0 and then with a corner of 2x3 should still
  // contain the corners
  expect_true!(expanded_2_r_2.contains(&Point::new(-50.0, -50.0)));
  expect_true!(expanded_2_r_2.contains(&Point::new(-50.0, 50.0)));
  expect_true!(expanded_2_r_2.contains(&Point::new(50.0, -50.0)));
  expect_true!(expanded_2_r_2.contains(&Point::new(50.0, 50.0)));

  // Now we try to box in the corner containment to exactly where the
  // rounded corner of the expanded round rect with radii of 2x3 lies.
  // The "45-degree diagonal point" of an ellipse of radii 2x3 lies at:
  //
  // (2 * sqrt(2) / 2, 3 * sqrt(2) / 2)
  // (sqrt(2), 3 * sqrt(2) / 2)
  //
  // And the center(s) of these corners are at:
  // (+/-(50 + 2 - 2), +/-(50 + 2 - 3))
  // = (+/-50, +/-49)
  let mut x_coord_out = 50.0 + kSqrt2 + kEhCloseEnough;
  let mut x_coord_in = 50.0 + kSqrt2 - kEhCloseEnough;
  let mut y_coord_out = 49.0 + 3.0 * kSqrt2 / 2.0 + kEhCloseEnough;
  let mut y_coord_in = 49.0 + 3.0 * kSqrt2 / 2.0 - kEhCloseEnough;
  // Upper left corner
  expect_true!(expanded_2_r_2.contains(&Point::new(-x_coord_in, -y_coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(-x_coord_out, -y_coord_out)));
  // Upper right corner
  expect_true!(expanded_2_r_2.contains(&Point::new(x_coord_in, -y_coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(x_coord_out, -y_coord_out)));
  // Lower left corner
  expect_true!(expanded_2_r_2.contains(&Point::new(-x_coord_in, y_coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(-x_coord_out, y_coord_out)));
  // Lower right corner
  expect_true!(expanded_2_r_2.contains(&Point::new(x_coord_in, y_coord_in)));
  expect_false!(expanded_2_r_2.contains(&Point::new(x_coord_out, y_coord_out)));
}

#[test]
fn differing_corners_round_rect_contains() {
  let mut bounds = Rect::make_ltrb(-50.0f32, -50.0f32, 50.0f32, 50.0f32);
  let mut round_rect = RoundRect::make_rect_radii(&bounds, &RoundingRadii {
                                           top_left: Size::new(2.0, 3.0),
                                           top_right: Size::new(4.0, 5.0),
                                           bottom_left: Size::new(6.0, 7.0),
                                           bottom_right: Size::new(8.0, 9.0),
                                         ..Default::default()
                                       });

  // For a corner with radii {A, B}, the "45 degree point" on the
  // corner curve will be at an offset of:
  //
  // (A * sqrt(2) / 2, B * sqrt(2) / 2)
  //
  // And the center(s) of these corners are at:
  //
  // (+/-(50 - A), +/-(50 - B))
  let mut coord = |radius: Scalar| {
    return 50.0 - radius + radius * kSqrt2 / 2.0f32 - kEhCloseEnough;
  };
  let mut coord_in = |radius: Scalar| {
    return coord(radius) - kEhCloseEnough;
  };
  let mut coord_out = |radius: Scalar| {
    // For some reason 1 kEhCloseEnough is not enough to put us outside
    // in some of the cases, so we use 2x the epsilon.
    return coord(radius) + 2.0 * kEhCloseEnough;
  };
  // Upper left corner (radii = Point::new(2.0, 3.0))
  expect_true!(round_rect.contains(&Point::new(-coord_in(2.0), -coord_in(3.0))));
  expect_false!(round_rect.contains(&Point::new(-coord_out(2.0), -coord_out(3.0))));
  // Upper right corner (radii = Point::new(4.0, 5.0))
  expect_true!(round_rect.contains(&Point::new(coord_in(4.0), -coord_in(5.0))));
  expect_false!(round_rect.contains(&Point::new(coord_out(4.0), -coord_out(5.0))));
  // Lower left corner (radii = Point::new(6.0, 7.0))
  expect_true!(round_rect.contains(&Point::new(-coord_in(6.0), coord_in(7.0))));
  expect_false!(round_rect.contains(&Point::new(-coord_out(6.0), coord_out(7.0))));
  // Lower right corner (radii = Point::new(8.0, 9.0))
  expect_true!(round_rect.contains(&Point::new(coord_in(8.0), coord_in(9.0))));
  expect_false!(round_rect.contains(&Point::new(coord_out(8.0), coord_out(9.0))));
}

