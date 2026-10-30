// Port of lib/src/parser/quote.dart.
//
// Strings are UTF-16 code units, as Dart strings are. The `location` an
// unescape error is reported at is a token. `considerCanonicalizeString`
// only shares equal strings, so it has no counterpart.

use crate::messages::codes::Message;
use crate::messages::diagnostic as diag;
use crate::scanner::characters::*;
use crate::scanner::token::TokenId;

/// `UnescapeErrorListener` (in listener.dart): what an unescape error is
/// reported to.
pub trait UnescapeErrorListener {
    fn handle_unescape_error(
        &mut self,
        message: &Message,
        location: TokenId,
        offset: i32,
        length: i32,
    );
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Quote {
    Single,
    Double,
    MultiLineSingle,
    MultiLineDouble,
    RawSingle,
    RawDouble,
    RawMultiLineSingle,
    RawMultiLineDouble,
}

fn starts_with(s: &[u16], prefix: &str) -> bool {
    let p: Vec<u16> = prefix.encode_utf16().collect();
    s.starts_with(&p)
}

fn contains(s: &[u16], c: i32) -> bool {
    s.iter().any(|&u| u as i32 == c)
}

pub fn analyze_quote(first: &[u16]) -> Quote {
    if starts_with(first, "\"\"\"") {
        return Quote::MultiLineDouble;
    }
    if starts_with(first, "r\"\"\"") {
        return Quote::RawMultiLineDouble;
    }
    if starts_with(first, "'''") {
        return Quote::MultiLineSingle;
    }
    if starts_with(first, "r'''") {
        return Quote::RawMultiLineSingle;
    }
    if starts_with(first, "\"") {
        return Quote::Double;
    }
    if starts_with(first, "r\"") {
        return Quote::RawDouble;
    }
    if starts_with(first, "'") {
        return Quote::Single;
    }
    if starts_with(first, "r'") {
        return Quote::RawSingle;
    }
    panic!("'{}' in analyzeQuote", String::from_utf16_lossy(first));
}

// Note: based on [StringValidator.quotingFromString]
// (pkg/compiler/lib/src/string_validator.dart).
pub fn length_of_optional_whitespace_prefix(first: &[u16], start: usize) -> usize {
    let code_units = first;
    let mut i = start;
    while i < code_units.len() {
        let mut code = code_units[i] as i32;
        if code == C_BACKSLASH {
            i += 1;
            if i < code_units.len() {
                code = code_units[i] as i32;
            } else {
                break;
            }
        }
        if code == C_TAB || code == C_SPACE {
            i += 1;
            continue;
        }
        if code == C_CR {
            if i + 1 < code_units.len() && code_units[i + 1] as i32 == C_LF {
                i += 1;
            }
            return i + 1;
        }
        if code == C_LF {
            return i + 1;
        }
        break; // Not a white-space character.
    }
    start
}

pub fn first_quote_length(first: &[u16], quote: Quote) -> usize {
    match quote {
        Quote::Single | Quote::Double => 1,
        Quote::MultiLineSingle | Quote::MultiLineDouble => {
            length_of_optional_whitespace_prefix(first, 3)
        }
        Quote::RawSingle | Quote::RawDouble => 2,
        Quote::RawMultiLineSingle | Quote::RawMultiLineDouble => {
            length_of_optional_whitespace_prefix(first, 4)
        }
    }
}

pub fn last_quote_length(quote: Quote) -> usize {
    match quote {
        Quote::Single | Quote::Double | Quote::RawSingle | Quote::RawDouble => 1,
        Quote::MultiLineSingle
        | Quote::MultiLineDouble
        | Quote::RawMultiLineSingle
        | Quote::RawMultiLineDouble => 3,
    }
}

pub fn unescape_first_string_part(
    first: &[u16],
    quote: Quote,
    location: TokenId,
    listener: &mut dyn UnescapeErrorListener,
) -> Vec<u16> {
    let start_index = first_quote_length(first, quote);
    unescape(
        &first[start_index..],
        quote,
        location,
        listener,
        start_index as i32,
    )
}

pub fn unescape_middle_string_part(
    middle: &[u16],
    quote: Quote,
    location: TokenId,
    listener: &mut dyn UnescapeErrorListener,
) -> Vec<u16> {
    unescape(middle, quote, location, listener, 0)
}

pub fn unescape_last_string_part(
    last: &[u16],
    quote: Quote,
    location: TokenId,
    is_last_quote_synthetic: bool,
    listener: &mut dyn UnescapeErrorListener,
) -> Vec<u16> {
    let end = last.len()
        - if is_last_quote_synthetic {
            0
        } else {
            last_quote_length(quote)
        };
    unescape(&last[..end], quote, location, listener, 0)
}

pub fn unescape_string(
    string: &[u16],
    location: TokenId,
    listener: &mut dyn UnescapeErrorListener,
) -> Vec<u16> {
    let quote = analyze_quote(string);
    let start_index = first_quote_length(string, quote) as i64;
    let end_index = string.len() as i64 - last_quote_length(quote) as i64;
    if start_index > end_index {
        // An error has already been signaled.
        return Vec::new();
    }
    unescape(
        &string[start_index as usize..end_index as usize],
        quote,
        location,
        listener,
        start_index as i32,
    )
}

pub fn unescape(
    string: &[u16],
    quote: Quote,
    location: TokenId,
    listener: &mut dyn UnescapeErrorListener,
    string_start_offset: i32,
) -> Vec<u16> {
    match quote {
        Quote::Single | Quote::Double => {
            if !contains(string, C_BACKSLASH) {
                string.to_vec()
            } else {
                unescape_code_units(string, false, location, listener, string_start_offset)
            }
        }
        Quote::MultiLineSingle | Quote::MultiLineDouble => {
            if !contains(string, C_BACKSLASH) && !contains(string, C_CR) {
                string.to_vec()
            } else {
                unescape_code_units(string, false, location, listener, string_start_offset)
            }
        }
        Quote::RawSingle | Quote::RawDouble => string.to_vec(),
        Quote::RawMultiLineSingle | Quote::RawMultiLineDouble => {
            if !contains(string, C_CR) {
                string.to_vec()
            } else {
                unescape_code_units(string, true, location, listener, string_start_offset)
            }
        }
    }
}

/// `new String.fromCharCodes(codes)`: code points above 0xFFFF become
/// surrogate pairs.
fn from_char_codes(codes: &[i32]) -> Vec<u16> {
    let mut result = Vec::with_capacity(codes.len());
    for &c in codes {
        if c > 0xFFFF {
            let c = c - 0x10000;
            result.push((0xD800 + (c >> 10)) as u16);
            result.push((0xDC00 + (c & 0x3FF)) as u16);
        } else {
            result.push(c as u16);
        }
    }
    result
}

// Note: based on
// [StringValidator.validateString](pkg/compiler/lib/src/string_validator.dart).
pub fn unescape_code_units(
    code_units: &[u16],
    is_raw: bool,
    location: TokenId,
    listener: &mut dyn UnescapeErrorListener,
    string_start_offset: i32,
) -> Vec<u16> {
    let length = code_units.len() as i32;
    let unit = |i: i32| code_units[i as usize] as i32;
    let original = || code_units.to_vec();
    // Can't use Uint8List or Uint16List here, the code units may be larger.
    let mut result: Vec<i32> = Vec::with_capacity(code_units.len());
    // When an error is reported below, `i` or `begin` is one past the
    // backslash, so the reported offset subtracts one to point at it.
    let mut i: i32 = 0;
    while i < length {
        let mut code = unit(i);
        if code == C_CR {
            if i + 1 < length && unit(i + 1) == C_LF {
                i += 1;
            }
            code = C_LF;
        } else if !is_raw && code == C_BACKSLASH {
            i += 1;
            if length == i {
                // This should only be reachable in error cases.
                listener.handle_unescape_error(
                    &diag::invalidEscapeStarted.message(),
                    location,
                    i + string_start_offset - 1,
                    1,
                );
                return original();
            }
            code = unit(i);
            if code == C_n {
                code = C_LF;
            } else if code == C_r {
                code = C_CR;
            } else if code == C_f {
                code = C_FF;
            } else if code == C_b {
                code = C_BS;
            } else if code == C_t {
                code = C_TAB;
            } else if code == C_v {
                code = C_VTAB;
            } else if code == C_x {
                // Expect exactly 2 hex digits.
                let begin = i;
                if length <= i + 2 {
                    listener.handle_unescape_error(
                        &diag::invalidHexEscape.message(),
                        location,
                        begin + string_start_offset - 1,
                        length + 1 - begin,
                    );
                    return original();
                }
                code = 0;
                for _ in 0..2 {
                    i += 1;
                    let digit = unit(i);
                    if !is_hex_digit(digit) {
                        listener.handle_unescape_error(
                            &diag::invalidHexEscape.message(),
                            location,
                            begin + string_start_offset - 1,
                            i + 1 - begin,
                        );
                        return original();
                    }
                    code = (code << 4) + hex_digit_value(digit);
                }
            } else if code == C_u {
                let begin = i;
                if length == i + 1 {
                    listener.handle_unescape_error(
                        &diag::invalidUnicodeEscapeUStarted.message(),
                        location,
                        begin + string_start_offset - 1,
                        length + 1 - begin,
                    );
                    return original();
                }
                code = unit(i + 1);
                let mut found_end_bracket = false;
                if code == C_OPEN_CURLY_BRACKET {
                    // Expect 1-6 hex digits followed by '}'.
                    i += 1;
                    if length == i {
                        listener.handle_unescape_error(
                            &diag::invalidUnicodeEscapeUBracket.message(),
                            location,
                            begin + string_start_offset - 1,
                            i + 1 - begin,
                        );
                        return original();
                    }
                    code = 0;
                    for j in 0..7 {
                        i += 1;
                        if length == i {
                            listener.handle_unescape_error(
                                &diag::invalidUnicodeEscapeUBracket.message(),
                                location,
                                begin + string_start_offset - 1,
                                i + 1 - begin,
                            );
                            return original();
                        }
                        let digit = unit(i);
                        if j != 0 && digit == C_CLOSE_CURLY_BRACKET {
                            found_end_bracket = true;
                            break;
                        } else if j == 6 {
                            break;
                        }
                        if !is_hex_digit(digit) {
                            listener.handle_unescape_error(
                                &diag::invalidUnicodeEscapeUBracket.message(),
                                location,
                                begin + string_start_offset - 1,
                                i + 2 - begin,
                            );
                            return original();
                        }
                        code = (code << 4) + hex_digit_value(digit);
                    }
                    if !found_end_bracket {
                        listener.handle_unescape_error(
                            &diag::invalidUnicodeEscapeUBracket.message(),
                            location,
                            begin + string_start_offset - 1,
                            i + 1 - begin,
                        );
                    }
                } else {
                    // Expect exactly 4 hex digits.
                    if length <= i + 4 {
                        listener.handle_unescape_error(
                            &diag::invalidUnicodeEscapeUNoBracket.message(),
                            location,
                            begin + string_start_offset - 1,
                            length + 1 - begin,
                        );
                        return original();
                    }
                    code = 0;
                    for _ in 0..4 {
                        i += 1;
                        let digit = unit(i);
                        if !is_hex_digit(digit) {
                            listener.handle_unescape_error(
                                &diag::invalidUnicodeEscapeUNoBracket.message(),
                                location,
                                begin + string_start_offset - 1,
                                i + 1 - begin,
                            );
                            return original();
                        }
                        code = (code << 4) + hex_digit_value(digit);
                    }
                }
                if code > 0x10FFFF {
                    listener.handle_unescape_error(
                        &diag::invalidCodePoint.message(),
                        location,
                        begin + string_start_offset - 1,
                        i + 1 - begin,
                    );
                    return original();
                }
            } else {
                // Nothing, escaped character is passed through;
            }
        }
        result.push(code);
        i += 1;
    }
    from_char_codes(&result)
}
