// flutter/impeller/geometry/rounding_radii_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn rounding_radii_empty_declaration() {
  let mut radii = RoundingRadii::default();

  expect_true!(radii.are_all_corners_empty());
  expect_true!(radii.are_all_corners_same());
  expect_true!(radii.are_all_corners_circular());
  expect_true!(radii.is_finite());
  expect_eq!(radii.top_left, Size::default());
  expect_eq!(radii.top_right, Size::default());
  expect_eq!(radii.bottom_left, Size::default());
  expect_eq!(radii.bottom_right, Size::default());
  expect_eq!(radii.top_left.width, 0.0f32);
  expect_eq!(radii.top_left.height, 0.0f32);
  expect_eq!(radii.top_right.width, 0.0f32);
  expect_eq!(radii.top_right.height, 0.0f32);
  expect_eq!(radii.bottom_left.width, 0.0f32);
  expect_eq!(radii.bottom_left.height, 0.0f32);
  expect_eq!(radii.bottom_right.width, 0.0f32);
  expect_eq!(radii.bottom_right.height, 0.0f32);
}

#[test]
fn rounding_radii_default_constructor() {
  let mut radii = RoundingRadii::default();

  expect_true!(radii.are_all_corners_empty());
  expect_true!(radii.are_all_corners_same());
  expect_true!(radii.are_all_corners_circular());
  expect_true!(radii.is_finite());
  expect_eq!(radii.top_left, Size::default());
  expect_eq!(radii.top_right, Size::default());
  expect_eq!(radii.bottom_left, Size::default());
  expect_eq!(radii.bottom_right, Size::default());
}

