// flutter/impeller/geometry/rect_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn rect_empty_declaration() {
  let mut rect = Rect::default();

  expect_eq!(rect.get_left(), 0.0f32);
  expect_eq!(rect.get_top(), 0.0f32);
  expect_eq!(rect.get_right(), 0.0f32);
  expect_eq!(rect.get_bottom(), 0.0f32);
  expect_eq!(rect.get_x(), 0.0f32);
  expect_eq!(rect.get_y(), 0.0f32);
  expect_eq!(rect.get_width(), 0.0f32);
  expect_eq!(rect.get_height(), 0.0f32);
  expect_true!(rect.is_empty());
  expect_true!(rect.is_finite());
}

#[test]
fn i_rect_empty_declaration() {
  let mut rect = IRect::default();

  expect_eq!(rect.get_left(), 0);
  expect_eq!(rect.get_top(), 0);
  expect_eq!(rect.get_right(), 0);
  expect_eq!(rect.get_bottom(), 0);
  expect_eq!(rect.get_x(), 0);
  expect_eq!(rect.get_y(), 0);
  expect_eq!(rect.get_width(), 0);
  expect_eq!(rect.get_height(), 0);
  expect_true!(rect.is_empty());
  // expect_true!(rect.is_finite());  // should fail to compile
}

#[test]
fn rect_default_constructor() {
  let mut rect = Rect::default();

  expect_eq!(rect.get_left(), 0.0f32);
  expect_eq!(rect.get_top(), 0.0f32);
  expect_eq!(rect.get_right(), 0.0f32);
  expect_eq!(rect.get_bottom(), 0.0f32);
  expect_eq!(rect.get_x(), 0.0f32);
  expect_eq!(rect.get_y(), 0.0f32);
  expect_eq!(rect.get_width(), 0.0f32);
  expect_eq!(rect.get_height(), 0.0f32);
  expect_true!(rect.is_empty());
  expect_true!(rect.is_finite());
}

#[test]
fn i_rect_default_constructor() {
  let mut rect = IRect::default();

  expect_eq!(rect.get_left(), 0);
  expect_eq!(rect.get_top(), 0);
  expect_eq!(rect.get_right(), 0);
  expect_eq!(rect.get_bottom(), 0);
  expect_eq!(rect.get_x(), 0);
  expect_eq!(rect.get_y(), 0);
  expect_eq!(rect.get_width(), 0);
  expect_eq!(rect.get_height(), 0);
  expect_true!(rect.is_empty());
}

#[test]
fn rect_simple_ltrb() {
  // Using fractional-power-of-2 friendly values for equality tests
  let mut rect = Rect::make_ltrb(5.125f32, 10.25f32, 20.625f32, 25.375f32);

  expect_eq!(rect.get_left(), 5.125f32);
  expect_eq!(rect.get_top(), 10.25f32);
  expect_eq!(rect.get_right(), 20.625f32);
  expect_eq!(rect.get_bottom(), 25.375f32);
  expect_eq!(rect.get_x(), 5.125f32);
  expect_eq!(rect.get_y(), 10.25f32);
  expect_eq!(rect.get_width(), 15.5f32);
  expect_eq!(rect.get_height(), 15.125f32);
  expect_false!(rect.is_empty());
  expect_true!(rect.is_finite());
}

#[test]
fn i_rect_simple_ltrb() {
  let mut rect = IRect::make_ltrb(5, 10, 20, 25);

  expect_eq!(rect.get_left(), 5);
  expect_eq!(rect.get_top(), 10);
  expect_eq!(rect.get_right(), 20);
  expect_eq!(rect.get_bottom(), 25);
  expect_eq!(rect.get_x(), 5);
  expect_eq!(rect.get_y(), 10);
  expect_eq!(rect.get_width(), 15);
  expect_eq!(rect.get_height(), 15);
  expect_false!(rect.is_empty());
}

#[test]
fn rect_simple_xywh() {
  // Using fractional-power-of-2 friendly values for equality tests
  let mut rect = Rect::make_xywh(5.125f32, 10.25f32, 15.5f32, 15.125f32);

  expect_eq!(rect.get_left(), 5.125f32);
  expect_eq!(rect.get_top(), 10.25f32);
  expect_eq!(rect.get_right(), 20.625f32);
  expect_eq!(rect.get_bottom(), 25.375f32);
  expect_eq!(rect.get_x(), 5.125f32);
  expect_eq!(rect.get_y(), 10.25f32);
  expect_eq!(rect.get_width(), 15.5f32);
  expect_eq!(rect.get_height(), 15.125f32);
  expect_false!(rect.is_empty());
  expect_true!(rect.is_finite());
}

#[test]
fn i_rect_simple_xywh() {
  let mut rect = IRect::make_xywh(5, 10, 15, 16);

  expect_eq!(rect.get_left(), 5);
  expect_eq!(rect.get_top(), 10);
  expect_eq!(rect.get_right(), 20);
  expect_eq!(rect.get_bottom(), 26);
  expect_eq!(rect.get_x(), 5);
  expect_eq!(rect.get_y(), 10);
  expect_eq!(rect.get_width(), 15);
  expect_eq!(rect.get_height(), 16);
  expect_false!(rect.is_empty());
}

#[test]
fn rect_simple_wh() {
  // Using fractional-power-of-2 friendly values for equality tests
  let mut rect = Rect::make_wh(15.5f32, 15.125f32);

  expect_eq!(rect.get_left(), 0.0f32);
  expect_eq!(rect.get_top(), 0.0f32);
  expect_eq!(rect.get_right(), 15.5f32);
  expect_eq!(rect.get_bottom(), 15.125f32);
  expect_eq!(rect.get_x(), 0.0f32);
  expect_eq!(rect.get_y(), 0.0f32);
  expect_eq!(rect.get_width(), 15.5f32);
  expect_eq!(rect.get_height(), 15.125f32);
  expect_false!(rect.is_empty());
  expect_true!(rect.is_finite());
}

#[test]
fn i_rect_simple_wh() {
  // Using fractional-power-of-2 friendly values for equality tests
  let mut rect = IRect::make_wh(15, 25);

  expect_eq!(rect.get_left(), 0);
  expect_eq!(rect.get_top(), 0);
  expect_eq!(rect.get_right(), 15);
  expect_eq!(rect.get_bottom(), 25);
  expect_eq!(rect.get_x(), 0);
  expect_eq!(rect.get_y(), 0);
  expect_eq!(rect.get_width(), 15);
  expect_eq!(rect.get_height(), 25);
  expect_false!(rect.is_empty());
}

#[test]
fn rect_from_i_rect() {
  let mut irect = IRect::make_ltrb(10, 20, 30, 40);
  let mut rect = Rect::make(&irect);

  expect_eq!(rect.get_left(), 10);
  expect_eq!(rect.get_top(), 20);
  expect_eq!(rect.get_right(), 30);
  expect_eq!(rect.get_bottom(), 40);

  // The following do not compile
  // IRect irect2 = IRect::make(rect);
  // IRect irect2 = IRect::make(irect);
}

#[test]
fn rect_make_circle_bounds() {
  let mut rect = Rect::make_circle_bounds(&Point::new(100.0f32, 200.0f32), 20.0f32);

  expect_false!(rect.is_empty());
  expect_eq!(rect.get_left(), 80.0f32);
  expect_eq!(rect.get_right(), 120.0f32);
  expect_eq!(rect.get_top(), 180.0f32);
  expect_eq!(rect.get_bottom(), 220.0f32);
}

#[test]
fn rect_make_circle_bounds_negative_radius() {
  let mut rect = Rect::make_circle_bounds(&Point::new(100.0f32, 200.0f32), -20.0f32);

  expect_true!(rect.is_empty());
  expect_eq!(rect.get_left(), 120.0f32);
  expect_eq!(rect.get_right(), 80.0f32);
  expect_eq!(rect.get_top(), 220.0f32);
  expect_eq!(rect.get_bottom(), 180.0f32);
}

#[test]
fn i_rect_make_circle_bounds() {
  let mut rect = IRect::make_circle_bounds(&IPoint::new(100, 200), 20);

  expect_false!(rect.is_empty());
  expect_eq!(rect.get_left(), 80);
  expect_eq!(rect.get_right(), 120);
  expect_eq!(rect.get_top(), 180);
  expect_eq!(rect.get_bottom(), 220);
}

#[test]
fn i_rect_make_circle_bounds_negative_radius() {
  let mut rect = IRect::make_circle_bounds(&IPoint::new(100, 200), -20);

  expect_true!(rect.is_empty());
  expect_eq!(rect.get_left(), 120);
  expect_eq!(rect.get_right(), 80);
  expect_eq!(rect.get_top(), 220);
  expect_eq!(rect.get_bottom(), 180);
}

#[test]
fn rect_make_ellipse_bounds_size() {
  let mut rect = Rect::make_ellipse_bounds(&Point::new(100.0f32, 200.0f32), &Size::new(20.0f32, 30.0f32));

  expect_false!(rect.is_empty());
  expect_eq!(rect.get_left(), 80.0f32);
  expect_eq!(rect.get_right(), 120.0f32);
  expect_eq!(rect.get_top(), 170.0f32);
  expect_eq!(rect.get_bottom(), 230.0f32);
}

#[test]
fn rect_make_ellipse_bounds_negative_size() {
  let mut rect = Rect::make_ellipse_bounds(&Point::new(100.0f32, 200.0f32), &Size::new(-20.0f32, -30.0f32));

  expect_true!(rect.is_empty());
  expect_eq!(rect.get_left(), 120.0f32);
  expect_eq!(rect.get_right(), 80.0f32);
  expect_eq!(rect.get_top(), 230.0f32);
  expect_eq!(rect.get_bottom(), 170.0f32);
}

#[test]
fn rect_make_ellipse_bounds_point() {
  let mut rect = Rect::make_ellipse_bounds_point(&Point::new(100.0f32, 200.0f32), &Point::new(20.0f32, 30.0f32));

  expect_false!(rect.is_empty());
  expect_eq!(rect.get_left(), 80.0f32);
  expect_eq!(rect.get_right(), 120.0f32);
  expect_eq!(rect.get_top(), 170.0f32);
  expect_eq!(rect.get_bottom(), 230.0f32);
}

#[test]
fn rect_make_ellipse_bounds_negative_point() {
  let mut rect = Rect::make_ellipse_bounds_point(&Point::new(100.0f32, 200.0f32), &Point::new(-20.0f32, -30.0f32));

  expect_true!(rect.is_empty());
  expect_eq!(rect.get_left(), 120.0f32);
  expect_eq!(rect.get_right(), 80.0f32);
  expect_eq!(rect.get_top(), 230.0f32);
  expect_eq!(rect.get_bottom(), 170.0f32);
}

#[test]
fn i_rect_make_ellipse_bounds_size() {
  let mut rect = IRect::make_ellipse_bounds(&IPoint::new(100, 200), &ISize::new(20, 30));

  expect_false!(rect.is_empty());
  expect_eq!(rect.get_left(), 80);
  expect_eq!(rect.get_right(), 120);
  expect_eq!(rect.get_top(), 170);
  expect_eq!(rect.get_bottom(), 230);
}

#[test]
fn i_rect_make_ellipse_bounds_negative_size() {
  let mut rect = IRect::make_ellipse_bounds(&IPoint::new(100, 200), &ISize::new(-20, -30));

  expect_true!(rect.is_empty());
  expect_eq!(rect.get_left(), 120);
  expect_eq!(rect.get_right(), 80);
  expect_eq!(rect.get_top(), 230);
  expect_eq!(rect.get_bottom(), 170);
}

#[test]
fn i_rect_make_ellipse_bounds_point() {
  let mut rect = IRect::make_ellipse_bounds_point(&IPoint::new(100, 200), &IPoint::new(20, 30));

  expect_false!(rect.is_empty());
  expect_eq!(rect.get_left(), 80);
  expect_eq!(rect.get_right(), 120);
  expect_eq!(rect.get_top(), 170);
  expect_eq!(rect.get_bottom(), 230);
}

#[test]
fn i_rect_make_ellipse_bounds_negative_point() {
  let mut rect = IRect::make_ellipse_bounds_point(&IPoint::new(100, 200), &IPoint::new(-20, -30));

  expect_true!(rect.is_empty());
  expect_eq!(rect.get_left(), 120);
  expect_eq!(rect.get_right(), 80);
  expect_eq!(rect.get_top(), 230);
  expect_eq!(rect.get_bottom(), 170);
}

#[test]
fn rect_overflow_xywh() {
  let mut min = f32::MIN;
  let mut max = f32::MAX;
  let mut inf = f32::INFINITY;

  // 8 cases:
  //   finite X, max W
  //   max X, max W
  //   finite Y, max H
  //   max Y, max H
  //   finite X, min W
  //   min X, min W
  //   finite Y, min H
  //   min Y, min H

  // a small finite value added to a max value will remain max
  // a very large finite value (like max) added to max will go to infinity

  {
    let mut rect = Rect::make_xywh(5.0, 10.0f32, max, 15.0f32);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), max);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), max);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_false!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(max, 10.0f32, max, 15.0f32);

    expect_eq!(rect.get_left(), max);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), inf);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), max);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), inf);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_false!(rect.is_empty());
    expect_false!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(5.0f32, 10.0f32, 20.0f32, max);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), 25.0f32);
    expect_eq!(rect.get_bottom(), max);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), 20.0f32);
    expect_eq!(rect.get_height(), max);
    expect_false!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(5.0f32, max, 20.0f32, max);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), max);
    expect_eq!(rect.get_right(), 25.0f32);
    expect_eq!(rect.get_bottom(), inf);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), max);
    expect_eq!(rect.get_width(), 20.0f32);
    expect_eq!(rect.get_height(), inf);
    expect_false!(rect.is_empty());
    expect_false!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(5.0, 10.0f32, min, 15.0f32);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), min);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), min);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_true!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(min, 10.0f32, min, 15.0f32);

    expect_eq!(rect.get_left(), min);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), -inf);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), min);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), -inf);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_true!(rect.is_empty());
    expect_false!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(5.0f32, 10.0f32, 20.0f32, min);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), 25.0f32);
    expect_eq!(rect.get_bottom(), min);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), 20.0f32);
    expect_eq!(rect.get_height(), min);
    expect_true!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_xywh(5.0f32, min, 20.0f32, min);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), min);
    expect_eq!(rect.get_right(), 25.0f32);
    expect_eq!(rect.get_bottom(), -inf);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), min);
    expect_eq!(rect.get_width(), 20.0f32);
    expect_eq!(rect.get_height(), -inf);
    expect_true!(rect.is_empty());
    expect_false!(rect.is_finite());
  }
}

#[test]
fn i_rect_overflow_xywh() {
  let mut min = i64::MIN;
  let mut max = i64::MAX;

  // 4 cases
  //   x near max, positive w takes it past max
  //   x near min, negative w takes it below min
  //   y near max, positive h takes it past max
  //   y near min, negative h takes it below min

  {
    let mut rect = IRect::make_xywh(max - 5, 10, 10, 16);

    expect_eq!(rect.get_left(), max - 5);
    expect_eq!(rect.get_top(), 10);
    expect_eq!(rect.get_right(), max);
    expect_eq!(rect.get_bottom(), 26);
    expect_eq!(rect.get_x(), max - 5);
    expect_eq!(rect.get_y(), 10);
    expect_eq!(rect.get_width(), 5);
    expect_eq!(rect.get_height(), 16);
    expect_false!(rect.is_empty());
  }

  {
    let mut rect = IRect::make_xywh(min + 5, 10, -10, 16);

    expect_eq!(rect.get_left(), min + 5);
    expect_eq!(rect.get_top(), 10);
    expect_eq!(rect.get_right(), min);
    expect_eq!(rect.get_bottom(), 26);
    expect_eq!(rect.get_x(), min + 5);
    expect_eq!(rect.get_y(), 10);
    expect_eq!(rect.get_width(), -5);
    expect_eq!(rect.get_height(), 16);
    expect_true!(rect.is_empty());
  }

  {
    let mut rect = IRect::make_xywh(5, max - 10, 10, 16);

    expect_eq!(rect.get_left(), 5);
    expect_eq!(rect.get_top(), max - 10);
    expect_eq!(rect.get_right(), 15);
    expect_eq!(rect.get_bottom(), max);
    expect_eq!(rect.get_x(), 5);
    expect_eq!(rect.get_y(), max - 10);
    expect_eq!(rect.get_width(), 10);
    expect_eq!(rect.get_height(), 10);
    expect_false!(rect.is_empty());
  }

  {
    let mut rect = IRect::make_xywh(5, min + 10, 10, -16);

    expect_eq!(rect.get_left(), 5);
    expect_eq!(rect.get_top(), min + 10);
    expect_eq!(rect.get_right(), 15);
    expect_eq!(rect.get_bottom(), min);
    expect_eq!(rect.get_x(), 5);
    expect_eq!(rect.get_y(), min + 10);
    expect_eq!(rect.get_width(), 10);
    expect_eq!(rect.get_height(), -10);
    expect_true!(rect.is_empty());
  }
}

