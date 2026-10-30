// Crate root of the Rust port of pkg/_fe_analyzer_shared (not a mirrored file).
//
// Every module below mirrors one Dart library under ../lib/src at the same
// relative path, keeps its structure and names, and names that library in
// its first line.
//
// The port keeps upstream's control flow and comparisons as written
// (`$0 <= next && next <= $9`, branches that repeat a body) so that it can
// be read against the Dart line by line.
#![allow(
    clippy::manual_range_contains,
    clippy::if_same_then_else,
    clippy::needless_borrow
)]
// Constants and enum values keep their Dart spelling (see ../README.md).
#![allow(non_upper_case_globals)]
// Ported code keeps upstream's signatures, `return` chains and doc comments.
#![allow(
    clippy::too_many_arguments,
    clippy::needless_return,
    clippy::doc_lazy_continuation,
    clippy::new_without_default
)]

pub mod experiments;
pub mod messages;
pub mod scanner;
pub mod util;
