// flutter/impeller/geometry/rstransform_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn construction() {
  let mut transform = RSTransform::make(Point::new(10.0, 12.0), 2.0, Radians::from(Degrees::new(90.0)));

  expect_eq!(transform.scaled_cos, 0.0f32);
  expect_eq!(transform.scaled_sin, 2.0f32);
  expect_eq!(transform.translate_x, 10.0f32);
  expect_eq!(transform.translate_y, 12.0f32);

  expect_eq!(transform.get_bounds(20.0f32, 30.0f32),
            // relative corners are at
            // 0, 0
            // 0, 40
            // -60, 0
            // -60, 40
            // then add 10, 12 to all values
            Some(Rect::make_ltrb(10.0 + -2.0 * 30.0, 12.0 + 0.0, 10.0 + 0.0, 12.0 + 40.0)));
}

#[test]
fn compare_to_matrix() {
  for tx in (0..=100).step_by(10) {
    for ty in (0..=100).step_by(10) {
      let origin = Point::new(tx as f32, ty as f32);
      for scale in (1..=20).step_by(5) {
        let scale = scale as f32;
        // Overshoot a full circle by 30 degrees
        for degrees in (0..=390).step_by(45) {
          let degrees = Degrees::new(degrees as f32);
          let matrix = Matrix::make_translation(Vector3::from(origin))
            * Matrix::make_rotation_z(Radians::from(degrees))
            * Matrix::make_scale2(Vector2::new(scale, scale));
          let rst = RSTransform::make(origin, scale, Radians::from(degrees));
          expect_matrix_near!(rst.get_matrix(), matrix);
          for w in (10..=100).step_by(10) {
            for h in (10..=100).step_by(10) {
              let (w, h) = (w as f32, h as f32);
              let q: Quad = rst.get_quad(w, h);
              let points = Rect::make_wh(w, h).get_transformed_points(&matrix);
              for i in 0..4 {
                expect_near!(q[i].x, points[i].x, kEhCloseEnough);
                expect_near!(q[i].y, points[i].y, kEhCloseEnough);
              }
            }
          }
        }
      }
    }
  }
}
