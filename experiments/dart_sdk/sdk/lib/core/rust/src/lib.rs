// Crate root of the Rust port of sdk/lib/core (not a mirrored file).
//
// Every module below mirrors one Dart file in .. (sdk/lib/core), keeps its
// structure and names, and names that file in its first line. See
// ../README.md.
#![forbid(unsafe_code)]
// Names keep their Dart spelling, so the port reads against upstream line
// by line.
#![allow(non_snake_case, non_upper_case_globals)]
#![allow(clippy::too_many_arguments)]

pub mod errors;
pub mod exceptions;
pub mod uri;
