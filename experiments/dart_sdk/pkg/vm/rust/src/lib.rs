// Crate root of the Rust port of pkg/vm (not a mirrored file).
//
// Every module below mirrors one Dart library under ../lib at the same
// relative path, keeps its structure and names, and names that library in
// its first line. See ../README.md.
#![forbid(unsafe_code)]
// Names keep their Dart spelling, so the port reads against upstream line
// by line.
#![allow(non_snake_case, non_upper_case_globals)]
#![allow(clippy::too_many_arguments, clippy::new_without_default)]

pub mod transformations;
