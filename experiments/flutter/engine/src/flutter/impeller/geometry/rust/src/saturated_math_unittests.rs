// flutter/impeller/geometry/saturated_math_unittests.cc

#![allow(unused_mut, unused_variables, unused_parens, unused_imports, unused_assignments, unused_braces, clippy::all)]

use crate::prelude::*;
use crate::*;

#[test]
fn explicit_add_of_signed_ints() {
  {
    expect_eq!(saturated::add::<i8>((0x79i128 as i8), (5i128 as i8)), (0x7Ei128 as i8));
    expect_eq!(saturated::add::<i8>((0x7Ai128 as i8), (5i128 as i8)), (0x7Fi128 as i8));
    expect_eq!(saturated::add::<i8>((0x7Bi128 as i8), (5i128 as i8)), (0x7Fi128 as i8));
  }
  {
    expect_eq!(saturated::add::<i8>((0x86i128 as i8), (-5i128 as i8)), (0x81i128 as i8));
    expect_eq!(saturated::add::<i8>((0x85i128 as i8), (-5i128 as i8)), (0x80i128 as i8));
    expect_eq!(saturated::add::<i8>((0x84i128 as i8), (-5i128 as i8)), (0x80i128 as i8));
  }
  {
    expect_eq!(saturated::add::<i16>((0x7FF9i128 as i16), (5i128 as i16)), (0x7FFEi128 as i16));
    expect_eq!(saturated::add::<i16>((0x7FFAi128 as i16), (5i128 as i16)), (0x7FFFi128 as i16));
    expect_eq!(saturated::add::<i16>((0x7FFBi128 as i16), (5i128 as i16)), (0x7FFFi128 as i16));
  }
  {
    expect_eq!(saturated::add::<i16>((0x8006i128 as i16), (-5i128 as i16)), (0x8001i128 as i16));
    expect_eq!(saturated::add::<i16>((0x8005i128 as i16), (-5i128 as i16)), (0x8000i128 as i16));
    expect_eq!(saturated::add::<i16>((0x8004i128 as i16), (-5i128 as i16)), (0x8000i128 as i16));
  }
  {
    expect_eq!(saturated::add::<i32>((0x7FFFFFF9i128 as i32), (5i128 as i32)), (0x7FFFFFFEi128 as i32));
    expect_eq!(saturated::add::<i32>((0x7FFFFFFAi128 as i32), (5i128 as i32)), (0x7FFFFFFFi128 as i32));
    expect_eq!(saturated::add::<i32>((0x7FFFFFFBi128 as i32), (5i128 as i32)), (0x7FFFFFFFi128 as i32));
  }
  {
    expect_eq!(saturated::add::<i32>((0x80000006i128 as i32), (-5i128 as i32)), (0x80000001i128 as i32));
    expect_eq!(saturated::add::<i32>((0x80000005i128 as i32), (-5i128 as i32)), (0x80000000i128 as i32));
    expect_eq!(saturated::add::<i32>((0x80000004i128 as i32), (-5i128 as i32)), (0x80000000i128 as i32));
  }
  {
    expect_eq!(saturated::add::<i64>((0x7FFFFFFFFFFFFFF9i128 as i64), (5i128 as i64)),
              (0x7FFFFFFFFFFFFFFEi128 as i64));
    expect_eq!(saturated::add::<i64>((0x7FFFFFFFFFFFFFFAi128 as i64), (5i128 as i64)),
              (0x7FFFFFFFFFFFFFFFi128 as i64));
    expect_eq!(saturated::add::<i64>((0x7FFFFFFFFFFFFFFBi128 as i64), (5i128 as i64)),
              (0x7FFFFFFFFFFFFFFFi128 as i64));
  }
  {
    expect_eq!(saturated::add::<i64>((0x8000000000000006i128 as i64), (-5i128 as i64)),
              (0x8000000000000001i128 as i64));
    expect_eq!(saturated::add::<i64>((0x8000000000000005i128 as i64), (-5i128 as i64)),
              (0x8000000000000000i128 as i64));
    expect_eq!(saturated::add::<i64>((0x8000000000000004i128 as i64), (-5i128 as i64)),
              (0x8000000000000000i128 as i64));
  }
}

#[test]
fn implicit_add_of_signed_ints() {
  {
    let mut a: i8 = 0x79i128 as i8;
    let mut b: i8 = 5i128 as i8;
    expect_eq!(saturated::add(a, b), (0x7Ei128 as i8));
    a = (0x7Ai128) as _;
    expect_eq!(saturated::add(a, b), (0x7Fi128 as i8));
    a = (0x7Bi128) as _;
    expect_eq!(saturated::add(a, b), (0x7Fi128 as i8));
  }
  {
    let mut a: i8 = 0x86i128 as i8;
    let mut b: i8 = -5i128 as i8;
    expect_eq!(saturated::add(a, b), (0x81i128 as i8));
    a = (0x85i128) as _;
    expect_eq!(saturated::add(a, b), (0x80i128 as i8));
    a = (0x84i128) as _;
    expect_eq!(saturated::add(a, b), (0x80i128 as i8));
  }
  {
    let mut a: i16 = 0x7FF9i128 as i16;
    let mut b: i16 = 5i128 as i16;
    expect_eq!(saturated::add(a, b), (0x7FFEi128 as i16));
    a = (0x7FFAi128) as _;
    expect_eq!(saturated::add(a, b), (0x7FFFi128 as i16));
    a = (0x7FFBi128) as _;
    expect_eq!(saturated::add(a, b), (0x7FFFi128 as i16));
  }
  {
    let mut a: i16 = 0x8006i128 as i16;
    let mut b: i16 = -5i128 as i16;
    expect_eq!(saturated::add(a, b), (0x8001i128 as i16));
    a = (0x8005i128) as _;
    expect_eq!(saturated::add(a, b), (0x8000i128 as i16));
    a = (0x8004i128) as _;
    expect_eq!(saturated::add(a, b), (0x8000i128 as i16));
  }
  {
    let mut a: i32 = 0x7FFFFFF9i128 as i32;
    let mut b: i32 = 5i128 as i32;
    expect_eq!(saturated::add(a, b), (0x7FFFFFFEi128 as i32));
    a = (0x7FFFFFFAi128) as _;
    expect_eq!(saturated::add(a, b), (0x7FFFFFFFi128 as i32));
    a = (0x7FFFFFFBi128) as _;
    expect_eq!(saturated::add(a, b), (0x7FFFFFFFi128 as i32));
  }
  {
    let mut a: i32 = 0x80000006i128 as i32;
    let mut b: i32 = -5i128 as i32;
    expect_eq!(saturated::add(a, b), (0x80000001i128 as i32));
    a = (0x80000005i128) as _;
    expect_eq!(saturated::add(a, b), (0x80000000i128 as i32));
    a = (0x80000004i128) as _;
    expect_eq!(saturated::add(a, b), (0x80000000i128 as i32));
  }
  {
    let mut a: i64 = 0x7FFFFFFFFFFFFFF9i128 as i64;
    let mut b: i64 = 5i128 as i64;
    expect_eq!(saturated::add(a, b), (0x7FFFFFFFFFFFFFFEi128 as i64));
    a = (0x7FFFFFFFFFFFFFFAi128) as _;
    expect_eq!(saturated::add(a, b), (0x7FFFFFFFFFFFFFFFi128 as i64));
    a = (0x7FFFFFFFFFFFFFFBi128) as _;
    expect_eq!(saturated::add(a, b), (0x7FFFFFFFFFFFFFFFi128 as i64));
  }
  {
    let mut a: i64 = 0x8000000000000006i128 as i64;
    let mut b: i64 = -5i128 as i64;
    expect_eq!(saturated::add(a, b), (0x8000000000000001i128 as i64));
    a = (0x8000000000000005i128) as _;
    expect_eq!(saturated::add(a, b), (0x8000000000000000i128 as i64));
    a = (0x8000000000000004i128) as _;
    expect_eq!(saturated::add(a, b), (0x8000000000000000i128 as i64));
  }
}

