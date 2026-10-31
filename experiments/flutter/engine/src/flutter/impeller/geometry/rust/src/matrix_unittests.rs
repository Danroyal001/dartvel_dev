// flutter/impeller/geometry/matrix_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use std::cmp::max;
use crate::prelude::*;
use crate::*;

#[test]
fn multiply() {
  let x = Matrix::new(0.0, 0.0, 0.0, 1.0,  //
           1.0, 0.0, 0.0, 1.0,  //
           0.0, 1.0, 0.0, 1.0,  //
           1.0, 1.0, 0.0, 1.0);
  let mut translate = Matrix::make_translation(Vector3::new(10.0, 20.0, 0.0));
  let mut result = translate * x;
  expect_true!(matrix_near(result, Matrix::new(10.0, 20.0, 0.0, 1.0,  //
                                        11.0, 20.0, 0.0, 1.0,  //
                                        10.0, 21.0, 0.0, 1.0,  //
                                        11.0, 21.0, 0.0, 1.0)));
}

#[test]
fn equals() {
  let mut x = Matrix::default();
  let mut y = x;
  expect_true!(x.equals(&y));
}

#[test]
fn not_equals() {
  let mut x = Matrix::default();
  let mut y = x.translate(&Vector3::new(1.0, 0.0, 0.0));
  expect_false!(x.equals(&y));
}

#[test]
fn has_perspective_2d() {
  expect_false!(Matrix::default().has_perspective_2d());

  let mut test = |index: usize, expect: bool| {
    let mut matrix = Matrix::default();
    expect_false!(matrix.has_perspective_2d());
    matrix.m[index] = 0.5f32;
    expect_eq!(matrix.has_perspective_2d(), expect);
  };

  // clang-format off
  test( 0, false);  test( 1, false);  test( 2, false);  test( 3, true);
  test( 4, false);  test( 5, false);  test( 6, false);  test( 7, true);
  test( 8, false);  test( 9, false);  test(10, false);  test(11, false);
  test(12, false);  test(13, false);  test(14, false);  test(15, true);
  // clang-format on
}

#[test]
fn has_perspective() {
  expect_false!(Matrix::default().has_perspective());

  let mut test = |index: usize, expect: bool| {
    let mut matrix = Matrix::default();
    expect_false!(matrix.has_perspective());
    matrix.m[index] = 0.5f32;
    expect_eq!(matrix.has_perspective(), expect);
  };

  // clang-format off
  test( 0, false);  test( 1, false);  test( 2, false);  test( 3, true);
  test( 4, false);  test( 5, false);  test( 6, false);  test( 7, true);
  test( 8, false);  test( 9, false);  test(10, false);  test(11, true);
  test(12, false);  test(13, false);  test(14, false);  test(15, true);
  // clang-format on
}

#[test]
fn has_translation() {
  expect_true!(Matrix::make_translation(Vector3::new(100.0, 100.0, 0.0)).has_translation());
  expect_true!(Matrix::make_translation(Vector3::new(0.0, 100.0, 0.0)).has_translation());
  expect_true!(Matrix::make_translation(Vector3::new(100.0, 0.0, 0.0)).has_translation());
  expect_false!(Matrix::default().has_translation());
}

#[test]
fn is_translation_only() {
  expect_true!(Matrix::make_translation(Vector3::new(100.0, 100.0, 0.0)).is_translation_only());
  expect_true!(Matrix::make_translation(Vector3::new(100.0, 100.0, 0.0)).is_translation_scale_only());
  expect_true!(Matrix::make_translation(Vector3::new(0.0, 100.0, 0.0)).is_translation_only());
  expect_true!(Matrix::make_translation(Vector3::new(0.0, 100.0, 0.0)).is_translation_scale_only());
  expect_true!(Matrix::make_translation(Vector3::new(100.0, 0.0, 0.0)).is_translation_only());
  expect_true!(Matrix::make_translation(Vector3::new(100.0, 0.0, 0.0)).is_translation_scale_only());
  expect_true!(Matrix::default().is_translation_only());
  expect_true!(Matrix::default().is_translation_scale_only());
}

