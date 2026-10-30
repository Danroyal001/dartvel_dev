// Port of lib/src/messages/conversions.dart.
//
// Where upstream throws a string, the port panics with it.

use crate::messages::codes::{demangle_mixin_application_name, itemize_names};
use crate::scanner::token::{TokenId, TokenStore};

pub fn code_point_to_unicode(code_point: i64) -> String {
    // Write unicode value using at least four (but otherwise no more than
    // necessary) hex digits, using uppercase letters.
    format!("U+{:04X}", code_point)
}

pub fn name_or_unnamed(name: &str) -> &str {
    if name.is_empty() { "(unnamed)" } else { name }
}

pub fn string_or_empty(string: &str) -> &str {
    if string.is_empty() { "(empty)" } else { string }
}

pub fn token_to_lexeme(tokens: &TokenStore, token: TokenId) -> String {
    tokens.lexeme_string(token)
}

pub fn validate_and_demangle_name(name: &str) -> String {
    if name.is_empty() {
        panic!("No name provided");
    }
    demangle_mixin_application_name(name)
}

pub fn validate_and_itemize_names(names: &[&str]) -> String {
    if names.is_empty() {
        panic!("No names provided");
    }
    itemize_names(names)
}

pub fn validate_character(character: &str) -> &str {
    if character.chars().count() != 1 {
        panic!("Not a character '{character}'");
    }
    character
}

pub fn validate_string(string: &str) -> &str {
    if string.is_empty() {
        panic!("No string provided");
    }
    string
}