#[test]
fn explicit_add_of_floating_point() {
  {
    let mut inf: f32 = f32::INFINITY;
    let mut max: f32 = f32::MAX;
    let mut big: f32 = max * 0.5f32;

    expect_eq!(saturated::add::<f32>(big, big), max);
    expect_eq!(saturated::add::<f32>(max, big), inf);
    expect_eq!(saturated::add::<f32>(big, max), inf);
    expect_eq!(saturated::add::<f32>(max, max), inf);
    expect_eq!(saturated::add::<f32>(max, inf), inf);
    expect_eq!(saturated::add::<f32>(inf, max), inf);
    expect_eq!(saturated::add::<f32>(inf, inf), inf);

    expect_eq!(saturated::add::<f32>(-big, -big), -max);
    expect_eq!(saturated::add::<f32>(-max, -big), -inf);
    expect_eq!(saturated::add::<f32>(-big, -max), -inf);
    expect_eq!(saturated::add::<f32>(-max, -max), -inf);
    expect_eq!(saturated::add::<f32>(-max, -inf), -inf);
    expect_eq!(saturated::add::<f32>(-inf, -max), -inf);
    expect_eq!(saturated::add::<f32>(-inf, -inf), -inf);

    expect_eq!(saturated::add::<f32>(big, -big), 0.0f32);
    expect_eq!(saturated::add::<f32>(max, -big), big);
    expect_eq!(saturated::add::<f32>(big, -max), -big);
    expect_eq!(saturated::add::<f32>(max, -max), 0.0f32);
    expect_eq!(saturated::add::<f32>(max, -inf), -inf);
    expect_eq!(saturated::add::<f32>(inf, -max), inf);
    expect_true!((saturated::add::<f32>(inf, -inf)).is_nan());

    expect_eq!(saturated::add::<f32>(-big, big), 0.0f32);
    expect_eq!(saturated::add::<f32>(-max, big), -big);
    expect_eq!(saturated::add::<f32>(-big, max), big);
    expect_eq!(saturated::add::<f32>(-max, max), 0.0f32);
    expect_eq!(saturated::add::<f32>(-max, inf), inf);
    expect_eq!(saturated::add::<f32>(-inf, max), -inf);
    expect_true!((saturated::add::<f32>(-inf, inf)).is_nan());
  }
  {
    let mut inf: f64 = f64::INFINITY;
    let mut max: f64 = f64::MAX;
    let mut big: f64 = max * 0.5;

    expect_eq!(saturated::add::<f64>(big, big), max);
    expect_eq!(saturated::add::<f64>(max, big), inf);
    expect_eq!(saturated::add::<f64>(big, max), inf);
    expect_eq!(saturated::add::<f64>(max, max), inf);
    expect_eq!(saturated::add::<f64>(max, inf), inf);
    expect_eq!(saturated::add::<f64>(inf, max), inf);
    expect_eq!(saturated::add::<f64>(inf, inf), inf);

    expect_eq!(saturated::add::<f64>(-big, -big), -max);
    expect_eq!(saturated::add::<f64>(-max, -big), -inf);
    expect_eq!(saturated::add::<f64>(-big, -max), -inf);
    expect_eq!(saturated::add::<f64>(-max, -max), -inf);
    expect_eq!(saturated::add::<f64>(-max, -inf), -inf);
    expect_eq!(saturated::add::<f64>(-inf, -max), -inf);
    expect_eq!(saturated::add::<f64>(-inf, -inf), -inf);

    expect_eq!(saturated::add::<f64>(big, -big), 0.0f32);
    expect_eq!(saturated::add::<f64>(max, -big), big);
    expect_eq!(saturated::add::<f64>(big, -max), -big);
    expect_eq!(saturated::add::<f64>(max, -max), 0.0f32);
    expect_eq!(saturated::add::<f64>(max, -inf), -inf);
    expect_eq!(saturated::add::<f64>(inf, -max), inf);
    expect_true!((saturated::add::<f64>(inf, -inf)).is_nan());

    expect_eq!(saturated::add::<f64>(-big, big), 0.0f32);
    expect_eq!(saturated::add::<f64>(-max, big), -big);
    expect_eq!(saturated::add::<f64>(-big, max), big);
    expect_eq!(saturated::add::<f64>(-max, max), 0.0f32);
    expect_eq!(saturated::add::<f64>(-max, inf), inf);
    expect_eq!(saturated::add::<f64>(-inf, max), -inf);
    expect_true!((saturated::add::<f64>(-inf, inf)).is_nan());
  }
  {
    let mut inf: Scalar = f32::INFINITY;
    let mut max: Scalar = f32::MAX;
    let mut big: Scalar = max * 0.5f32;

    expect_eq!(saturated::add::<Scalar>(big, big), max);
    expect_eq!(saturated::add::<Scalar>(max, big), inf);
    expect_eq!(saturated::add::<Scalar>(big, max), inf);
    expect_eq!(saturated::add::<Scalar>(max, max), inf);
    expect_eq!(saturated::add::<Scalar>(max, inf), inf);
    expect_eq!(saturated::add::<Scalar>(inf, max), inf);
    expect_eq!(saturated::add::<Scalar>(inf, inf), inf);

    expect_eq!(saturated::add::<Scalar>(-big, -big), -max);
    expect_eq!(saturated::add::<Scalar>(-max, -big), -inf);
    expect_eq!(saturated::add::<Scalar>(-big, -max), -inf);
    expect_eq!(saturated::add::<Scalar>(-max, -max), -inf);
    expect_eq!(saturated::add::<Scalar>(-max, -inf), -inf);
    expect_eq!(saturated::add::<Scalar>(-inf, -max), -inf);
    expect_eq!(saturated::add::<Scalar>(-inf, -inf), -inf);

    expect_eq!(saturated::add::<Scalar>(big, -big), 0.0f32);
    expect_eq!(saturated::add::<Scalar>(max, -big), big);
    expect_eq!(saturated::add::<Scalar>(big, -max), -big);
    expect_eq!(saturated::add::<Scalar>(max, -max), 0.0f32);
    expect_eq!(saturated::add::<Scalar>(max, -inf), -inf);
    expect_eq!(saturated::add::<Scalar>(inf, -max), inf);
    expect_true!((saturated::add::<Scalar>(inf, -inf)).is_nan());

    expect_eq!(saturated::add::<Scalar>(-big, big), 0.0f32);
    expect_eq!(saturated::add::<Scalar>(-max, big), -big);
    expect_eq!(saturated::add::<Scalar>(-big, max), big);
    expect_eq!(saturated::add::<Scalar>(-max, max), 0.0f32);
    expect_eq!(saturated::add::<Scalar>(-max, inf), inf);
    expect_eq!(saturated::add::<Scalar>(-inf, max), -inf);
    expect_true!((saturated::add::<Scalar>(-inf, inf)).is_nan());
  }
}