#[test]
fn is_translation_scale_only() {
  expect_false!(Matrix::make_scale(Vector3::new(100.0, 100.0, 1.0)).is_translation_only());
  expect_true!(Matrix::make_scale(Vector3::new(100.0, 100.0, 1.0)).is_translation_scale_only());
  expect_false!(Matrix::make_scale(Vector3::new(1.0, 100.0, 1.0)).is_translation_only());
  expect_true!(Matrix::make_scale(Vector3::new(1.0, 100.0, 1.0)).is_translation_scale_only());
  expect_false!(Matrix::make_scale(Vector3::new(100.0, 1.0, 1.0)).is_translation_only());
  expect_true!(Matrix::make_scale(Vector3::new(100.0, 1.0, 1.0)).is_translation_scale_only());
  expect_true!(Matrix::default().is_translation_only());
  expect_true!(Matrix::default().is_translation_scale_only());
}

#[test]
fn is_invertible_get_determinant() {
  expect_true!(Matrix::default().is_invertible());
  expect_ne!(Matrix::default().get_determinant(), 0.0f32);

  expect_true!(Matrix::make_translation(Vector3::new(100.0, 100.0, 0.0)).is_invertible());
  expect_ne!(Matrix::make_translation(Vector3::new(100.0, 100.0, 0.0)).get_determinant(), 0.0f32);

  expect_true!(Matrix::make_scale(Vector3::new(100.0, 100.0, 1.0)).is_invertible());
  expect_ne!(Matrix::make_scale(Vector3::new(100.0, 100.0, 1.0)).get_determinant(), 0.0f32);

  expect_true!(Matrix::make_rotation_x(Radians::from(Degrees::new(30.0))).is_invertible());
  expect_ne!(Matrix::make_rotation_x(Radians::from(Degrees::new(30.0))).get_determinant(), 0.0f32);

  expect_true!(Matrix::make_rotation_y(Radians::from(Degrees::new(30.0))).is_invertible());
  expect_ne!(Matrix::make_rotation_y(Radians::from(Degrees::new(30.0))).get_determinant(), 0.0f32);

  expect_true!(Matrix::make_rotation_z(Radians::from(Degrees::new(30.0))).is_invertible());
  expect_ne!(Matrix::make_rotation_z(Radians::from(Degrees::new(30.0))).get_determinant(), 0.0f32);

  expect_false!(Matrix::make_scale(Vector3::new(0.0, 1.0, 1.0)).is_invertible());
  expect_eq!(Matrix::make_scale(Vector3::new(0.0, 1.0, 1.0)).get_determinant(), 0.0f32);
  expect_false!(Matrix::make_scale(Vector3::new(1.0, 0.0, 1.0)).is_invertible());
  expect_eq!(Matrix::make_scale(Vector3::new(1.0, 0.0, 1.0)).get_determinant(), 0.0f32);
  expect_false!(Matrix::make_scale(Vector3::new(1.0, 1.0, 0.0)).is_invertible());
  expect_eq!(Matrix::make_scale(Vector3::new(1.0, 1.0, 0.0)).get_determinant(), 0.0f32);
}

#[test]
fn is_finite() {
  expect_true!(Matrix::default().is_finite());

  expect_true!(Matrix::make_translation(Vector3::new(100.0, 100.0, 0.0)).is_finite());
  expect_true!(Matrix::make_scale(Vector3::new(100.0, 100.0, 1.0)).is_finite());

  expect_true!(Matrix::make_rotation_x(Radians::from(Degrees::new(30.0))).is_finite());
  expect_true!(Matrix::make_rotation_y(Radians::from(Degrees::new(30.0))).is_finite());
  expect_true!(Matrix::make_rotation_z(Radians::from(Degrees::new(30.0))).is_finite());

  expect_true!(Matrix::make_scale(Vector3::new(0.0, 1.0, 1.0)).is_finite());
  expect_true!(Matrix::make_scale(Vector3::new(1.0, 0.0, 1.0)).is_finite());
  expect_true!(Matrix::make_scale(Vector3::new(1.0, 1.0, 0.0)).is_finite());

  for i in 0..16 {
    {
      let mut matrix = Matrix::default();
      expect_true!(matrix.is_finite());
      matrix.m[i] = f32::INFINITY;
      expect_false!(matrix.is_finite());
    }

    {
      let mut matrix = Matrix::default();
      expect_true!(matrix.is_finite());
      matrix.m[i] = -f32::INFINITY;
      expect_false!(matrix.is_finite());
    }

    {
      let mut matrix = Matrix::default();
      expect_true!(matrix.is_finite());
      matrix.m[i] = -f32::NAN;
      expect_false!(matrix.is_finite());
    }
  }
}