#[test]
fn rect_overflow_ltrb() {
  let mut min = f32::MIN;
  let mut max = f32::MAX;
  let mut inf = f32::INFINITY;

  // 8 cases:
  //   finite negative X, max W
  //   ~min X, ~max W
  //   finite negative Y, max H
  //   ~min Y, ~max H
  //   finite positive X, min W
  //   ~min X, ~min W
  //   finite positive Y, min H
  //   ~min Y, ~min H

  // a small finite value subtracted from a max value will remain max
  // a very large finite value (like min) subtracted from max will go to inf

  {
    let mut rect = Rect::make_ltrb(-5.0f32, 10.0f32, max, 25.0f32);

    expect_eq!(rect.get_left(), -5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), max);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), -5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), max);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_false!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(min + 5.0f32, 10.0f32, max - 5.0f32, 25.0f32);

    expect_eq!(rect.get_left(), min + 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), max - 5.0f32);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), min + 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), inf);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_false!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(5.0f32, -10.0f32, 20.0f32, max);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), -10.0f32);
    expect_eq!(rect.get_right(), 20.0f32);
    expect_eq!(rect.get_bottom(), max);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), -10.0f32);
    expect_eq!(rect.get_width(), 15.0f32);
    expect_eq!(rect.get_height(), max);
    expect_false!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(5.0f32, min + 10.0f32, 20.0f32, max - 15.0f32);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), min + 10.0f32);
    expect_eq!(rect.get_right(), 20.0f32);
    expect_eq!(rect.get_bottom(), max - 15.0f32);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), min + 10.0f32);
    expect_eq!(rect.get_width(), 15.0f32);
    expect_eq!(rect.get_height(), inf);
    expect_false!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(5.0f32, 10.0f32, min, 25.0f32);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), min);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), min);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_true!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(max - 5.0f32, 10.0f32, min + 10.0f32, 25.0f32);

    expect_eq!(rect.get_left(), max - 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), min + 10.0f32);
    expect_eq!(rect.get_bottom(), 25.0f32);
    expect_eq!(rect.get_x(), max - 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), -inf);
    expect_eq!(rect.get_height(), 15.0f32);
    expect_true!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(5.0f32, 10.0f32, 20.0f32, min);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), 10.0f32);
    expect_eq!(rect.get_right(), 20.0f32);
    expect_eq!(rect.get_bottom(), min);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), 10.0f32);
    expect_eq!(rect.get_width(), 15.0f32);
    expect_eq!(rect.get_height(), min);
    expect_true!(rect.is_empty());
    expect_true!(rect.is_finite());
  }

  {
    let mut rect = Rect::make_ltrb(5.0f32, max - 5.0f32, 20.0f32, min + 10.0f32);

    expect_eq!(rect.get_left(), 5.0f32);
    expect_eq!(rect.get_top(), max - 5.0f32);
    expect_eq!(rect.get_right(), 20.0f32);
    expect_eq!(rect.get_bottom(), min + 10.0f32);
    expect_eq!(rect.get_x(), 5.0f32);
    expect_eq!(rect.get_y(), max - 5.0f32);
    expect_eq!(rect.get_width(), 15.0f32);
    expect_eq!(rect.get_height(), -inf);
    expect_true!(rect.is_empty());
    expect_true!(rect.is_finite());
  }
}

#[test]
fn i_rect_overflow_ltrb() {
  let mut min = i64::MIN;
  let mut max = i64::MAX;

  // 4 cases
  //   negative l, r near max takes width past max
  //   positive l, r near min takes width below min
  //   negative t, b near max takes width past max
  //   positive t, b near min takes width below min

  {
    let mut rect = IRect::make_ltrb(-10, 10, max - 5, 26);

    expect_eq!(rect.get_left(), -10);
    expect_eq!(rect.get_top(), 10);
    expect_eq!(rect.get_right(), max - 5);
    expect_eq!(rect.get_bottom(), 26);
    expect_eq!(rect.get_x(), -10);
    expect_eq!(rect.get_y(), 10);
    expect_eq!(rect.get_width(), max);
    expect_eq!(rect.get_height(), 16);
    expect_false!(rect.is_empty());
  }

  {
    let mut rect = IRect::make_ltrb(10, 10, min + 5, 26);

    expect_eq!(rect.get_left(), 10);
    expect_eq!(rect.get_top(), 10);
    expect_eq!(rect.get_right(), min + 5);
    expect_eq!(rect.get_bottom(), 26);
    expect_eq!(rect.get_x(), 10);
    expect_eq!(rect.get_y(), 10);
    expect_eq!(rect.get_width(), min);
    expect_eq!(rect.get_height(), 16);
    expect_true!(rect.is_empty());
  }

  {
    let mut rect = IRect::make_ltrb(5, -10, 15, max - 5);

    expect_eq!(rect.get_left(), 5);
    expect_eq!(rect.get_top(), -10);
    expect_eq!(rect.get_right(), 15);
    expect_eq!(rect.get_bottom(), max - 5);
    expect_eq!(rect.get_x(), 5);
    expect_eq!(rect.get_y(), -10);
    expect_eq!(rect.get_width(), 10);
    expect_eq!(rect.get_height(), max);
    expect_false!(rect.is_empty());
  }

  {
    let mut rect = IRect::make_ltrb(5, 10, 15, min + 5);

    expect_eq!(rect.get_left(), 5);
    expect_eq!(rect.get_top(), 10);
    expect_eq!(rect.get_right(), 15);
    expect_eq!(rect.get_bottom(), min + 5);
    expect_eq!(rect.get_x(), 5);
    expect_eq!(rect.get_y(), 10);
    expect_eq!(rect.get_width(), 10);
    expect_eq!(rect.get_height(), min);
    expect_true!(rect.is_empty());
  }
}

#[test]
fn rect_make_size() {
  {
    let mut s = Size::new(100.0, 200.0);
    let mut r = Rect::make_size(&s);
    let mut expected = Rect::make_ltrb(0.0, 0.0, 100.0, 200.0);
    expect_rect_near!(r, expected);
  }

  {
    let mut s = ISize::new(100, 200);
    let mut r = Rect::make_size(&s);
    let mut expected = Rect::make_ltrb(0.0, 0.0, 100.0, 200.0);
    expect_rect_near!(r, expected);
  }

  {
    let mut s = Size::new(100.0, 200.0);
    let mut r = IRect::make_size(&s);
    let mut expected = IRect::make_ltrb(0, 0, 100, 200);
    expect_eq!(r, expected);
  }

  {
    let mut s = ISize::new(100, 200);
    let mut r = IRect::make_size(&s);
    let mut expected = IRect::make_ltrb(0, 0, 100, 200);
    expect_eq!(r, expected);
  }
}

#[test]
fn rect_make_maximum() {
  let mut rect = Rect::make_maximum();
  let mut inf = f32::INFINITY;
  let mut min = f32::MIN;
  let mut max = f32::MAX;

  expect_eq!(rect.get_left(), min);
  expect_eq!(rect.get_top(), min);
  expect_eq!(rect.get_right(), max);
  expect_eq!(rect.get_bottom(), max);
  expect_eq!(rect.get_x(), min);
  expect_eq!(rect.get_y(), min);
  expect_eq!(rect.get_width(), inf);
  expect_eq!(rect.get_height(), inf);
  expect_false!(rect.is_empty());
  expect_true!(rect.is_finite());
}

#[test]
fn i_rect_make_maximum() {
  let mut rect = IRect::make_maximum();
  let mut min = i64::MIN;
  let mut max = i64::MAX;

  expect_eq!(rect.get_left(), min);
  expect_eq!(rect.get_top(), min);
  expect_eq!(rect.get_right(), max);
  expect_eq!(rect.get_bottom(), max);
  expect_eq!(rect.get_x(), min);
  expect_eq!(rect.get_y(), min);
  expect_eq!(rect.get_width(), max);
  expect_eq!(rect.get_height(), max);
  expect_false!(rect.is_empty());
}

#[test]
fn rect_from_rect() {
  expect_eq!(Rect::make_xywh(2.0, 3.0, 7.0, 15.0),
            Rect::make_xywh(2.0, 3.0, 7.0, 15.0));
  expect_eq!(Rect::make_ltrb(2.0, 3.0, 7.0, 15.0),
            Rect::make_ltrb(2.0, 3.0, 7.0, 15.0));
}

#[test]
fn i_rect_from_i_rect() {
  expect_eq!(IRect::make_xywh(2, 3, 7, 15),  //
            IRect::make_xywh(2, 3, 7, 15));
  expect_eq!(IRect::make_ltrb(2, 3, 7, 15),  //
            IRect::make_ltrb(2, 3, 7, 15));
}

#[test]
fn rect_copy() {
  // Using fractional-power-of-2 friendly values for equality tests
  let mut rect = Rect::make_ltrb(5.125f32, 10.25f32, 20.625f32, 25.375f32);
  let mut copy = rect;

  expect_eq!(rect, copy);
  expect_eq!(copy.get_left(), 5.125f32);
  expect_eq!(copy.get_top(), 10.25f32);
  expect_eq!(copy.get_right(), 20.625f32);
  expect_eq!(copy.get_bottom(), 25.375f32);
  expect_eq!(copy.get_x(), 5.125f32);
  expect_eq!(copy.get_y(), 10.25f32);
  expect_eq!(copy.get_width(), 15.5f32);
  expect_eq!(copy.get_height(), 15.125f32);
  expect_false!(copy.is_empty());
  expect_true!(copy.is_finite());
}

#[test]
fn i_rect_copy() {
  let mut rect = IRect::make_ltrb(5, 10, 20, 25);
  let mut copy = rect;

  expect_eq!(rect, copy);
  expect_eq!(copy.get_left(), 5);
  expect_eq!(copy.get_top(), 10);
  expect_eq!(copy.get_right(), 20);
  expect_eq!(copy.get_bottom(), 25);
  expect_eq!(copy.get_x(), 5);
  expect_eq!(copy.get_y(), 10);
  expect_eq!(copy.get_width(), 15);
  expect_eq!(copy.get_height(), 15);
  expect_false!(copy.is_empty());
}

#[test]
fn rect_origin_size_xywh_getters() {
  {
    let mut r = Rect::make_origin_size(&Point::new(10.0, 20.0), &Size::new(50.0, 40.0));
    expect_eq!(r.get_origin(), Point::new(10.0, 20.0));
    expect_eq!(r.get_size(), Size::new(50.0, 40.0));
    expect_eq!(r.get_x(), 10);
    expect_eq!(r.get_y(), 20);
    expect_eq!(r.get_width(), 50);
    expect_eq!(r.get_height(), 40);
    let mut expected_array = [10.0, 20.0, 50.0, 40.0];
    expect_eq!(r.get_xywh(), expected_array);
  }

  {
    let mut r = Rect::make_ltrb(10.0, 20.0, 50.0, 40.0);
    expect_eq!(r.get_origin(), Point::new(10.0, 20.0));
    expect_eq!(r.get_size(), Size::new(40.0, 20.0));
    expect_eq!(r.get_x(), 10);
    expect_eq!(r.get_y(), 20);
    expect_eq!(r.get_width(), 40);
    expect_eq!(r.get_height(), 20);
    let mut expected_array = [10.0, 20.0, 40.0, 20.0];
    expect_eq!(r.get_xywh(), expected_array);
  }
}

#[test]
fn i_rect_origin_size_xywh_getters() {
  {
    let mut r = IRect::make_origin_size(&IPoint::new(10, 20), &ISize::new(50, 40));
    expect_eq!(r.get_origin(), IPoint::new(10, 20));
    expect_eq!(r.get_size(), ISize::new(50, 40));
    expect_eq!(r.get_x(), 10);
    expect_eq!(r.get_y(), 20);
    expect_eq!(r.get_width(), 50);
    expect_eq!(r.get_height(), 40);
    let mut expected_array = [10, 20, 50, 40];
    expect_eq!(r.get_xywh(), expected_array);
  }

  {
    let mut r = IRect::make_ltrb(10, 20, 50, 40);
    expect_eq!(r.get_origin(), IPoint::new(10, 20));
    expect_eq!(r.get_size(), ISize::new(40, 20));
    expect_eq!(r.get_x(), 10);
    expect_eq!(r.get_y(), 20);
    expect_eq!(r.get_width(), 40);
    expect_eq!(r.get_height(), 20);
    let mut expected_array = [10, 20, 40, 20];
    expect_eq!(r.get_xywh(), expected_array);
  }
}

#[test]
fn rect_round_out_empty() {
  let mut rect = Rect::default();

  expect_eq!(Rect::round_out(&rect), Rect::default());

  expect_eq!(IRect::round_out(&rect), IRect::default());
}

#[test]
fn rect_round_out_simple() {
  let mut rect = Rect::make_ltrb(5.125f32, 10.75f32, 20.625f32, 25.375f32);

  expect_eq!(Rect::round_out(&rect), Rect::make_ltrb(5.0f32, 10.0f32, 21.0f32, 26.0f32));

  expect_eq!(IRect::round_out(&rect), IRect::make_ltrb(5, 10, 21, 26));
}

#[test]
fn rect_round_out_to_i_rect_huge() {
  let mut test = |corners: i32| {
    expect_true!(corners >= 0 && corners <= 0xf);
    let mut l: Scalar;
    let mut t: Scalar;
    let mut r: Scalar;
    let mut b: Scalar;
    let mut il: i64;
    let mut it: i64;
    let mut ir: i64;
    let mut ib: i64;
    il = 50 as _;
    l = il as Scalar;
    it = 50 as _;
    t = it as Scalar;
    ir = 80 as _;
    r = ir as Scalar;
    ib = 80 as _;
    b = ib as Scalar;
    if ((corners & (1 << 0)) != 0) {
      l = -1e20;
      il = i64::MIN;
    }
    if ((corners & (1 << 1)) != 0) {
      t = -1e20;
      it = i64::MIN;
    }
    if ((corners & (1 << 2)) != 0) {
      r = 1e20;
      ir = i64::MAX;
    }
    if ((corners & (1 << 3)) != 0) {
      b = 1e20;
      ib = i64::MAX;
    }

    let mut rect = Rect::make_ltrb(l, t, r, b);
    let mut irect = IRect::round_out(&rect);
    expect_eq!(irect.get_left(), il);
    expect_eq!(irect.get_top(), it);
    expect_eq!(irect.get_right(), ir);
    expect_eq!(irect.get_bottom(), ib);
  };

  for corners in 0..= 15 {
    test(corners);
  }
}

#[test]
fn rect_does_not_intersect_empty() {
  let mut rect = Rect::make_ltrb(50.0, 50.0, 100.0, 100.0);

  let mut test = |l: Scalar, t: Scalar, r: Scalar, b: Scalar, label: &str| {
    expect_false!(rect.intersects_with_rect(&Rect::make_ltrb(l, b, r, t)));
    expect_false!(rect.intersects_with_rect(&Rect::make_ltrb(r, b, l, t)));
    expect_false!(rect.intersects_with_rect(&Rect::make_ltrb(r, t, l, b)));
  };

  test(20.0, 20.0, 30.0, 30.0, "Above and Left");
  test(70.0, 20.0, 80.0, 30.0, "Above");
  test(120.0, 20.0, 130.0, 30.0, "Above and Right");
  test(120.0, 70.0, 130.0, 80.0, "Right");
  test(120.0, 120.0, 130.0, 130.0, "Below and Right");
  test(70.0, 120.0, 80.0, 130.0, "Below");
  test(20.0, 120.0, 30.0, 130.0, "Below and Left");
  test(20.0, 70.0, 30.0, 80.0, "Left");

  test(70.0, 70.0, 80.0, 80.0, "Inside");

  test(40.0, 70.0, 60.0, 80.0, "Straddling Left");
  test(70.0, 40.0, 80.0, 60.0, "Straddling Top");
  test(90.0, 70.0, 110.0, 80.0, "Straddling Right");
  test(70.0, 90.0, 80.0, 110.0, "Straddling Bottom");
}