#[test]
fn implicit_add_of_floating_point() {
  {
    let mut inf: f32 = f32::INFINITY;
    let mut max: f32 = f32::MAX;
    let mut big: f32 = max * 0.5f32;

    expect_eq!(saturated::add(big, big), max);
    expect_eq!(saturated::add(max, big), inf);
    expect_eq!(saturated::add(big, max), inf);
    expect_eq!(saturated::add(max, max), inf);
    expect_eq!(saturated::add(max, inf), inf);
    expect_eq!(saturated::add(inf, max), inf);
    expect_eq!(saturated::add(inf, inf), inf);

    expect_eq!(saturated::add(-big, -big), -max);
    expect_eq!(saturated::add(-max, -big), -inf);
    expect_eq!(saturated::add(-big, -max), -inf);
    expect_eq!(saturated::add(-max, -max), -inf);
    expect_eq!(saturated::add(-max, -inf), -inf);
    expect_eq!(saturated::add(-inf, -max), -inf);
    expect_eq!(saturated::add(-inf, -inf), -inf);

    expect_eq!(saturated::add(big, -big), 0.0f32);
    expect_eq!(saturated::add(max, -big), big);
    expect_eq!(saturated::add(big, -max), -big);
    expect_eq!(saturated::add(max, -max), 0.0f32);
    expect_eq!(saturated::add(max, -inf), -inf);
    expect_eq!(saturated::add(inf, -max), inf);
    expect_true!((saturated::add(inf, -inf)).is_nan());

    expect_eq!(saturated::add(-big, big), 0.0f32);
    expect_eq!(saturated::add(-max, big), -big);
    expect_eq!(saturated::add(-big, max), big);
    expect_eq!(saturated::add(-max, max), 0.0f32);
    expect_eq!(saturated::add(-max, inf), inf);
    expect_eq!(saturated::add(-inf, max), -inf);
    expect_true!((saturated::add(-inf, inf)).is_nan());
  }
  {
    let mut inf: f64 = f64::INFINITY;
    let mut max: f64 = f64::MAX;
    let mut big: f64 = max * 0.5;

    expect_eq!(saturated::add(big, big), max);
    expect_eq!(saturated::add(max, big), inf);
    expect_eq!(saturated::add(big, max), inf);
    expect_eq!(saturated::add(max, max), inf);
    expect_eq!(saturated::add(max, inf), inf);
    expect_eq!(saturated::add(inf, max), inf);
    expect_eq!(saturated::add(inf, inf), inf);

    expect_eq!(saturated::add(-big, -big), -max);
    expect_eq!(saturated::add(-max, -big), -inf);
    expect_eq!(saturated::add(-big, -max), -inf);
    expect_eq!(saturated::add(-max, -max), -inf);
    expect_eq!(saturated::add(-max, -inf), -inf);
    expect_eq!(saturated::add(-inf, -max), -inf);
    expect_eq!(saturated::add(-inf, -inf), -inf);

    expect_eq!(saturated::add(big, -big), 0.0f32);
    expect_eq!(saturated::add(max, -big), big);
    expect_eq!(saturated::add(big, -max), -big);
    expect_eq!(saturated::add(max, -max), 0.0f32);
    expect_eq!(saturated::add(max, -inf), -inf);
    expect_eq!(saturated::add(inf, -max), inf);
    expect_true!((saturated::add(inf, -inf)).is_nan());

    expect_eq!(saturated::add(-big, big), 0.0f32);
    expect_eq!(saturated::add(-max, big), -big);
    expect_eq!(saturated::add(-big, max), big);
    expect_eq!(saturated::add(-max, max), 0.0f32);
    expect_eq!(saturated::add(-max, inf), inf);
    expect_eq!(saturated::add(-inf, max), -inf);
    expect_true!((saturated::add(-inf, inf)).is_nan());
  }
  {
    let mut inf: Scalar = f32::INFINITY;
    let mut max: Scalar = f32::MAX;
    let mut big: Scalar = max * 0.5f32;

    expect_eq!(saturated::add(big, big), max);
    expect_eq!(saturated::add(max, big), inf);
    expect_eq!(saturated::add(big, max), inf);
    expect_eq!(saturated::add(max, max), inf);
    expect_eq!(saturated::add(max, inf), inf);
    expect_eq!(saturated::add(inf, max), inf);
    expect_eq!(saturated::add(inf, inf), inf);

    expect_eq!(saturated::add(-big, -big), -max);
    expect_eq!(saturated::add(-max, -big), -inf);
    expect_eq!(saturated::add(-big, -max), -inf);
    expect_eq!(saturated::add(-max, -max), -inf);
    expect_eq!(saturated::add(-max, -inf), -inf);
    expect_eq!(saturated::add(-inf, -max), -inf);
    expect_eq!(saturated::add(-inf, -inf), -inf);

    expect_eq!(saturated::add(big, -big), 0.0f32);
    expect_eq!(saturated::add(max, -big), big);
    expect_eq!(saturated::add(big, -max), -big);
    expect_eq!(saturated::add(max, -max), 0.0f32);
    expect_eq!(saturated::add(max, -inf), -inf);
    expect_eq!(saturated::add(inf, -max), inf);
    expect_true!((saturated::add(inf, -inf)).is_nan());

    expect_eq!(saturated::add(-big, big), 0.0f32);
    expect_eq!(saturated::add(-max, big), -big);
    expect_eq!(saturated::add(-big, max), big);
    expect_eq!(saturated::add(-max, max), 0.0f32);
    expect_eq!(saturated::add(-max, inf), inf);
    expect_eq!(saturated::add(-inf, max), -inf);
    expect_true!((saturated::add(-inf, inf)).is_nan());
  }
}

#[test]
fn explicit_sub_of_signed_ints() {
  {
    expect_eq!(saturated::sub::<i8>((0x79i128 as i8), (-5i128 as i8)), (0x7Ei128 as i8));
    expect_eq!(saturated::sub::<i8>((0x7Ai128 as i8), (-5i128 as i8)), (0x7Fi128 as i8));
    expect_eq!(saturated::sub::<i8>((0x7Bi128 as i8), (-5i128 as i8)), (0x7Fi128 as i8));
  }
  {
    expect_eq!(saturated::sub::<i8>((0x86i128 as i8), (5i128 as i8)), (0x81i128 as i8));
    expect_eq!(saturated::sub::<i8>((0x85i128 as i8), (5i128 as i8)), (0x80i128 as i8));
    expect_eq!(saturated::sub::<i8>((0x84i128 as i8), (5i128 as i8)), (0x80i128 as i8));
  }
  {
    expect_eq!(saturated::sub::<i16>((0x7FF9i128 as i16), (-5i128 as i16)), (0x7FFEi128 as i16));
    expect_eq!(saturated::sub::<i16>((0x7FFAi128 as i16), (-5i128 as i16)), (0x7FFFi128 as i16));
    expect_eq!(saturated::sub::<i16>((0x7FFBi128 as i16), (-5i128 as i16)), (0x7FFFi128 as i16));
  }
  {
    expect_eq!(saturated::sub::<i16>((0x8006i128 as i16), (5i128 as i16)), (0x8001i128 as i16));
    expect_eq!(saturated::sub::<i16>((0x8005i128 as i16), (5i128 as i16)), (0x8000i128 as i16));
    expect_eq!(saturated::sub::<i16>((0x8004i128 as i16), (5i128 as i16)), (0x8000i128 as i16));
  }
  {
    expect_eq!(saturated::sub::<i32>((0x7FFFFFF9i128 as i32), (-5i128 as i32)), (0x7FFFFFFEi128 as i32));
    expect_eq!(saturated::sub::<i32>((0x7FFFFFFAi128 as i32), (-5i128 as i32)), (0x7FFFFFFFi128 as i32));
    expect_eq!(saturated::sub::<i32>((0x7FFFFFFBi128 as i32), (-5i128 as i32)), (0x7FFFFFFFi128 as i32));
  }
  {
    expect_eq!(saturated::sub::<i32>((0x80000006i128 as i32), (5i128 as i32)), (0x80000001i128 as i32));
    expect_eq!(saturated::sub::<i32>((0x80000005i128 as i32), (5i128 as i32)), (0x80000000i128 as i32));
    expect_eq!(saturated::sub::<i32>((0x80000004i128 as i32), (5i128 as i32)), (0x80000000i128 as i32));
  }
  {
    expect_eq!(saturated::sub::<i64>((0x7FFFFFFFFFFFFFF9i128 as i64), (-5i128 as i64)),
              (0x7FFFFFFFFFFFFFFEi128 as i64));
    expect_eq!(saturated::sub::<i64>((0x7FFFFFFFFFFFFFFAi128 as i64), (-5i128 as i64)),
              (0x7FFFFFFFFFFFFFFFi128 as i64));
    expect_eq!(saturated::sub::<i64>((0x7FFFFFFFFFFFFFFBi128 as i64), (-5i128 as i64)),
              (0x7FFFFFFFFFFFFFFFi128 as i64));
  }
  {
    expect_eq!(saturated::sub::<i64>((0x8000000000000006i128 as i64), (5i128 as i64)),
              (0x8000000000000001i128 as i64));
    expect_eq!(saturated::sub::<i64>((0x8000000000000005i128 as i64), (5i128 as i64)),
              (0x8000000000000000i128 as i64));
    expect_eq!(saturated::sub::<i64>((0x8000000000000004i128 as i64), (5i128 as i64)),
              (0x8000000000000000i128 as i64));
  }
}