#[test]
fn is_aligned_2d() {
  expect_true!(Matrix::default().is_aligned_2d());
  expect_true!(Matrix::make_scale(Vector3::new(1.0, 1.0, 2.0)).is_aligned_2d());

  let mut test = |index: usize, expect: bool| {
    let mut matrix = Matrix::default();
    expect_true!(matrix.is_aligned_2d());
    matrix.m[index] = 0.5f32;
    expect_eq!(matrix.is_aligned_2d(), expect);
  };

  // clang-format off
  test( 0, true);   test( 1, false);  test( 2, true);   test( 3, false);
  test( 4, false);  test( 5, true);   test( 6, true);   test( 7, false);
  test( 8, true);   test( 9, true);   test(10, true);   test(11, true);
  test(12, true);   test(13, true);   test(14, true);   test(15, false);
  // clang-format on

  // True for quadrant rotations from -250 to +250 full circles
  for i in -1000..1000 {
    let mut d = Degrees::new(i as f32 * 90.0);
    let mut matrix = Matrix::make_rotation_z(Radians::from(d));
    expect_true!(matrix.is_aligned_2d());
  }

  // False for half degree rotations from -999.5 to +1000.5 degrees
  for i in -1000..1000 {
    let mut d = Degrees::new(i as f32 + 0.5);
    let mut matrix = Matrix::make_rotation_z(Radians::from(d));
    expect_false!(matrix.is_aligned_2d());
  }
}

#[test]
fn is_aligned() {
  expect_true!(Matrix::default().is_aligned());
  expect_true!(Matrix::make_scale(Vector3::new(1.0, 1.0, 2.0)).is_aligned());

  // Begin Legacy tests transferred over from geometry_unittests.cc
  {
    let mut m = Matrix::make_translation(Vector3::new(1.0, 2.0, 3.0));
    let mut result = m.is_aligned();
    expect_true!(result);
  }

  {
    let mut m = Matrix::make_rotation_z(Radians::from(Degrees::new(123.0)));
    let mut result = m.is_aligned();
    expect_false!(result);
  }
  // End Legacy tests transferred over from geometry_unittests.cc

  let mut test = |index: usize, expect: bool| {
    let mut matrix = Matrix::default();
    expect_true!(matrix.is_aligned());
    matrix.m[index] = 0.5f32;
    expect_eq!(matrix.is_aligned(), expect);
  };

  // clang-format off
  test( 0, true);   test( 1, false);  test( 2, false);  test( 3, false);
  test( 4, false);  test( 5, true);   test( 6, false);  test( 7, false);
  test( 8, false);  test( 9, false);  test(10, true);   test(11, false);
  test(12, true);   test(13, true);   test(14, true);   test(15, false);
  // clang-format on

  // True for quadrant rotations from -250 to +250 full circles
  for i in -1000..1000 {
    let mut d = Degrees::new(i as f32 * 90.0);
    let mut matrix = Matrix::make_rotation_z(Radians::from(d));
    expect_true!(matrix.is_aligned());
  }

  // False for half degree rotations from -999.5 to +1000.5 degrees
  for i in -1000..1000 {
    let mut d = Degrees::new(i as f32 + 0.5);
    let mut matrix = Matrix::make_rotation_z(Radians::from(d));
    expect_false!(matrix.is_aligned());
  }
}