#[test]
fn i_rect_does_not_intersect_empty() {
  let mut rect = IRect::make_ltrb(50, 50, 100, 100);

  let mut test = |l: i64, t: i64, r: i64, b: i64, label: &str| {
    expect_false!(rect.intersects_with_rect(&IRect::make_ltrb(l, b, r, t)));
    expect_false!(rect.intersects_with_rect(&IRect::make_ltrb(r, b, l, t)));
    expect_false!(rect.intersects_with_rect(&IRect::make_ltrb(r, t, l, b)));
  };

  test(20, 20, 30, 30, "Above and Left");
  test(70, 20, 80, 30, "Above");
  test(120, 20, 130, 30, "Above and Right");
  test(120, 70, 130, 80, "Right");
  test(120, 120, 130, 130, "Below and Right");
  test(70, 120, 80, 130, "Below");
  test(20, 120, 30, 130, "Below and Left");
  test(20, 70, 30, 80, "Left");

  test(70, 70, 80, 80, "Inside");

  test(40, 70, 60, 80, "Straddling Left");
  test(70, 40, 80, 60, "Straddling Top");
  test(90, 70, 110, 80, "Straddling Right");
  test(70, 90, 80, 110, "Straddling Bottom");
}

#[test]
fn empty_rect_does_not_intersect() {
  let mut rect = Rect::make_ltrb(50.0, 50.0, 100.0, 100.0);

  let mut test = |l: Scalar, t: Scalar, r: Scalar, b: Scalar, label: &str| {
    expect_false!(Rect::make_ltrb(l, b, r, t).intersects_with_rect(&rect));
    expect_false!(Rect::make_ltrb(r, b, l, t).intersects_with_rect(&rect));
    expect_false!(Rect::make_ltrb(r, t, l, b).intersects_with_rect(&rect));
  };

  test(20.0, 20.0, 30.0, 30.0, "Above and Left");
  test(70.0, 20.0, 80.0, 30.0, "Above");
  test(120.0, 20.0, 130.0, 30.0, "Above and Right");
  test(120.0, 70.0, 130.0, 80.0, "Right");
  test(120.0, 120.0, 130.0, 130.0, "Below and Right");
  test(70.0, 120.0, 80.0, 130.0, "Below");
  test(20.0, 120.0, 30.0, 130.0, "Below and Left");
  test(20.0, 70.0, 30.0, 80.0, "Left");

  test(70.0, 70.0, 80.0, 80.0, "Inside");

  test(40.0, 70.0, 60.0, 80.0, "Straddling Left");
  test(70.0, 40.0, 80.0, 60.0, "Straddling Top");
  test(90.0, 70.0, 110.0, 80.0, "Straddling Right");
  test(70.0, 90.0, 80.0, 110.0, "Straddling Bottom");
}

#[test]
fn empty_i_rect_does_not_intersect() {
  let mut rect = IRect::make_ltrb(50, 50, 100, 100);

  let mut test = |l: i64, t: i64, r: i64, b: i64, label: &str| {
    expect_false!(IRect::make_ltrb(l, b, r, t).intersects_with_rect(&rect));
    expect_false!(IRect::make_ltrb(r, b, l, t).intersects_with_rect(&rect));
    expect_false!(IRect::make_ltrb(r, t, l, b).intersects_with_rect(&rect));
  };

  test(20, 20, 30, 30, "Above and Left");
  test(70, 20, 80, 30, "Above");
  test(120, 20, 130, 30, "Above and Right");
  test(120, 70, 130, 80, "Right");
  test(120, 120, 130, 130, "Below and Right");
  test(70, 120, 80, 130, "Below");
  test(20, 120, 30, 130, "Below and Left");
  test(20, 70, 30, 80, "Left");

  test(70, 70, 80, 80, "Inside");

  test(40, 70, 60, 80, "Straddling Left");
  test(70, 40, 80, 60, "Straddling Top");
  test(90, 70, 110, 80, "Straddling Right");
  test(70, 90, 80, 110, "Straddling Bottom");
}

#[test]
fn rect_scale() {
  let mut test1 = |rect: Rect, scale: Scalar| {
    let mut expected = Rect::make_xywh(rect.get_x() * scale,      //
                                   rect.get_y() * scale,      //
                                   rect.get_width() * scale,  //
                                   rect.get_height() * scale);

    expect_rect_near!(rect.scale(scale), expected);
    expect_rect_near!(rect.scale_xy(scale, scale), expected);
    expect_rect_near!(rect.scale_point(Point::new(scale, scale)), expected);
    expect_rect_near!(rect.scale_size(Size::new(scale, scale)), expected);
  };

  let mut test2 = |rect: Rect, scale_x: Scalar, scale_y: Scalar| {
    let mut expected = Rect::make_xywh(rect.get_x() * scale_x,      //
                                   rect.get_y() * scale_y,      //
                                   rect.get_width() * scale_x,  //
                                   rect.get_height() * scale_y);

    expect_rect_near!(rect.scale_xy(scale_x, scale_y), expected);
    expect_rect_near!(rect.scale_point(Point::new(scale_x, scale_y)), expected);
    expect_rect_near!(rect.scale_size(Size::new(scale_x, scale_y)), expected);

    test1(rect, scale_x);
    test1(rect, scale_y);
  };

  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), 1.0, 0.0);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), 0.0, 1.0);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), 0.0, 0.0);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), 2.5, 3.5);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), 3.5, 2.5);
  test2(Rect::make_ltrb(10.0, 15.0, -100.0, 150.0), 2.5, 3.5);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, -150.0), 2.5, 3.5);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), -2.5, 3.5);
  test2(Rect::make_ltrb(10.0, 15.0, 100.0, 150.0), 2.5, -3.5);
}

#[test]
fn i_rect_scale() {
  let mut test1 = |rect: IRect, scale: i64| {
    let mut expected = IRect::make_xywh(rect.get_x() * scale,      //
                                     rect.get_y() * scale,      //
                                     rect.get_width() * scale,  //
                                     rect.get_height() * scale);

    expect_eq!(rect.scale(scale), expected);
    expect_eq!(rect.scale_xy(scale, scale), expected);
    expect_eq!(rect.scale_point(IPoint::new(scale, scale)), expected);
    expect_eq!(rect.scale_size(ISize::new(scale, scale)), expected);
  };

  let mut test2 = |rect: IRect, scale_x: i64, scale_y: i64| {
    let mut expected = IRect::make_xywh(rect.get_x() * scale_x,      //
                                     rect.get_y() * scale_y,      //
                                     rect.get_width() * scale_x,  //
                                     rect.get_height() * scale_y);

    expect_eq!(rect.scale_xy(scale_x, scale_y), expected);
    expect_eq!(rect.scale_point(IPoint::new(scale_x, scale_y)), expected);
    expect_eq!(rect.scale_size(ISize::new(scale_x, scale_y)), expected);

    test1(rect, scale_x);
    test1(rect, scale_y);
  };

  test2(IRect::make_ltrb(10, 15, 100, 150), 2, 3);
  test2(IRect::make_ltrb(10, 15, 100, 150), 3, 2);
  test2(IRect::make_ltrb(10, 15, -100, 150), 2, 3);
  test2(IRect::make_ltrb(10, 15, 100, -150), 2, 3);
  test2(IRect::make_ltrb(10, 15, 100, 150), -2, 3);
  test2(IRect::make_ltrb(10, 15, 100, 150), 2, -3);
}

#[test]
fn rect_area() {
  expect_eq!(Rect::make_xywh(0.0, 0.0, 100.0, 200.0).area(), 20000);
  expect_eq!(Rect::make_xywh(10.0, 20.0, 100.0, 200.0).area(), 20000);
  expect_eq!(Rect::make_xywh(0.0, 0.0, 200.0, 100.0).area(), 20000);
  expect_eq!(Rect::make_xywh(10.0, 20.0, 200.0, 100.0).area(), 20000);
  expect_eq!(Rect::make_xywh(0.0, 0.0, 100.0, 100.0).area(), 10000);
  expect_eq!(Rect::make_xywh(10.0, 20.0, 100.0, 100.0).area(), 10000);
}

#[test]
fn i_rect_area() {
  expect_eq!(IRect::make_xywh(0, 0, 100, 200).area(), 20000);
  expect_eq!(IRect::make_xywh(10, 20, 100, 200).area(), 20000);
  expect_eq!(IRect::make_xywh(0, 0, 200, 100).area(), 20000);
  expect_eq!(IRect::make_xywh(10, 20, 200, 100).area(), 20000);
  expect_eq!(IRect::make_xywh(0, 0, 100, 100).area(), 10000);
  expect_eq!(IRect::make_xywh(10, 20, 100, 100).area(), 10000);
}

#[test]
fn rect_get_normalizing_transform() {
  {
    // Checks for expected matrix values

    let mut r = Rect::make_xywh(100.0, 200.0, 200.0, 400.0);

    expect_eq!(r.get_normalizing_transform(),
              Matrix::make_scale(Vector3::new(0.005, 0.0025, 1.0)) *
                  Matrix::make_translation(Point::new(-100.0, -200.0).into()));
  }

  {
    // Checks for expected transform of points relative to the rect

    let mut r = Rect::make_ltrb(300.0, 500.0, 400.0, 700.0);
    let mut m = r.get_normalizing_transform();

    // The 4 corners of the rect => (0, 0) to (1, 1)
    expect_eq!(m * Point::new(300.0, 500.0), Point::new(0.0, 0.0));
    expect_eq!(m * Point::new(400.0, 500.0), Point::new(1.0, 0.0));
    expect_eq!(m * Point::new(400.0, 700.0), Point::new(1.0, 1.0));
    expect_eq!(m * Point::new(300.0, 700.0), Point::new(0.0, 1.0));

    // The center => (0.5, 0.5)
    expect_eq!(m * Point::new(350.0, 600.0), Point::new(0.5, 0.5));

    // Outside the 4 corners => (-1, -1) to (2, 2)
    expect_eq!(m * Point::new(200.0, 300.0), Point::new(-1.0, -1.0));
    expect_eq!(m * Point::new(500.0, 300.0), Point::new(2.0, -1.0));
    expect_eq!(m * Point::new(500.0, 900.0), Point::new(2.0, 2.0));
    expect_eq!(m * Point::new(200.0, 900.0), Point::new(-1.0, 2.0));
  }

  {
    // Checks for behavior with empty rects

    let mut zero = Matrix::make_scale(Vector3::new(0.0, 0.0, 1.0));

    // Empty for width and/or height == 0
    expect_eq!(Rect::make_xywh(10.0, 10.0, 0.0, 10.0).get_normalizing_transform(), zero);
    expect_eq!(Rect::make_xywh(10.0, 10.0, 10.0, 0.0).get_normalizing_transform(), zero);
    expect_eq!(Rect::make_xywh(10.0, 10.0, 0.0, 0.0).get_normalizing_transform(), zero);

    // Empty for width and/or height < 0
    expect_eq!(Rect::make_xywh(10.0, 10.0, -1.0, 10.0).get_normalizing_transform(), zero);
    expect_eq!(Rect::make_xywh(10.0, 10.0, 10.0, -1.0).get_normalizing_transform(), zero);
    expect_eq!(Rect::make_xywh(10.0, 10.0, -1.0, -1.0).get_normalizing_transform(), zero);
  }

  {
    // Checks for behavior with non-finite rects

    let mut z = Matrix::make_scale(Vector3::new(0.0, 0.0, 1.0));
    let mut nan = f32::NAN;
    let mut inf = f32::INFINITY;

    // Non-finite for width and/or height == nan
    expect_eq!(Rect::make_xywh(10.0, 10.0, nan, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, 10.0, 10.0, nan).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, 10.0, nan, nan).get_normalizing_transform(), z);

    // Non-finite for width and/or height == inf
    expect_eq!(Rect::make_xywh(10.0, 10.0, inf, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, 10.0, 10.0, inf).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, 10.0, inf, inf).get_normalizing_transform(), z);

    // Non-finite for width and/or height == -inf
    expect_eq!(Rect::make_xywh(10.0, 10.0, -inf, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, 10.0, 10.0, -inf).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, 10.0, -inf, -inf).get_normalizing_transform(), z);

    // Non-finite for origin X and/or Y == nan
    expect_eq!(Rect::make_xywh(nan, 10.0, 10.0, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, nan, 10.0, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(nan, nan, 10.0, 10.0).get_normalizing_transform(), z);

    // Non-finite for origin X and/or Y == inf
    expect_eq!(Rect::make_xywh(inf, 10.0, 10.0, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, inf, 10.0, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(inf, inf, 10.0, 10.0).get_normalizing_transform(), z);

    // Non-finite for origin X and/or Y == -inf
    expect_eq!(Rect::make_xywh(-inf, 10.0, 10.0, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(10.0, -inf, 10.0, 10.0).get_normalizing_transform(), z);
    expect_eq!(Rect::make_xywh(-inf, -inf, 10.0, 10.0).get_normalizing_transform(), z);
  }
}

#[test]
fn i_rect_get_normalizing_transform() {
  {
    // Checks for expected matrix values

    let mut r = IRect::make_xywh(100, 200, 200, 400);

    expect_eq!(r.get_normalizing_transform(),
              Matrix::make_scale(Vector3::new(0.005, 0.0025, 1.0)) *
                  Matrix::make_translation(Point::new(-100.0, -200.0).into()));
  }

  {
    // Checks for expected transform of points relative to the rect

    let mut r = IRect::make_ltrb(300, 500, 400, 700);
    let mut m = r.get_normalizing_transform();

    // The 4 corners of the rect => (0, 0) to (1, 1)
    expect_eq!(m * Point::new(300.0, 500.0), Point::new(0.0, 0.0));
    expect_eq!(m * Point::new(400.0, 500.0), Point::new(1.0, 0.0));
    expect_eq!(m * Point::new(400.0, 700.0), Point::new(1.0, 1.0));
    expect_eq!(m * Point::new(300.0, 700.0), Point::new(0.0, 1.0));

    // The center => (0.5, 0.5)
    expect_eq!(m * Point::new(350.0, 600.0), Point::new(0.5, 0.5));

    // Outside the 4 corners => (-1, -1) to (2, 2)
    expect_eq!(m * Point::new(200.0, 300.0), Point::new(-1.0, -1.0));
    expect_eq!(m * Point::new(500.0, 300.0), Point::new(2.0, -1.0));
    expect_eq!(m * Point::new(500.0, 900.0), Point::new(2.0, 2.0));
    expect_eq!(m * Point::new(200.0, 900.0), Point::new(-1.0, 2.0));
  }

  {
    // Checks for behavior with empty rects

    let mut zero = Matrix::make_scale(Vector3::new(0.0, 0.0, 1.0));

    // Empty for width and/or height == 0
    expect_eq!(IRect::make_xywh(10, 10, 0, 10).get_normalizing_transform(), zero);
    expect_eq!(IRect::make_xywh(10, 10, 10, 0).get_normalizing_transform(), zero);
    expect_eq!(IRect::make_xywh(10, 10, 0, 0).get_normalizing_transform(), zero);

    // Empty for width and/or height < 0
    expect_eq!(IRect::make_xywh(10, 10, -1, 10).get_normalizing_transform(), zero);
    expect_eq!(IRect::make_xywh(10, 10, 10, -1).get_normalizing_transform(), zero);
    expect_eq!(IRect::make_xywh(10, 10, -1, -1).get_normalizing_transform(), zero);
  }
}

#[test]
fn rect_xywh_is_empty() {
  let mut nan = f32::NAN;

  // Non-empty
  expect_false!(Rect::make_xywh(1.5, 2.3, 10.5, 7.2).is_empty());

  // Empty both width and height both 0 or negative, in all combinations
  expect_true!(Rect::make_xywh(1.5, 2.3, 0.0, 0.0).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, -1.0, -1.0).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, 0.0, -1.0).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, -1.0, 0.0).is_empty());

  // Empty for 0 or negative width or height (but not both at the same time)
  expect_true!(Rect::make_xywh(1.5, 2.3, 10.5, 0.0).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, 10.5, -1.0).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, 0.0, 7.2).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, -1.0, 7.2).is_empty());

  // Empty for NaN in width or height or both
  expect_true!(Rect::make_xywh(1.5, 2.3, 10.5, nan).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, nan, 7.2).is_empty());
  expect_true!(Rect::make_xywh(1.5, 2.3, nan, nan).is_empty());
}