#[test]
fn implicit_sub_of_signed_ints() {
  {
    let mut a: i8 = 0x79i128 as i8;
    let mut b: i8 = -5i128 as i8;
    expect_eq!(saturated::sub(a, b), (0x7Ei128 as i8));
    a = (0x7Ai128) as _;
    expect_eq!(saturated::sub(a, b), (0x7Fi128 as i8));
    a = (0x7Bi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7Fi128 as i8));
  }
  {
    let mut a: i8 = 0x86i128 as i8;
    let mut b: i8 = 5i128 as i8;
    expect_eq!(saturated::sub(a, b), (0x81i128 as i8));
    a = (0x85i128) as _;
    expect_eq!(saturated::sub(a, b), (0x80i128 as i8));
    a = (0x84i128) as _;
    expect_eq!(saturated::sub(a, b), (0x80i128 as i8));
  }
  {
    let mut a: i16 = 0x7FF9i128 as i16;
    let mut b: i16 = -5i128 as i16;
    expect_eq!(saturated::sub(a, b), (0x7FFEi128 as i16));
    a = (0x7FFAi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7FFFi128 as i16));
    a = (0x7FFBi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7FFFi128 as i16));
  }
  {
    let mut a: i16 = 0x8006i128 as i16;
    let mut b: i16 = 5i128 as i16;
    expect_eq!(saturated::sub(a, b), (0x8001i128 as i16));
    a = (0x8005i128) as _;
    expect_eq!(saturated::sub(a, b), (0x8000i128 as i16));
    a = (0x8004i128) as _;
    expect_eq!(saturated::sub(a, b), (0x8000i128 as i16));
  }
  {
    let mut a: i32 = 0x7FFFFFF9i128 as i32;
    let mut b: i32 = -5i128 as i32;
    expect_eq!(saturated::sub(a, b), (0x7FFFFFFEi128 as i32));
    a = (0x7FFFFFFAi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7FFFFFFFi128 as i32));
    a = (0x7FFFFFFBi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7FFFFFFFi128 as i32));
  }
  {
    let mut a: i32 = 0x80000006i128 as i32;
    let mut b: i32 = 5i128 as i32;
    expect_eq!(saturated::sub(a, b), (0x80000001i128 as i32));
    a = (0x80000005i128) as _;
    expect_eq!(saturated::sub(a, b), (0x80000000i128 as i32));
    a = (0x80000004i128) as _;
    expect_eq!(saturated::sub(a, b), (0x80000000i128 as i32));
  }
  {
    let mut a: i64 = 0x7FFFFFFFFFFFFFF9i128 as i64;
    let mut b: i64 = -5i128 as i64;
    expect_eq!(saturated::sub(a, b), (0x7FFFFFFFFFFFFFFEi128 as i64));
    a = (0x7FFFFFFFFFFFFFFAi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7FFFFFFFFFFFFFFFi128 as i64));
    a = (0x7FFFFFFFFFFFFFFBi128) as _;
    expect_eq!(saturated::sub(a, b), (0x7FFFFFFFFFFFFFFFi128 as i64));
  }
  {
    let mut a: i64 = 0x8000000000000006i128 as i64;
    let mut b: i64 = 5i128 as i64;
    expect_eq!(saturated::sub(a, b), (0x8000000000000001i128 as i64));
    a = (0x8000000000000005i128) as _;
    expect_eq!(saturated::sub(a, b), (0x8000000000000000i128 as i64));
    a = (0x8000000000000004i128) as _;
    expect_eq!(saturated::sub(a, b), (0x8000000000000000i128 as i64));
  }
}

