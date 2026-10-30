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

/// Every public item of the crate, for the ported tests.
#[cfg(test)]
#[allow(unused_imports)]
pub(crate) mod prelude {
    pub use crate::arc::*;
    pub use crate::color::*;
    pub use crate::constants::*;
    pub use crate::dashed_line_path_source::*;
    pub use crate::geometry_asserts::*;
    pub use crate::gradient::*;
    pub use crate::half::*;
    pub use crate::matrix::*;
    pub use crate::matrix_decomposition::*;
    pub use crate::path_source::*;
    pub use crate::point::*;
    pub use crate::quaternion::*;
    pub use crate::rational::*;
    pub use crate::rect::*;
    pub use crate::round_rect::*;
    pub use crate::round_superellipse::*;
    pub use crate::round_superellipse_param::RoundSuperellipseParam;
    pub use crate::rounding_radii::*;
    pub use crate::rstransform::*;
    pub use crate::saturated;
    pub use crate::scalar::*;
    pub use crate::separated_vector::*;
    pub use crate::shear::*;
    pub use crate::sigma::*;
    pub use crate::size::*;
    pub use crate::stroke_parameters::*;
    pub use crate::trig::*;
    pub use crate::vector::*;
    pub use crate::wangs_formula::*;
}

#[cfg(test)]
mod geometry_asserts;
#[cfg(test)]
mod point_unittests;
#[cfg(test)]
mod rational_unittests;
#[cfg(test)]
mod rstransform_unittests;
#[cfg(test)]
mod size_unittests;
#[cfg(test)]
mod trig_unittests;
#[cfg(test)]
mod wangs_formula_unittests;
#[cfg(test)]
mod matrix_unittests;
#[cfg(test)]
mod rounding_radii_unittests;
#[cfg(test)]
mod saturated_math_unittests;
#[cfg(test)]
mod arc_unittests;
#[cfg(test)]
mod geometry_unittests;
#[cfg(test)]
mod path_source_unittests;
#[cfg(test)]
mod rect_unittests;
#[cfg(test)]
mod round_rect_unittests;
#[cfg(test)]
mod round_superellipse_unittests;