#[test]
fn i_rect_xywh_is_empty() {
  // Non-empty
  expect_false!(IRect::make_xywh(1, 2, 10, 7).is_empty());

  // Empty both width and height both 0 or negative, in all combinations
  expect_true!(IRect::make_xywh(1, 2, 0, 0).is_empty());
  expect_true!(IRect::make_xywh(1, 2, -1, -1).is_empty());
  expect_true!(IRect::make_xywh(1, 2, -1, 0).is_empty());
  expect_true!(IRect::make_xywh(1, 2, 0, -1).is_empty());

  // Empty for 0 or negative width or height (but not both at the same time)
  expect_true!(IRect::make_xywh(1, 2, 10, 0).is_empty());
  expect_true!(IRect::make_xywh(1, 2, 10, -1).is_empty());
  expect_true!(IRect::make_xywh(1, 2, 0, 7).is_empty());
  expect_true!(IRect::make_xywh(1, 2, -1, 7).is_empty());
}

#[test]
fn make_point_bounds_quad() {
  let quad: Quad = [
      Point::new(10.0, 10.0),
      Point::new(20.0, 10.0),
      Point::new(10.0, 20.0),
      Point::new(20.0, 20.0),
  ];
  let bounds: Option<Rect> = Rect::make_point_bounds(&quad);
  expect_true!(bounds.is_some());
  if (bounds.is_some()) {
    expect_true!(rect_near(bounds.unwrap(), Rect::make_ltrb(10.0, 10.0, 20.0, 20.0)));
  }
}

#[test]
fn is_square() {
  expect_true!(Rect::make_xywh(10.0, 30.0, 20.0, 20.0).is_square());
  expect_false!(Rect::make_xywh(10.0, 30.0, 20.0, 19.0).is_square());
  expect_false!(Rect::make_xywh(10.0, 30.0, 19.0, 20.0).is_square());
  expect_true!(Rect::make_maximum().is_square());

  expect_true!(IRect::make_xywh(10, 30, 20, 20).is_square());
  expect_false!(IRect::make_xywh(10, 30, 20, 19).is_square());
  expect_false!(IRect::make_xywh(10, 30, 19, 20).is_square());
  expect_true!(IRect::make_maximum().is_square());
}

#[test]
fn get_center() {
  expect_eq!(Rect::make_xywh(10.0, 30.0, 20.0, 20.0).get_center(), Point::new(20.0, 40.0));
  expect_eq!(Rect::make_xywh(10.0, 30.0, 20.0, 19.0).get_center(), Point::new(20.0, 39.5));
  expect_eq!(Rect::make_maximum().get_center(), Point::new(0.0, 0.0));

  // Note that we expect a Point as the answer from an IRect
  expect_eq!(IRect::make_xywh(10, 30, 20, 20).get_center(), Point::new(20.0, 40.0));
  expect_eq!(IRect::make_xywh(10, 30, 20, 19).get_center(), Point::new(20.0, 39.5));
  expect_eq!(IRect::make_maximum().get_center(), Point::new(0.0, 0.0));
}

#[test]
fn rect_expand() {
  let mut rect = Rect::make_ltrb(100.0, 100.0, 200.0, 200.0);

  // Expand(T amount)
  expect_eq!(rect.expand(10.0), Rect::make_ltrb(90.0, 90.0, 210.0, 210.0));
  expect_eq!(rect.expand(-10.0), Rect::make_ltrb(110.0, 110.0, 190.0, 190.0));

  // Expand(amount, amount)
  expect_eq!(rect.expand_xy(10.0, 10.0), Rect::make_ltrb(90.0, 90.0, 210.0, 210.0));
  expect_eq!(rect.expand_xy(10.0, -10.0), Rect::make_ltrb(90.0, 110.0, 210.0, 190.0));
  expect_eq!(rect.expand_xy(-10.0, 10.0), Rect::make_ltrb(110.0, 90.0, 190.0, 210.0));
  expect_eq!(rect.expand_xy(-10.0, -10.0), Rect::make_ltrb(110.0, 110.0, 190.0, 190.0));

  // Expand(amount, amount, amount, amount)
  expect_eq!(rect.expand_ltrb(10.0, 20.0, 30.0, 40.0), Rect::make_ltrb(90.0, 80.0, 230.0, 240.0));
  expect_eq!(rect.expand_ltrb(-10.0, 20.0, 30.0, 40.0), Rect::make_ltrb(110.0, 80.0, 230.0, 240.0));
  expect_eq!(rect.expand_ltrb(10.0, -20.0, 30.0, 40.0), Rect::make_ltrb(90.0, 120.0, 230.0, 240.0));
  expect_eq!(rect.expand_ltrb(10.0, 20.0, -30.0, 40.0), Rect::make_ltrb(90.0, 80.0, 170.0, 240.0));
  expect_eq!(rect.expand_ltrb(10.0, 20.0, 30.0, -40.0), Rect::make_ltrb(90.0, 80.0, 230.0, 160.0));

  // Expand(Point amount)
  expect_eq!(rect.expand_point(Point::new(10.0, 10.0)), Rect::make_ltrb(90.0, 90.0, 210.0, 210.0));
  expect_eq!(rect.expand_point(Point::new(10.0, -10.0)), Rect::make_ltrb(90.0, 110.0, 210.0, 190.0));
  expect_eq!(rect.expand_point(Point::new(-10.0, 10.0)), Rect::make_ltrb(110.0, 90.0, 190.0, 210.0));
  expect_eq!(rect.expand_point(Point::new(-10.0, -10.0)), Rect::make_ltrb(110.0, 110.0, 190.0, 190.0));

  // Expand(Size amount)
  expect_eq!(rect.expand_size(Size::new(10.0, 10.0)), Rect::make_ltrb(90.0, 90.0, 210.0, 210.0));
  expect_eq!(rect.expand_size(Size::new(10.0, -10.0)), Rect::make_ltrb(90.0, 110.0, 210.0, 190.0));
  expect_eq!(rect.expand_size(Size::new(-10.0, 10.0)), Rect::make_ltrb(110.0, 90.0, 190.0, 210.0));
  expect_eq!(rect.expand_size(Size::new(-10.0, -10.0)), Rect::make_ltrb(110.0, 110.0, 190.0, 190.0));
}

#[test]
fn i_rect_expand() {
  let mut rect = IRect::make_ltrb(100, 100, 200, 200);

  // Expand(T amount)
  expect_eq!(rect.expand(10), IRect::make_ltrb(90, 90, 210, 210));
  expect_eq!(rect.expand(-10), IRect::make_ltrb(110, 110, 190, 190));

  // Expand(amount, amount)
  expect_eq!(rect.expand_xy(10, 10), IRect::make_ltrb(90, 90, 210, 210));
  expect_eq!(rect.expand_xy(10, -10), IRect::make_ltrb(90, 110, 210, 190));
  expect_eq!(rect.expand_xy(-10, 10), IRect::make_ltrb(110, 90, 190, 210));
  expect_eq!(rect.expand_xy(-10, -10), IRect::make_ltrb(110, 110, 190, 190));

  // Expand(amount, amount, amount, amount)
  expect_eq!(rect.expand_ltrb(10, 20, 30, 40), IRect::make_ltrb(90, 80, 230, 240));
  expect_eq!(rect.expand_ltrb(-10, 20, 30, 40), IRect::make_ltrb(110, 80, 230, 240));
  expect_eq!(rect.expand_ltrb(10, -20, 30, 40), IRect::make_ltrb(90, 120, 230, 240));
  expect_eq!(rect.expand_ltrb(10, 20, -30, 40), IRect::make_ltrb(90, 80, 170, 240));
  expect_eq!(rect.expand_ltrb(10, 20, 30, -40), IRect::make_ltrb(90, 80, 230, 160));

  // Expand(IPoint amount)
  expect_eq!(rect.expand_point(IPoint::new(10, 10)), IRect::make_ltrb(90, 90, 210, 210));
  expect_eq!(rect.expand_point(IPoint::new(10, -10)), IRect::make_ltrb(90, 110, 210, 190));
  expect_eq!(rect.expand_point(IPoint::new(-10, 10)), IRect::make_ltrb(110, 90, 190, 210));
  expect_eq!(rect.expand_point(IPoint::new(-10, -10)), IRect::make_ltrb(110, 110, 190, 190));

  // Expand(ISize amount)
  expect_eq!(rect.expand_size(ISize::new(10, 10)), IRect::make_ltrb(90, 90, 210, 210));
  expect_eq!(rect.expand_size(ISize::new(10, -10)), IRect::make_ltrb(90, 110, 210, 190));
  expect_eq!(rect.expand_size(ISize::new(-10, 10)), IRect::make_ltrb(110, 90, 190, 210));
  expect_eq!(rect.expand_size(ISize::new(-10, -10)), IRect::make_ltrb(110, 110, 190, 190));
}

#[test]
fn rect_expand_to_min_transformed_size_null_for_scaled_to_zero() {
  let mut rect = Rect::default();
  let mut transform = Matrix::make_scale2(Vector2::new(0.0f32, 1.0f32));
  expect_eq!(rect.expand_to_min_transformed_size(Size::new(1.0, 1.0), &transform),
            None);
}

#[test]
fn rect_expand_to_min_transformed_size_returns_unmodified_when_large_enough() {
  let mut rect = Rect::make_xywh(0.0, 0.0, 10.0, 20.0);
  let mut transform = Matrix::make_scale2(Vector2::new(0.5f32, 0.5f32));
  expect_eq!(rect.expand_to_min_transformed_size(Size::new(1.0, 1.0), &transform), rect);
}

#[test]
fn rect_expand_to_min_transformed_size_returns_unmodified_when_large_enough_with_fractional_size() {
  // Regression test for https://github.com/flutter/flutter/issues/189807.
  let mut rect = Rect::make_xywh(100.0f32, 50.0f32, 64.2f32, 40.0f32);
  let mut transform = Matrix::default();
  expect_eq!(rect.expand_to_min_transformed_size(Size::new(1.0, 1.0), &transform), rect);
}

#[test]
fn rect_expand_to_min_transformed_size_rect_with_identity_transform() {
  let mut size = Size::new(2.0f32, 2.0f32);
  let mut rect = Rect::make_ellipse_bounds(&Point::default(), &(size * 0.5f32));

  let mut transform = Matrix::default();

  // Expand to a width and height less than the original size.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(0.5, 0.75), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), size);
    }
  }

  // Expand to a minimum width. Minimum height is less than the original size.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(4.0, 1.5), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), Size::new(4.0f32, 2.0f32));
    }
  }

  // Expand to a minimum height. Minimum width is less than the original size.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(1.5, 4.0), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), Size::new(2.0f32, 4.0f32));
    }
  }

  // Expand to a minimum width and height.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(3.0, 4.0), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), Size::new(3.0f32, 4.0f32));
    }
  }
}

#[test]
fn rect_expand_to_min_transformed_size_rect_with_scaling_transform() {
  let mut size = Size::new(2.0f32, 2.0f32);
  let mut rect = Rect::make_ellipse_bounds(&Point::default(), &(size * 0.5f32));

  // Scale by 2x in the X direction and 3x in the Y direction.
  // Transformed rect size is (4.0, 6.0).
  let mut transform = Matrix::make_scale2(Vector2::new(2.0f32, 3.0f32));

  // Expand to a transformed width and height less than the transformed size of
  // the original rectangle.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(3.0, 4.0), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), size);
    }
  }

  // Expand to 5.0 transformed width.
  // This is equal to 5.0 / 2.0 = 2.5 local width.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(5.0, 4.0), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), Size::new(2.5f32, 2.0f32));
    }
  }

  // Expand to 9.0 transformed height.
  // This is equal to 9.0 / 3.0 = 3.0 local height.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(3.0, 9.0), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), Size::new(2.0f32, 3.0));
    }
  }

  // Expand both width and height.
  {
    let mut expanded = rect.expand_to_min_transformed_size(Size::new(5.0, 9.0), &transform);
    expect_true!(expanded.is_some());
    if (expanded.is_some()) {
      expect_eq!(expanded.unwrap().get_size(), Size::new(2.5f32, 3.0f32));
    }
  }
}

#[test]
fn contains_floating_point() {
  let mut rect1 = Rect::make_xywh(472.599945f32, 440.999969f32, 1102.80005f32, 654.000061f32);
  let mut rect2 = Rect::make_xywh(724.0f32, 618.0f32, 600.0f32, 300.0f32);
  expect_true!(rect1.contains_rect(&rect2));
}

#[test]
fn float_contains_integer() {
  let mut rect1 = Rect::make_ltrb(472.599945f32, 440.999969f32, 1574.80005f32, 1094.000000f32);
  expect_true!(rect1.contains_rect_of(&IRect::make_ltrb(473, 441, 1574, 1094)));

  // Now test failure to contain same rect expanded by 1 on each side
  expect_false!(rect1.contains_rect_of(&IRect::make_ltrb(472, 441, 1574, 1094)));
  expect_false!(rect1.contains_rect_of(&IRect::make_ltrb(473, 440, 1574, 1094)));
  expect_false!(rect1.contains_rect_of(&IRect::make_ltrb(473, 441, 1575, 1094)));
  expect_false!(rect1.contains_rect_of(&IRect::make_ltrb(473, 441, 1574, 1095)));
}

fn flip_lr<T: RectNum>(rect: TRect<T>) -> TRect<T> {
  TRect::make_ltrb(rect.get_right(), rect.get_top(), rect.get_left(), rect.get_bottom())
}

fn flip_tb<T: RectNum>(rect: TRect<T>) -> TRect<T> {
  TRect::make_ltrb(rect.get_left(), rect.get_bottom(), rect.get_right(), rect.get_top())
}

fn flip_lrtb<T: RectNum>(rect: TRect<T>) -> TRect<T> {
  flip_lr(flip_tb(rect))
}

/// Upstream's two `swap_nan` overloads (Rect and Point).
trait SwapNan: Sized {
  fn swap_nan(&self, index: i32) -> Self;
}

impl SwapNan for Rect {
  fn swap_nan(&self, index: i32) -> Rect {
    let nan = f32::NAN;
    assert!(index >= 0 && index <= 15);
    let l = if (index & (1 << 0)) != 0 { nan } else { self.get_left() };
    let t = if (index & (1 << 1)) != 0 { nan } else { self.get_top() };
    let r = if (index & (1 << 2)) != 0 { nan } else { self.get_right() };
    let b = if (index & (1 << 3)) != 0 { nan } else { self.get_bottom() };
    Rect::make_ltrb(l, t, r, b)
  }
}

impl SwapNan for Point {
  fn swap_nan(&self, index: i32) -> Point {
    let nan = f32::NAN;
    assert!(index >= 0 && index <= 3);
    let x = if (index & (1 << 0)) != 0 { nan } else { self.x };
    let y = if (index & (1 << 1)) != 0 { nan } else { self.y };
    Point::new(x, y)
  }
}