#[test]
fn explicit_sub_of_floating_point() {
  {
    let mut inf: f32 = f32::INFINITY;
    let mut max: f32 = f32::MAX;
    let mut big: f32 = max * 0.5f32;

    expect_eq!(saturated::sub::<f32>(big, big), 0.0f32);
    expect_eq!(saturated::sub::<f32>(max, big), big);
    expect_eq!(saturated::sub::<f32>(big, max), -big);
    expect_eq!(saturated::sub::<f32>(max, max), 0.0f32);
    expect_eq!(saturated::sub::<f32>(max, inf), -inf);
    expect_eq!(saturated::sub::<f32>(inf, max), inf);
    expect_true!((saturated::sub::<f32>(inf, inf)).is_nan());

    expect_eq!(saturated::sub::<f32>(-big, -big), 0.0f32);
    expect_eq!(saturated::sub::<f32>(-max, -big), -big);
    expect_eq!(saturated::sub::<f32>(-big, -max), big);
    expect_eq!(saturated::sub::<f32>(-max, -max), 0.0f32);
    expect_eq!(saturated::sub::<f32>(-max, -inf), inf);
    expect_eq!(saturated::sub::<f32>(-inf, -max), -inf);
    expect_true!((saturated::sub::<f32>(-inf, -inf)).is_nan());

    expect_eq!(saturated::sub::<f32>(big, -big), max);
    expect_eq!(saturated::sub::<f32>(max, -big), inf);
    expect_eq!(saturated::sub::<f32>(big, -max), inf);
    expect_eq!(saturated::sub::<f32>(max, -max), inf);
    expect_eq!(saturated::sub::<f32>(max, -inf), inf);
    expect_eq!(saturated::sub::<f32>(inf, -max), inf);
    expect_eq!(saturated::sub::<f32>(inf, -inf), inf);

    expect_eq!(saturated::sub::<f32>(-big, big), -max);
    expect_eq!(saturated::sub::<f32>(-max, big), -inf);
    expect_eq!(saturated::sub::<f32>(-big, max), -inf);
    expect_eq!(saturated::sub::<f32>(-max, max), -inf);
    expect_eq!(saturated::sub::<f32>(-max, inf), -inf);
    expect_eq!(saturated::sub::<f32>(-inf, max), -inf);
    expect_eq!(saturated::sub::<f32>(-inf, inf), -inf);
  }
  {
    let mut inf: f64 = f64::INFINITY;
    let mut max: f64 = f64::MAX;
    let mut big: f64 = max * 0.5;

    expect_eq!(saturated::sub::<f64>(big, big), 0.0f32);
    expect_eq!(saturated::sub::<f64>(max, big), big);
    expect_eq!(saturated::sub::<f64>(big, max), -big);
    expect_eq!(saturated::sub::<f64>(max, max), 0.0f32);
    expect_eq!(saturated::sub::<f64>(max, inf), -inf);
    expect_eq!(saturated::sub::<f64>(inf, max), inf);
    expect_true!((saturated::sub::<f64>(inf, inf)).is_nan());

    expect_eq!(saturated::sub::<f64>(-big, -big), 0.0f32);
    expect_eq!(saturated::sub::<f64>(-max, -big), -big);
    expect_eq!(saturated::sub::<f64>(-big, -max), big);
    expect_eq!(saturated::sub::<f64>(-max, -max), 0.0f32);
    expect_eq!(saturated::sub::<f64>(-max, -inf), inf);
    expect_eq!(saturated::sub::<f64>(-inf, -max), -inf);
    expect_true!((saturated::sub::<f64>(-inf, -inf)).is_nan());

    expect_eq!(saturated::sub::<f64>(big, -big), max);
    expect_eq!(saturated::sub::<f64>(max, -big), inf);
    expect_eq!(saturated::sub::<f64>(big, -max), inf);
    expect_eq!(saturated::sub::<f64>(max, -max), inf);
    expect_eq!(saturated::sub::<f64>(max, -inf), inf);
    expect_eq!(saturated::sub::<f64>(inf, -max), inf);
    expect_eq!(saturated::sub::<f64>(inf, -inf), inf);

    expect_eq!(saturated::sub::<f64>(-big, big), -max);
    expect_eq!(saturated::sub::<f64>(-max, big), -inf);
    expect_eq!(saturated::sub::<f64>(-big, max), -inf);
    expect_eq!(saturated::sub::<f64>(-max, max), -inf);
    expect_eq!(saturated::sub::<f64>(-max, inf), -inf);
    expect_eq!(saturated::sub::<f64>(-inf, max), -inf);
    expect_eq!(saturated::sub::<f64>(-inf, inf), -inf);
  }
  {
    let mut inf: Scalar = f32::INFINITY;
    let mut max: Scalar = f32::MAX;
    let mut big: Scalar = max * 0.5f32;

    expect_eq!(saturated::sub::<Scalar>(big, big), 0.0f32);
    expect_eq!(saturated::sub::<Scalar>(max, big), big);
    expect_eq!(saturated::sub::<Scalar>(big, max), -big);
    expect_eq!(saturated::sub::<Scalar>(max, max), 0.0f32);
    expect_eq!(saturated::sub::<Scalar>(max, inf), -inf);
    expect_eq!(saturated::sub::<Scalar>(inf, max), inf);
    expect_true!((saturated::sub::<Scalar>(inf, inf)).is_nan());

    expect_eq!(saturated::sub::<Scalar>(-big, -big), 0.0f32);
    expect_eq!(saturated::sub::<Scalar>(-max, -big), -big);
    expect_eq!(saturated::sub::<Scalar>(-big, -max), big);
    expect_eq!(saturated::sub::<Scalar>(-max, -max), 0.0f32);
    expect_eq!(saturated::sub::<Scalar>(-max, -inf), inf);
    expect_eq!(saturated::sub::<Scalar>(-inf, -max), -inf);
    expect_true!((saturated::sub::<Scalar>(-inf, -inf)).is_nan());

    expect_eq!(saturated::sub::<Scalar>(big, -big), max);
    expect_eq!(saturated::sub::<Scalar>(max, -big), inf);
    expect_eq!(saturated::sub::<Scalar>(big, -max), inf);
    expect_eq!(saturated::sub::<Scalar>(max, -max), inf);
    expect_eq!(saturated::sub::<Scalar>(max, -inf), inf);
    expect_eq!(saturated::sub::<Scalar>(inf, -max), inf);
    expect_eq!(saturated::sub::<Scalar>(inf, -inf), inf);

    expect_eq!(saturated::sub::<Scalar>(-big, big), -max);
    expect_eq!(saturated::sub::<Scalar>(-max, big), -inf);
    expect_eq!(saturated::sub::<Scalar>(-big, max), -inf);
    expect_eq!(saturated::sub::<Scalar>(-max, max), -inf);
    expect_eq!(saturated::sub::<Scalar>(-max, inf), -inf);
    expect_eq!(saturated::sub::<Scalar>(-inf, max), -inf);
    expect_eq!(saturated::sub::<Scalar>(-inf, inf), -inf);
  }
}