#[test]
fn transform_homogenous() {
  let mut matrix = Matrix::make_column(
      // clang-format off
       2.0f32,  3.0f32,  5.0f32,  7.0f32,
      11.0f32, 13.0f32, 17.0f32, 19.0f32,
      23.0f32, 29.0f32, 31.0f32, 37.0f32,
      41.0f32, 43.0f32, 47.0f32, 53.0f32
      // clang-format on
  );
  expect_eq!(matrix.transform_homogenous(&Point::new(1.0, -1.0)),
            Vector3::new(32.0f32, 33.0f32, 41.0f32));
}

#[test]
fn get_max_basis_xy_negative_scale() {
  let mut m = Matrix::make_scale(Vector3::new(-2.0, 1.0, 1.0));

  expect_eq!(m.get_max_basis_length_xy(), 2);

  m = Matrix::make_scale(Vector3::new(1.0, -3.0, 1.0));

  expect_eq!(m.get_max_basis_length_xy(), 3);
}

#[test]
fn get_max_basis_xy_with_large_and_small_scaling_factor() {
  let mut m = Matrix::make_scale(Vector3::new(2.625e+20, 2.625e+20, 1.0));
  expect_near!(m.get_max_basis_length_xy(), 2.625e+20, 1e+20);

  m = Matrix::make_scale(Vector3::new(2.625e-20, 2.625e-20, 1.0));
  expect_near!(m.get_max_basis_length_xy(), 2.625e-20, 1e-20);
}

#[test]
fn get_max_basis_xy_with_large_and_small_scaling_factor_non_scale_translate() {
  let mut m = Matrix::make_scale(Vector3::new(2.625e+20, 2.625e+20, 1.0));
  *m.e_mut(0, 1) = 2 as f32;

  expect_true!((m.get_max_basis_length_xy()).is_infinite());
}

#[test]
fn get_basis_xy_scale_2d() {
  let mut m = Matrix::make_scale(Vector3::new(5.0, 3.0, 1.0));
  expect_point_near!(m.get_basis_x_2d(), Vector2::new(5.0f32, 0.0f32));
  expect_point_near!(m.get_basis_y_2d(), Vector2::new(0.0f32, 3.0f32));
  expect_point_near!(m.get_basis_scale_xy(), Vector2::new(5.0f32, 3.0f32));

  let mut m2 = Matrix::make_column(
      // clang-format off
      2.0f32, 3.0f32, 0.0f32, 0.0f32,
      5.0f32, 7.0f32, 0.0f32, 0.0f32,
      0.0f32, 0.0f32, 1.0f32, 0.0f32,
      0.0f32, 0.0f32, 0.0f32, 1.0f32
      // clang-format on
  );
  expect_point_near!(m2.get_basis_x_2d(), Vector2::new(2.0f32, 3.0f32));
  expect_point_near!(m2.get_basis_y_2d(), Vector2::new(5.0f32, 7.0f32));
  expect_point_near!(m2.get_basis_scale_xy(), Vector2::new(13.0f32.sqrt(), 74.0f32.sqrt()));

  let mut m3 = Matrix::make_column(
      // clang-format off
      2.0f32, 3.0f32, 4.0f32, 11.0f32,
      5.0f32, 7.0f32, 6.0f32, 13.0f32,
      1.0f32, 8.0f32, 9.0f32, 15.0f32,
      1.0f32, 1.0f32, 1.0f32, 17.0f32
      // clang-format on
  );
  expect_point_near!(m3.get_basis_x_2d(), Vector2::new(2.0f32, 3.0f32));
  expect_point_near!(m3.get_basis_y_2d(), Vector2::new(5.0f32, 7.0f32));
  expect_point_near!(m2.get_basis_scale_xy(), Vector2::new(13.0f32.sqrt(), 74.0f32.sqrt()));
}