#[test]
fn rect_union() {
  let mut check_nans = |a: Rect, b: Rect, label: &str| {
    expect_true!(a.is_finite());
    expect_true!(b.is_finite());
    expect_false!(a.union(&b).is_empty());

    for i in 1..16 {
      // NaN in a produces b
      expect_eq!(a.swap_nan(i).union(&b), b);
      // NaN in b produces a
      expect_eq!(a.union(&b.swap_nan(i)), a);
      // NaN in both is empty
      for j in 1..16 {
        expect_true!(a.swap_nan(i).union(&b.swap_nan(j)).is_empty());
      }
    }
  };

  let mut check_empty_flips = |a: Rect, b: Rect, label: &str| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    // unflipped a vs flipped (empty) b yields a
    expect_eq!(a.union(&flip_lr(b)), a);
    expect_eq!(a.union(&flip_tb(b)), a);
    expect_eq!(a.union(&flip_lrtb(b)), a);

    // flipped (empty) a vs unflipped b yields b
    expect_eq!(flip_lr(a).union(&b), b);
    expect_eq!(flip_tb(a).union(&b), b);
    expect_eq!(flip_lrtb(a).union(&b), b);

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_true!(flip_lr(a).union(&flip_lr(b)).is_empty());
    expect_true!(flip_tb(a).union(&flip_tb(b)).is_empty());
    expect_true!(flip_lrtb(a).union(&flip_lrtb(b)).is_empty());
  };

  let mut test = |a: Rect, b: Rect, result: Rect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_eq!(a.union(&b), result);
    expect_eq!(b.union(&a), result);
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(0.0, 0.0, 0.0, 0.0);
    let mut expected = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    test(a, b, expected);
  }

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(0.0, 0.0, 1.0, 1.0);
    let mut expected = Rect::make_xywh(0.0, 0.0, 200.0, 200.0);
    test(a, b, expected);
  }

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(10.0, 10.0, 1.0, 1.0);
    let mut expected = Rect::make_xywh(10.0, 10.0, 190.0, 190.0);
    test(a, b, expected);
  }

  {
    let mut a = Rect::make_xywh(0.0, 0.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(10.0, 10.0, 100.0, 100.0);
    let mut expected = Rect::make_xywh(0.0, 0.0, 110.0, 110.0);
    test(a, b, expected);
  }

  {
    let mut a = Rect::make_xywh(0.0, 0.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut expected = Rect::make_xywh(0.0, 0.0, 200.0, 200.0);
    test(a, b, expected);
  }
}

#[test]
fn opt_rect_union() {
  let mut a = Rect::make_ltrb(0.0, 0.0, 100.0, 100.0);
  let mut b = Rect::make_ltrb(100.0, 100.0, 200.0, 200.0);
  let mut c = Rect::make_ltrb(100.0, 0.0, 200.0, 100.0);

  // NullOpt, NullOpt
  expect_false!(Rect::union_opt(None, None).is_some());
  expect_eq!(Rect::union_opt(None, None), None);

  let mut test1 = |r: Rect| {
    // Rect, NullOpt
    expect_eq!(Rect::union_opt_b(&r, None), r);

    // OptRect, NullOpt
    expect_true!(Rect::union_opt(Some(r), None).is_some());
    expect_eq!(Rect::union_opt(Some(r), None).unwrap(), r);

    // NullOpt, Rect
    expect_eq!(Rect::union_opt_a(None, &r), r);

    // NullOpt, OptRect
    expect_true!(Rect::union_opt(None, Some(r)).is_some());
    expect_eq!(Rect::union_opt(None, Some(r)).unwrap(), r);
  };

  test1(a);
  test1(b);
  test1(c);

  let mut test2 = |a: Rect, b: Rect, u: Rect| {
    expect_eq!(a.union(&b), u);

    // Rect, OptRect
    expect_eq!(Rect::union_opt_b(&a, Some(b)), u);

    // OptRect, Rect
    expect_eq!(Rect::union_opt_a(Some(a), &b), u);

    // OptRect, OptRect
    expect_true!(Rect::union_opt(Some(a), Some(b)).is_some());
    expect_eq!(Rect::union_opt(Some(a), Some(b)).unwrap(), u);
  };

  test2(a, b, Rect::make_ltrb(0.0, 0.0, 200.0, 200.0));
  test2(a, c, Rect::make_ltrb(0.0, 0.0, 200.0, 100.0));
  test2(b, c, Rect::make_ltrb(100.0, 0.0, 200.0, 200.0));
}

#[test]
fn i_rect_union() {
  let mut check_empty_flips = |a: IRect, b: IRect, label: &str| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    // unflipped a vs flipped (empty) b yields a
    expect_eq!(a.union(&flip_lr(b)), a);
    expect_eq!(a.union(&flip_tb(b)), a);
    expect_eq!(a.union(&flip_lrtb(b)), a);

    // flipped (empty) a vs unflipped b yields b
    expect_eq!(flip_lr(a).union(&b), b);
    expect_eq!(flip_tb(a).union(&b), b);
    expect_eq!(flip_lrtb(a).union(&b), b);

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_true!(flip_lr(a).union(&flip_lr(b)).is_empty());
    expect_true!(flip_tb(a).union(&flip_tb(b)).is_empty());
    expect_true!(flip_lrtb(a).union(&flip_lrtb(b)).is_empty());
  };

  let mut test = |a: IRect, b: IRect, result: IRect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_eq!(a.union(&b), result);
    expect_eq!(b.union(&a), result);
    check_empty_flips(a, b, &label);
  };

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(0, 0, 0, 0);
    let mut expected = IRect::make_xywh(100, 100, 100, 100);
    test(a, b, expected);
  }

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(0, 0, 1, 1);
    let mut expected = IRect::make_xywh(0, 0, 200, 200);
    test(a, b, expected);
  }

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(10, 10, 1, 1);
    let mut expected = IRect::make_xywh(10, 10, 190, 190);
    test(a, b, expected);
  }

  {
    let mut a = IRect::make_xywh(0, 0, 100, 100);
    let mut b = IRect::make_xywh(10, 10, 100, 100);
    let mut expected = IRect::make_xywh(0, 0, 110, 110);
    test(a, b, expected);
  }

  {
    let mut a = IRect::make_xywh(0, 0, 100, 100);
    let mut b = IRect::make_xywh(100, 100, 100, 100);
    let mut expected = IRect::make_xywh(0, 0, 200, 200);
    test(a, b, expected);
  }
}

#[test]
fn opt_i_rect_union() {
  let mut a = IRect::make_ltrb(0, 0, 100, 100);
  let mut b = IRect::make_ltrb(100, 100, 200, 200);
  let mut c = IRect::make_ltrb(100, 0, 200, 100);

  // NullOpt, NullOpt
  expect_false!(IRect::union_opt(None, None).is_some());
  expect_eq!(IRect::union_opt(None, None), None);

  let mut test1 = |r: IRect| {
    // Rect, NullOpt
    expect_eq!(IRect::union_opt_b(&r, None), r);

    // OptRect, NullOpt
    expect_true!(IRect::union_opt(Some(r), None).is_some());
    expect_eq!(IRect::union_opt(Some(r), None).unwrap(), r);

    // NullOpt, Rect
    expect_eq!(IRect::union_opt_a(None, &r), r);

    // NullOpt, OptRect
    expect_true!(IRect::union_opt(None, Some(r)).is_some());
    expect_eq!(IRect::union_opt(None, Some(r)).unwrap(), r);
  };

  test1(a);
  test1(b);
  test1(c);

  let mut test2 = |a: IRect, b: IRect, u: IRect| {
    expect_eq!(a.union(&b), u);

    // Rect, OptRect
    expect_eq!(IRect::union_opt_b(&a, Some(b)), u);

    // OptRect, Rect
    expect_eq!(IRect::union_opt_a(Some(a), &b), u);

    // OptRect, OptRect
    expect_true!(IRect::union_opt(Some(a), Some(b)).is_some());
    expect_eq!(IRect::union_opt(Some(a), Some(b)).unwrap(), u);
  };

  test2(a, b, IRect::make_ltrb(0, 0, 200, 200));
  test2(a, c, IRect::make_ltrb(0, 0, 200, 100));
  test2(b, c, IRect::make_ltrb(100, 0, 200, 200));
}

#[test]
fn rect_intersection() {
  let mut check_nans = |a: Rect, b: Rect, label: &str| {
    expect_true!(a.is_finite());
    expect_true!(b.is_finite());

    for i in 1..16 {
      // NaN in a produces empty
      expect_false!(a.swap_nan(i).intersection(&b).is_some());
      // NaN in b produces empty
      expect_false!(a.intersection(&b.swap_nan(i)).is_some());
      // NaN in both is empty
      for j in 1..16 {
        expect_false!(a.swap_nan(i).intersection(&b.swap_nan(j)).is_some());
      }
    }
  };

  let mut check_empty_flips = |a: Rect, b: Rect, label: &str| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    // unflipped a vs flipped (empty) b yields a
    expect_false!(a.intersection(&flip_lr(b)).is_some());
    expect_true!(a.intersection_or_empty(&flip_lr(b)).is_empty());
    expect_false!(a.intersection(&flip_tb(b)).is_some());
    expect_true!(a.intersection_or_empty(&flip_tb(b)).is_empty());
    expect_false!(a.intersection(&flip_lrtb(b)).is_some());
    expect_true!(a.intersection_or_empty(&flip_lrtb(b)).is_empty());

    // flipped (empty) a vs unflipped b yields b
    expect_false!(flip_lr(a).intersection(&b).is_some());
    expect_true!(flip_lr(a).intersection_or_empty(&b).is_empty());
    expect_false!(flip_tb(a).intersection(&b).is_some());
    expect_true!(flip_tb(a).intersection_or_empty(&b).is_empty());
    expect_false!(flip_lrtb(a).intersection(&b).is_some());
    expect_true!(flip_lrtb(a).intersection_or_empty(&b).is_empty());

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_false!(flip_lr(a).intersection(&flip_lr(b)).is_some());
    expect_true!(flip_lr(a).intersection_or_empty(&flip_lr(b)).is_empty());
    expect_false!(flip_tb(a).intersection(&flip_tb(b)).is_some());
    expect_true!(flip_tb(a).intersection_or_empty(&flip_tb(b)).is_empty());
    expect_false!(flip_lrtb(a).intersection(&flip_lrtb(b)).is_some());
    expect_true!(flip_lrtb(a).intersection_or_empty(&flip_lrtb(b)).is_empty());
  };

  let mut test_non_empty = |a: Rect, b: Rect, result: Rect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_true!(a.intersection(&b).is_some());
    expect_true!(b.intersection(&a).is_some());
    expect_eq!(a.intersection(&b), result);
    expect_eq!(b.intersection(&a), result);
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  let mut test_empty = |a: Rect, b: Rect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_false!(a.intersection(&b).is_some());
    expect_true!(a.intersection_or_empty(&b).is_empty());
    expect_false!(b.intersection(&a).is_some());
    expect_true!(b.intersection_or_empty(&a).is_empty());
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(0.0, 0.0, 0.0, 0.0);

    test_empty(a, b);
  }

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(10.0, 10.0, 0.0, 0.0);

    test_empty(a, b);
  }

  {
    let mut a = Rect::make_xywh(0.0, 0.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(10.0, 10.0, 100.0, 100.0);
    let mut expected = Rect::make_xywh(10.0, 10.0, 90.0, 90.0);

    test_non_empty(a, b, expected);
  }

  {
    let mut a = Rect::make_xywh(0.0, 0.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);

    test_empty(a, b);
  }

  {
    let mut a = Rect::make_maximum();
    let mut b = Rect::make_xywh(10.0, 10.0, 300.0, 300.0);

    test_non_empty(a, b, b);
  }

  {
    let mut a = Rect::make_maximum();
    let mut b = Rect::make_maximum();

    test_non_empty(a, b, Rect::make_maximum());
  }
}

#[test]
fn opt_rect_intersection() {
  let mut a = Rect::make_ltrb(0.0, 0.0, 110.0, 110.0);
  let mut b = Rect::make_ltrb(100.0, 100.0, 200.0, 200.0);
  let mut c = Rect::make_ltrb(100.0, 0.0, 200.0, 110.0);

  // NullOpt, NullOpt
  expect_false!(Rect::intersection_opt(None, None).is_some());
  expect_eq!(Rect::intersection_opt(None, None), None);

  let mut test1 = |r: Rect| {
    // Rect, NullOpt
    expect_true!(Rect::intersection_opt_b(&r, None).is_some());
    expect_eq!(Rect::intersection_opt_b(&r, None).unwrap(), r);

    // OptRect, NullOpt
    expect_true!(Rect::intersection_opt(Some(r), None).is_some());
    expect_eq!(Rect::intersection_opt(Some(r), None).unwrap(), r);

    // NullOpt, Rect
    expect_true!(Rect::intersection_opt_a(None, &r).is_some());
    expect_eq!(Rect::intersection_opt_a(None, &r).unwrap(), r);

    // NullOpt, OptRect
    expect_true!(Rect::intersection_opt(None, Some(r)).is_some());
    expect_eq!(Rect::intersection_opt(None, Some(r)).unwrap(), r);
  };

  test1(a);
  test1(b);
  test1(c);

  let mut test2 = |a: Rect, b: Rect, i: Rect| {
    expect_eq!(a.intersection(&b), i);

    // Rect, OptRect
    expect_true!(Rect::intersection_opt_b(&a, Some(b)).is_some());
    expect_eq!(Rect::intersection_opt_b(&a, Some(b)).unwrap(), i);

    // OptRect, Rect
    expect_true!(Rect::intersection_opt_a(Some(a), &b).is_some());
    expect_eq!(Rect::intersection_opt_a(Some(a), &b).unwrap(), i);

    // OptRect, OptRect
    expect_true!(
        Rect::intersection_opt(Some(a), Some(b)).is_some());
    expect_eq!(Rect::intersection_opt(Some(a), Some(b)).unwrap(),
              i);
  };

  test2(a, b, Rect::make_ltrb(100.0, 100.0, 110.0, 110.0));
  test2(a, c, Rect::make_ltrb(100.0, 0.0, 110.0, 110.0));
  test2(b, c, Rect::make_ltrb(100.0, 100.0, 200.0, 110.0));
}

#[test]
fn i_rect_intersection() {
  let mut check_empty_flips = |a: IRect, b: IRect, label: &str| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    // unflipped a vs flipped (empty) b yields a
    expect_false!(a.intersection(&flip_lr(b)).is_some());
    expect_false!(a.intersection(&flip_tb(b)).is_some());
    expect_false!(a.intersection(&flip_lrtb(b)).is_some());

    // flipped (empty) a vs unflipped b yields b
    expect_false!(flip_lr(a).intersection(&b).is_some());
    expect_false!(flip_tb(a).intersection(&b).is_some());
    expect_false!(flip_lrtb(a).intersection(&b).is_some());

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_false!(flip_lr(a).intersection(&flip_lr(b)).is_some());
    expect_false!(flip_tb(a).intersection(&flip_tb(b)).is_some());
    expect_false!(flip_lrtb(a).intersection(&flip_lrtb(b)).is_some());
  };

  let mut test_non_empty = |a: IRect, b: IRect, result: IRect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_true!(a.intersection(&b).is_some());
    expect_true!(b.intersection(&a).is_some());
    expect_eq!(a.intersection(&b), result);
    expect_eq!(b.intersection(&a), result);
    check_empty_flips(a, b, &label);
  };

  let mut test_empty = |a: IRect, b: IRect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_false!(a.intersection(&b).is_some());
    expect_false!(b.intersection(&a).is_some());
    check_empty_flips(a, b, &label);
  };

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(0, 0, 0, 0);

    test_empty(a, b);
  }

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(10, 10, 0, 0);

    test_empty(a, b);
  }

  {
    let mut a = IRect::make_xywh(0, 0, 100, 100);
    let mut b = IRect::make_xywh(10, 10, 100, 100);
    let mut expected = IRect::make_xywh(10, 10, 90, 90);

    test_non_empty(a, b, expected);
  }

  {
    let mut a = IRect::make_xywh(0, 0, 100, 100);
    let mut b = IRect::make_xywh(100, 100, 100, 100);

    test_empty(a, b);
  }

  {
    let mut a = IRect::make_maximum();
    let mut b = IRect::make_xywh(10, 10, 300, 300);

    test_non_empty(a, b, b);
  }

  {
    let mut a = IRect::make_maximum();
    let mut b = IRect::make_maximum();

    test_non_empty(a, b, IRect::make_maximum());
  }
}

#[test]
fn opt_i_rect_intersection() {
  let mut a = IRect::make_ltrb(0, 0, 110, 110);
  let mut b = IRect::make_ltrb(100, 100, 200, 200);
  let mut c = IRect::make_ltrb(100, 0, 200, 110);

  // NullOpt, NullOpt
  expect_false!(IRect::intersection_opt(None, None).is_some());
  expect_eq!(IRect::intersection_opt(None, None), None);

  let mut test1 = |r: IRect| {
    // Rect, NullOpt
    expect_true!(IRect::intersection_opt_b(&r, None).is_some());
    expect_eq!(IRect::intersection_opt_b(&r, None).unwrap(), r);

    // OptRect, NullOpt
    expect_true!(
        IRect::intersection_opt(Some(r), None).is_some());
    expect_eq!(IRect::intersection_opt(Some(r), None).unwrap(), r);

    // NullOpt, Rect
    expect_true!(IRect::intersection_opt_a(None, &r).is_some());
    expect_eq!(IRect::intersection_opt_a(None, &r).unwrap(), r);

    // NullOpt, OptRect
    expect_true!(
        IRect::intersection_opt(None, Some(r)).is_some());
    expect_eq!(IRect::intersection_opt(None, Some(r)).unwrap(), r);
  };

  test1(a);
  test1(b);
  test1(c);

  let mut test2 = |a: IRect, b: IRect, i: IRect| {
    expect_eq!(a.intersection(&b), i);

    // Rect, OptRect
    expect_true!(IRect::intersection_opt_b(&a, Some(b)).is_some());
    expect_eq!(IRect::intersection_opt_b(&a, Some(b)).unwrap(), i);

    // OptRect, Rect
    expect_true!(IRect::intersection_opt_a(Some(a), &b).is_some());
    expect_eq!(IRect::intersection_opt_a(Some(a), &b).unwrap(), i);

    // OptRect, OptRect
    expect_true!(
        IRect::intersection_opt(Some(a), Some(b)).is_some());
    expect_eq!(IRect::intersection_opt(Some(a), Some(b)).unwrap(),
              i);
  };

  test2(a, b, IRect::make_ltrb(100, 100, 110, 110));
  test2(a, c, IRect::make_ltrb(100, 0, 110, 110));
  test2(b, c, IRect::make_ltrb(100, 100, 200, 110));
}

