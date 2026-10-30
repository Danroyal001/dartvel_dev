// Crate root of the Rust port of pkg/_fe_analyzer_shared (not a mirrored file).
//
// Every module below mirrors one Dart library under ../lib/src at the same
// relative path, keeps its structure and names, and names that library in
// its first line.
//
// The port keeps upstream's control flow and comparisons as written
// (`$0 <= next && next <= $9`, branches that repeat a body) so that it can
// be read against the Dart line by line.
#![allow(clippy::manual_range_contains, clippy::if_same_then_else, clippy::needless_borrow)]

pub mod scanner;
pub mod util;
