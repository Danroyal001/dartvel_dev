// Not an upstream file: the crate root of the Rust port of flutter/fml.
//
// Each module ports the flutter/fml file at the same path and names it in
// its first line; `*_unittest(s)` modules port the upstream gtest files of
// the same name. See README.md.

pub mod ascii_trie;
pub mod base32;
pub mod endianness;
pub mod hash_combine;
pub mod hex_codec;
pub mod math;
pub mod string_conversion;
pub mod time;

#[cfg(test)]
mod ascii_trie_unittests;
#[cfg(test)]
mod base32_unittest;
#[cfg(test)]
mod endianness_unittests;
#[cfg(test)]
mod hash_combine_unittests;
#[cfg(test)]
mod hex_codec_unittest;
#[cfg(test)]
mod math_unittests;
#[cfg(test)]
mod string_conversion_unittests;
