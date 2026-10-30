// flutter/impeller/geometry/geometry_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn scalar_nearly_equal() {
  expect_false!(crate::scalar::scalar_nearly_equal(0.0021f32, 0.001f32));
  expect_true!(crate::scalar::scalar_nearly_equal(0.0019f32, 0.001f32));
  expect_true!(crate::scalar::scalar_nearly_equal_tol(0.002f32, 0.001f32, 0.0011f32));
  expect_false!(crate::scalar::scalar_nearly_equal_tol(0.002f32, 0.001f32, 0.0009f32));
  expect_true!(crate::scalar::scalar_nearly_equal(
      1.0f32, 1.0f32 + f32::EPSILON * 4.0));
}

#[test]
fn make_column() {
  let mut matrix = Matrix::make_column(1.0, 2.0, 3.0, 4.0,     //
                                   5.0, 6.0, 7.0, 8.0,     //
                                   9.0, 10.0, 11.0, 12.0,  //
                                   13.0, 14.0, 15.0, 16.0);

  let mut expect = Matrix::new(1.0,  2.0,  3.0,  4.0,   //
                       5.0,  6.0,  7.0,  8.0,   //
                       9.0,  10.0, 11.0, 12.0,  //
                       13.0, 14.0, 15.0, 16.0);

  expect_true!(matrix == expect);
}

#[test]
fn make_row() {
  let mut matrix = Matrix::make_row(1.0, 2.0, 3.0, 4.0,     //
                                5.0, 6.0, 7.0, 8.0,     //
                                9.0, 10.0, 11.0, 12.0,  //
                                13.0, 14.0, 15.0, 16.0);

  let mut expect = Matrix::new(1.0, 5.0, 9.0,  13.0,  //
                       2.0, 6.0, 10.0, 14.0,  //
                       3.0, 7.0, 11.0, 15.0,  //
                       4.0, 8.0, 12.0, 16.0);

  expect_true!(matrix == expect);
}

#[test]
fn rotation_matrix() {
  let mut rotation = Matrix::make_rotation_z(Radians::new(kPiOver4));
  // clang-format off
  let mut expect = Matrix::new(k1OverSqrt2,  k1OverSqrt2, 0.0, 0.0,
                       -k1OverSqrt2, k1OverSqrt2, 0.0, 0.0,
                       0.0,            0.0,           1.0, 0.0,
                       0.0,            0.0,           0.0, 1.0);
  // clang-format on
  expect_matrix_near!(rotation, expect);
}

#[test]
fn invert_mult_matrix() {
  {
    let mut rotation = Matrix::make_rotation_z(Radians::new(kPiOver4));
    let mut invert = rotation.invert();
    // clang-format off
    let mut expect = Matrix::new(k1OverSqrt2, -k1OverSqrt2, 0.0, 0.0,
                         k1OverSqrt2, k1OverSqrt2,  0.0, 0.0,
                         0.0,           0.0,            1.0, 0.0,
                         0.0,           0.0,            0.0, 1.0);
    // clang-format on
    expect_matrix_near!(invert, expect);
  }
  {
    let mut scale = Matrix::make_scale2(Vector2::new(2.0, 4.0).into());
    let mut invert = scale.invert();
    let mut expect = Matrix::new(0.5, 0.0,    0.0, 0.0,  //
                         0.0,   0.25, 0.0, 0.0,  //
                         0.0,   0.0,    1.0, 0.0,  //
                         0.0,   0.0,    0.0, 1.0);
    expect_matrix_near!(invert, expect);
  }
}

#[test]
fn matrix_basis() {
  let mut matrix = Matrix::new(1.0,  2.0,  3.0,  4.0,   //
                       5.0,  6.0,  7.0,  8.0,   //
                       9.0,  10.0, 11.0, 12.0,  //
                       13.0, 14.0, 15.0, 16.0);
  let mut basis = matrix.basis();
  let mut expect = Matrix::new(1.0, 2.0,  3.0,  0.0,  //
                       5.0, 6.0,  7.0,  0.0,  //
                       9.0, 10.0, 11.0, 0.0,  //
                       0.0, 0.0,  0.0,  1.0);
  expect_matrix_near!(basis, expect);
}

#[test]
fn mutliplication_matrix() {
  let mut rotation = Matrix::make_rotation_z(Radians::new(kPiOver4));
  let mut invert = rotation.invert();
  expect_matrix_near!(rotation * invert, Matrix::default());
}

#[test]
fn determinant_test() {
  let mut matrix = Matrix::new(3.0, 4.0, 14.0, 155.0, 2.0, 1.0, 3.0, 4.0, 2.0, 3.0, 2.0, 1.0, 1.0, 2.0, 4.0, 2.0);
  expect_eq!(matrix.get_determinant(), -1889);
}

#[test]
fn invert_matrix() {
  let mut inverted = Matrix::new(10.0,  -9.0,  -12.0, 8.0,   //
                         7.0,   -12.0, 11.0,  22.0,  //
                         -10.0, 10.0,  3.0,   6.0,   //
                         -2.0,  22.0,  2.0,   1.0)
                      .invert();

  let mut result = Matrix::new(
      438.0 / 85123.0,   1751.0 / 85123.0, -7783.0 / 85123.0, 4672.0 / 85123.0,
      393.0 / 85123.0,   -178.0 / 85123.0, -570.0 / 85123.0,  4192.0 / 85123.0,
      -5230.0 / 85123.0, 2802.0 / 85123.0, -3461.0 / 85123.0, 962.0 / 85123.0,
      2690.0 / 85123.0,  1814.0 / 85123.0, 3896.0 / 85123.0,  319.0 / 85123.0);

  expect_matrix_near!(inverted, result);
}

#[test]
fn test_decomposition() {
  let mut rotated = Matrix::make_rotation_z(Radians::new(kPiOver4));

  let mut result = rotated.decompose();

  expect_true!(result.is_some());

  let mut res = result.unwrap();

  let mut quaternion = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver4);
  expect_quaternion_near!(res.rotation, quaternion);
}

#[test]
fn test_decomposition2() {
  let mut rotated = Matrix::make_rotation_z(Radians::new(kPiOver4));
  let mut scaled = Matrix::make_scale(Vector3::new(2.0, 3.0, 1.0));
  let mut translated = Matrix::make_translation(Vector3::new(-200.0, 750.0, 20.0));

  let mut result = (translated * rotated * scaled).decompose();

  expect_true!(result.is_some());

  let mut res = result.unwrap();

  let mut quaternion = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver4);

  expect_quaternion_near!(res.rotation, quaternion);

  expect_float_eq!(res.translation.x, -200);
  expect_float_eq!(res.translation.y, 750);
  expect_float_eq!(res.translation.z, 20);

  expect_float_eq!(res.scale.x, 2);
  expect_float_eq!(res.scale.y, 3);
  expect_float_eq!(res.scale.z, 1);
}

#[test]
fn test_recomposition() {
  /*
   *  Decomposition.
   */
  let mut rotated = Matrix::make_rotation_z(Radians::new(kPiOver4));

  let mut result = rotated.decompose();

  expect_true!(result.is_some());

  let mut res = result.unwrap();

  let mut quaternion = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver4);

  expect_quaternion_near!(res.rotation, quaternion);

  /*
   *  Recomposition.
   */
  expect_matrix_near!(rotated, Matrix::from_decomposition(&res));
}

#[test]
fn test_recomposition2() {
  let mut matrix = Matrix::make_translation(Vector3::new(100.0, 100.0, 100.0)) *
                Matrix::make_rotation_z(Radians::new(kPiOver4)) *
                Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));

  let mut result = matrix.decompose();

  expect_true!(result.is_some());

  expect_matrix_near!(matrix, Matrix::from_decomposition(&result.unwrap()));
}

#[test]
fn matrix_vector_multiplication() {
  {
    let mut matrix = Matrix::make_translation(Vector3::new(100.0, 100.0, 100.0)) *
                  Matrix::make_rotation_z(Radians::new(kPiOver2)) *
                  Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));
    let mut vector = Vector4::new(10.0, 20.0, 30.0, 2.0);

    let mut result = matrix * vector;
    let mut expected = Vector4::new(160.0, 220.0, 260.0, 2.0);
    expect_vector4_near!(result, expected);
  }

  {
    let mut matrix = Matrix::make_translation(Vector3::new(100.0, 100.0, 100.0)) *
                  Matrix::make_rotation_z(Radians::new(kPiOver2)) *
                  Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));
    let mut vector = Vector3::new(10.0, 20.0, 30.0);

    let mut result = matrix * vector;
    let mut expected = Vector3::new(60.0, 120.0, 160.0);
    expect_vector3_near!(result, expected);
  }

  {
    let mut matrix = Matrix::make_translation(Vector3::new(100.0, 100.0, 100.0)) *
                  Matrix::make_rotation_z(Radians::new(kPiOver2)) *
                  Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));
    let mut vector = Point::new(10.0, 20.0);

    let mut result = matrix * vector;
    let mut expected = Point::new(60.0, 120.0);
    expect_point_near!(result, expected);
  }

  // Matrix Vector ops should respect perspective transforms.
  {
    let mut matrix = Matrix::make_perspective(Radians::new(kPiOver2), 1.0, 1.0, 100.0);
    let mut vector = Vector3::new(3.0, 3.0, -3.0);

    let mut result = matrix * vector;
    let mut expected = Vector3::new(-1.0, -1.0, 1.3468);
    expect_vector3_near!(result, expected);
  }

  {
    let mut matrix = Matrix::make_perspective(Radians::new(kPiOver2), 1.0, 1.0, 100.0) *
                  Matrix::make_translation(Vector3::new(0.0, 0.0, -3.0));
    let mut point = Point::new(3.0, 3.0);

    let mut result = matrix * point;
    let mut expected = Point::new(-1.0, -1.0);
    expect_point_near!(result, expected);
  }

  // Resolves to 0 on perspective singularity.
  {
    let mut matrix = Matrix::make_perspective(Radians::new(kPiOver2), 1.0, 1.0, 100.0);
    let mut point = Point::new(3.0, 3.0);

    let mut result = matrix * point;
    let mut expected = Point::new(0.0, 0.0);
    expect_point_near!(result, expected);
  }
}