#[test]
fn implicit_sub_of_floating_point() {
  {
    let mut inf: f32 = f32::INFINITY;
    let mut max: f32 = f32::MAX;
    let mut big: f32 = max * 0.5f32;

    expect_eq!(saturated::sub(big, big), 0.0f32);
    expect_eq!(saturated::sub(max, big), big);
    expect_eq!(saturated::sub(big, max), -big);
    expect_eq!(saturated::sub(max, max), 0.0f32);
    expect_eq!(saturated::sub(max, inf), -inf);
    expect_eq!(saturated::sub(inf, max), inf);
    expect_true!((saturated::sub(inf, inf)).is_nan());

    expect_eq!(saturated::sub(-big, -big), 0.0f32);
    expect_eq!(saturated::sub(-max, -big), -big);
    expect_eq!(saturated::sub(-big, -max), big);
    expect_eq!(saturated::sub(-max, -max), 0.0f32);
    expect_eq!(saturated::sub(-max, -inf), inf);
    expect_eq!(saturated::sub(-inf, -max), -inf);
    expect_true!((saturated::sub(-inf, -inf)).is_nan());

    expect_eq!(saturated::sub(big, -big), max);
    expect_eq!(saturated::sub(max, -big), inf);
    expect_eq!(saturated::sub(big, -max), inf);
    expect_eq!(saturated::sub(max, -max), inf);
    expect_eq!(saturated::sub(max, -inf), inf);
    expect_eq!(saturated::sub(inf, -max), inf);
    expect_eq!(saturated::sub(inf, -inf), inf);

    expect_eq!(saturated::sub(-big, big), -max);
    expect_eq!(saturated::sub(-max, big), -inf);
    expect_eq!(saturated::sub(-big, max), -inf);
    expect_eq!(saturated::sub(-max, max), -inf);
    expect_eq!(saturated::sub(-max, inf), -inf);
    expect_eq!(saturated::sub(-inf, max), -inf);
    expect_eq!(saturated::sub(-inf, inf), -inf);
  }
  {
    let mut inf: f64 = f64::INFINITY;
    let mut max: f64 = f64::MAX;
    let mut big: f64 = max * 0.5;

    expect_eq!(saturated::sub(big, big), 0.0f32);
    expect_eq!(saturated::sub(max, big), big);
    expect_eq!(saturated::sub(big, max), -big);
    expect_eq!(saturated::sub(max, max), 0.0f32);
    expect_eq!(saturated::sub(max, inf), -inf);
    expect_eq!(saturated::sub(inf, max), inf);
    expect_true!((saturated::sub(inf, inf)).is_nan());

    expect_eq!(saturated::sub(-big, -big), 0.0f32);
    expect_eq!(saturated::sub(-max, -big), -big);
    expect_eq!(saturated::sub(-big, -max), big);
    expect_eq!(saturated::sub(-max, -max), 0.0f32);
    expect_eq!(saturated::sub(-max, -inf), inf);
    expect_eq!(saturated::sub(-inf, -max), -inf);
    expect_true!((saturated::sub(-inf, -inf)).is_nan());

    expect_eq!(saturated::sub(big, -big), max);
    expect_eq!(saturated::sub(max, -big), inf);
    expect_eq!(saturated::sub(big, -max), inf);
    expect_eq!(saturated::sub(max, -max), inf);
    expect_eq!(saturated::sub(max, -inf), inf);
    expect_eq!(saturated::sub(inf, -max), inf);
    expect_eq!(saturated::sub(inf, -inf), inf);

    expect_eq!(saturated::sub(-big, big), -max);
    expect_eq!(saturated::sub(-max, big), -inf);
    expect_eq!(saturated::sub(-big, max), -inf);
    expect_eq!(saturated::sub(-max, max), -inf);
    expect_eq!(saturated::sub(-max, inf), -inf);
    expect_eq!(saturated::sub(-inf, max), -inf);
    expect_eq!(saturated::sub(-inf, inf), -inf);
  }
  {
    let mut inf: Scalar = f32::INFINITY;
    let mut max: Scalar = f32::MAX;
    let mut big: Scalar = max * 0.5f32;

    expect_eq!(saturated::sub(big, big), 0.0f32);
    expect_eq!(saturated::sub(max, big), big);
    expect_eq!(saturated::sub(big, max), -big);
    expect_eq!(saturated::sub(max, max), 0.0f32);
    expect_eq!(saturated::sub(max, inf), -inf);
    expect_eq!(saturated::sub(inf, max), inf);
    expect_true!((saturated::sub(inf, inf)).is_nan());

    expect_eq!(saturated::sub(-big, -big), 0.0f32);
    expect_eq!(saturated::sub(-max, -big), -big);
    expect_eq!(saturated::sub(-big, -max), big);
    expect_eq!(saturated::sub(-max, -max), 0.0f32);
    expect_eq!(saturated::sub(-max, -inf), inf);
    expect_eq!(saturated::sub(-inf, -max), -inf);
    expect_true!((saturated::sub(-inf, -inf)).is_nan());

    expect_eq!(saturated::sub(big, -big), max);
    expect_eq!(saturated::sub(max, -big), inf);
    expect_eq!(saturated::sub(big, -max), inf);
    expect_eq!(saturated::sub(max, -max), inf);
    expect_eq!(saturated::sub(max, -inf), inf);
    expect_eq!(saturated::sub(inf, -max), inf);
    expect_eq!(saturated::sub(inf, -inf), inf);

    expect_eq!(saturated::sub(-big, big), -max);
    expect_eq!(saturated::sub(-max, big), -inf);
    expect_eq!(saturated::sub(-big, max), -inf);
    expect_eq!(saturated::sub(-max, max), -inf);
    expect_eq!(saturated::sub(-max, inf), -inf);
    expect_eq!(saturated::sub(-inf, max), -inf);
    expect_eq!(saturated::sub(-inf, inf), -inf);
  }
}

#[test]
fn explicit_average_scalar_of_signed_ints() {
  // For each type try:
  //
  // - near the limits, averaging to 0
  // - at the limits, averaging to 0 or 0.5 depending on precision
  // - both large enough for the sum to overflow
  // - both negative enough for the sum to underflow
  {
    expect_eq!(saturated::average_scalar::<i8>((0x81i128 as i8), (0x7Fi128 as i8)), -0.0f32);
    expect_eq!(saturated::average_scalar::<i8>((0x80i128 as i8), (0x7Fi128 as i8)), -0.5f32);
    expect_eq!(saturated::average_scalar::<i8>((0x70i128 as i8), (0x75i128 as i8)), 114.5f32);
    expect_eq!(saturated::average_scalar::<i8>((0x85i128 as i8), (0x8Ai128 as i8)), -120.5f32);
  }
  {
    expect_eq!(saturated::average_scalar::<i16>((0x8001i128 as i16), (0x7FFFi128 as i16)), -0.0f32);
    expect_eq!(saturated::average_scalar::<i16>((0x8000i128 as i16), (0x7FFFi128 as i16)), -0.5f32);
    expect_eq!(saturated::average_scalar::<i16>((0x7000i128 as i16), (0x7005i128 as i16)), 28674.5f32);
    expect_eq!(saturated::average_scalar::<i16>((0x8005i128 as i16), (0x800Ai128 as i16)), -32760.5f32);
  }
  {
    expect_eq!(saturated::average_scalar::<i32>((0x80000001i128 as i32), (0x7FFFFFFFi128 as i32)), -0.0f32);
    expect_eq!(saturated::average_scalar::<i32>((0x80000000i128 as i32), (0x7FFFFFFFi128 as i32)), -0.5f32);
    expect_eq!(saturated::average_scalar::<i32>((0x70000000i128 as i32), (0x70000005i128 as i32)),
              1879048195.5f32);
    expect_eq!(saturated::average_scalar::<i32>((0x80000005i128 as i32), (0x8000000Ai128 as i32)),
              -2147483655.5f32);
  }
  {
    expect_eq!(saturated::average_scalar::<i64>((0x8000000000000001i128 as i64),
                                                (0x7FFFFFFFFFFFFFFFi128 as i64)),
              0.0f32);
    // 64-bit integers overflow the ability of a Scalar (float) to
    // represent discrete integers and so the two numbers we are
    // averaging here will look like the same number with different
    // signs and the answer will be "0"
    expect_eq!(saturated::average_scalar::<i64>((0x8000000000000000i128 as i64),
                                                (0x7FFFFFFFFFFFFFFFi128 as i64)),
              0.0f32);
    expect_near!(saturated::average_scalar::<i64>((0x7000000000000000i128 as i64),
                                                  (0x7000000000000005i128 as i64)),
                8.07045053e+18, 1e18);
    expect_near!(saturated::average_scalar::<i64>((0x8000000000000005i128 as i64),
                                                  (0x800000000000000Ai128 as i64)),
                -9.223372e+18, 1e18);
  }
}

#[test]
fn implicit_average_scalar_of_signed_ints() {
  // For each type try:
  //
  // - near the limits, averaging to 0
  // - at the limits, averaging to 0 or 0.5 depending on precision
  // - both large enough for the sum to overflow
  // - both negative enough for the sum to underflow
  {
    let mut a: i8 = 0x81i128 as i8;
    let mut b: i8 = 0x7fi128 as i8;
    expect_eq!(saturated::average_scalar(a, b), -0.0f32);
    a = (0x80i128) as _;
    expect_eq!(saturated::average_scalar(a, b), -0.5f32);
    a = (0x70i128) as _;
    b = (0x75i128) as _;
    expect_eq!(saturated::average_scalar(a, b), 114.5f32);
    a = (0x85i128) as _;
    b = (0x8Ai128) as _;
    expect_eq!(saturated::average_scalar(a, b), -120.5f32);
  }
  {
    let mut a: i16 = 0x8001i128 as i16;
    let mut b: i16 = 0x7FFFi128 as i16;
    expect_eq!(saturated::average_scalar(a, b), -0.0f32);
    a = (0x8000i128) as _;
    expect_eq!(saturated::average_scalar(a, b), -0.5f32);
    a = (0x7000i128) as _;
    b = (0x7005i128) as _;
    expect_eq!(saturated::average_scalar(a, b), 28674.5f32);
    a = (0x8005i128) as _;
    b = (0x800Ai128) as _;
    expect_eq!(saturated::average_scalar(a, b), -32760.5f32);
  }
  {
    let mut a: i32 = 0x80000001i128 as i32;
    let mut b: i32 = 0x7FFFFFFFi128 as i32;
    expect_eq!(saturated::average_scalar(a, b), -0.0f32);
    a = (0x80000000i128) as _;
    expect_eq!(saturated::average_scalar(a, b), -0.5f32);
    a = (0x70000000i128) as _;
    b = (0x70000005i128) as _;
    expect_eq!(saturated::average_scalar(a, b), 1879048195.5f32);
    a = (0x80000005i128) as _;
    b = (0x8000000Ai128) as _;
    expect_eq!(saturated::average_scalar(a, b), -2147483655.5f32);
  }
  {
    let mut a: i64 = 0x8000000000000001i128 as i64;
    let mut b: i64 = 0x7FFFFFFFFFFFFFFFi128 as i64;
    expect_eq!(saturated::average_scalar(a, b), 0.0f32);
    // 64-bit integers overflow the ability of a Scalar (float) to
    // represent discrete integers and so the two numbers we are
    // averaging here will look like the same number with different
    // signs and the answer will be "0"
    a = (0x8000000000000000i128) as _;
    expect_eq!(saturated::average_scalar::<i64>(a, b), 0.0f32);
    a = (0x7000000000000000i128) as _;
    b = (0x7000000000000005i128) as _;
    expect_near!(saturated::average_scalar::<i64>(a, b), 8.0704505e+18, 1e18);
    a = (0x8000000000000005i128) as _;
    b = (0x800000000000000Ai128) as _;
    expect_near!(saturated::average_scalar::<i64>(a, b), -9.223372e+18, 1e18);
  }
}

