// Crate root of the Rust port of pkg/kernel (not a mirrored file).
//
// Every module below mirrors one Dart library under ../lib at the same
// relative path, keeps its structure and names, and names that library in
// its first line. See ../README.md.
#![forbid(unsafe_code)]
// Names keep their Dart spelling, so the port reads against upstream line
// by line.
#![allow(non_snake_case, non_upper_case_globals)]
#![allow(clippy::too_many_arguments, clippy::new_without_default)]

pub mod ast;
pub mod binary;
pub mod canonical_name;
pub mod class_hierarchy;
pub mod core_types;
pub mod reference_index;
pub mod src;
pub mod type_algebra;
pub mod type_environment;
pub mod visitor;
