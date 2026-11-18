// flutter/impeller/geometry/trig_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn trig_angles() {
  {
    let mut trig = Trig::from_radians(Radians::from(Degrees::new(0.0)));
    expect_eq!(trig.cos, 1.0);
    expect_eq!(trig.sin, 0.0);
  }

  {
    let mut trig = Trig::from_radians(Radians::new(0.0));
    expect_eq!(trig.cos, 1.0);
    expect_eq!(trig.sin, 0.0);
  }

  {
    let mut trig = Trig::from_radians(Radians::from(Degrees::new(30.0)));
    expect_near!(trig.cos, 0.75f64.sqrt(), kEhCloseEnough);
    expect_near!(trig.sin, 0.5, kEhCloseEnough);
  }

  {
    let mut trig = Trig::from_radians(Radians::new(kPi / 6.0));
    expect_near!(trig.cos, 0.75f64.sqrt(), kEhCloseEnough);
    expect_near!(trig.sin, 0.5, kEhCloseEnough);
  }

  {
    let mut trig = Trig::from_radians(Radians::from(Degrees::new(60.0)));
    expect_near!(trig.cos, 0.5, kEhCloseEnough);
    expect_near!(trig.sin, 0.75f64.sqrt(), kEhCloseEnough);
  }

  {
    let mut trig = Trig::from_radians(Radians::new(kPi / 3.0));
    expect_near!(trig.cos, 0.5, kEhCloseEnough);
    expect_near!(trig.sin, 0.75f64.sqrt(), kEhCloseEnough);
  }

  {
    let mut trig = Trig::from_radians(Radians::from(Degrees::new(90.0)));
    expect_near!(trig.cos, 0.0, kEhCloseEnough);
    expect_near!(trig.sin, 1.0, kEhCloseEnough);
  }

  {
    let mut trig = Trig::from_radians(Radians::new(kPi / 2.0));
    expect_near!(trig.cos, 0.0, kEhCloseEnough);
    expect_near!(trig.sin, 1.0, kEhCloseEnough);
  }
}

#[test]
fn multiply_by_scalar_radius() {
  for _i in 0..=360 {
    // Upstream shadows the outer i (kept).
    for i in 1..=10 {
      let i = i as f32;
      let radius: Scalar = i * 5.0;
      expect_eq!(
        Trig::from_radians(Radians::from(Degrees::new(i))) * radius as f64,
        Point::new(radius * (i * kPi / 180.0).cos(), radius * (i * kPi / 180.0).sin())
      );
    }
  }
}
