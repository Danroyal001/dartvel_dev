// Module list for lib/src/scanner (not a mirrored file).

pub mod abstract_scanner;
pub mod characters;
pub mod error_token;
pub mod internal_utils;
pub mod keyword_state;
pub mod recover;
#[allow(clippy::module_inception)]
pub mod scanner;
pub mod string_canonicalizer;
pub mod string_scanner;
pub mod token;
pub mod token_constants;
pub mod token_impl;
pub mod utf8_bytes_scanner;