#[test]
fn matrix_make_rotation_from_quaternion() {
  {
    let mut matrix = Matrix::make_rotation(Quaternion::from_axis_angle(&Vector3::new(1.0, 0.0, 0.0), kPiOver2));
    let mut expected = Matrix::make_rotation_x(Radians::new(kPiOver2));
    expect_matrix_near!(matrix, expected);
  }

  {
    let mut matrix = Matrix::make_rotation(Quaternion::from_axis_angle(&Vector3::new(0.0, 1.0, 0.0), kPiOver2));
    let mut expected = Matrix::make_rotation_y(Radians::new(kPiOver2));
    expect_matrix_near!(matrix, expected);
  }

  {
    let mut matrix = Matrix::make_rotation(Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver2));
    let mut expected = Matrix::make_rotation_z(Radians::new(kPiOver2));
    expect_matrix_near!(matrix, expected);
  }
}

#[test]
fn matrix_transform_direction() {
  {
    let mut matrix = Matrix::make_translation(Vector3::new(100.0, 100.0, 100.0)) *
                  Matrix::make_rotation_z(Radians::new(kPiOver2)) *
                  Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));
    let mut vector = Vector4::new(10.0, 20.0, 30.0, 2.0);

    let mut result = matrix.transform_direction4(&vector);
    let mut expected = Vector4::new(-40.0, 20.0, 60.0, 2.0);
    expect_vector4_near!(result, expected);
  }

  {
    let mut matrix = Matrix::make_translation(Vector3::new(100.0, 100.0, 100.0)) *
                  Matrix::make_rotation_z(Radians::new(kPiOver2)) *
                  Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));
    let mut vector = Vector3::new(10.0, 20.0, 30.0);

    let mut result = matrix.transform_direction3(&vector);
    let mut expected = Vector3::new(-40.0, 20.0, 60.0);
    expect_vector3_near!(result, expected);
  }

  {
    let mut matrix = Matrix::make_translation(Vector3::new(0.0, -0.4, 100.0)) *
                  Matrix::make_rotation_z(Radians::new(kPiOver2)) *
                  Matrix::make_scale(Vector3::new(2.0, 2.0, 2.0));
    let mut vector = Point::new(10.0, 20.0);

    let mut result = matrix.transform_direction2(&vector);
    let mut expected = Point::new(-40.0, 20.0);
    expect_point_near!(result, expected);
  }
}

#[test]
fn matrix_get_max_basis_length_xy() {
  {
    let mut m = Matrix::make_scale(Vector3::new(3.0, 1.0, 1.0));
    expect_eq!(m.get_max_basis_length_xy(), 3);

    m = m * Matrix::make_skew(0.0, 4.0);
    expect_eq!(m.get_max_basis_length_xy(), 5);
  }

  {
    let mut m = Matrix::make_scale(Vector3::new(-3.0, 4.0, 7.0));
    expect_eq!(m.get_max_basis_length_xy(), 4);
  }

  {
    // clang-format off
    let mut m = Matrix::make_column(
        1.0f32, 0.0f32, 0.0f32, 0.0f32,
        0.0f32, 1.0f32, 0.0f32, 0.0f32,
        4.0f32, 0.0f32, 1.0f32, 0.0f32,
        0.0f32, 0.0f32, 0.0f32, 1.0f32
    );
    // clang-format on
    expect_eq!(m.get_max_basis_length_xy(), 1.0f32);
  }
}

#[test]
fn matrix_make_orthographic() {
  {
    let mut m = Matrix::make_orthographic(Size::new(100.0, 200.0));
    let mut expect = Matrix::new(
        0.02, 0.0,     0.0,   0.0,  //
        0.0,    -0.01, 0.0,   0.0,  //
        0.0,    0.0,     0.0,   0.0,  //
        -1.0,   1.0,     0.5, 1.0,  //
    );
    expect_matrix_near!(m, expect);
  }

  {
    let mut m = Matrix::make_orthographic(Size::new(400.0, 100.0));
    let mut expect = Matrix::new(
        0.005, 0.0,     0.0,   0.0,  //
        0.0,     -0.02, 0.0,   0.0,  //
        0.0,     0.0,     0.0,   0.0,  //
        -1.0,    1.0,     0.5, 1.0,  //
    );
    expect_matrix_near!(m, expect);
  }
}

#[test]
fn matrix_make_perspective() {
  {
    let mut m = Matrix::make_perspective_size(Degrees::new(60.0).into(), Size::new(100.0, 200.0), 1.0, 10.0);
    let mut expect = Matrix::new(
        3.4641, 0.0,       0.0,        0.0,  //
        0.0,      1.73205, 0.0,        0.0,  //
        0.0,      0.0,       1.11111,  1.0,  //
        0.0,      0.0,       -1.11111, 0.0,  //
    );
    expect_matrix_near!(m, expect);
  }

  {
    let mut m = Matrix::make_perspective(Radians::new(1.0), 2.0, 10.0, 20.0);
    let mut expect = Matrix::new(
        0.915244, 0.0,       0.0,   0.0,  //
        0.0,        1.83049, 0.0,   0.0,  //
        0.0,        0.0,       2.0,   1.0,  //
        0.0,        0.0,       -20.0, 0.0,  //
    );
    expect_matrix_near!(m, expect);
  }
}

#[test]
fn matrix_get_basis_vectors() {
  {
    let mut m = Matrix::default();
    let mut x = m.get_basis_x();
    let mut y = m.get_basis_y();
    let mut z = m.get_basis_z();
    expect_vector3_near!(x, Vector3::new(1.0, 0.0, 0.0));
    expect_vector3_near!(y, Vector3::new(0.0, 1.0, 0.0));
    expect_vector3_near!(z, Vector3::new(0.0, 0.0, 1.0));
  }

  {
    let mut m = Matrix::make_rotation_z(Radians::new(kPiOver2)) *
             Matrix::make_rotation_x(Radians::new(kPiOver2)) *
             Matrix::make_scale(Vector3::new(2.0, 3.0, 4.0));
    let mut x = m.get_basis_x();
    let mut y = m.get_basis_y();
    let mut z = m.get_basis_z();
    expect_vector3_near!(x, Vector3::new(0.0, 2.0, 0.0));
    expect_vector3_near!(y, Vector3::new(0.0, 0.0, 3.0));
    expect_vector3_near!(z, Vector3::new(4.0, 0.0, 0.0));
  }
}

#[test]
fn matrix_get_direction_scale() {
  {
    let mut m = Matrix::default();
    let mut result = m.get_direction_scale(Vector3::new(1.0, 0.0, 0.0));
    expect_float_eq!(result, 1);
  }

  {
    let mut m = Matrix::make_rotation_x(Radians::from(Degrees::new(10.0))) *
             Matrix::make_rotation_y(Radians::from(Degrees::new(83.0))) *
             Matrix::make_rotation_z(Radians::from(Degrees::new(172.0)));
    let mut result = m.get_direction_scale(Vector3::new(0.0, 1.0, 0.0));
    expect_float_eq!(result, 1);
  }

  {
    let mut m = Matrix::make_rotation_z(Radians::new(kPiOver2)) *
             Matrix::make_scale(Vector3::new(3.0, 4.0, 5.0));
    let mut result = m.get_direction_scale(Vector3::new(2.0, 0.0, 0.0));
    expect_float_eq!(result, 8);
  }
}

#[test]
fn matrix_translation_scale_only() {
  {
    let mut m = Matrix::default();
    let mut result = m.is_translation_scale_only();
    expect_true!(result);
  }

  {
    let mut m = Matrix::make_scale(Vector3::new(2.0, 3.0, 4.0));
    let mut result = m.is_translation_scale_only();
    expect_true!(result);
  }

  {
    let mut m = Matrix::make_translation(Vector3::new(2.0, 3.0, 4.0));
    let mut result = m.is_translation_scale_only();
    expect_true!(result);
  }

  {
    let mut m = Matrix::make_rotation_z(Radians::from(Degrees::new(10.0)));
    let mut result = m.is_translation_scale_only();
    expect_false!(result);
  }
}

