// Not an upstream file: the crate root of the Rust port of
// flutter/impeller/geometry.
//
// Each module ports the file of the same name under `..` and names it in its
// first line; `*_unittests` modules port the upstream gtest files of the same
// name. See README.md.

#![forbid(unsafe_code)]
#![allow(non_upper_case_globals, non_snake_case)]

pub mod constants;
pub mod cxx;
pub mod print;
pub mod saturated_math;
pub mod scalar;
pub mod type_traits;

pub use saturated_math::saturated;