#[test]
fn rect_intersects_with_rect() {
  let mut check_nans = |a: Rect, b: Rect, label: &str| {
    expect_true!(a.is_finite());
    expect_true!(b.is_finite());

    for i in 1..16 {
      // NaN in a produces b
      expect_false!(a.swap_nan(i).intersects_with_rect(&b));
      // NaN in b produces a
      expect_false!(a.intersects_with_rect(&b.swap_nan(i)));
      // NaN in both is empty
      for j in 1..16 {
        expect_false!(a.swap_nan(i).intersects_with_rect(&b.swap_nan(j)));
      }
    }
  };

  let mut check_empty_flips = |a: Rect, b: Rect, label: &str| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    // unflipped a vs flipped (empty) b yields a
    expect_false!(a.intersects_with_rect(&flip_lr(b)));
    expect_false!(a.intersects_with_rect(&flip_tb(b)));
    expect_false!(a.intersects_with_rect(&flip_lrtb(b)));

    // flipped (empty) a vs unflipped b yields b
    expect_false!(flip_lr(a).intersects_with_rect(&b));
    expect_false!(flip_tb(a).intersects_with_rect(&b));
    expect_false!(flip_lrtb(a).intersects_with_rect(&b));

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_false!(flip_lr(a).intersects_with_rect(&flip_lr(b)));
    expect_false!(flip_tb(a).intersects_with_rect(&flip_tb(b)));
    expect_false!(flip_lrtb(a).intersects_with_rect(&flip_lrtb(b)));
  };

  let mut test_non_empty = |a: Rect, b: Rect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_true!(a.intersects_with_rect(&b));
    expect_true!(b.intersects_with_rect(&a));
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  let mut test_empty = |a: Rect, b: Rect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_false!(a.intersects_with_rect(&b));
    expect_false!(b.intersects_with_rect(&a));
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(0.0, 0.0, 0.0, 0.0);

    test_empty(a, b);
  }

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(10.0, 10.0, 0.0, 0.0);

    test_empty(a, b);
  }

  {
    let mut a = Rect::make_xywh(0.0, 0.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(10.0, 10.0, 100.0, 100.0);

    test_non_empty(a, b);
  }

  {
    let mut a = Rect::make_xywh(0.0, 0.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);

    test_empty(a, b);
  }

  {
    let mut a = Rect::make_maximum();
    let mut b = Rect::make_xywh(10.0, 10.0, 100.0, 100.0);

    test_non_empty(a, b);
  }

  {
    let mut a = Rect::make_maximum();
    let mut b = Rect::make_maximum();

    test_non_empty(a, b);
  }
}

#[test]
fn i_rect_intersects_with_rect() {
  let mut check_empty_flips = |a: IRect, b: IRect, label: &str| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    // unflipped a vs flipped (empty) b yields a
    expect_false!(a.intersects_with_rect(&flip_lr(b)));
    expect_false!(a.intersects_with_rect(&flip_tb(b)));
    expect_false!(a.intersects_with_rect(&flip_lrtb(b)));

    // flipped (empty) a vs unflipped b yields b
    expect_false!(flip_lr(a).intersects_with_rect(&b));
    expect_false!(flip_tb(a).intersects_with_rect(&b));
    expect_false!(flip_lrtb(a).intersects_with_rect(&b));

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_false!(flip_lr(a).intersects_with_rect(&flip_lr(b)));
    expect_false!(flip_tb(a).intersects_with_rect(&flip_tb(b)));
    expect_false!(flip_lrtb(a).intersects_with_rect(&flip_lrtb(b)));
  };

  let mut test_non_empty = |a: IRect, b: IRect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_true!(a.intersects_with_rect(&b));
    expect_true!(b.intersects_with_rect(&a));
    check_empty_flips(a, b, &label);
  };

  let mut test_empty = |a: IRect, b: IRect| {
    expect_false!(a.is_empty());
    // b is allowed to be empty

    let mut label = format!("{} union {}", a, b);

    expect_false!(a.intersects_with_rect(&b));
    expect_false!(b.intersects_with_rect(&a));
    check_empty_flips(a, b, &label);
  };

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(0, 0, 0, 0);

    test_empty(a, b);
  }

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(10, 10, 0, 0);

    test_empty(a, b);
  }

  {
    let mut a = IRect::make_xywh(0, 0, 100, 100);
    let mut b = IRect::make_xywh(10, 10, 100, 100);

    test_non_empty(a, b);
  }

  {
    let mut a = IRect::make_xywh(0, 0, 100, 100);
    let mut b = IRect::make_xywh(100, 100, 100, 100);

    test_empty(a, b);
  }

  {
    let mut a = IRect::make_maximum();
    let mut b = IRect::make_xywh(10, 10, 100, 100);

    test_non_empty(a, b);
  }

  {
    let mut a = IRect::make_maximum();
    let mut b = IRect::make_maximum();

    test_non_empty(a, b);
  }
}

#[test]
fn rect_contains_point() {
  let mut check_nans = |rect: Rect, point: Point, label: &str| {
    expect_true!(rect.is_finite());
    expect_true!(point.is_finite());

    for i in 1..16 {
      expect_false!(rect.swap_nan(i).contains(&point));
      for j in 1..4 {
        expect_false!(rect.swap_nan(i).contains(&point.swap_nan(j)));
      }
    }
  };

  let mut check_empty_flips = |rect: Rect, point: Point, label: &str| {
    expect_false!(rect.is_empty());

    expect_false!(flip_lr(rect).contains(&point));
    expect_false!(flip_tb(rect).contains(&point));
    expect_false!(flip_lrtb(rect).contains(&point));
  };

  let mut test_inside = |rect: Rect, point: Point| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_true!(rect.contains(&point));
    check_empty_flips(rect, point, &label);
    check_nans(rect, point, &label);
  };

  let mut test_outside = |rect: Rect, point: Point| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_false!(rect.contains(&point));
    check_empty_flips(rect, point, &label);
    check_nans(rect, point, &label);
  };

  {
    // Origin is inclusive
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(100.0, 100.0);

    test_inside(r, p);
  }
  {
    // Size is exclusive
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(200.0, 200.0);

    test_outside(r, p);
  }
  {
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(99.0, 99.0);

    test_outside(r, p);
  }
  {
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(199.0, 199.0);

    test_inside(r, p);
  }

  {
    let mut r = Rect::make_maximum();
    let mut p = Point::new(199.0, 199.0);

    test_inside(r, p);
  }
}

#[test]
fn i_rect_contains_i_point() {
  let mut check_empty_flips = |rect: IRect, point: IPoint, label: &str| {
    expect_false!(rect.is_empty());

    expect_false!(flip_lr(rect).contains(&point));
    expect_false!(flip_tb(rect).contains(&point));
    expect_false!(flip_lrtb(rect).contains(&point));
  };

  let mut test_inside = |rect: IRect, point: IPoint| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_true!(rect.contains(&point));
    check_empty_flips(rect, point, &label);
  };

  let mut test_outside = |rect: IRect, point: IPoint| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_false!(rect.contains(&point));
    check_empty_flips(rect, point, &label);
  };

  {
    // Origin is inclusive
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(100, 100);

    test_inside(r, p);
  }
  {
    // Size is exclusive
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(200, 200);

    test_outside(r, p);
  }
  {
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(99, 99);

    test_outside(r, p);
  }
  {
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(199, 199);

    test_inside(r, p);
  }

  {
    let mut r = IRect::make_maximum();
    let mut p = IPoint::new(199, 199);

    test_inside(r, p);
  }
}

#[test]
fn rect_contains_inclusive_point() {
  let mut check_nans = |rect: Rect, point: Point, label: &str| {
    expect_true!(rect.is_finite());
    expect_true!(point.is_finite());

    for i in 1..16 {
      expect_false!(rect.swap_nan(i).contains_inclusive(&point));
      for j in 1..4 {
        expect_false!(rect.swap_nan(i).contains_inclusive(&point.swap_nan(j)));
      }
    }
  };

  let mut check_empty_flips = |rect: Rect, point: Point, label: &str| {
    expect_false!(rect.is_empty());

    expect_false!(flip_lr(rect).contains_inclusive(&point));
    expect_false!(flip_tb(rect).contains_inclusive(&point));
    expect_false!(flip_lrtb(rect).contains_inclusive(&point));
  };

  let mut test_inside = |rect: Rect, point: Point| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_true!(rect.contains_inclusive(&point));
    check_empty_flips(rect, point, &label);
    check_nans(rect, point, &label);
  };

  let mut test_outside = |rect: Rect, point: Point| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_false!(rect.contains_inclusive(&point));
    check_empty_flips(rect, point, &label);
    check_nans(rect, point, &label);
  };

  {
    // Origin is inclusive
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(100.0, 100.0);

    test_inside(r, p);
  }
  {
    // Size is inclusive
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(200.0, 200.0);

    test_inside(r, p);
  }
  {
    // Size + epsilon is exclusive
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(200.0 + kEhCloseEnough, 200.0 + kEhCloseEnough);

    test_outside(r, p);
  }
  {
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(99.0, 99.0);

    test_outside(r, p);
  }
  {
    let mut r = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut p = Point::new(199.0, 199.0);

    test_inside(r, p);
  }

  {
    let mut r = Rect::make_maximum();
    let mut p = Point::new(199.0, 199.0);

    test_inside(r, p);
  }
}

#[test]
fn i_rect_contains_inclusive_i_point() {
  let mut check_empty_flips = |rect: IRect, point: IPoint, label: &str| {
    expect_false!(rect.is_empty());

    expect_false!(flip_lr(rect).contains_inclusive(&point));
    expect_false!(flip_tb(rect).contains_inclusive(&point));
    expect_false!(flip_lrtb(rect).contains_inclusive(&point));
  };

  let mut test_inside = |rect: IRect, point: IPoint| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_true!(rect.contains_inclusive(&point));
    check_empty_flips(rect, point, &label);
  };

  let mut test_outside = |rect: IRect, point: IPoint| {
    expect_false!(rect.is_empty());

    let mut label = format!("{} contains {}", rect, point);

    expect_false!(rect.contains_inclusive(&point));
    check_empty_flips(rect, point, &label);
  };

  {
    // Origin is inclusive
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(100, 100);

    test_inside(r, p);
  }
  {
    // Size is inclusive
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(200, 200);

    test_inside(r, p);
  }
  {
    // Size + "epsilon" is exclusive
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(201, 201);

    test_outside(r, p);
  }
  {
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(99, 99);

    test_outside(r, p);
  }
  {
    let mut r = IRect::make_xywh(100, 100, 100, 100);
    let mut p = IPoint::new(199, 199);

    test_inside(r, p);
  }

  {
    let mut r = IRect::make_maximum();
    let mut p = IPoint::new(199, 199);

    test_inside(r, p);
  }
}

#[test]
fn rect_contains_rect() {
  let mut check_nans = |a: Rect, b: Rect, label: &str| {
    expect_true!(a.is_finite());
    expect_true!(b.is_finite());
    expect_false!(a.is_empty());

    for i in 1..16 {
      // NaN in a produces false
      expect_false!(a.swap_nan(i).contains_rect(&b));
      // NaN in b produces false
      expect_true!(a.contains_rect(&b.swap_nan(i)));
      // NaN in both is false
      for j in 1..16 {
        expect_false!(a.swap_nan(i).contains_rect(&b.swap_nan(j)));
      }
    }
  };

  let mut check_empty_flips = |a: Rect, b: Rect, label: &str| {
    expect_false!(a.is_empty());
    // test b rects are allowed to have 0 w/h, but not be backwards
    expect_false!(b.get_left() > b.get_right() || b.get_top() > b.get_bottom());

    // unflipped a vs flipped (empty) b yields false
    expect_true!(a.contains_rect(&flip_lr(b)));
    expect_true!(a.contains_rect(&flip_tb(b)));
    expect_true!(a.contains_rect(&flip_lrtb(b)));

    // flipped (empty) a vs unflipped b yields false
    expect_false!(flip_lr(a).contains_rect(&b));
    expect_false!(flip_tb(a).contains_rect(&b));
    expect_false!(flip_lrtb(a).contains_rect(&b));

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_false!(flip_lr(a).contains_rect(&flip_lr(b)));
    expect_false!(flip_tb(a).contains_rect(&flip_tb(b)));
    expect_false!(flip_lrtb(a).contains_rect(&flip_lrtb(b)));
  };

  let mut test_inside = |a: Rect, b: Rect| {
    expect_false!(a.is_empty());
    // test b rects are allowed to have 0 w/h, but not be backwards
    expect_false!(b.get_left() > b.get_right() || b.get_top() > b.get_bottom());

    let mut label = format!("{} contains {}", a, b);

    expect_true!(a.contains_rect(&b));
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  let mut test_not_inside = |a: Rect, b: Rect| {
    expect_false!(a.is_empty());
    // If b was empty, it would be contained and should not be tested with
    // this function - use |test_inside| instead.
    expect_false!(b.is_empty());

    let mut label = format!("{} contains {}", a, b);

    expect_false!(a.contains_rect(&b));
    check_empty_flips(a, b, &label);
    check_nans(a, b, &label);
  };

  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);

    test_inside(a, a);
  }
  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(0.0, 0.0, 0.0, 0.0);

    test_inside(a, b);
  }
  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(150.0, 150.0, 20.0, 20.0);

    test_inside(a, b);
  }
  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(150.0, 150.0, 100.0, 100.0);

    test_not_inside(a, b);
  }
  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(50.0, 50.0, 100.0, 100.0);

    test_not_inside(a, b);
  }
  {
    let mut a = Rect::make_xywh(100.0, 100.0, 100.0, 100.0);
    let mut b = Rect::make_xywh(0.0, 0.0, 300.0, 300.0);

    test_not_inside(a, b);
  }
  {
    let mut a = Rect::make_maximum();
    let mut b = Rect::make_xywh(0.0, 0.0, 300.0, 300.0);

    test_inside(a, b);
  }
}

#[test]
fn i_rect_contains_i_rect() {
  let mut check_empty_flips = |a: IRect, b: IRect, label: &str| {
    expect_false!(a.is_empty());
    // test b rects are allowed to have 0 w/h, but not be backwards
    expect_false!(b.get_left() > b.get_right() || b.get_top() > b.get_bottom());

    // unflipped a vs flipped (empty) b yields true
    expect_true!(a.contains_rect(&flip_lr(b)));
    expect_true!(a.contains_rect(&flip_tb(b)));
    expect_true!(a.contains_rect(&flip_lrtb(b)));

    // flipped (empty) a vs unflipped b yields false
    expect_false!(flip_lr(a).contains_rect(&b));
    expect_false!(flip_tb(a).contains_rect(&b));
    expect_false!(flip_lrtb(a).contains_rect(&b));

    // flipped (empty) a vs flipped (empty) b yields empty
    expect_false!(flip_lr(a).contains_rect(&flip_lr(b)));
    expect_false!(flip_tb(a).contains_rect(&flip_tb(b)));
    expect_false!(flip_lrtb(a).contains_rect(&flip_lrtb(b)));
  };

  let mut test_inside = |a: IRect, b: IRect| {
    expect_false!(a.is_empty());
    // test b rects are allowed to have 0 w/h, but not be backwards
    expect_false!(b.get_left() > b.get_right() || b.get_top() > b.get_bottom());

    let mut label = format!("{} contains {}", a, b);

    expect_true!(a.contains_rect(&b));
    check_empty_flips(a, b, &label);
  };

  let mut test_not_inside = |a: IRect, b: IRect| {
    expect_false!(a.is_empty());
    // If b was empty, it would be contained and should not be tested with
    // this function - use |test_inside| instead.
    expect_false!(b.is_empty());

    let mut label = format!("{} contains {}", a, b);

    expect_false!(a.contains_rect(&b));
    check_empty_flips(a, b, &label);
  };

  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);

    test_inside(a, a);
  }
  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(0, 0, 0, 0);

    test_inside(a, b);
  }
  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(150, 150, 20, 20);

    test_inside(a, b);
  }
  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(150, 150, 100, 100);

    test_not_inside(a, b);
  }
  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(50, 50, 100, 100);

    test_not_inside(a, b);
  }
  {
    let mut a = IRect::make_xywh(100, 100, 100, 100);
    let mut b = IRect::make_xywh(0, 0, 300, 300);

    test_not_inside(a, b);
  }
  {
    let mut a = IRect::make_maximum();
    let mut b = IRect::make_xywh(0, 0, 300, 300);

    test_inside(a, b);
  }
}