#[test]
fn translate_with_perspective() {
  let mut m = Matrix::make_row(1.0, 0.0, 0.0, 10.0,  //
                             0.0, 1.0, 0.0, 20.0,  //
                             0.0, 0.0, 1.0, 0.0,   //
                             0.0, 2.0, 0.0, 30.0);
  let mut result = m.translate(&Vector3::from(Point::new(100.0, 200.0)));
  expect_true!(matrix_near(result, Matrix::make_row(1.0, 0.0, 0.0, 110.0,  //
                                                 0.0, 1.0, 0.0, 220.0,  //
                                                 0.0, 0.0, 1.0, 0.0,    //
                                                 0.0, 2.0, 0.0, 430.0)));
}

#[test]
fn make_scale_translate() {
  expect_true!(matrix_near(
      Matrix::make_translate_scale(Vector3::new(1.0, 1.0, 1.0 / 1024.0), Vector3::new(10.0, 10.0, 1.0 / 1024.0)),
      Matrix::make_translation(Vector3::new(10.0, 10.0, 1.0 / 1024.0)) *
          Matrix::make_scale(Vector3::new(1.0, 1.0, 1.0 / 1024.0))));

  expect_true!(matrix_near(
      Matrix::make_translate_scale(Vector3::new(2.0, 2.0, 2.0), Vector3::new(10.0, 10.0, 0.0)),
      Matrix::make_translation(Vector3::new(10.0, 10.0, 0.0)) * Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0))));

  expect_true!(matrix_near(
      Matrix::make_translate_scale(Vector3::new(0.0, 0.0, 0.0), Vector3::new(0.0, 0.0, 0.0)),
      Matrix::make_translation(Vector3::new(0.0, 0.0, 0.0)) * Matrix::make_scale(Vector3::new(0.0, 0.0, 0.0))));
}

#[test]
fn to3x3() {
  let x = Matrix::new(1.0, 0.0, 4.0, 0.0,    //
           0.0, 1.0, 4.0, 0.0,    //
           6.0, 5.0, 111.0, 7.0,  //
           0.0, 0.0, 9.0, 1.0);

  expect_true!(matrix_near(x.to3x3(), Matrix::default()));
}