#[test]
fn matrix_look_at() {
  {
    let mut m = Matrix::make_look_at(Vector3::new(0.0, 0.0, -1.0), Vector3::new(0.0, 0.0, 1.0),
                                Vector3::new(0.0, 1.0, 0.0));
    let mut expected = Matrix::new(
        1.0, 0.0, 0.0, 0.0,  //
        0.0, 1.0, 0.0, 0.0,  //
        0.0, 0.0, 1.0, 0.0,  //
        0.0, 0.0, 1.0, 1.0,  //
    );
    expect_matrix_near!(m, expected);
  }

  // Sideways tilt.
  {
    let mut m = Matrix::make_look_at(Vector3::new(0.0, 0.0, -1.0), Vector3::new(0.0, 0.0, 1.0),
                                Vector3::new(1.0, 1.0, 0.0).normalize());

    // clang-format off
    let mut expected = Matrix::new(
        k1OverSqrt2, k1OverSqrt2, 0.0, 0.0,
       -k1OverSqrt2, k1OverSqrt2, 0.0, 0.0,
        0.0,           0.0,           1.0, 0.0,
        0.0,           0.0,           1.0, 1.0,
    );
    // clang-format on
    expect_matrix_near!(m, expected);
  }

  // Half way between +x and -y, yaw 90
  {
    let mut m = Matrix::make_look_at(Vector3::default(), Vector3::new(10.0, -10.0, 0.0), Vector3::new(0.0, 0.0, -1.0));

    // clang-format off
    let mut expected = Matrix::new(
       -k1OverSqrt2,  0.0,  k1OverSqrt2, 0.0,
       -k1OverSqrt2,  0.0, -k1OverSqrt2, 0.0,
        0.0,           -1.0,  0.0,           0.0,
        0.0,            0.0,  0.0,           1.0,
    );
    // clang-format on
    expect_matrix_near!(m, expected);
  }
}

#[test]
fn quaternion_lerp() {
  let mut q1 = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), 0.0);
  let mut q2 = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver4);

  let mut q3 = q1.slerp(&q2, 0.5);

  let mut expected = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver4 / 2.0);

  expect_quaternion_near!(q3, expected);
}

#[test]
fn quaternion_vector_multiply() {
  {
    let mut q = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), 0.0);
    let mut v = Vector3::new(0.0, 1.0, 0.0);

    let mut result = q * v;
    let mut expected = Vector3::new(0.0, 1.0, 0.0);

    expect_vector3_near!(result, expected);
  }

  {
    let mut q = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), k2Pi);
    let mut v = Vector3::new(1.0, 0.0, 0.0);

    let mut result = q * v;
    let mut expected = Vector3::new(1.0, 0.0, 0.0);

    expect_vector3_near!(result, expected);
  }

  {
    let mut q = Quaternion::from_axis_angle(&Vector3::new(0.0, 0.0, 1.0), kPiOver4);
    let mut v = Vector3::new(0.0, 1.0, 0.0);

    let mut result = q * v;
    let mut expected = Vector3::new(-k1OverSqrt2, k1OverSqrt2, 0.0);

    expect_vector3_near!(result, expected);
  }

  {
    let mut q = Quaternion::from_axis_angle(&Vector3::new(1.0, 0.0, 1.0).normalize(), kPi);
    let mut v = Vector3::new(0.0, 0.0, -1.0);

    let mut result = q * v;
    let mut expected = Vector3::new(-1.0, 0.0, 0.0);

    expect_vector3_near!(result, expected);
  }
}

#[test]
fn can_generate_mip_counts() {
  expect_eq!((Size::new(128.0, 128.0).mip_count()), 7u32);
  expect_eq!((Size::new(128.0, 256.0).mip_count()), 7u32);
  expect_eq!((Size::new(128.0, 130.0).mip_count()), 7u32);
  expect_eq!((Size::new(128.0, 257.0).mip_count()), 7u32);
  expect_eq!((Size::new(257.0, 128.0).mip_count()), 7u32);
  expect_eq!((Size::new(128.0, 0.0).mip_count()), 1u32);
  expect_eq!((Size::new(128.0, -25.0).mip_count()), 1u32);
  expect_eq!((Size::new(-128.0, 25.0).mip_count()), 1u32);
  expect_eq!((Size::new(1.0, 1.0).mip_count()), 1u32);
  expect_eq!((Size::new(0.0, 0.0).mip_count()), 1u32);
}

#[test]
fn can_convert_t_types_explicitly() {
  {
    let mut p1 = Point::new(1.0, 2.0);
    let mut p2 = IPoint::from_point(p1);
    expect_eq!(p2.x, 1u32);
    expect_eq!(p2.y, 2u32);
  }

  {
    let mut s1 = Size::new(1.0, 2.0);
    let mut s2 = ISize::from_size(s1);
    expect_eq!(s2.width, 1u32);
    expect_eq!(s2.height, 2u32);
  }

  {
    let mut s1 = Size::new(1.0, 2.0);
    let mut p1 = Point::from_size(s1);
    expect_eq!(p1.x, 1u32);
    expect_eq!(p1.y, 2u32);
  }
}

#[test]
fn can_perform_algebraic_point_ops() {
  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 + IPoint::new(1, 2);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(3, 6);
    let mut p2 = p1 - IPoint::new(1, 2);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 * IPoint::new(2, 3);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 6u32);
  }

  {
    let mut p1 = IPoint::new(2, 6);
    let mut p2 = p1 / IPoint::new(2, 3);
    expect_eq!(p2.x, 1u32);
    expect_eq!(p2.y, 2u32);
  }
}

#[test]
fn can_perform_algebraic_point_ops_with_arithmetic_types() {
  // LHS
  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 * 2.0f32;
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(2, 6);
    let mut p2 = p1 / 2.0f32;
    expect_eq!(p2.x, 1u32);
    expect_eq!(p2.y, 3u32);
  }

  // RHS
  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = 2.0f32 * p1;
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(2, 6);
    let mut p2 = 12.0f32 / p1;
    expect_eq!(p2.x, 6u32);
    expect_eq!(p2.y, 2u32);
  }
}

#[test]
fn point_integer_coerces_to_float() {
  // Integer on LHS, float on RHS
  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 + Point::new(1.0, 2.0);
    expect_float_eq!(p2.x, 2u32);
    expect_float_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(3, 6);
    let mut p2 = p1 - Point::new(1.0, 2.0);
    expect_float_eq!(p2.x, 2u32);
    expect_float_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 * Point::new(2.0, 3.0);
    expect_float_eq!(p2.x, 2u32);
    expect_float_eq!(p2.y, 6u32);
  }

  {
    let mut p1 = IPoint::new(2, 6);
    let mut p2 = p1 / Point::new(2.0, 3.0);
    expect_float_eq!(p2.x, 1u32);
    expect_float_eq!(p2.y, 2u32);
  }

  // Float on LHS, integer on RHS
  {
    let mut p1 = Point::new(1.0, 2.0);
    let mut p2 = p1 + IPoint::new(1, 2);
    expect_float_eq!(p2.x, 2u32);
    expect_float_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = Point::new(3.0, 6.0);
    let mut p2 = p1 - IPoint::new(1, 2);
    expect_float_eq!(p2.x, 2u32);
    expect_float_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = Point::new(1.0, 2.0);
    let mut p2 = p1 * IPoint::new(2, 3);
    expect_float_eq!(p2.x, 2u32);
    expect_float_eq!(p2.y, 6u32);
  }

  {
    let mut p1 = Point::new(2.0, 6.0);
    let mut p2 = p1 / IPoint::new(2, 3);
    expect_float_eq!(p2.x, 1u32);
    expect_float_eq!(p2.y, 2u32);
  }
}

#[test]
fn size_coerces_to_point() {
  // Point on LHS, Size on RHS
  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 + ISize::new(1, 2);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(3, 6);
    let mut p2 = p1 - ISize::new(1, 2);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = IPoint::new(1, 2);
    let mut p2 = p1 * ISize::new(2, 3);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 6u32);
  }

  {
    let mut p1 = IPoint::new(2, 6);
    let mut p2 = p1 / ISize::new(2, 3);
    expect_eq!(p2.x, 1u32);
    expect_eq!(p2.y, 2u32);
  }

  // Size on LHS, Point on RHS
  {
    let mut p1 = ISize::new(1, 2);
    let mut p2 = p1 + IPoint::new(1, 2);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = ISize::new(3, 6);
    let mut p2 = p1 - IPoint::new(1, 2);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
  }

  {
    let mut p1 = ISize::new(1, 2);
    let mut p2 = p1 * IPoint::new(2, 3);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 6u32);
  }

  {
    let mut p1 = ISize::new(2, 6);
    let mut p2 = p1 / IPoint::new(2, 3);
    expect_eq!(p2.x, 1u32);
    expect_eq!(p2.y, 2u32);
  }
}

