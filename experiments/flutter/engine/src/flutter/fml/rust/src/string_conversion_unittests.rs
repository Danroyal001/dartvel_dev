// Port of flutter/fml/string_conversion_unittests.cc.

use super::string_conversion::*;
use std::path::Path;

fn u(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

#[test]
fn utf16_to_utf16_empty() {
    assert_eq!(utf8_to_utf16(""), u(""));
}

#[test]
fn utf8_to_utf16_ascii() {
    assert_eq!(utf8_to_utf16("abc123"), u("abc123"));
}

#[test]
fn utf8_to_utf16_unicode() {
    assert_eq!(utf8_to_utf16(b"\xe2\x98\x83"), vec![0x2603]);
}

#[test]
fn utf16_to_utf8_empty() {
    assert_eq!(utf16_to_utf8(&u("")), "");
}

#[test]
fn utf16_to_utf8_ascii() {
    assert_eq!(utf16_to_utf8(&u("abc123")), "abc123");
}

#[test]
fn utf16_to_utf8_unicode() {
    assert_eq!(utf16_to_utf8(&[0x2603]).as_bytes(), b"\xe2\x98\x83");
}

#[test]
fn path_to_utf8_test() {
    assert_eq!(path_to_utf8(Path::new("abc")), b"abc");
    assert_eq!(path_to_utf8(Path::new("\u{2603}")), b"\xe2\x98\x83");
}