#[test]
fn min_max_scales_2d() {
  // The GetScales2D() method is allowed to return the scales in any
  // order so we need to take special care in verifying the return
  // value to test them in either order.
  let mut check_pair = |matrix: Matrix, scale1: Scalar, scale2: Scalar| {
    let mut pair = matrix.get_scales_2d();
    expect_true!(pair.is_some());
    if (scalar_nearly_equal(pair.unwrap().0, scale1)) {
      expect_float_eq!(pair.unwrap().0, scale1);
      expect_float_eq!(pair.unwrap().1, scale2);
    } else {
      expect_float_eq!(pair.unwrap().0, scale2);
      expect_float_eq!(pair.unwrap().1, scale1);
    }
  };

  for i in 1..10 {
    let mut xScale = (i as Scalar);
    for j in 1..10 {
      let mut yScale = (j as Scalar);
      let mut minScale = cxx::min(xScale, yScale);
      let mut maxScale = cxx::max(xScale, yScale);

      {
        // Simple scale
        let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32));
        expect_true!(matrix.get_min_scale_2d().is_some());
        expect_true!(matrix.get_max_scale_2d().is_some());
        expect_float_eq!(matrix.get_min_scale_2d().unwrap_or(-1.0f32), minScale);
        expect_float_eq!(matrix.get_max_scale_2d().unwrap_or(-1.0f32), maxScale);
        check_pair(matrix, xScale, yScale);
      }

      {
        // Simple scale with Z scale
        let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 5.0f32));
        expect_true!(matrix.get_min_scale_2d().is_some());
        expect_true!(matrix.get_max_scale_2d().is_some());
        expect_float_eq!(matrix.get_min_scale_2d().unwrap_or(-1.0f32), minScale);
        expect_float_eq!(matrix.get_max_scale_2d().unwrap_or(-1.0f32), maxScale);
        check_pair(matrix, xScale, yScale);
      }

      {
        // Simple scale + translate
        let mut matrix = Matrix::make_translate_scale(Vector3::new(xScale, yScale, 1.0f32),
                                                   Vector3::new(10.0, 15.0, 2.0));
        expect_true!(matrix.get_min_scale_2d().is_some());
        expect_true!(matrix.get_max_scale_2d().is_some());
        expect_float_eq!(matrix.get_min_scale_2d().unwrap_or(-1.0f32), minScale);
        expect_float_eq!(matrix.get_max_scale_2d().unwrap_or(-1.0f32), maxScale);
        check_pair(matrix, xScale, yScale);
      }

      for d in (45..360).step_by(45) {
        {
          // Rotation * Scale
          let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32)) *
                          Matrix::make_rotation_z(Radians::from(Degrees::new(d as f32)));
          expect_true!(matrix.get_min_scale_2d().is_some());
          expect_true!(matrix.get_max_scale_2d().is_some());
          expect_float_eq!(matrix.get_min_scale_2d().unwrap_or(-1.0f32), minScale);
          expect_float_eq!(matrix.get_max_scale_2d().unwrap_or(-1.0f32), maxScale);
          check_pair(matrix, xScale, yScale);
        }

        {
          // Scale * Rotation
          let mut matrix = Matrix::make_rotation_z(Radians::from(Degrees::new(d as f32))) *
                          Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32));
          expect_true!(matrix.get_min_scale_2d().is_some());
          expect_true!(matrix.get_max_scale_2d().is_some());
          expect_float_eq!(matrix.get_min_scale_2d().unwrap_or(-1.0f32), minScale);
          expect_float_eq!(matrix.get_max_scale_2d().unwrap_or(-1.0f32), maxScale);
          check_pair(matrix, xScale, yScale);
        }
      }

      {
        // Scale + PerspectiveX (returns invalid values)
        let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32));
        matrix.m[3] = 0.1;
        expect_false!(matrix.get_min_scale_2d().is_some());
        expect_false!(matrix.get_max_scale_2d().is_some());
        expect_false!(matrix.get_scales_2d().is_some());
      }

      {
        // Scale + PerspectiveY (returns invalid values)
        let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32));
        matrix.m[7] = 0.1;
        expect_false!(matrix.get_min_scale_2d().is_some());
        expect_false!(matrix.get_max_scale_2d().is_some());
        expect_false!(matrix.get_scales_2d().is_some());
      }

      {
        // Scale + PerspectiveZ (Z ignored; returns actual scales)
        let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32));
        matrix.m[11] = 0.1;
        expect_true!(matrix.get_min_scale_2d().is_some());
        expect_true!(matrix.get_max_scale_2d().is_some());
        expect_float_eq!(matrix.get_min_scale_2d().unwrap_or(-1.0f32), minScale);
        expect_float_eq!(matrix.get_max_scale_2d().unwrap_or(-1.0f32), maxScale);
        check_pair(matrix, xScale, yScale);
      }

      {
        // Scale + PerspectiveW (returns invalid values)
        let mut matrix = Matrix::make_scale(Vector3::new(xScale, yScale, 1.0f32));
        matrix.m[15] = 0.1;
        expect_false!(matrix.get_min_scale_2d().is_some());
        expect_false!(matrix.get_max_scale_2d().is_some());
        expect_false!(matrix.get_scales_2d().is_some());
      }
    }
  }
}