#[test]
fn can_use_point_assignment_operators() {
  // Point on RHS
  {
    let mut p = IPoint::new(1, 2);
    p += IPoint::new(1, 2);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
  }

  {
    let mut p = IPoint::new(3, 6);
    p -= IPoint::new(1, 2);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
  }

  {
    let mut p = IPoint::new(1, 2);
    p *= IPoint::new(2, 3);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 6u32);
  }

  {
    let mut p = IPoint::new(2, 6);
    p /= IPoint::new(2, 3);
    expect_eq!(p.x, 1u32);
    expect_eq!(p.y, 2u32);
  }

  // Size on RHS
  {
    let mut p = IPoint::new(1, 2);
    p += ISize::new(1, 2);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
  }

  {
    let mut p = IPoint::new(3, 6);
    p -= ISize::new(1, 2);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
  }

  {
    let mut p = IPoint::new(1, 2);
    p *= ISize::new(2, 3);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 6u32);
  }

  {
    let mut p = IPoint::new(2, 6);
    p /= ISize::new(2, 3);
    expect_eq!(p.x, 1u32);
    expect_eq!(p.y, 2u32);
  }

  // Arithmetic type on RHS
  {
    let mut p = IPoint::new(1, 2);
    p *= 3;
    expect_eq!(p.x, 3u32);
    expect_eq!(p.y, 6u32);
  }

  {
    let mut p = IPoint::new(3, 6);
    p /= 3;
    expect_eq!(p.x, 1u32);
    expect_eq!(p.y, 2u32);
  }
}

#[test]
fn point_dot_product() {
  {
    let mut p = Point::new(1.0, 0.0);
    let mut s = p.dot(&Point::new(-1.0, 0.0));
    expect_float_eq!(s, -1);
  }

  {
    let mut p = Point::new(0.0, -1.0);
    let mut s = p.dot(&Point::new(-1.0, 0.0));
    expect_float_eq!(s, 0);
  }

  {
    let mut p = Point::new(1.0, 2.0);
    let mut s = p.dot(&Point::new(3.0, -4.0));
    expect_float_eq!(s, -5);
  }
}

#[test]
fn point_cross_product() {
  {
    let mut p = Point::new(1.0, 0.0);
    let mut s = p.cross(&Point::new(-1.0, 0.0));
    expect_float_eq!(s, 0);
  }

  {
    let mut p = Point::new(0.0, -1.0);
    let mut s = p.cross(&Point::new(-1.0, 0.0));
    expect_float_eq!(s, -1);
  }

  {
    let mut p = Point::new(1.0, 2.0);
    let mut s = p.cross(&Point::new(3.0, -4.0));
    expect_float_eq!(s, -10);
  }
}

#[test]
fn point_reflect() {
  {
    let mut axis = Point::new(0.0, 1.0);
    let mut a = Point::new(2.0, 3.0);
    let mut reflected = a.reflect(&axis);
    let mut expected = Point::new(2.0, -3.0);
    expect_point_near!(reflected, expected);
  }

  {
    let mut axis = Point::new(1.0, 1.0).normalize();
    let mut a = Point::new(1.0, 0.0);
    let mut reflected = a.reflect(&axis);
    let mut expected = Point::new(0.0, -1.0);
    expect_point_near!(reflected, expected);
  }

  {
    let mut axis = Point::new(1.0, 1.0).normalize();
    let mut a = Point::new(-1.0, -1.0);
    let mut reflected = a.reflect(&axis);
    expect_point_near!(reflected, -a);
  }
}

#[test]
fn point_abs() {
  let mut a = Point::new(-1.0, -2.0);
  let mut a_abs = a.abs();
  let mut expected = Point::new(1.0, 2.0);
  expect_point_near!(a_abs, expected);
}

#[test]
fn point_rotate() {
  {
    let mut a = Point::new(1.0, 0.0);
    let mut rotated = a.rotate(&Radians::new(kPiOver2));
    let mut expected = Point::new(0.0, 1.0);
    expect_point_near!(rotated, expected);
  }

  {
    let mut a = Point::new(1.0, 0.0);
    let mut rotated = a.rotate(&Radians::new(-kPiOver2));
    let mut expected = Point::new(0.0, -1.0);
    expect_point_near!(rotated, expected);
  }

  {
    let mut a = Point::new(1.0, 0.0);
    let mut rotated = a.rotate(&Radians::new(kPi));
    let mut expected = Point::new(-1.0, 0.0);
    expect_point_near!(rotated, expected);
  }

  {
    let mut a = Point::new(1.0, 0.0);
    let mut rotated = a.rotate(&Radians::new(kPi * 1.5));
    let mut expected = Point::new(0.0, -1.0);
    expect_point_near!(rotated, expected);
  }
}

#[test]
fn point_angle_to() {
  // Negative result in the CCW (with up = -Y) direction.
  {
    let mut a = Point::new(1.0, 1.0);
    let mut b = Point::new(1.0, -1.0);
    let mut actual = a.angle_to(&b);
    let mut expected = Radians::new(-kPi / 2.0);
    expect_float_eq!(actual.radians, expected.radians);
  }

  // Check the other direction to ensure the result is signed correctly.
  {
    let mut a = Point::new(1.0, -1.0);
    let mut b = Point::new(1.0, 1.0);
    let mut actual = a.angle_to(&b);
    let mut expected = Radians::new(kPi / 2.0);
    expect_float_eq!(actual.radians, expected.radians);
  }

  // Differences in magnitude should have no impact on the result.
  {
    let mut a = Point::new(100.0, -100.0);
    let mut b = Point::new(0.01, 0.01);
    let mut actual = a.angle_to(&b);
    let mut expected = Radians::new(kPi / 2.0);
    expect_float_eq!(actual.radians, expected.radians);
  }
}

#[test]
fn point_min() {
  let mut p = Point::new(1.0, 2.0);
  let mut result = p.min(&Point::new(0.0, 10.0));
  let mut expected = Point::new(0.0, 2.0);
  expect_point_near!(result, expected);
}

#[test]
fn vector4_is_finite() {
  {
    let mut v = Vector4::default();
    expect_true!(v.is_finite());
    v.x = f32::INFINITY;
    expect_false!(v.is_finite());
    v.x = -f32::INFINITY;
    expect_false!(v.is_finite());
    v.x = -f32::NAN;
    expect_false!(v.is_finite());
  }

  {
    let mut v = Vector4::default();
    expect_true!(v.is_finite());
    v.y = f32::INFINITY;
    expect_false!(v.is_finite());
    v.y = -f32::INFINITY;
    expect_false!(v.is_finite());
    v.y = -f32::NAN;
    expect_false!(v.is_finite());
  }

  {
    let mut v = Vector4::default();
    expect_true!(v.is_finite());
    v.z = f32::INFINITY;
    expect_false!(v.is_finite());
    v.z = -f32::INFINITY;
    expect_false!(v.is_finite());
    v.z = -f32::NAN;
    expect_false!(v.is_finite());
  }

  {
    let mut v = Vector4::default();
    expect_true!(v.is_finite());
    v.w = f32::INFINITY;
    expect_false!(v.is_finite());
    v.w = -f32::INFINITY;
    expect_false!(v.is_finite());
    v.w = -f32::NAN;
    expect_false!(v.is_finite());
  }
}

#[test]
fn vector3_min() {
  let mut p = Vector3::new(1.0, 2.0, 3.0);
  let mut result = p.min(&Vector3::new(0.0, 10.0, 2.0));
  let mut expected = Vector3::new(0.0, 2.0, 2.0);
  expect_vector3_near!(result, expected);
}

#[test]
fn vector4_min() {
  let mut p = Vector4::new(1.0, 2.0, 3.0, 4.0);
  let mut result = p.min(&Vector4::new(0.0, 10.0, 2.0, 1.0));
  let mut expected = Vector4::new(0.0, 2.0, 2.0, 1.0);
  expect_vector4_near!(result, expected);
}

#[test]
fn point_max() {
  let mut p = Point::new(1.0, 2.0);
  let mut result = p.max(&Point::new(0.0, 10.0));
  let mut expected = Point::new(1.0, 10.0);
  expect_point_near!(result, expected);
}

#[test]
fn vector3_max() {
  let mut p = Vector3::new(1.0, 2.0, 3.0);
  let mut result = p.max(&Vector3::new(0.0, 10.0, 2.0));
  let mut expected = Vector3::new(1.0, 10.0, 3.0);
  expect_vector3_near!(result, expected);
}

#[test]
fn vector4_max() {
  let mut p = Vector4::new(1.0, 2.0, 3.0, 4.0);
  let mut result = p.max(&Vector4::new(0.0, 10.0, 2.0, 1.0));
  let mut expected = Vector4::new(1.0, 10.0, 3.0, 4.0);
  expect_vector4_near!(result, expected);
}

#[test]
fn point_floor() {
  let mut p = Point::new(1.5, 2.3);
  let mut result = p.floor();
  let mut expected = Point::new(1.0, 2.0);
  expect_point_near!(result, expected);
}