#[test]
fn explicit_average_scalar_of_floating_point() {
  let mut s_inf: Scalar = f32::INFINITY;
  let mut s_max: Scalar = f32::MAX;
  let mut s_big: Scalar = s_max * 0.5f32;

  {
    let mut inf: f32 = f32::INFINITY;
    let mut max: f32 = f32::MAX;
    let mut big: f32 = max * 0.5f32;

    expect_eq!(saturated::average_scalar::<f32>(big, big), s_big);
    expect_eq!(saturated::average_scalar::<f32>(max, max), s_max);
    expect_eq!(saturated::average_scalar::<f32>(big, -big), 0.0f32);
    expect_eq!(saturated::average_scalar::<f32>(max, -max), 0.0f32);
    expect_eq!(saturated::average_scalar::<f32>(-big, big), 0.0f32);
    expect_eq!(saturated::average_scalar::<f32>(-max, max), 0.0f32);
    expect_eq!(saturated::average_scalar::<f32>(-big, -big), -s_big);
    expect_eq!(saturated::average_scalar::<f32>(-max, -max), -s_max);

    expect_eq!(saturated::average_scalar::<f32>(inf, inf), s_inf);
    expect_eq!(saturated::average_scalar::<f32>(-inf, -inf), -s_inf);
    expect_true!((saturated::average_scalar::<f32>(-inf, inf)).is_nan());
    expect_true!((saturated::average_scalar::<f32>(inf, -inf)).is_nan());
  }
  {
    let mut inf: f64 = f32::INFINITY as f64;
    let mut max: f64 = f64::MAX;
    let mut big: f64 = max * 0.5;

    // Most of the averages below using the double constants will
    // overflow the Scalar return value and result in infinity,
    // so we also test with some Scalar constants (promoted to double)
    // to verify that they don't overflow in the double template
    expect_eq!(saturated::average_scalar::<f64>((s_big) as f64, (s_big) as f64), s_big);
    expect_eq!(saturated::average_scalar::<f64>((s_max) as f64, (s_max) as f64), s_max);
    expect_eq!(saturated::average_scalar::<f64>((-s_big) as f64, (-s_big) as f64), -s_big);
    expect_eq!(saturated::average_scalar::<f64>((-s_max) as f64, (-s_max) as f64), -s_max);

    // And now testing continues with the double constants which
    // mostly overflow
    expect_eq!(saturated::average_scalar::<f64>(big, big), s_inf);
    expect_eq!(saturated::average_scalar::<f64>(max, max), s_inf);
    expect_eq!(saturated::average_scalar::<f64>(big, -big), 0.0f32);
    expect_eq!(saturated::average_scalar::<f64>(max, -max), 0.0f32);
    expect_eq!(saturated::average_scalar::<f64>(-big, big), 0.0f32);
    expect_eq!(saturated::average_scalar::<f64>(-max, max), 0.0f32);
    expect_eq!(saturated::average_scalar::<f64>(-big, -big), -s_inf);
    expect_eq!(saturated::average_scalar::<f64>(-max, -max), -s_inf);

    expect_eq!(saturated::average_scalar::<f64>(inf, inf), s_inf);
    expect_eq!(saturated::average_scalar::<f64>(-inf, -inf), -s_inf);
    expect_true!((saturated::average_scalar::<f64>(-inf, inf)).is_nan());
    expect_true!((saturated::average_scalar::<f64>(inf, -inf)).is_nan());
  }
  {
    let mut inf: Scalar = f32::INFINITY;
    let mut max: Scalar = f32::MAX;
    let mut big: Scalar = max * 0.5f32;

    expect_eq!(saturated::average_scalar::<Scalar>(big, big), s_big);
    expect_eq!(saturated::average_scalar::<Scalar>(max, max), s_max);
    expect_eq!(saturated::average_scalar::<Scalar>(big, -big), 0.0f32);
    expect_eq!(saturated::average_scalar::<Scalar>(max, -max), 0.0f32);
    expect_eq!(saturated::average_scalar::<Scalar>(-big, big), 0.0f32);
    expect_eq!(saturated::average_scalar::<Scalar>(-max, max), 0.0f32);
    expect_eq!(saturated::average_scalar::<Scalar>(-big, -big), -s_big);
    expect_eq!(saturated::average_scalar::<Scalar>(-max, -max), -s_max);

    expect_eq!(saturated::average_scalar::<Scalar>(inf, inf), s_inf);
    expect_eq!(saturated::average_scalar::<Scalar>(-inf, -inf), -s_inf);
    expect_true!((saturated::average_scalar::<Scalar>(-inf, s_inf)).is_nan());
    expect_true!((saturated::average_scalar::<Scalar>(inf, -s_inf)).is_nan());
  }
}

