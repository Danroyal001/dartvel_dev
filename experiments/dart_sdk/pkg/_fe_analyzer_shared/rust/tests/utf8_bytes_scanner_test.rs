// Port of pkg/_fe_analyzer_shared/test/scanner/utf8_bytes_scanner_test.dart.
//
// Upstream counts `advance()` calls with a subclass to show that
// `passIdentifierCharAllowDollar` does not re-scan; the port's
// `pass_identifier_char_allow_dollar` does not call `advance` at all, so
// that case checks where the scan stops, which is what the count protected.

use std::rc::Rc;

use fe_analyzer_shared::scanner::abstract_scanner::ScannerSubclass;
use fe_analyzer_shared::scanner::characters::C_EOF;
use fe_analyzer_shared::scanner::utf8_bytes_scanner::Utf8BytesScanner;

fn bytes(s: &str) -> Rc<[u8]> {
    Rc::from(s.as_bytes())
}

#[test]
fn scan_until_line_end_at_eof_for_ascii_comment() {
    let mut scanner = Utf8BytesScanner::new(bytes("// hello"), None, false, None, true);
    scanner.sub.advance(); // '/'
    scanner.sub.advance(); // '/'
    // $EOF (-1) should not make it look like non-ascii.
    assert!(scanner.sub.scan_until_line_end());
}

#[test]
fn pass_identifier_char_allow_dollar_does_not_rescan_on_loop_exit() {
    // 11 identifier chars + trailing spaces
    let mut scanner = Utf8BytesScanner::new(bytes("abcdefghijk "), None, false, None, true);
    scanner.sub.advance(); // reads 'a'
    let next = scanner.sub.pass_identifier_char_allow_dollar();
    assert_eq!(next, 0x20);
    assert_eq!(scanner.sub.byte_offset, 11);
}

#[test]
fn current_before_advance_returns_eof() {
    let scanner = Utf8BytesScanner::new(bytes("hello"), None, false, None, true);
    assert_eq!(scanner.sub.current(), C_EOF);
}

#[test]
fn initial_string_offset_is_minus_one() {
    let scanner = Utf8BytesScanner::new(bytes("hello"), None, false, None, true);
    assert_eq!(scanner.sub.string_offset(), -1);
}

#[test]
fn current_and_string_offset_on_empty_input() {
    let mut scanner = Utf8BytesScanner::new(bytes(""), None, false, None, true);
    assert_eq!(scanner.sub.current(), C_EOF);
    assert_eq!(scanner.sub.string_offset(), -1);
    scanner.sub.advance();
    assert_eq!(scanner.sub.current(), C_EOF);
    assert_eq!(scanner.sub.string_offset(), 0);
}