#[test]
fn rounding_radii_scalar_constructor() {
  let mut radii = RoundingRadii::make_radius(5.0f32);

  expect_false!(radii.are_all_corners_empty());
  expect_true!(radii.are_all_corners_same());
  expect_true!(radii.are_all_corners_circular());
  expect_true!(radii.is_finite());
  expect_eq!(radii.top_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(radii.top_right, Size::new(5.0f32, 5.0f32));
  expect_eq!(radii.bottom_left, Size::new(5.0f32, 5.0f32));
  expect_eq!(radii.bottom_right, Size::new(5.0f32, 5.0f32));
}

#[test]
fn rounding_radii_empty_scalar_constructor() {
  let mut radii = RoundingRadii::make_radius(-5.0f32);

  expect_true!(radii.are_all_corners_empty());
  expect_true!(radii.are_all_corners_same());
  expect_true!(radii.are_all_corners_circular());
  expect_true!(radii.is_finite());
  expect_eq!(radii.top_left, Size::new(-5.0f32, -5.0f32));
  expect_eq!(radii.top_right, Size::new(-5.0f32, -5.0f32));
  expect_eq!(radii.bottom_left, Size::new(-5.0f32, -5.0f32));
  expect_eq!(radii.bottom_right, Size::new(-5.0f32, -5.0f32));
}

#[test]
fn rounding_radii_size_constructor() {
  let mut radii = RoundingRadii::make_radii(Size::new(5.0f32, 6.0f32));

  expect_false!(radii.are_all_corners_empty());
  expect_true!(radii.are_all_corners_same());
  expect_false!(radii.are_all_corners_circular());
  expect_true!(radii.is_finite());
  expect_eq!(radii.top_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(radii.top_right, Size::new(5.0f32, 6.0f32));
  expect_eq!(radii.bottom_left, Size::new(5.0f32, 6.0f32));
  expect_eq!(radii.bottom_right, Size::new(5.0f32, 6.0f32));
}

#[test]
fn rounding_radii_empty_size_constructor() {
  {
    let mut radii = RoundingRadii::make_radii(Size::new(-5.0f32, 6.0f32));

    expect_true!(radii.are_all_corners_empty());
    expect_true!(radii.are_all_corners_same());
    expect_false!(radii.are_all_corners_circular());
    expect_true!(radii.is_finite());
    expect_eq!(radii.top_left, Size::new(-5.0f32, 6.0f32));
    expect_eq!(radii.top_right, Size::new(-5.0f32, 6.0f32));
    expect_eq!(radii.bottom_left, Size::new(-5.0f32, 6.0f32));
    expect_eq!(radii.bottom_right, Size::new(-5.0f32, 6.0f32));
  }

  {
    let mut radii = RoundingRadii::make_radii(Size::new(5.0f32, -6.0f32));

    expect_true!(radii.are_all_corners_empty());
    expect_true!(radii.are_all_corners_same());
    expect_false!(radii.are_all_corners_circular());
    expect_true!(radii.is_finite());
    expect_eq!(radii.top_left, Size::new(5.0f32, -6.0f32));
    expect_eq!(radii.top_right, Size::new(5.0f32, -6.0f32));
    expect_eq!(radii.bottom_left, Size::new(5.0f32, -6.0f32));
    expect_eq!(radii.bottom_right, Size::new(5.0f32, -6.0f32));
  }
}

#[test]
fn rounding_radii_named_sizes_constructor() {
  let mut radii = RoundingRadii {
      top_left: Size::new(5.0f32, 5.5f32),
      top_right: Size::new(6.0f32, 6.5f32),
      bottom_left: Size::new(7.0f32, 7.5f32),
      bottom_right: Size::new(8.0f32, 8.5f32),
    ..Default::default()
  };

  expect_false!(radii.are_all_corners_empty());
  expect_false!(radii.are_all_corners_same());
  expect_false!(radii.are_all_corners_circular());
  expect_true!(radii.is_finite());
  expect_eq!(radii.top_left, Size::new(5.0f32, 5.5f32));
  expect_eq!(radii.top_right, Size::new(6.0f32, 6.5f32));
  expect_eq!(radii.bottom_left, Size::new(7.0f32, 7.5f32));
  expect_eq!(radii.bottom_right, Size::new(8.0f32, 8.5f32));
}

#[test]
fn rounding_radii_partial_named_sizes_constructor() {
  {
    let mut radii = RoundingRadii {
        top_left: Size::new(5.0f32, 5.5f32),
      ..Default::default()
    };

    expect_false!(radii.are_all_corners_empty());
    expect_false!(radii.are_all_corners_same());
    expect_false!(radii.are_all_corners_circular());
    expect_true!(radii.is_finite());
    expect_eq!(radii.top_left, Size::new(5.0f32, 5.5f32));
    expect_eq!(radii.top_right, Size::default());
    expect_eq!(radii.bottom_left, Size::default());
    expect_eq!(radii.bottom_right, Size::default());
  }

  {
    let mut radii = RoundingRadii {
        top_right: Size::new(6.0f32, 6.5f32),
        ..Default::default()
    };

    expect_false!(radii.are_all_corners_empty());
    expect_false!(radii.are_all_corners_same());
    expect_false!(radii.are_all_corners_circular());
    expect_true!(radii.is_finite());
    expect_eq!(radii.top_left, Size::default());
    expect_eq!(radii.top_right, Size::new(6.0f32, 6.5f32));
    expect_eq!(radii.bottom_left, Size::default());
    expect_eq!(radii.bottom_right, Size::default());
  }

  {
    let mut radii = RoundingRadii {
        bottom_left: Size::new(7.0f32, 7.5f32),
        ..Default::default()
    };

    expect_false!(radii.are_all_corners_empty());
    expect_false!(radii.are_all_corners_same());
    expect_false!(radii.are_all_corners_circular());
    expect_true!(radii.is_finite());
    expect_eq!(radii.top_left, Size::default());
    expect_eq!(radii.top_right, Size::default());
    expect_eq!(radii.bottom_left, Size::new(7.0f32, 7.5f32));
    expect_eq!(radii.bottom_right, Size::default());
  }

  {
    let mut radii = RoundingRadii {
        bottom_right: Size::new(8.0f32, 8.5f32),
        ..Default::default()
    };

    expect_false!(radii.are_all_corners_empty());
    expect_false!(radii.are_all_corners_same());
    expect_false!(radii.are_all_corners_circular());
    expect_true!(radii.is_finite());
    expect_eq!(radii.top_left, Size::default());
    expect_eq!(radii.top_right, Size::default());
    expect_eq!(radii.bottom_left, Size::default());
    expect_eq!(radii.bottom_right, Size::new(8.0f32, 8.5f32));
  }
}

#[test]
fn rounding_radii_multiply() {
  let mut radii = RoundingRadii {
      top_left: Size::new(5.0f32, 5.5f32),
      top_right: Size::new(6.0f32, 6.5f32),
      bottom_left: Size::new(7.0f32, 7.5f32),
      bottom_right: Size::new(8.0f32, 8.5f32),
    ..Default::default()
  };
  let mut doubled = radii * 2.0f32;

  expect_false!(doubled.are_all_corners_empty());
  expect_false!(doubled.are_all_corners_same());
  expect_false!(doubled.are_all_corners_circular());
  expect_true!(doubled.is_finite());
  expect_eq!(doubled.top_left, Size::new(10.0f32, 11.0f32));
  expect_eq!(doubled.top_right, Size::new(12.0f32, 13.0f32));
  expect_eq!(doubled.bottom_left, Size::new(14.0f32, 15.0f32));
  expect_eq!(doubled.bottom_right, Size::new(16.0f32, 17.0f32));
}

#[test]
fn rounding_radii_equals() {
  let mut radii = RoundingRadii {
      top_left: Size::new(5.0f32, 5.5f32),
      top_right: Size::new(6.0f32, 6.5f32),
      bottom_left: Size::new(7.0f32, 7.5f32),
      bottom_right: Size::new(8.0f32, 8.5f32),
    ..Default::default()
  };
  let mut other = RoundingRadii {
      top_left: Size::new(5.0f32, 5.5f32),
      top_right: Size::new(6.0f32, 6.5f32),
      bottom_left: Size::new(7.0f32, 7.5f32),
      bottom_right: Size::new(8.0f32, 8.5f32),
    ..Default::default()
  };

  expect_eq!(radii, other);
}

#[test]
fn rounding_radii_not_equals() {
  let mut radii = RoundingRadii {
      top_left: Size::new(5.0f32, 5.5f32),
      top_right: Size::new(6.0f32, 6.5f32),
      bottom_left: Size::new(7.0f32, 7.5f32),
      bottom_right: Size::new(8.0f32, 8.5f32),
    ..Default::default()
  };

  {
    let mut different = radii;
    different.top_left.width = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.top_left.height = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.top_right.width = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.top_right.height = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.bottom_left.width = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.bottom_left.height = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.bottom_right.width = 100.0f32;
    expect_ne!(different, radii);
  }
  {
    let mut different = radii;
    different.bottom_right.height = 100.0f32;
    expect_ne!(different, radii);
  }
}

#[test]
fn rounding_radii_corners_same_tolerance() {
  let mut radii = RoundingRadii {
      top_left: Size::new(10.0, 20.0),
      top_right: Size::new(10.01, 20.01),
      bottom_left: Size::new(9.99, 19.99),
      bottom_right: Size::new(9.99, 20.01),
    ..Default::default()
  };

  expect_true!(radii.are_all_corners_same_tol(0.02));

  {
    let mut different = radii;
    different.top_left.width = 10.03f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.top_left.height = 20.03f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.top_right.width = 10.03f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.top_right.height = 20.03f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.bottom_left.width = 9.97f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.bottom_left.height = 19.97f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.bottom_right.width = 9.97f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
  {
    let mut different = radii;
    different.bottom_right.height = 20.03f32;
    expect_false!(different.are_all_corners_same_tol(0.02));
  }
}

