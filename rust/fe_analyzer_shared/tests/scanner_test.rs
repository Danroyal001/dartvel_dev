// Port of pkg/front_end/test/scanner_test.dart, the classes with no oracle
// equivalent: CharSequenceReaderTest and TokenTypeTest. ScannerTest's cases
// scan source strings; those strings are in the oracle's corpus (see
// scanner_oracle.rs), which checks every token the upstream scanner makes
// for them rather than the subset each case asserts.

use fe_analyzer_shared::scanner::reader::{CharSequenceReader, CharacterReader};
use fe_analyzer_shared::scanner::token::TokenType;

fn units(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

// -- CharSequenceReaderTest -------------------------------------------------

#[test]
fn char_sequence_reader_test_advance() {
    let mut reader = CharSequenceReader::new(units("x"));
    assert_eq!(reader.advance(), 0x78);
    assert_eq!(reader.advance(), -1);
    assert_eq!(reader.advance(), -1);
}

#[test]
fn char_sequence_reader_test_creation() {
    let reader = CharSequenceReader::new(units("x"));
    assert_eq!(reader.get_contents(), units("x"));
}

#[test]
fn char_sequence_reader_test_get_offset() {
    let mut reader = CharSequenceReader::new(units("x"));
    assert_eq!(reader.offset(), -1);
    reader.advance();
    assert_eq!(reader.offset(), 0);
    reader.advance();
    assert_eq!(reader.offset(), 0);
}

#[test]
fn char_sequence_reader_test_get_string() {
    let mut reader = CharSequenceReader::new(units("xyzzy"));
    reader.set_offset(3);
    assert_eq!(reader.get_string(1, 0), units("yzz"));
    assert_eq!(reader.get_string(2, 1), units("zzy"));
}

#[test]
fn char_sequence_reader_test_peek() {
    let mut reader = CharSequenceReader::new(units("xy"));
    assert_eq!(reader.peek(), 0x78);
    assert_eq!(reader.peek(), 0x78);
    reader.advance();
    assert_eq!(reader.peek(), 0x79);
    assert_eq!(reader.peek(), 0x79);
    reader.advance();
    assert_eq!(reader.peek(), -1);
    assert_eq!(reader.peek(), -1);
}

#[test]
fn char_sequence_reader_test_set_offset() {
    let mut reader = CharSequenceReader::new(units("xyz"));
    reader.set_offset(2);
    assert_eq!(reader.offset(), 2);
}

// -- TokenTypeTest ------------------------------------------------------------

#[test]
fn token_type_test_is_operator() {
    for t in [
        TokenType::AMPERSAND,
        TokenType::AMPERSAND_AMPERSAND,
        TokenType::AMPERSAND_EQ,
        TokenType::BANG,
        TokenType::BANG_EQ,
        TokenType::BAR,
        TokenType::BAR_BAR,
        TokenType::BAR_EQ,
        TokenType::CARET,
        TokenType::CARET_EQ,
        TokenType::EQ,
        TokenType::EQ_EQ,
        TokenType::GT,
        TokenType::GT_EQ,
        TokenType::GT_GT,
        TokenType::GT_GT_EQ,
        TokenType::INDEX,
        TokenType::INDEX_EQ,
        TokenType::LT,
        TokenType::LT_EQ,
        TokenType::LT_LT,
        TokenType::LT_LT_EQ,
        TokenType::MINUS,
        TokenType::MINUS_EQ,
        TokenType::MINUS_MINUS,
        TokenType::PERCENT,
        TokenType::PERCENT_EQ,
        TokenType::PERIOD_PERIOD,
        TokenType::PLUS,
        TokenType::PLUS_EQ,
        TokenType::PLUS_PLUS,
        TokenType::QUESTION,
        TokenType::SLASH,
        TokenType::SLASH_EQ,
        TokenType::STAR,
        TokenType::STAR_EQ,
        TokenType::TILDE,
        TokenType::TILDE_SLASH,
        TokenType::TILDE_SLASH_EQ,
    ] {
        assert!(t.is_operator, "{t}");
    }
}

#[test]
fn token_type_test_is_user_definable_operator() {
    for t in [
        TokenType::AMPERSAND,
        TokenType::BAR,
        TokenType::CARET,
        TokenType::EQ_EQ,
        TokenType::GT,
        TokenType::GT_EQ,
        TokenType::GT_GT,
        TokenType::INDEX,
        TokenType::INDEX_EQ,
        TokenType::LT,
        TokenType::LT_EQ,
        TokenType::LT_LT,
        TokenType::MINUS,
        TokenType::PERCENT,
        TokenType::PLUS,
        TokenType::SLASH,
        TokenType::STAR,
        TokenType::TILDE,
        TokenType::TILDE_SLASH,
    ] {
        assert!(t.is_user_definable_operator, "{t}");
    }
}
