// Port of flutter/fml/math.h (namespace flutter::math).
//
// Upstream writes each constant as a double literal converted to float; the
// port does the same (`f64 as f32`), since a decimal literal read straight
// into an f32 can round differently.
#![allow(non_upper_case_globals)]
// The literals are upstream's, digit for digit.
#![allow(clippy::approx_constant, clippy::excessive_precision)]

// e
pub const kE: f32 = 2.7182818284590452354_f64 as f32;

// log_2 e
pub const kLog2E: f32 = 1.4426950408889634074_f64 as f32;

// log_10 e
pub const kLog10E: f32 = 0.43429448190325182765_f64 as f32;

// log_e 2
pub const kLogE2: f32 = 0.69314718055994530942_f64 as f32;

// log_e 10
pub const kLogE10: f32 = 2.30258509299404568402_f64 as f32;

// pi
pub const kPi: f32 = 3.14159265358979323846_f64 as f32;

// pi/2
pub const kPiOver2: f32 = 1.57079632679489661923_f64 as f32;

// pi/4
pub const kPiOver4: f32 = 0.78539816339744830962_f64 as f32;

// 1/pi
pub const k1OverPi: f32 = 0.31830988618379067154_f64 as f32;

// 2/pi
pub const k2OverPi: f32 = 0.63661977236758134308_f64 as f32;

// 2/sqrt(pi)
pub const k2OverSqrtPi: f32 = 1.12837916709551257390_f64 as f32;

// sqrt(2)
pub const kSqrt2: f32 = 1.41421356237309504880_f64 as f32;

// 1/sqrt(2)
pub const k1OverSqrt2: f32 = 0.70710678118654752440_f64 as f32;