#[test]
fn vector3_floor() {
  let mut p = Vector3::new(1.5, 2.3, 3.9);
  let mut result = p.floor();
  let mut expected = Vector3::new(1.0, 2.0, 3.0);
  expect_vector3_near!(result, expected);
}

#[test]
fn vector4_floor() {
  let mut p = Vector4::new(1.5, 2.3, 3.9, 4.0);
  let mut result = p.floor();
  let mut expected = Vector4::new(1.0, 2.0, 3.0, 4.0);
  expect_vector4_near!(result, expected);
}

#[test]
fn point_ceil() {
  let mut p = Point::new(1.5, 2.3);
  let mut result = p.ceil();
  let mut expected = Point::new(2.0, 3.0);
  expect_point_near!(result, expected);
}

#[test]
fn vector3_ceil() {
  let mut p = Vector3::new(1.5, 2.3, 3.9);
  let mut result = p.ceil();
  let mut expected = Vector3::new(2.0, 3.0, 4.0);
  expect_vector3_near!(result, expected);
}

#[test]
fn vector4_ceil() {
  let mut p = Vector4::new(1.5, 2.3, 3.9, 4.0);
  let mut result = p.ceil();
  let mut expected = Vector4::new(2.0, 3.0, 4.0, 4.0);
  expect_vector4_near!(result, expected);
}

#[test]
fn point_round() {
  let mut p = Point::new(1.5, 2.3);
  let mut result = p.round();
  let mut expected = Point::new(2.0, 2.0);
  expect_point_near!(result, expected);
}

#[test]
fn vector3_round() {
  let mut p = Vector3::new(1.5, 2.3, 3.9);
  let mut result = p.round();
  let mut expected = Vector3::new(2.0, 2.0, 4.0);
  expect_vector3_near!(result, expected);
}

#[test]
fn vector4_round() {
  let mut p = Vector4::new(1.5, 2.3, 3.9, 4.0);
  let mut result = p.round();
  let mut expected = Vector4::new(2.0, 2.0, 4.0, 4.0);
  expect_vector4_near!(result, expected);
}

#[test]
fn point_lerp() {
  let mut p = Point::new(1.0, 2.0);
  let mut result = p.lerp(&Point::new(5.0, 10.0), 0.75);
  let mut expected = Point::new(4.0, 8.0);
  expect_point_near!(result, expected);
}

#[test]
fn vector3_lerp() {
  let mut p = Vector3::new(1.0, 2.0, 3.0);
  let mut result = p.lerp(&Vector3::new(5.0, 10.0, 15.0), 0.75);
  let mut expected = Vector3::new(4.0, 8.0, 12.0);
  expect_vector3_near!(result, expected);
}

#[test]
fn vector4_lerp() {
  let mut p = Vector4::new(1.0, 2.0, 3.0, 4.0);
  let mut result = p.lerp(&Vector4::new(5.0, 10.0, 15.0, 20.0), 0.75);
  let mut expected = Vector4::new(4.0, 8.0, 12.0, 16.0);
  expect_vector4_near!(result, expected);
}

#[test]
fn separated_vector2_normalizes_with_constructor() {
  let mut v = SeparatedVector2::from_vector(Vector2::new(10.0, 0.0));
  expect_point_near!(v.direction, Vector2::new(1.0, 0.0));
  expect_near!(v.magnitude, 10, kEhCloseEnough);
}

#[test]
fn separated_vector2_get_vector() {
  let mut v = SeparatedVector2::from_vector(Vector2::new(10.0, 0.0));
  expect_point_near!(v.get_vector(), Vector2::new(10.0, 0.0));
}

#[test]
fn separated_vector2_get_alignment() {
  // Parallel
  {
    let mut v = SeparatedVector2::from_vector(Vector2::new(10.0, 0.0));
    let mut actual = v.get_alignment(&SeparatedVector2::from_vector(Vector2::new(5.0, 0.0)));
    expect_near!(actual, 1, kEhCloseEnough);
  }

  // Perpendicular
  {
    let mut v = SeparatedVector2::from_vector(Vector2::new(10.0, 0.0));
    let mut actual = v.get_alignment(&SeparatedVector2::from_vector(Vector2::new(0.0, 5.0)));
    expect_near!(actual, 0, kEhCloseEnough);
  }

  // Opposite parallel
  {
    let mut v = SeparatedVector2::from_vector(Vector2::new(0.0, 10.0));
    let mut actual = v.get_alignment(&SeparatedVector2::from_vector(Vector2::new(0.0, -5.0)));
    expect_near!(actual, -1, kEhCloseEnough);
  }
}

#[test]
fn separated_vector2_angle_to() {
  {
    let mut v = SeparatedVector2::from_vector(Vector2::new(10.0, 0.0));
    let mut actual = v.angle_to(&SeparatedVector2::from_vector(Vector2::new(5.0, 0.0)));
    let mut expected = Radians::new(0.0);
    expect_near!(actual.radians, expected.radians, kEhCloseEnough);
  }

  {
    let mut v = SeparatedVector2::from_vector(Vector2::new(10.0, 0.0));
    let mut actual = v.angle_to(&SeparatedVector2::from_vector(Vector2::new(0.0, -5.0)));
    let mut expected = Radians::new(-kPi / 2.0);
    expect_near!(actual.radians, expected.radians, kEhCloseEnough);
  }
}

#[test]
fn can_use_vector3_assignment_operators() {
  {
    let mut p = Vector3::new(1.0, 2.0, 4.0);
    p += Vector3::new(1.0, 2.0, 4.0);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
    expect_eq!(p.z, 8u32);
  }

  {
    let mut p = Vector3::new(3.0, 6.0, 8.0);
    p -= Vector3::new(1.0, 2.0, 3.0);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
    expect_eq!(p.z, 5u32);
  }

  {
    let mut p = Vector3::new(1.0, 2.0, 3.0);
    p *= Vector3::new(2.0, 3.0, 4.0);
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 6u32);
    expect_eq!(p.z, 12u32);
  }

  {
    let mut p = Vector3::new(1.0, 2.0, 3.0);
    p *= 2;
    expect_eq!(p.x, 2u32);
    expect_eq!(p.y, 4u32);
    expect_eq!(p.z, 6u32);
  }

  {
    let mut p = Vector3::new(2.0, 6.0, 12.0);
    p /= Vector3::new(2.0, 3.0, 4.0);
    expect_eq!(p.x, 1u32);
    expect_eq!(p.y, 2u32);
    expect_eq!(p.z, 3u32);
  }

  {
    let mut p = Vector3::new(2.0, 6.0, 12.0);
    p /= 2;
    expect_eq!(p.x, 1u32);
    expect_eq!(p.y, 3u32);
    expect_eq!(p.z, 6u32);
  }
}

#[test]
fn can_perform_algebraic_vector3_ops() {
  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = p1 + Vector3::new(1.0, 2.0, 3.0);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
    expect_eq!(p2.z, 6u32);
  }

  {
    let mut p1 = Vector3::new(3.0, 6.0, 9.0);
    let mut p2 = p1 - Vector3::new(1.0, 2.0, 3.0);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 4u32);
    expect_eq!(p2.z, 6u32);
  }

  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = p1 * Vector3::new(2.0, 3.0, 4.0);
    expect_eq!(p2.x, 2u32);
    expect_eq!(p2.y, 6u32);
    expect_eq!(p2.z, 12u32);
  }

  {
    let mut p1 = Vector3::new(2.0, 6.0, 12.0);
    let mut p2 = p1 / Vector3::new(2.0, 3.0, 4.0);
    expect_eq!(p2.x, 1u32);
    expect_eq!(p2.y, 2u32);
    expect_eq!(p2.z, 3u32);
  }
}

#[test]
fn can_perform_algebraic_vector3_ops_with_arithmetic_types() {
  // LHS
  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = p1 + 2.0f32;
    expect_eq!(p2.x, 3);
    expect_eq!(p2.y, 4);
    expect_eq!(p2.z, 5);
  }

  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = p1 - 2.0f32;
    expect_eq!(p2.x, -1);
    expect_eq!(p2.y, 0);
    expect_eq!(p2.z, 1);
  }

  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = p1 * 2.0f32;
    expect_eq!(p2.x, 2);
    expect_eq!(p2.y, 4);
    expect_eq!(p2.z, 6);
  }

  {
    let mut p1 = Vector3::new(2.0, 6.0, 12.0);
    let mut p2 = p1 / 2.0f32;
    expect_eq!(p2.x, 1);
    expect_eq!(p2.y, 3);
    expect_eq!(p2.z, 6);
  }

  // RHS
  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = 2.0f32 + p1;
    expect_eq!(p2.x, 3);
    expect_eq!(p2.y, 4);
    expect_eq!(p2.z, 5);
  }

  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = 2.0f32 - p1;
    expect_eq!(p2.x, 1);
    expect_eq!(p2.y, 0);
    expect_eq!(p2.z, -1);
  }

  {
    let mut p1 = Vector3::new(1.0, 2.0, 3.0);
    let mut p2 = 2.0f32 * p1;
    expect_eq!(p2.x, 2);
    expect_eq!(p2.y, 4);
    expect_eq!(p2.z, 6);
  }

  {
    let mut p1 = Vector3::new(2.0, 6.0, 12.0);
    let mut p2 = 12.0f32 / p1;
    expect_eq!(p2.x, 6);
    expect_eq!(p2.y, 2);
    expect_eq!(p2.z, 1);
  }
}