#[test]
fn implicit_average_scalar_of_floating_point() {
  // All return values are Scalar regardless of the operand types
  // so these constants are used as the expected answers.
  let mut s_inf: Scalar = f32::INFINITY;
  let mut s_max: Scalar = f32::MAX;
  let mut s_big: Scalar = s_max * 0.5f32;

  {
    let mut inf: f32 = f32::INFINITY;
    let mut max: f32 = f32::MAX;
    let mut big: f32 = max * 0.5f32;

    expect_eq!(saturated::average_scalar(big, big), s_big);
    expect_eq!(saturated::average_scalar(max, max), s_max);
    expect_eq!(saturated::average_scalar(big, -big), 0.0f32);
    expect_eq!(saturated::average_scalar(max, -max), 0.0f32);
    expect_eq!(saturated::average_scalar(-big, big), 0.0f32);
    expect_eq!(saturated::average_scalar(-max, max), 0.0f32);
    expect_eq!(saturated::average_scalar(-big, -big), -s_big);
    expect_eq!(saturated::average_scalar(-max, -max), -s_max);

    expect_eq!(saturated::average_scalar(inf, inf), s_inf);
    expect_eq!(saturated::average_scalar(-inf, -inf), -s_inf);
    expect_true!((saturated::average_scalar(-inf, inf)).is_nan());
    expect_true!((saturated::average_scalar(inf, -inf)).is_nan());
  }
  {
    let mut inf: f64 = f64::INFINITY;
    let mut max: f64 = f64::MAX;
    let mut big: f64 = max * 0.5;

    // The s_constants converted to double. We should get finite results
    // from finding the averages of these values, but we'll get a lot of
    // overflow to infinity when testing the large double constants.
    let mut d_s_max: f64 = s_max as f64;
    let mut d_s_big: f64 = s_big as f64;
    expect_eq!(saturated::average_scalar(d_s_big, d_s_big), s_big);
    expect_eq!(saturated::average_scalar(d_s_max, d_s_max), s_max);
    expect_eq!(saturated::average_scalar(-d_s_big, -d_s_big), -s_big);
    expect_eq!(saturated::average_scalar(-d_s_max, -d_s_max), -s_max);

    // And now testing continues with the double constants which
    // mostly overflow
    expect_eq!(saturated::average_scalar(big, big), s_inf);
    expect_eq!(saturated::average_scalar(max, max), s_inf);
    expect_eq!(saturated::average_scalar(big, -big), 0.0f32);
    expect_eq!(saturated::average_scalar(max, -max), 0.0f32);
    expect_eq!(saturated::average_scalar(-big, big), 0.0f32);
    expect_eq!(saturated::average_scalar(-max, max), 0.0f32);
    expect_eq!(saturated::average_scalar(-big, -big), -s_inf);
    expect_eq!(saturated::average_scalar(-max, -max), -s_inf);

    expect_eq!(saturated::average_scalar(inf, inf), s_inf);
    expect_eq!(saturated::average_scalar(-inf, -inf), -s_inf);
    expect_true!((saturated::average_scalar(-inf, inf)).is_nan());
    expect_true!((saturated::average_scalar(inf, -inf)).is_nan());
  }
  {
    let mut inf: Scalar = f32::INFINITY;
    let mut max: Scalar = f32::MAX;
    let mut big: Scalar = max * 0.5f32;

    expect_eq!(saturated::average_scalar(big, big), s_big);
    expect_eq!(saturated::average_scalar(max, max), s_max);
    expect_eq!(saturated::average_scalar(big, -big), 0.0f32);
    expect_eq!(saturated::average_scalar(max, -max), 0.0f32);
    expect_eq!(saturated::average_scalar(-big, big), 0.0f32);
    expect_eq!(saturated::average_scalar(-max, max), 0.0f32);
    expect_eq!(saturated::average_scalar(-big, -big), -s_big);
    expect_eq!(saturated::average_scalar(-max, -max), -s_max);

    expect_eq!(saturated::average_scalar(inf, inf), s_inf);
    expect_eq!(saturated::average_scalar(-inf, -inf), -s_inf);
    expect_true!((saturated::average_scalar(-inf, s_inf)).is_nan());
    expect_true!((saturated::average_scalar(inf, -s_inf)).is_nan());
  }
}

#[test]
fn casting_finite_double_to_float_stays_finite() {
  let mut d_max: f64 = f64::MAX;
  let mut f_max: f32 = f32::MAX;

  {
    let mut result: f32 = saturated::cast::<f64, f32>(d_max);
    expect_eq!(result, f_max);
  }

  {
    let mut result: f32 = saturated::cast::<f64, f32>(-d_max);
    expect_eq!(result, -f_max);
  }
}

#[test]
fn casting_infinite_double_to_float_stays_infinite() {
  let mut d_inf: f64 = f64::INFINITY;
  let mut f_max: f32 = f32::INFINITY;

  {
    let mut result: f32 = saturated::cast::<f64, f32>(d_inf);
    expect_eq!(result, f_max);
  }

  {
    let mut result: f32 = saturated::cast::<f64, f32>(-d_inf);
    expect_eq!(result, -f_max);
  }
}

#[test]
fn casting_na_n_double_to_float_stays_na_n() {
  let mut d_nan: f64 = f64::NAN;

  {
    let mut result: f32 = saturated::cast::<f64, f32>(d_nan);
    expect_true!((result).is_nan());
  }

  {
    let mut result: f32 = saturated::cast::<f64, f32>(-d_nan);
    expect_true!((result).is_nan());
  }
}

#[test]
fn casting_large_scalar_to_signed_int_produces_limit() {
  // larger than even any [u]int64_t;
  let mut large: Scalar = 1e20f32;

  {
    let mut result = saturated::cast::<Scalar, i8>(large);
    expect_eq!(result, (0x7Fi128 as i8));
  }
  {
    let mut result = saturated::cast::<Scalar, i8>(-large);
    expect_eq!(result, (0x80i128 as i8));
  }

  {
    let mut result = saturated::cast::<Scalar, i16>(large);
    expect_eq!(result, (0x7FFFi128 as i16));
  }
  {
    let mut result = saturated::cast::<Scalar, i16>(-large);
    expect_eq!(result, (0x8000i128 as i16));
  }

  {
    let mut result = saturated::cast::<Scalar, i32>(large);
    expect_eq!(result, (0x7FFFFFFFi128 as i32));
  }
  {
    let mut result = saturated::cast::<Scalar, i32>(-large);
    expect_eq!(result, (0x80000000i128 as i32));
  }

  {
    let mut result = saturated::cast::<Scalar, i64>(large);
    expect_eq!(result, (0x7FFFFFFFFFFFFFFFi128 as i64));
  }
  {
    let mut result = saturated::cast::<Scalar, i64>(-large);
    expect_eq!(result, (0x8000000000000000i128 as i64));
  }
}

#[test]
fn casting_infinite_scalar_to_signed_int_produces_limit() {
  // larger than even any [u]int64_t;
  let mut inf: Scalar = f32::INFINITY;

  {
    let mut result = saturated::cast::<Scalar, i8>(inf);
    expect_eq!(result, (0x7Fi128 as i8));
  }
  {
    let mut result = saturated::cast::<Scalar, i8>(-inf);
    expect_eq!(result, (0x80i128 as i8));
  }

  {
    let mut result = saturated::cast::<Scalar, i16>(inf);
    expect_eq!(result, (0x7FFFi128 as i16));
  }
  {
    let mut result = saturated::cast::<Scalar, i16>(-inf);
    expect_eq!(result, (0x8000i128 as i16));
  }

  {
    let mut result = saturated::cast::<Scalar, i32>(inf);
    expect_eq!(result, (0x7FFFFFFFi128 as i32));
  }
  {
    let mut result = saturated::cast::<Scalar, i32>(-inf);
    expect_eq!(result, (0x80000000i128 as i32));
  }

  {
    let mut result = saturated::cast::<Scalar, i64>(inf);
    expect_eq!(result, (0x7FFFFFFFFFFFFFFFi128 as i64));
  }
  {
    let mut result = saturated::cast::<Scalar, i64>(-inf);
    expect_eq!(result, (0x8000000000000000i128 as i64));
  }
}

#[test]
fn casting_na_n_scalar_to_signed_int_produces_zero() {
  // larger than even any [u]int64_t;
  let mut nan: Scalar = f32::NAN;

  {
    let mut result = saturated::cast::<Scalar, i8>(nan);
    expect_eq!(result, (0i128 as i8));
  }

  {
    let mut result = saturated::cast::<Scalar, i16>(nan);
    expect_eq!(result, (0i128 as i16));
  }

  {
    let mut result = saturated::cast::<Scalar, i32>(nan);
    expect_eq!(result, (0i128 as i32));
  }

  {
    let mut result = saturated::cast::<Scalar, i64>(nan);
    expect_eq!(result, (0i128 as i64));
  }
}