#[test]
fn get_transformed_pixel_size() {
  {
    // Identity matrix: 1 device pixel = 1 local unit.
    let mut identity = Matrix::default();
    expect_eq!(identity.get_transformed_pixel_size(), Vector2::new(1.0f32, 1.0f32));
  }

  {
    // Pure scaling: 1 device pixel = 1/scale local units.
    let mut scale = Matrix::make_scale(Vector3::new(2.0, 4.0, 1.0));
    expect_eq!(scale.get_transformed_pixel_size(), Vector2::new(0.5f32, 0.25f32));
  }

  {
    // Negative scaling: pixel size is always positive.
    let mut neg_scale = Matrix::make_scale(Vector3::new(-2.0, 4.0, 1.0));
    expect_eq!(neg_scale.get_transformed_pixel_size(), Vector2::new(0.5f32, 0.25f32));
  }

  {
    // Rotation: 1 device pixel = 1 local unit.
    let mut rotation = Matrix::make_rotation_z(Radians::new(kPiOver2));
    let mut rot_size = rotation.get_transformed_pixel_size();
    expect_near!(rot_size.x, 1.0f32, 1e-5);
    expect_near!(rot_size.y, 1.0f32, 1e-5);
  }

  {
    // Rotation 45 degrees: 1 device pixel = 1 local unit.
    let mut rotation = Matrix::make_rotation_z(Radians::new(kPiOver4));
    let mut rot_size = rotation.get_transformed_pixel_size();
    expect_near!(rot_size.x, 1.0f32, 1e-5);
    expect_near!(rot_size.y, 1.0f32, 1e-5);
  }

  {
    // Scale then rotate 45 degrees:
    // Basis vectors rotated by 45 degrees, lengths preserved.
    let mut rotate_scale = Matrix::make_rotation_z(Radians::new(kPiOver4)) *
                          Matrix::make_scale(Vector3::new(2.0, 4.0, 1.0));
    let mut rs_size = rotate_scale.get_transformed_pixel_size();
    expect_near!(rs_size.x, 0.5f32, 1e-5);
    expect_near!(rs_size.y, 0.25f32, 1e-5);
  }

  {
    // Rotate 45 degrees then scale:
    let mut scale_rotate = Matrix::make_scale(Vector3::new(2.0, 4.0, 1.0)) *
                          Matrix::make_rotation_z(Radians::new(kPiOver4));
    let mut sr_size = scale_rotate.get_transformed_pixel_size();
    // Basis X = (sqrt(2), 2*sqrt(2)), length = sqrt(10)
    // Basis Y = (-sqrt(2), 2*sqrt(2)), length = sqrt(10)
    // det = 8 -> pixel_size = sqrt(10) / 8 ≈ 0.3952847f32
    expect_near!(sr_size.x, 0.3952847f32, 1e-5);
    expect_near!(sr_size.y, 0.3952847f32, 1e-5);
  }

  {
    // Skew: accounts for non-orthogonal axes and determinant.
    let mut skew = Matrix::make_skew(0.75f32, 0.5f32);
    let mut skew_size = skew.get_transformed_pixel_size();
    // det = 1.0 * 1.0 - 0.75 * 0.5 = 0.625
    // Basis Y length = sqrt(0.75^2 + 1.0^2) = 1.25 -> pixel_size.x = 1.25 /
    // 0.625 = 2.0 Basis X length = sqrt(1.0^2 + 0.5^2) = sqrt(1.25) ->
    // pixel_size.y = sqrt(1.25) / 0.625
    expect_near!(skew_size.x, 2.0f32, 1e-5);
    expect_near!(skew_size.y, 1.7888544f32, 1e-5);
  }

  {
    // Singular matrix: returns zero.
    let singular = Matrix::new(1.0f32, 2.0f32, 0.0f32, 0.0f32,  //
                    2.0f32, 4.0f32, 0.0f32, 0.0f32,  //
                    0.0f32, 0.0f32, 1.0f32, 0.0f32,  //
                    0.0f32, 0.0f32, 0.0f32, 1.0f32);
    expect_eq!(singular.get_transformed_pixel_size(), Vector2::new(0.0f32, 0.0f32));

    let mut singular_scale_x = Matrix::make_scale(Vector3::new(0.0, 4.0, 1.0));
    expect_eq!(singular_scale_x.get_transformed_pixel_size(), Vector2::new(0.0f32, 0.0f32));

    let mut singular_scale_y = Matrix::make_scale(Vector3::new(2.0, 0.0, 1.0));
    expect_eq!(singular_scale_y.get_transformed_pixel_size(), Vector2::new(0.0f32, 0.0f32));

    let mut singular_scale_xy = Matrix::make_scale(Vector3::new(0.0, 0.0, 1.0));
    expect_eq!(singular_scale_xy.get_transformed_pixel_size(), Vector2::new(0.0f32, 0.0f32));
  }
}