#[test]
fn color_premultiply() {
  {
    let mut a = Color::new(1.0, 0.5, 0.2, 0.5);
    let mut premultiplied = a.premultiply();
    let mut expected = Color::new(0.5, 0.25, 0.1, 0.5);
    expect_color_near!(premultiplied, expected);
  }

  {
    let mut a = Color::new(0.5, 0.25, 0.1, 0.5);
    let mut unpremultiplied = a.unpremultiply();
    let mut expected = Color::new(1.0, 0.5, 0.2, 0.5);
    expect_color_near!(unpremultiplied, expected);
  }

  {
    let mut a = Color::new(0.5, 0.25, 0.1, 0.0);
    let mut unpremultiplied = a.unpremultiply();
    let mut expected = Color::new(0.0, 0.0, 0.0, 0.0);
    expect_color_near!(unpremultiplied, expected);
  }
}

#[test]
fn color_r8_g8_b8_a8() {
  {
    let mut a = Color::new(1.0, 0.5, 0.2, 0.5);
    let expected: [u8; 4] = [255, 128, 51, 128];
    expect_array4_near!(a.to_r8g8b8a8(), expected);
  }

  {
    let mut a = Color::new(0.0, 0.0, 0.0, 0.0);
    let expected: [u8; 4] = [0, 0, 0, 0];
    expect_array4_near!(a.to_r8g8b8a8(), expected);
  }

  {
    let mut a = Color::new(1.0, 1.0, 1.0, 1.0);
    let expected: [u8; 4] = [255, 255, 255, 255];
    expect_array4_near!(a.to_r8g8b8a8(), expected);
  }
}

#[test]
fn color_lerp() {
  {
    let mut a = Color::new(0.0, 0.0, 0.0, 0.0);
    let mut b = Color::new(1.0, 1.0, 1.0, 1.0);

    expect_color_near!(Color::lerp(a, b, 0.5), Color::new(0.5, 0.5, 0.5, 0.5));
    expect_color_near!(Color::lerp(a, b, 0.0), a);
    expect_color_near!(Color::lerp(a, b, 1.0), b);
    expect_color_near!(Color::lerp(a, b, 0.2), Color::new(0.2, 0.2, 0.2, 0.2));
  }

  {
    let mut a = Color::new(0.2, 0.4, 1.0, 0.5);
    let mut b = Color::new(0.4, 1.0, 0.2, 0.3);

    expect_color_near!(Color::lerp(a, b, 0.5), Color::new(0.3, 0.7, 0.6, 0.4));
    expect_color_near!(Color::lerp(a, b, 0.0), a);
    expect_color_near!(Color::lerp(a, b, 1.0), b);
    expect_color_near!(Color::lerp(a, b, 0.2), Color::new(0.24, 0.52, 0.84, 0.46));
  }
}

#[test]
fn color_clamp01() {
  {
    let mut result = Color::new(0.5, 0.5, 0.5, 0.5).clamp01();
    let mut expected = Color::new(0.5, 0.5, 0.5, 0.5);
    expect_color_near!(result, expected);
  }

  {
    let mut result = Color::new(-1.0, -1.0, -1.0, -1.0).clamp01();
    let mut expected = Color::new(0.0, 0.0, 0.0, 0.0);
    expect_color_near!(result, expected);
  }

  {
    let mut result = Color::new(2.0, 2.0, 2.0, 2.0).clamp01();
    let mut expected = Color::new(1.0, 1.0, 1.0, 1.0);
    expect_color_near!(result, expected);
  }
}

#[test]
fn color_make_rgba8() {
  {
    let mut a = Color::make_rgba8(0, 0, 0, 0);
    let mut b = Color::black_transparent();
    expect_color_near!(a, b);
  }

  {
    let mut a = Color::make_rgba8(255, 255, 255, 255);
    let mut b = Color::white();
    expect_color_near!(a, b);
  }

  {
    let mut a = Color::make_rgba8(63, 127, 191, 127);
    let mut b = Color::new(0.247059, 0.498039, 0.74902, 0.498039);
    expect_color_near!(a, b);
  }
}

#[test]
fn color_apply_color_matrix() {
  {
    let mut color_matrix = ColorMatrix { array: [
        1.0, 1.0, 1.0, 1.0, 1.0,  //
        1.0, 1.0, 1.0, 1.0, 1.0,  //
        1.0, 1.0, 1.0, 1.0, 1.0,  //
        1.0, 1.0, 1.0, 1.0, 1.0,  //
    ] };
    let mut result = Color::white().apply_color_matrix(&color_matrix);
    let mut expected = Color::new(1.0, 1.0, 1.0, 1.0);
    expect_color_near!(result, expected);
  }

  {
    let mut color_matrix = ColorMatrix { array: [
        0.1, 0.0,   0.0,   0.0,   0.01,  //
        0.0,   0.2, 0.0,   0.0,   0.02,  //
        0.0,   0.0,   0.3, 0.0,   0.03,  //
        0.0,   0.0,   0.0,   0.4, 0.04,  //
    ] };
    let mut result = Color::white().apply_color_matrix(&color_matrix);
    let mut expected = Color::new(0.11, 0.22, 0.33, 0.44);
    expect_color_near!(result, expected);
  }
}

#[test]
fn color_linear_to_srgb() {
  {
    let mut result = Color::white().linear_to_srgb();
    let mut expected = Color::new(1.0, 1.0, 1.0, 1.0);
    expect_color_near!(result, expected);
  }

  {
    let mut result = Color::black_transparent().linear_to_srgb();
    let mut expected = Color::new(0.0, 0.0, 0.0, 0.0);
    expect_color_near!(result, expected);
  }

  {
    let mut result = Color::new(0.2, 0.4, 0.6, 0.8).linear_to_srgb();
    let mut expected = Color::new(0.484529, 0.665185, 0.797738, 0.8);
    expect_color_near!(result, expected);
  }
}

#[test]
fn color_srgb_to_linear() {
  {
    let mut result = Color::white().srgb_to_linear();
    let mut expected = Color::new(1.0, 1.0, 1.0, 1.0);
    expect_color_near!(result, expected);
  }

  {
    let mut result = Color::black_transparent().srgb_to_linear();
    let mut expected = Color::new(0.0, 0.0, 0.0, 0.0);
    expect_color_near!(result, expected);
  }

  {
    let mut result = Color::new(0.2, 0.4, 0.6, 0.8).srgb_to_linear();
    let mut expected = Color::new(0.0331048, 0.132868, 0.318547, 0.8);
    expect_color_near!(result, expected);
  }
}

struct ColorBlendTestData;

impl ColorBlendTestData {
  fn k_destination_color() -> Color {
    Color::cornflower_blue().with_alpha(0.75)
  }

  fn k_source_colors() -> [Color; 3] {
    [Color::white().with_alpha(0.75), Color::lime_green().with_alpha(0.75), Color::black().with_alpha(0.75)]
  }