#[test]
fn rect_cut_out() {
  let mut cull_rect = Rect::make_ltrb(20.0, 20.0, 40.0, 40.0);

  let mut check_nans = |diff_rect: Rect, label: &str| {
    expect_true!(cull_rect.is_finite());
    expect_true!(diff_rect.is_finite());

    for i in 1..16 {
      // NaN in cull_rect produces empty
      expect_false!(cull_rect.swap_nan(i).cutout(&diff_rect).is_some());
      expect_eq!(cull_rect.swap_nan(i).cutout_or_empty(&diff_rect), Rect::default());

      // NaN in diff_rect is nop
      expect_true!(cull_rect.cutout(&diff_rect.swap_nan(i)).is_some());
      expect_eq!(cull_rect.cutout_or_empty(&diff_rect.swap_nan(i)), cull_rect);

      for j in 1..16 {
        // NaN in both is also empty
        expect_false!(
            cull_rect.swap_nan(i).cutout(&diff_rect.swap_nan(j)).is_some());
        expect_eq!(cull_rect.swap_nan(i).cutout_or_empty(&diff_rect.swap_nan(j)),
                  Rect::default());
      }
    }
  };

  let mut check_empty_flips = |diff_rect: Rect, label: &str| {
    expect_false!(cull_rect.is_empty());
    expect_false!(diff_rect.is_empty());

    // unflipped cull_rect vs flipped(empty) diff_rect
    // == cull_rect
    expect_true!(cull_rect.cutout(&flip_lr(diff_rect)).is_some());
    expect_eq!(cull_rect.cutout(&flip_lr(diff_rect)), cull_rect);
    expect_true!(cull_rect.cutout(&flip_tb(diff_rect)).is_some());
    expect_eq!(cull_rect.cutout(&flip_tb(diff_rect)), cull_rect);
    expect_true!(cull_rect.cutout(&flip_lrtb(diff_rect)).is_some());
    expect_eq!(cull_rect.cutout(&flip_lrtb(diff_rect)), cull_rect);

    // flipped(empty) cull_rect vs unflipped diff_rect
    // == empty
    expect_false!(flip_lr(cull_rect).cutout(&diff_rect).is_some());
    expect_eq!(flip_lr(cull_rect).cutout_or_empty(&diff_rect), Rect::default());
    expect_false!(flip_tb(cull_rect).cutout(&diff_rect).is_some());
    expect_eq!(flip_tb(cull_rect).cutout_or_empty(&diff_rect), Rect::default());
    expect_false!(flip_lrtb(cull_rect).cutout(&diff_rect).is_some());
    expect_eq!(flip_lrtb(cull_rect).cutout_or_empty(&diff_rect), Rect::default());

    // flipped(empty) cull_rect vs flipped(empty) diff_rect
    // == empty
    expect_false!(flip_lr(cull_rect).cutout(&flip_lr(diff_rect)).is_some());
    expect_eq!(flip_lr(cull_rect).cutout_or_empty(&flip_lr(diff_rect)), Rect::default());
    expect_false!(flip_tb(cull_rect).cutout(&flip_tb(diff_rect)).is_some());
    expect_eq!(flip_tb(cull_rect).cutout_or_empty(&flip_tb(diff_rect)), Rect::default());
    expect_false!(flip_lrtb(cull_rect).cutout(&flip_lrtb(diff_rect)).is_some());
    expect_eq!(flip_lrtb(cull_rect).cutout_or_empty(&flip_lrtb(diff_rect)), Rect::default());
  };

  let mut non_reducing = |diff_rect: Rect, label: &str| {
    expect_eq!(cull_rect.cutout(&diff_rect), cull_rect);
    expect_eq!(cull_rect.cutout_or_empty(&diff_rect), cull_rect);
    check_empty_flips(diff_rect, label);
    check_nans(diff_rect, label);
  };

  let mut reducing = |diff_rect: Rect, result_rect: Rect, label: &str| {
    expect_true!(!result_rect.is_empty());
    expect_eq!(cull_rect.cutout(&diff_rect), result_rect);
    expect_eq!(cull_rect.cutout_or_empty(&diff_rect), result_rect);
    check_empty_flips(diff_rect, label);
    check_nans(diff_rect, label);
  };

  let mut emptying = |diff_rect: Rect, label: &str| {
    expect_false!(cull_rect.cutout(&diff_rect).is_some());
    expect_eq!(cull_rect.cutout_or_empty(&diff_rect), Rect::default());
    check_empty_flips(diff_rect, label);
    check_nans(diff_rect, label);
  };

  // Skim the corners and edge
  non_reducing(Rect::make_ltrb(10.0, 10.0, 20.0, 20.0), "outside UL corner");
  non_reducing(Rect::make_ltrb(20.0, 10.0, 40.0, 20.0), "Above");
  non_reducing(Rect::make_ltrb(40.0, 10.0, 50.0, 20.0), "outside UR corner");
  non_reducing(Rect::make_ltrb(40.0, 20.0, 50.0, 40.0), "Right");
  non_reducing(Rect::make_ltrb(40.0, 40.0, 50.0, 50.0), "outside LR corner");
  non_reducing(Rect::make_ltrb(20.0, 40.0, 40.0, 50.0), "Below");
  non_reducing(Rect::make_ltrb(10.0, 40.0, 20.0, 50.0), "outside LR corner");
  non_reducing(Rect::make_ltrb(10.0, 20.0, 20.0, 40.0), "Left");

  // Overlap corners
  non_reducing(Rect::make_ltrb(15.0, 15.0, 25.0, 25.0), "covering UL corner");
  non_reducing(Rect::make_ltrb(35.0, 15.0, 45.0, 25.0), "covering UR corner");
  non_reducing(Rect::make_ltrb(35.0, 35.0, 45.0, 45.0), "covering LR corner");
  non_reducing(Rect::make_ltrb(15.0, 35.0, 25.0, 45.0), "covering LL corner");

  // Overlap edges, but not across an entire side
  non_reducing(Rect::make_ltrb(20.0, 15.0, 39.0, 25.0), "Top edge left-biased");
  non_reducing(Rect::make_ltrb(21.0, 15.0, 40.0, 25.0), "Top edge, right biased");
  non_reducing(Rect::make_ltrb(35.0, 20.0, 45.0, 39.0), "Right edge, top-biased");
  non_reducing(Rect::make_ltrb(35.0, 21.0, 45.0, 40.0), "Right edge, bottom-biased");
  non_reducing(Rect::make_ltrb(20.0, 35.0, 39.0, 45.0), "Bottom edge, left-biased");
  non_reducing(Rect::make_ltrb(21.0, 35.0, 40.0, 45.0), "Bottom edge, right-biased");
  non_reducing(Rect::make_ltrb(15.0, 20.0, 25.0, 39.0), "Left edge, top-biased");
  non_reducing(Rect::make_ltrb(15.0, 21.0, 25.0, 40.0), "Left edge, bottom-biased");

  // Slice all the way through the middle
  non_reducing(Rect::make_ltrb(25.0, 15.0, 35.0, 45.0), "Vertical interior slice");
  non_reducing(Rect::make_ltrb(15.0, 25.0, 45.0, 35.0), "Horizontal interior slice");

  // Slice off each edge
  reducing(Rect::make_ltrb(20.0, 15.0, 40.0, 25.0),  //
           Rect::make_ltrb(20.0, 25.0, 40.0, 40.0),  //
           "Slice off top");
  reducing(Rect::make_ltrb(35.0, 20.0, 45.0, 40.0),  //
           Rect::make_ltrb(20.0, 20.0, 35.0, 40.0),  //
           "Slice off right");
  reducing(Rect::make_ltrb(20.0, 35.0, 40.0, 45.0),  //
           Rect::make_ltrb(20.0, 20.0, 40.0, 35.0),  //
           "Slice off bottom");
  reducing(Rect::make_ltrb(15.0, 20.0, 25.0, 40.0),  //
           Rect::make_ltrb(25.0, 20.0, 40.0, 40.0),  //
           "Slice off left");

  // cull rect contains diff rect
  non_reducing(Rect::make_ltrb(21.0, 21.0, 39.0, 39.0), "Contained, non-covering");

  // cull rect equals diff rect
  emptying(cull_rect, "Perfectly covering");

  // diff rect contains cull rect
  emptying(Rect::make_ltrb(15.0, 15.0, 45.0, 45.0), "Smothering");
}

#[test]
fn i_rect_cut_out() {
  let mut cull_rect = IRect::make_ltrb(20, 20, 40, 40);

  let mut check_empty_flips = |diff_rect: IRect, label: &str| {
    expect_false!(diff_rect.is_empty());
    expect_false!(cull_rect.is_empty());

    // unflipped cull_rect vs flipped(empty) diff_rect
    // == cull_rect
    expect_true!(cull_rect.cutout(&flip_lr(diff_rect)).is_some());
    expect_eq!(cull_rect.cutout(&flip_lr(diff_rect)), cull_rect);
    expect_true!(cull_rect.cutout(&flip_tb(diff_rect)).is_some());
    expect_eq!(cull_rect.cutout(&flip_tb(diff_rect)), cull_rect);
    expect_true!(cull_rect.cutout(&flip_lrtb(diff_rect)).is_some());
    expect_eq!(cull_rect.cutout(&flip_lrtb(diff_rect)), cull_rect);

    // flipped(empty) cull_rect vs flipped(empty) diff_rect
    // == empty
    expect_false!(flip_lr(cull_rect).cutout(&diff_rect).is_some());
    expect_eq!(flip_lr(cull_rect).cutout_or_empty(&diff_rect), IRect::default());
    expect_false!(flip_tb(cull_rect).cutout(&diff_rect).is_some());
    expect_eq!(flip_tb(cull_rect).cutout_or_empty(&diff_rect), IRect::default());
    expect_false!(flip_lrtb(cull_rect).cutout(&diff_rect).is_some());
    expect_eq!(flip_lrtb(cull_rect).cutout_or_empty(&diff_rect), IRect::default());

    // flipped(empty) cull_rect vs unflipped diff_rect
    // == empty
    expect_false!(flip_lr(cull_rect).cutout(&flip_lr(diff_rect)).is_some());
    expect_eq!(flip_lr(cull_rect).cutout_or_empty(&flip_lr(diff_rect)), IRect::default());
    expect_false!(flip_tb(cull_rect).cutout(&flip_tb(diff_rect)).is_some());
    expect_eq!(flip_tb(cull_rect).cutout_or_empty(&flip_tb(diff_rect)), IRect::default());
    expect_false!(flip_lrtb(cull_rect).cutout(&flip_lrtb(diff_rect)).is_some());
    expect_eq!(flip_lrtb(cull_rect).cutout_or_empty(&flip_lrtb(diff_rect)), IRect::default());
  };

  let mut non_reducing = |diff_rect: IRect, label: &str| {
    expect_eq!(cull_rect.cutout(&diff_rect), cull_rect);
    expect_eq!(cull_rect.cutout_or_empty(&diff_rect), cull_rect);
    check_empty_flips(diff_rect, label);
  };

  let mut reducing = |diff_rect: IRect, result_rect: IRect, label: &str| {
    expect_true!(!result_rect.is_empty());
    expect_eq!(cull_rect.cutout(&diff_rect), result_rect);
    expect_eq!(cull_rect.cutout_or_empty(&diff_rect), result_rect);
    check_empty_flips(diff_rect, label);
  };

  let mut emptying = |diff_rect: IRect, label: &str| {
    expect_false!(cull_rect.cutout(&diff_rect).is_some());
    expect_eq!(cull_rect.cutout_or_empty(&diff_rect), IRect::default());
    check_empty_flips(diff_rect, label);
  };

  // Skim the corners and edge
  non_reducing(IRect::make_ltrb(10, 10, 20, 20), "outside UL corner");
  non_reducing(IRect::make_ltrb(20, 10, 40, 20), "Above");
  non_reducing(IRect::make_ltrb(40, 10, 50, 20), "outside UR corner");
  non_reducing(IRect::make_ltrb(40, 20, 50, 40), "Right");
  non_reducing(IRect::make_ltrb(40, 40, 50, 50), "outside LR corner");
  non_reducing(IRect::make_ltrb(20, 40, 40, 50), "Below");
  non_reducing(IRect::make_ltrb(10, 40, 20, 50), "outside LR corner");
  non_reducing(IRect::make_ltrb(10, 20, 20, 40), "Left");

  // Overlap corners
  non_reducing(IRect::make_ltrb(15, 15, 25, 25), "covering UL corner");
  non_reducing(IRect::make_ltrb(35, 15, 45, 25), "covering UR corner");
  non_reducing(IRect::make_ltrb(35, 35, 45, 45), "covering LR corner");
  non_reducing(IRect::make_ltrb(15, 35, 25, 45), "covering LL corner");

  // Overlap edges, but not across an entire side
  non_reducing(IRect::make_ltrb(20, 15, 39, 25), "Top edge left-biased");
  non_reducing(IRect::make_ltrb(21, 15, 40, 25), "Top edge, right biased");
  non_reducing(IRect::make_ltrb(35, 20, 45, 39), "Right edge, top-biased");
  non_reducing(IRect::make_ltrb(35, 21, 45, 40), "Right edge, bottom-biased");
  non_reducing(IRect::make_ltrb(20, 35, 39, 45), "Bottom edge, left-biased");
  non_reducing(IRect::make_ltrb(21, 35, 40, 45), "Bottom edge, right-biased");
  non_reducing(IRect::make_ltrb(15, 20, 25, 39), "Left edge, top-biased");
  non_reducing(IRect::make_ltrb(15, 21, 25, 40), "Left edge, bottom-biased");

  // Slice all the way through the middle
  non_reducing(IRect::make_ltrb(25, 15, 35, 45), "Vertical interior slice");
  non_reducing(IRect::make_ltrb(15, 25, 45, 35), "Horizontal interior slice");

  // Slice off each edge
  reducing(IRect::make_ltrb(20, 15, 40, 25),  //
           IRect::make_ltrb(20, 25, 40, 40),  //
           "Slice off top");
  reducing(IRect::make_ltrb(35, 20, 45, 40),  //
           IRect::make_ltrb(20, 20, 35, 40),  //
           "Slice off right");
  reducing(IRect::make_ltrb(20, 35, 40, 45),  //
           IRect::make_ltrb(20, 20, 40, 35),  //
           "Slice off bottom");
  reducing(IRect::make_ltrb(15, 20, 25, 40),  //
           IRect::make_ltrb(25, 20, 40, 40),  //
           "Slice off left");

  // cull rect contains diff rect
  non_reducing(IRect::make_ltrb(21, 21, 39, 39), "Contained, non-covering");

  // cull rect equals diff rect
  emptying(cull_rect, "Perfectly covering");

  // diff rect contains cull rect
  emptying(IRect::make_ltrb(15, 15, 45, 45), "Smothering");
}

#[test]
fn rect_get_points() {
  {
    let mut r = Rect::make_xywh(100.0, 200.0, 300.0, 400.0);
    let mut points = r.get_points();
    expect_point_near!(points[0], Point::new(100.0, 200.0));
    expect_point_near!(points[1], Point::new(400.0, 200.0));
    expect_point_near!(points[2], Point::new(100.0, 600.0));
    expect_point_near!(points[3], Point::new(400.0, 600.0));
  }

  {
    let mut r = Rect::make_maximum();
    let mut points = r.get_points();
    expect_eq!(points[0], Point::new(f32::MIN,
                               f32::MIN));
    expect_eq!(points[1], Point::new(f32::MAX,
                               f32::MIN));
    expect_eq!(points[2], Point::new(f32::MIN,
                               f32::MAX));
    expect_eq!(points[3], Point::new(f32::MAX,
                               f32::MAX));
  }
}

