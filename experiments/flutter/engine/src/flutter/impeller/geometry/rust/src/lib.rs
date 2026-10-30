// Not an upstream file: the crate root of the Rust port of
// flutter/impeller/geometry.
//
// Each module ports the file of the same name under `..` and names it in its
// first line; `*_unittests` modules port the upstream gtest files of the same
// name. See README.md.

#![forbid(unsafe_code)]
#![allow(non_upper_case_globals, non_snake_case, non_camel_case_types)]

pub mod arc;
pub mod color;
pub mod constants;
pub mod cxx;
pub mod dashed_line_path_source;
pub mod gradient;
pub mod half;
pub mod matrix;
pub mod matrix_decomposition;
pub mod path_source;
pub mod point;
pub mod print;
pub mod quaternion;
pub mod rational;
pub mod rect;
pub mod round_rect;
pub mod round_superellipse;
pub mod round_superellipse_param;
pub mod rounding_radii;
pub mod rstransform;
pub mod saturated_math;
pub mod scalar;
pub mod separated_vector;
pub mod shear;
pub mod sigma;
pub mod size;
pub mod stroke_parameters;
pub mod trig;
pub mod type_traits;
pub mod vector;
pub mod wangs_formula;

pub use saturated_math::saturated;