  // THIS RESULT TABLE IS GENERATED!
  //
  // Uncomment the `GenerateColorBlendResults` test below to print a new table
  // after making changes to `Color::Blend`.
  fn k_expected_results() -> [Vec<(BlendMode, Color)>; 3] {
    [
      vec![
        (BlendMode::kClear, Color::new(0.0, 0.0, 0.0, 0.0)),
        (BlendMode::kSrc, Color::new(1.0, 1.0, 1.0, 0.75)),
        (BlendMode::kDst, Color::new(0.392157, 0.584314, 0.929412, 0.75)),
        (BlendMode::kSrcOver, Color::new(0.878431, 0.916863, 0.985882, 0.9375)),
        (BlendMode::kDstOver, Color::new(0.513726, 0.667451, 0.943529, 0.9375)),
        (BlendMode::kSrcIn, Color::new(1.0, 1.0, 1.0, 0.5625)),
        (BlendMode::kDstIn, Color::new(0.392157, 0.584314, 0.929412, 0.5625)),
        (BlendMode::kSrcOut, Color::new(1.0, 1.0, 1.0, 0.1875)),
        (BlendMode::kDstOut, Color::new(0.392157, 0.584314, 0.929412, 0.1875)),
        (BlendMode::kSrcATop, Color::new(0.848039, 0.896078, 0.982353, 0.75)),
        (BlendMode::kDstATop, Color::new(0.544118, 0.688235, 0.947059, 0.75)),
        (BlendMode::kXor, Color::new(0.696078, 0.792157, 0.964706, 0.375)),
        (BlendMode::kPlus, Color::new(1.0, 1.0, 1.0, 1.0)),
        (BlendMode::kModulate, Color::new(0.392157, 0.584314, 0.929412, 0.5625)),
        (BlendMode::kScreen, Color::new(0.878431, 0.916863, 0.985882, 0.9375)),
        (BlendMode::kOverlay, Color::new(0.74902, 0.916863, 0.985882, 0.9375)),
        (BlendMode::kDarken, Color::new(0.513726, 0.667451, 0.943529, 0.9375)),
        (BlendMode::kLighten, Color::new(0.878431, 0.916863, 0.985882, 0.9375)),
        (BlendMode::kColorDodge, Color::new(0.878431, 0.916863, 0.985882, 0.9375)),
        (BlendMode::kColorBurn, Color::new(0.513725, 0.667451, 0.943529, 0.9375)),
        (BlendMode::kHardLight, Color::new(0.878431, 0.916863, 0.985882, 0.9375)),
        (BlendMode::kSoftLight, Color::new(0.654166, 0.775505, 0.964318, 0.9375)),
        (BlendMode::kDifference, Color::new(0.643137, 0.566275, 0.428235, 0.9375)),
        (BlendMode::kExclusion, Color::new(0.643137, 0.566275, 0.428235, 0.9375)),
        (BlendMode::kMultiply, Color::new(0.513726, 0.667451, 0.943529, 0.9375)),
        (BlendMode::kHue, Color::new(0.617208, 0.655639, 0.724659, 0.9375)),
        (BlendMode::kSaturation, Color::new(0.617208, 0.655639, 0.724659, 0.9375)),
        (BlendMode::kColor, Color::new(0.617208, 0.655639, 0.724659, 0.9375)),
        (BlendMode::kLuminosity, Color::new(0.878431, 0.916863, 0.985882, 0.9375)),
      ],
      vec![
        (BlendMode::kClear, Color::new(0.0, 0.0, 0.0, 0.0)),
        (BlendMode::kSrc, Color::new(0.196078, 0.803922, 0.196078, 0.75)),
        (BlendMode::kDst, Color::new(0.392157, 0.584314, 0.929412, 0.75)),
        (BlendMode::kSrcOver, Color::new(0.235294, 0.76, 0.342745, 0.9375)),
        (BlendMode::kDstOver, Color::new(0.352941, 0.628235, 0.782745, 0.9375)),
        (BlendMode::kSrcIn, Color::new(0.196078, 0.803922, 0.196078, 0.5625)),
        (BlendMode::kDstIn, Color::new(0.392157, 0.584314, 0.929412, 0.5625)),
        (BlendMode::kSrcOut, Color::new(0.196078, 0.803922, 0.196078, 0.1875)),
        (BlendMode::kDstOut, Color::new(0.392157, 0.584314, 0.929412, 0.1875)),
        (BlendMode::kSrcATop, Color::new(0.245098, 0.74902, 0.379412, 0.75)),
        (BlendMode::kDstATop, Color::new(0.343137, 0.639216, 0.746078, 0.75)),
        (BlendMode::kXor, Color::new(0.294118, 0.694118, 0.562745, 0.375)),
        (BlendMode::kPlus, Color::new(0.441176, 1.0, 0.844118, 1.0)),
        (BlendMode::kModulate, Color::new(0.0768935, 0.469742, 0.182238, 0.5625)),
        (BlendMode::kScreen, Color::new(0.424452, 0.828743, 0.79105, 0.9375)),
        (BlendMode::kOverlay, Color::new(0.209919, 0.779839, 0.757001, 0.9375)),
        (BlendMode::kDarken, Color::new(0.235294, 0.628235, 0.342745, 0.9375)),
        (BlendMode::kLighten, Color::new(0.352941, 0.76, 0.782745, 0.9375)),
        (BlendMode::kColorDodge, Color::new(0.41033, 0.877647, 0.825098, 0.9375)),
        (BlendMode::kColorBurn, Color::new(0.117647, 0.567403, 0.609098, 0.9375)),
        (BlendMode::kHardLight, Color::new(0.209919, 0.779839, 0.443783, 0.9375)),
        (BlendMode::kSoftLight, Color::new(0.266006, 0.693915, 0.758818, 0.9375)),
        (BlendMode::kDifference, Color::new(0.235294, 0.409412, 0.665098, 0.9375)),
        (BlendMode::kExclusion, Color::new(0.378316, 0.546897, 0.681707, 0.9375)),
        (BlendMode::kMultiply, Color::new(0.163783, 0.559493, 0.334441, 0.9375)),
        (BlendMode::kHue, Color::new(0.266235, 0.748588, 0.373686, 0.9375)),
        (BlendMode::kSaturation, Color::new(0.339345, 0.629787, 0.811502, 0.9375)),
        (BlendMode::kColor, Color::new(0.241247, 0.765953, 0.348698, 0.9375)),
        (BlendMode::kLuminosity, Color::new(0.346988, 0.622282, 0.776792, 0.9375)),
      ],
      vec![
        (BlendMode::kClear, Color::new(0.0, 0.0, 0.0, 0.0)),
        (BlendMode::kSrc, Color::new(0.0, 0.0, 0.0, 0.75)),
        (BlendMode::kDst, Color::new(0.392157, 0.584314, 0.929412, 0.75)),
        (BlendMode::kSrcOver, Color::new(0.0784314, 0.116863, 0.185882, 0.9375)),
        (BlendMode::kDstOver, Color::new(0.313726, 0.467451, 0.743529, 0.9375)),
        (BlendMode::kSrcIn, Color::new(0.0, 0.0, 0.0, 0.5625)),
        (BlendMode::kDstIn, Color::new(0.392157, 0.584314, 0.929412, 0.5625)),
        (BlendMode::kSrcOut, Color::new(0.0, 0.0, 0.0, 0.1875)),
        (BlendMode::kDstOut, Color::new(0.392157, 0.584314, 0.929412, 0.1875)),
        (BlendMode::kSrcATop, Color::new(0.0980392, 0.146078, 0.232353, 0.75)),
        (BlendMode::kDstATop, Color::new(0.294118, 0.438235, 0.697059, 0.75)),
        (BlendMode::kXor, Color::new(0.196078, 0.292157, 0.464706, 0.375)),
        (BlendMode::kPlus, Color::new(0.294118, 0.438235, 0.697059, 1.0)),
        (BlendMode::kModulate, Color::new(0.0, 0.0, 0.0, 0.5625)),
        (BlendMode::kScreen, Color::new(0.313726, 0.467451, 0.743529, 0.9375)),
        (BlendMode::kOverlay, Color::new(0.0784314, 0.218039, 0.701176, 0.9375)),
        (BlendMode::kDarken, Color::new(0.0784314, 0.116863, 0.185882, 0.9375)),
        (BlendMode::kLighten, Color::new(0.313726, 0.467451, 0.743529, 0.9375)),
        (BlendMode::kColorDodge, Color::new(0.313726, 0.467451, 0.743529, 0.9375)),
        (BlendMode::kColorBurn, Color::new(0.0784314, 0.116863, 0.185882, 0.9375)),
        (BlendMode::kHardLight, Color::new(0.0784314, 0.116863, 0.185882, 0.9375)),
        (BlendMode::kSoftLight, Color::new(0.170704, 0.321716, 0.704166, 0.9375)),
        (BlendMode::kDifference, Color::new(0.313726, 0.467451, 0.743529, 0.9375)),
        (BlendMode::kExclusion, Color::new(0.313726, 0.467451, 0.743529, 0.9375)),
        (BlendMode::kMultiply, Color::new(0.0784314, 0.116863, 0.185882, 0.9375)),
        (BlendMode::kHue, Color::new(0.417208, 0.455639, 0.524659, 0.9375)),
        (BlendMode::kSaturation, Color::new(0.417208, 0.455639, 0.524659, 0.9375)),
        (BlendMode::kColor, Color::new(0.417208, 0.455639, 0.524659, 0.9375)),
        (BlendMode::kLuminosity, Color::new(0.0784314, 0.116863, 0.185882, 0.9375)),
      ],
    ]
  }
}

// To print a new ColorBlendTestData::kExpectedResults table, uncomment this
// test (upstream's GenerateColorBlendResults is commented out too).

#[test]
fn color_blend_returns_expected_results() {
  let dst = ColorBlendTestData::k_destination_color();
  for source_i in 0..ColorBlendTestData::k_source_colors().len() {
    let src = ColorBlendTestData::k_source_colors()[source_i];

    // IMPELLER_FOR_EACH_BLEND_MODE(_BLEND_MODE_RESULT_CHECK)
    for m in 0..=BlendMode::kLastMode as u8 {
      let mode = BlendMode::from_u8(m).unwrap();
      let expected = ColorBlendTestData::k_expected_results()[source_i]
        .iter()
        .find(|(k, _)| *k == mode)
        .unwrap()
        .1;
      expect_color_near!(dst.blend(src, mode), expected);
    }
  }
}