#[test]
fn rect_shift() {
  let mut r = Rect::make_ltrb(0.0, 0.0, 100.0, 100.0);

  expect_eq!(r.shift_point(Point::new(10.0, 5.0)), Rect::make_ltrb(10.0, 5.0, 110.0, 105.0));
  expect_eq!(r.shift_point(Point::new(-10.0, -5.0)), Rect::make_ltrb(-10.0, -5.0, 90.0, 95.0));
}

#[test]
fn rect_get_transformed_points() {
  let mut r = Rect::make_xywh(100.0, 200.0, 300.0, 400.0);
  let mut points = r.get_transformed_points(&Matrix::make_translation(Point::new(10.0, 20.0).into()));
  expect_point_near!(points[0], Point::new(110.0, 220.0));
  expect_point_near!(points[1], Point::new(410.0, 220.0));
  expect_point_near!(points[2], Point::new(110.0, 620.0));
  expect_point_near!(points[3], Point::new(410.0, 620.0));
}

#[test]
fn rect_make_point_bounds() {
  {
    let mut points: Vec<Point> = vec![Point::new(1.0, 5.0), Point::new(4.0, -1.0), Point::new(0.0, 6.0)];
    let mut r = Rect::make_point_bounds(&points);
    let mut expected = Rect::make_xywh(0.0, -1.0, 4.0, 7.0);
    expect_true!(r.is_some());
    if (r.is_some()) {
      expect_rect_near!(r.unwrap(), expected);
    }
  }
  {
    let mut points: Vec<Point> = Vec::new();
    let r: Option<Rect> = Rect::make_point_bounds(&points);
    expect_false!(r.is_some());
  }
}

#[test]
fn rect_get_positive() {
  {
    let mut r = Rect::make_xywh(100.0, 200.0, 300.0, 400.0);
    let mut actual = r.get_positive();
    expect_rect_near!(r, actual);
  }
  {
    let mut r = Rect::make_xywh(100.0, 200.0, -100.0, -100.0);
    let mut actual = r.get_positive();
    let mut expected = Rect::make_xywh(0.0, 100.0, 100.0, 100.0);
    expect_rect_near!(expected, actual);
  }
}

#[test]
fn rect_directions() {
  let mut r = Rect::make_ltrb(1.0, 2.0, 3.0, 4.0);

  expect_eq!(r.get_left(), 1);
  expect_eq!(r.get_top(), 2);
  expect_eq!(r.get_right(), 3);
  expect_eq!(r.get_bottom(), 4);

  expect_point_near!(r.get_left_top(), Point::new(1.0, 2.0));
  expect_point_near!(r.get_right_top(), Point::new(3.0, 2.0));
  expect_point_near!(r.get_left_bottom(), Point::new(1.0, 4.0));
  expect_point_near!(r.get_right_bottom(), Point::new(3.0, 4.0));
}

#[test]
fn rect_project() {
  {
    let mut r = Rect::make_ltrb(-100.0, -100.0, 100.0, 100.0);
    let mut actual = r.project(r);
    let mut expected = Rect::make_ltrb(0.0, 0.0, 1.0, 1.0);
    expect_rect_near!(expected, actual);
  }
  {
    let mut r = Rect::make_ltrb(-100.0, -100.0, 100.0, 100.0);
    let mut actual = r.project(Rect::make_ltrb(0.0, 0.0, 100.0, 100.0));
    let mut expected = Rect::make_ltrb(0.5, 0.5, 1.0, 1.0);
    expect_rect_near!(expected, actual);
  }
}

#[test]
fn rect_round_out() {
  {
    let mut r = Rect::make_ltrb(-100.0, -200.0, 300.0, 400.0);
    expect_eq!(Rect::round_out(&r), r);
  }
  {
    let mut r = Rect::make_ltrb(-100.1, -200.1, 300.1, 400.1);
    expect_eq!(Rect::round_out(&r), Rect::make_ltrb(-101.0, -201.0, 301.0, 401.0));
  }
}

#[test]
fn i_rect_round_out() {
  {
    let mut r = Rect::make_ltrb(-100.0, -200.0, 300.0, 400.0);
    let mut ir = IRect::make_ltrb(-100, -200, 300, 400);
    expect_eq!(IRect::round_out(&r), ir);
  }
  {
    let mut r = Rect::make_ltrb(-100.1, -200.1, 300.1, 400.1);
    let mut ir = IRect::make_ltrb(-101, -201, 301, 401);
    expect_eq!(IRect::round_out(&r), ir);
  }
}

#[test]
fn rect_round() {
  {
    let mut r = Rect::make_ltrb(-100.0, -200.0, 300.0, 400.0);
    expect_eq!(Rect::round(&r), r);
  }
  {
    let mut r = Rect::make_ltrb(-100.4, -200.4, 300.4, 400.4);
    expect_eq!(Rect::round(&r), Rect::make_ltrb(-100.0, -200.0, 300.0, 400.0));
  }
  {
    let mut r = Rect::make_ltrb(-100.5, -200.5, 300.5, 400.5);
    expect_eq!(Rect::round(&r), Rect::make_ltrb(-101.0, -201.0, 301.0, 401.0));
  }
}

#[test]
fn i_rect_round() {
  {
    let mut r = Rect::make_ltrb(-100.0, -200.0, 300.0, 400.0);
    let mut ir = IRect::make_ltrb(-100, -200, 300, 400);
    expect_eq!(IRect::round(&r), ir);
  }
  {
    let mut r = Rect::make_ltrb(-100.4, -200.4, 300.4, 400.4);
    let mut ir = IRect::make_ltrb(-100, -200, 300, 400);
    expect_eq!(IRect::round(&r), ir);
  }
  {
    let mut r = Rect::make_ltrb(-100.5, -200.5, 300.5, 400.5);
    let mut ir = IRect::make_ltrb(-101, -201, 301, 401);
    expect_eq!(IRect::round(&r), ir);
  }
}

#[test]
fn transform_and_clip_bounds_no_corners_clipped() {
  // This matrix should clip no corners.
  let mut matrix = Matrix::make_column(
      // clang-format off
      2.0f32, 0.0f32, 0.0f32, 0.0f32,
      0.0f32, 4.0f32, 0.0f32, 0.0f32,
      0.0f32, 0.0f32, 1.0f32, 0.0f32,
      0.0f32, 0.0f32, 0.0f32, 8.0f32
      // clang-format on
  );
  let mut src = Rect::make_ltrb(100.0f32, 100.0f32, 200.0f32, 200.0f32);

  // None of these should have a W<0

  expect_eq!(matrix.transform_homogenous(&src.get_left_top()),
            Vector3::new(200.0f32, 400.0f32, 8.0f32));
  expect_eq!(matrix.transform_homogenous(&src.get_right_top()),
            Vector3::new(400.0f32, 400.0f32, 8.0f32));
  expect_eq!(matrix.transform_homogenous(&src.get_left_bottom()),
            Vector3::new(200.0f32, 800.0f32, 8.0f32));
  expect_eq!(matrix.transform_homogenous(&src.get_right_bottom()),
            Vector3::new(400.0f32, 800.0f32, 8.0f32));

  let mut expect = Rect::make_ltrb(25.0f32, 50.0f32, 50.0f32, 100.0f32);
  expect_false!(src.transform_and_clip_bounds(&matrix).is_empty());
  expect_eq!(src.transform_and_clip_bounds(&matrix), expect);
}

#[test]
fn transform_and_clip_bounds_one_corner_clipped() {
  // This matrix should clip one corner.
  let mut matrix = Matrix::make_column(
      // clang-format off
      2.0f32, 0.0f32, 0.0f32, -0.01f32,
      0.0f32, 2.0f32, 0.0f32, -0.006f32,
      0.0f32, 0.0f32, 1.0f32, 0.0f32,
      0.0f32, 0.0f32, 0.0f32, 3.0f32
      // clang-format on
  );
  let mut src = Rect::make_ltrb(100.0f32, 100.0f32, 200.0f32, 200.0f32);

  // Exactly one of these should have a W<0
  //
  // When W<0 we interpolate the point back towards the adjacent points
  // that have W>0 to a location just greater than the W=0 half-plane.
  // We interpolate them to W=epsilon where epsilon == 2^-14.

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_top()),
                      Vector3::new(200.0f32, 200.0f32, 1.4f32));
  // Contributes (200, 200) / 1.4 == (142.85714, 142.85714)

  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_top()),
                      Vector3::new(400.0f32, 200.0f32, 0.4f32));
  // Contributes (400, 200) / 0.4 == (1000, 500)

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_bottom()),
                      Vector3::new(200.0f32, 400.0f32, 0.8f32));
  // Contributes (200, 400) / 0.8 == (250, 500)

  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_bottom()),
                      Vector3::new(400.0f32, 400.0f32, -0.2f32));
  // Interpolates at epsilon against RightTop to produce:
  // t = (epsilon - -.2) / (.4 - -.2)
  //   = (epsilon + .2) / .6
  //   = 0.333435
  // Lerp(RightBottom, RightTop, 0.333435) = (400, 333.313, epsilon)
  //                                       = (6553600, 5461000)
  //
  // It also interpolates at epsilon against LeftBottom to produce:
  // t = (epsilon - -.2) / (.8 - -.2)
  //   = (epsilon + .2) / 1
  //   = 0.200061
  // Lerp(RightBottom, LeftBottom, 0.200061) = (359.988, 400, epsilon)
  //                                         = (5898040, 6553600)

  // Min/Max X and Y of all the points generated above are:
  // Min X == 142.85714
  // Min Y == 142.85714
  // Max X == 6553600
  // Max Y == 6553600

  let mut expect = Rect::make_ltrb(142.85714f32, 142.85714f32, 6553600.0f32, 6553600.0f32);
  expect_false!(src.transform_and_clip_bounds(&matrix).is_empty());
  expect_rect_near!(src.transform_and_clip_bounds(&matrix), expect);
}

#[test]
fn transform_and_clip_bounds_two_corners_clipped() {
  // This matrix should clip two corners.
  let mut matrix = Matrix::make_column(
      // clang-format off
      2.0f32, 0.0f32, 0.0f32, -0.015f32,
      0.0f32, 2.0f32, 0.0f32, -0.006f32,
      0.0f32, 0.0f32, 1.0f32, 0.0f32,
      0.0f32, 0.0f32, 0.0f32, 3.0f32
      // clang-format on
  );
  let mut src = Rect::make_ltrb(100.0f32, 100.0f32, 200.0f32, 200.0f32);

  // Exactly two of these homogenous results should have a W<0
  //
  // When W<0 we interpolate the point back towards the adjacent points
  // that have W>0 to a location just greater than the W=0 half-plane.
  // We interpolate them to W=epsilon where epsilon == 2^-14.

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_top()),
                      Vector3::new(200.0f32, 200.0f32, 0.9f32));
  // Contributes (200, 200) / 0.9 == (222.2222, 222.2222) to bounds

  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_top()),
                      Vector3::new(400.0f32, 200.0f32, -0.6f32));
  // Interpolates at epsilon against LeftTop to produce:
  // t = (epsilon - -.6) / (.9 - -.6)
  //   = (epsilon + .6) / 1.5
  //   = 0.4000407
  // Lerp(RightTop, LeftTop, 0.4000407) = (319.9919, 200, epsilon)
  //                                    = (5242747, 3276800)
  // Cannot interpolate against RightBottom because it also has W<0

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_bottom()),
                      Vector3::new(200.0f32, 400.0f32, 0.3f32));
  // Contributes (200, 400) / 0.3 == (666.6667, 1333.3333) to bounds

  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_bottom()),
                      Vector3::new(400.0f32, 400.0f32, -1.2f32));
  // Interpolates at epsilon against LeftBottom to produce:
  // t = (epsilon - -1.2) / (.3 - -1.2)
  //   = (epsilon + 1.2) / 1.5
  //   = 0.8000407
  // Lerp(RightBottom, LeftBottom, 0.8000407) = (239.9919, 400, epsilon)
  //                                          = (3932026.667, 6553600)
  // Cannot interpolate against RightTop because it also has W<0

  // Min/Max X and Y of all the points generated above are:
  // Min X == 222.2222
  // Min Y == 222.2222
  // Max X == 5242747
  // Max Y == 6553600

  let mut expect = Rect::make_ltrb(222.2222f32, 222.2222f32, 5242747.0f32, 6553600.0f32);

  expect_false!(src.transform_and_clip_bounds(&matrix).is_empty());
  expect_rect_near!(src.transform_and_clip_bounds(&matrix), expect);
}

#[test]
fn transform_and_clip_bounds_three_corners_clipped() {
  // This matrix should clip three corners.
  let mut matrix = Matrix::make_column(
      // clang-format off
      2.0f32, 0.0f32, 0.0f32, -0.02f32,
      0.0f32, 2.0f32, 0.0f32, -0.006f32,
      0.0f32, 0.0f32, 1.0f32, 0.0f32,
      0.0f32, 0.0f32, 0.0f32, 3.0f32
      // clang-format on
  );
  let mut src = Rect::make_ltrb(100.0f32, 100.0f32, 200.0f32, 200.0f32);

  // Exactly three of these homogenous results should have a W<0
  //
  // When W<0 we interpolate the point back towards the adjacent points
  // that have W>0 to a location just greater than the W=0 half-plane.
  // We interpolate them to W=epsilon where epsilon == 2^-14.

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_top()),
                      Vector3::new(200.0f32, 200.0f32, 0.4f32));
  // Contributes (200, 200) / 0.4 == (500, 500) to bounds

  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_top()),
                      Vector3::new(400.0f32, 200.0f32, -1.6f32));
  // Interpolates at epsilon against LeftTop to produce:
  // t = (epsilon - -1.6) / (.4 - -1.6)
  //   = (epsilon + 1.6) / 2
  //   = 0.8000305
  // Lerp(RightTop, LeftTop, 0.8000305) = (239.9939, 200, epsilon)
  //                                    = (3932060, 3276800)
  // Cannot interpolate against RightBottom because it also has W<0

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_bottom()),
                      Vector3::new(200.0f32, 400.0f32, -0.2f32));
  // Interpolates against LeftTop to produce:
  // t = (epsilon - -.2) / (.4 - -.2)
  //   = (epsilon + .2) / .6
  //   = 0.333435
  // Lerp(LeftBottom, LeftTop, .333435) = (200, 333.31299, epsilon)
  //                                    = (3276800, 5461000)
  // Cannot interpolate against RightBottom because it also has W<0

  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_bottom()),
                      Vector3::new(400.0f32, 400.0f32, -2.2f32));
  // Cannot interpolate against either RightTop or LeftBottom because
  // both of those adjacent points transformed to a W<0 homogenous point.

  // Min/Max X and Y of all the points generated above are:
  // Min X == 500
  // Min Y == 500
  // Max X == 3932060
  // Max Y == 5461000

  let mut expect = Rect::make_ltrb(500.0f32, 500.0f32, 3932060.0f32, 5461000.0f32);

  expect_false!(src.transform_and_clip_bounds(&matrix).is_empty());
  expect_rect_near!(src.transform_and_clip_bounds(&matrix), expect);
}

#[test]
fn transform_and_clip_bounds_all_four_corners_clipped() {
  // This matrix should clip all four corners.
  let mut matrix = Matrix::make_column(
      // clang-format off
      2.0f32, 0.0f32, 0.0f32, -0.025f32,
      0.0f32, 2.0f32, 0.0f32, -0.006f32,
      0.0f32, 0.0f32, 1.0f32, 0.0f32,
      0.0f32, 0.0f32, 0.0f32, 3.0f32
      // clang-format on
  );
  let mut src = Rect::make_ltrb(100.0f32, 100.0f32, 200.0f32, 200.0f32);

  // All of these should have a W<0
  //
  // When W<0 we interpolate the point back towards the adjacent points
  // that have W>0 to a location just greater than the W=0 half-plane.
  // We interpolate them to W=epsilon where epsilon == 2^-14.

  // In this case, none of the homogenous results are in bounds (W > 0)
  // so we can perform no interpolation - the operation is not visible.

  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_top()),
                      Vector3::new(200.0f32, 200.0f32, -0.1f32));
  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_top()),
                      Vector3::new(400.0f32, 200.0f32, -2.6f32));
  expect_vector3_near!(matrix.transform_homogenous(&src.get_left_bottom()),
                      Vector3::new(200.0f32, 400.0f32, -0.7f32));
  expect_vector3_near!(matrix.transform_homogenous(&src.get_right_bottom()),
                      Vector3::new(400.0f32, 400.0f32, -3.2f32));

  expect_true!(src.transform_and_clip_bounds(&matrix).is_empty());
}