#[test]
fn blend_mode_to_string() {
  macro_rules! names {
    ($($name:ident),*) => { [$(stringify!($name)),*] };
  }
  let names: [&str; 29] = crate::impeller_for_each_blend_mode!(names);
  for i in 0..=BlendMode::kLastMode as u8 {
    let mode = BlendMode::from_u8(i).unwrap();
    let result = crate::color::blend_mode_to_string(mode);
    expect_eq!(result, names[i as usize]);
  }
}
#[test]
fn can_convert_between_degress_and_radians() {
  {
    let mut deg = Degrees::new(90.0);
    let mut rad = Radians::from(deg);
    expect_float_eq!(rad.radians, kPiOver2);
  }
}

#[test]
fn matrix_printing() {
  {
    let mut m = Matrix::default();
    // stream << m;
    expect_eq!(format!("{}", m), r"(
       1.000000,       0.000000,       0.000000,       0.000000,
       0.000000,       1.000000,       0.000000,       0.000000,
       0.000000,       0.000000,       1.000000,       0.000000,
       0.000000,       0.000000,       0.000000,       1.000000,
)");
  }

  {
    let mut m = Matrix::make_translation(Vector3::new(10.0, 20.0, 30.0));
    // stream << m;

    expect_eq!(format!("{}", m), r"(
       1.000000,       0.000000,       0.000000,      10.000000,
       0.000000,       1.000000,       0.000000,      20.000000,
       0.000000,       0.000000,       1.000000,      30.000000,
       0.000000,       0.000000,       0.000000,       1.000000,
)");
  }
}

#[test]
fn point_printing() {
  {
    let mut m = Point::default();
    // stream << m;
    expect_eq!(format!("{}", m), "(0, 0)");
  }

  {
    let mut m = Point::new(13.0, 37.0);
    // stream << m;
    expect_eq!(format!("{}", m), "(13, 37)");
  }
}

#[test]
fn vector3_printing() {
  {
    let mut m = Vector3::default();
    // stream << m;
    expect_eq!(format!("{}", m), "(0, 0, 0)");
  }

  {
    let mut m = Vector3::new(1.0, 2.0, 3.0);
    // stream << m;
    expect_eq!(format!("{}", m), "(1, 2, 3)");
  }
}

#[test]
fn vector4_printing() {
  {
    let mut m = Vector4::default();
    // stream << m;
    expect_eq!(format!("{}", m), "(0, 0, 0, 1)");
  }

  {
    let mut m = Vector4::new(1.0, 2.0, 3.0, 4.0);
    // stream << m;
    expect_eq!(format!("{}", m), "(1, 2, 3, 4)");
  }
}

#[test]
fn color_printing() {
  {
    let mut m = Color::default();
    // stream << m;
    expect_eq!(format!("{}", m), "(0, 0, 0, 0)");
  }

  {
    let mut m = Color::new(1.0, 2.0, 3.0, 4.0);
    // stream << m;
    expect_eq!(format!("{}", m), "(1, 2, 3, 4)");
  }
}

#[test]
fn to_i_color() {
  expect_eq!(Color::to_i_color(Color::new(0.0, 0.0, 0.0, 0.0)), 0u32);
  expect_eq!(Color::to_i_color(Color::new(1.0, 1.0, 1.0, 1.0)), 0xFFFFFFFFu32);
  expect_eq!(Color::to_i_color(Color::new(0.5, 0.5, 1.0, 1.0)), 0xFF8080FFu32);
}

#[test]
fn color_is_wide_gamut() {
  expect_false!(Color::red().is_wide_gamut());
  expect_false!(Color::white().is_wide_gamut());
  expect_false!(Color::black_transparent().is_wide_gamut());
  expect_false!(Color::new(0.5f32, 0.5f32, 0.5f32, 1.0f32).is_wide_gamut());

  // Wide gamut Display P3 values in extended linear sRGB
  expect_true!(Color::new(1.0931f32, -0.2268f32, -0.1501f32, 1.0f32).is_wide_gamut());
  expect_true!(Color::new(-0.5116f32, 1.0183f32, -0.3107f32, 1.0f32).is_wide_gamut());
  expect_true!(Color::new(1.5f32, 0.5f32, 0.5f32, 1.0f32).is_wide_gamut());
  expect_true!(Color::new(-0.1f32, 0.5f32, 0.5f32, 1.0f32).is_wide_gamut());
}

#[test]
fn gradient() {
  {
    // Simple 2 color gradient produces color buffer containing exactly those
    // values.
    let mut colors: Vec<Color> = vec![Color::red(), Color::blue()];
    let mut stops: Vec<Scalar> = vec![0.0, 1.0];

    let mut gradient = create_gradient_buffer(&colors, &stops);

    expect_colors_near!(gradient.colors.clone(), colors.clone());
    expect_eq!(gradient.colors.len(), 2usize);
  }

  {
    // Gradient with duplicate stops creates a 1024 texture.
    let mut colors: Vec<Color> = vec![Color::red(), Color::yellow(), Color::black(),
                                 Color::blue()];
    let mut stops: Vec<Scalar> = vec![0.0, 0.25, 0.25, 1.0];

    let mut gradient = create_gradient_buffer(&colors, &stops);
    expect_eq!(gradient.colors.len(), 1024usize);

    let mut expected_colors: Vec<Color> = vec![Color::default(); 1024];
    for i in 0..1024 {
      let mut t = i as f32 / 1023.0;
      if (i < 256) {
        // Interval 1: texels 0 to 255 (stop interval 0 to 0.25)
        expected_colors[i] =
            Color::lerp(Color::red(), Color::yellow(), t / 0.25);
      } else {
        // Interval 2: texels 256 to 1023 (stop interval 0.25 to 1.0)
        expected_colors[i] =
            Color::lerp(Color::black(), Color::blue(), (t - 0.25) / 0.75);
      }
    }
    expect_colors_near!(gradient.colors.clone(), expected_colors.clone());
  }

  {
    // Simple N color gradient produces color buffer containing exactly those
    // values.
    let mut colors: Vec<Color> = vec![Color::red(), Color::blue(), Color::green(),
                                 Color::white()];
    let mut stops: Vec<Scalar> = vec![0.0, 0.33, 0.66, 1.0];

    let mut gradient = create_gradient_buffer(&colors, &stops);

    expect_colors_near!(gradient.colors.clone(), colors.clone());
    expect_eq!(gradient.colors.len(), 4usize);
  }

  {
    // Gradient with color stops will lerp and scale buffer.
    let mut colors: Vec<Color> = vec![Color::red(), Color::blue(), Color::green()];
    let mut stops: Vec<Scalar> = vec![0.0, 0.25, 1.0];

    let mut gradient = create_gradient_buffer(&colors, &stops);

    let mut lerped_colors: Vec<Color> = vec![
        Color::red(),
        Color::blue(),
        Color::lerp(Color::blue(), Color::green(), 0.3333),
        Color::lerp(Color::blue(), Color::green(), 0.6666),
        Color::green(),
    ];
    expect_colors_near!(gradient.colors.clone(), lerped_colors.clone());
    expect_eq!(gradient.colors.len(), 5usize);
  }

  {
    // Gradient size is capped at 1024.
    let mut colors: Vec<Color> = vec![];
    let mut stops: Vec<Scalar> = vec![];
    for i in 0u32..1025 {
      colors.push(Color::blue());
      stops.push(i as f32 / 1025.0);
    }

    let mut gradient = create_gradient_buffer(&colors, &stops);

    expect_eq!(gradient.colors.len(), 1024usize);
  }

  {
    // Gradient with wide-gamut (out of [0, 1]) colors produces wide-gamut
    // values.
    let mut p3_red = Color::new(1.0931f32, -0.2268f32, -0.1501f32, 1.0f32);
    let mut p3_green = Color::new(-0.5116f32, 1.0183f32, -0.3107f32, 1.0f32);
    let mut colors: Vec<Color> = vec![p3_red, p3_green];
    let mut stops: Vec<Scalar> = vec![0.0, 1.0];

    let mut gradient = create_gradient_buffer(&colors, &stops);

    expect_eq!(gradient.colors.len(), 2usize);
    expect_colors_near!(gradient.colors.clone(), colors.clone());
  }

  {
    // Multi-stop wide-gamut gradient interpolates floats accurately.
    let mut p3_red = Color::new(1.0931f32, -0.2268f32, -0.1501f32, 1.0f32);
    let mut p3_green = Color::new(-0.5116f32, 1.0183f32, -0.3107f32, 1.0f32);
    let mut colors: Vec<Color> = vec![p3_red, Color::white(), p3_green];
    let mut stops: Vec<Scalar> = vec![0.0, 0.5, 1.0];

    let mut gradient = create_gradient_buffer(&colors, &stops);

    expect_eq!(gradient.colors.len(), 3usize);
    expect_colors_near!(gradient.colors.clone(), colors.clone());
  }
}

#[test]
#[ignore = "Half-precision floats (IEEE 754) are not portable and only used on Apple platforms."]
fn half_conversions() {
  // GTEST_SKIP on every platform but Apple's (FML_OS_MACOSX, FML_OS_IOS,
  // FML_OS_IOS_SIMULATOR), whose _Float16 branch the port does not have.
}
