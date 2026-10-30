// Port of lib/src/scanner/token_impl.dart.
//
// The token classes here are constructors on `TokenStore` that tag the new
// token with the class's `TokenRuntimeType`. Upstream's `_LazySubstring`
// (`_CompactLazySubstring`, `_FullLazySubstring`) defers building a
// lexeme's `String` until it is read; a `Lexeme::Utf16` or `Lexeme::Utf8`
// range is that deferral, so the lexeme is decoded on every read instead of
// once. `LAZY_THRESHOLD` and `allowLazy` only choose when upstream builds the
// string, never what it contains, so they have no counterpart.

use super::characters::*;
use super::token::{
    Keyword, KeywordStyle, Lexeme, TokenId, TokenRuntimeType, TokenStore, TokenType,
};

/// `StringTokenImpl.LAZY_THRESHOLD`, kept for reference.
pub const LAZY_THRESHOLD: i32 = 4;

impl TokenStore {
    /// `new StringTokenImpl.fromString(type, value, charOffset, ...)`.
    /// `canonicalize` has no observable effect (see string_canonicalizer.rs).
    pub fn string_token_impl_from_string(
        &mut self,
        type_: &TokenType,
        value: Vec<u16>,
        char_offset: i32,
        preceding_comments: TokenId,
    ) -> TokenId {
        let index = self.add_string(value);
        self.push(
            TokenRuntimeType::StringTokenImpl,
            type_,
            char_offset,
            preceding_comments,
            Lexeme::Owned(index),
        )
    }

    /// `new StringTokenImpl.fromSubstring(type, data, start, end, charOffset,
    /// ...)` over the scanner's UTF-16 source.
    #[inline]
    pub fn string_token_impl_from_substring(
        &mut self,
        type_: &TokenType,
        start: i32,
        end: i32,
        char_offset: i32,
        preceding_comments: TokenId,
    ) -> TokenId {
        self.push(
            TokenRuntimeType::StringTokenImpl,
            type_,
            char_offset,
            preceding_comments,
            Lexeme::Utf16 {
                start: start as u32,
                end: end as u32,
            },
        )
    }

    /// `new StringTokenImpl.fromUtf8Bytes(type, data, start, end, asciiOnly,
    /// charOffset, ...)` over the scanner's UTF-8 source.
    #[inline]
    pub fn string_token_impl_from_utf8_bytes(
        &mut self,
        type_: &TokenType,
        start: i32,
        end: i32,
        ascii_only: bool,
        char_offset: i32,
        preceding_comments: TokenId,
    ) -> TokenId {
        self.push(
            TokenRuntimeType::StringTokenImpl,
            type_,
            char_offset,
            preceding_comments,
            Lexeme::Utf8 {
                start: start as u32,
                end: end as u32,
                ascii_only,
            },
        )
    }

    /// `new CommentTokenImpl.fromSubstring(...)`, and `DartDocToken`'s when
    /// `dart_doc` is set.
    pub fn comment_token_impl_from_substring(
        &mut self,
        type_: &TokenType,
        start: i32,
        end: i32,
        char_offset: i32,
        dart_doc: bool,
    ) -> TokenId {
        let runtime_type = if dart_doc {
            TokenRuntimeType::DartDocToken
        } else {
            TokenRuntimeType::CommentTokenImpl
        };
        self.push(
            runtime_type,
            type_,
            char_offset,
            super::token::NO_TOKEN,
            Lexeme::Utf16 {
                start: start as u32,
                end: end as u32,
            },
        )
    }

    /// `new CommentTokenImpl.fromUtf8Bytes(...)`, and `DartDocToken`'s when
    /// `dart_doc` is set.
    pub fn comment_token_impl_from_utf8_bytes(
        &mut self,
        type_: &TokenType,
        start: i32,
        end: i32,
        ascii_only: bool,
        char_offset: i32,
        dart_doc: bool,
    ) -> TokenId {
        let runtime_type = if dart_doc {
            TokenRuntimeType::DartDocToken
        } else {
            TokenRuntimeType::CommentTokenImpl
        };
        self.push(
            runtime_type,
            type_,
            char_offset,
            super::token::NO_TOKEN,
            Lexeme::Utf8 {
                start: start as u32,
                end: end as u32,
                ascii_only,
            },
        )
    }

    /// `new LanguageVersionTokenImpl.fromSubstring(string, start, end,
    /// tokenStart, major, minor)`.
    pub fn language_version_token_impl_from_substring(
        &mut self,
        start: i32,
        end: i32,
        token_start: i32,
        major: i64,
        minor: i64,
    ) -> TokenId {
        let id = self.push(
            TokenRuntimeType::LanguageVersionTokenImpl,
            TokenType::SINGLE_LINE_COMMENT,
            token_start,
            super::token::NO_TOKEN,
            Lexeme::Utf16 {
                start: start as u32,
                end: end as u32,
            },
        );
        self.versions.push((major, minor));
        self.extras_mut(id).a = (self.versions.len() - 1) as i32;
        id
    }

    /// `new LanguageVersionTokenImpl.fromUtf8Bytes(bytes, start, end,
    /// tokenStart, major, minor)`: always decoded as ASCII.
    pub fn language_version_token_impl_from_utf8_bytes(
        &mut self,
        start: i32,
        end: i32,
        token_start: i32,
        major: i64,
        minor: i64,
    ) -> TokenId {
        let id = self.push(
            TokenRuntimeType::LanguageVersionTokenImpl,
            TokenType::SINGLE_LINE_COMMENT,
            token_start,
            super::token::NO_TOKEN,
            Lexeme::Utf8 {
                start: start as u32,
                end: end as u32,
                ascii_only: true,
            },
        );
        self.versions.push((major, minor));
        self.extras_mut(id).a = (self.versions.len() - 1) as i32;
        id
    }

    /// `LanguageVersionToken.major`.
    pub fn major(&self, token: TokenId) -> i64 {
        debug_assert!(self.runtime_type(token).is_language_version_token());
        self.versions[self.extras(token).a as usize].0
    }

    /// `LanguageVersionToken.minor`.
    pub fn minor(&self, token: TokenId) -> i64 {
        debug_assert!(self.runtime_type(token).is_language_version_token());
        self.versions[self.extras(token).a as usize].1
    }
}

pub fn is_user_definable_operator(value: &str) -> bool {
    is_binary_operator(value)
        || is_minus_operator(value)
        || is_ternary_operator(value)
        || is_unary_operator(value)
}

pub fn is_unary_operator(value: &str) -> bool {
    value == "~"
}

pub fn is_binary_operator(value: &str) -> bool {
    matches!(
        value,
        "==" | "[]"
            | "*"
            | "/"
            | "%"
            | "~/"
            | "+"
            | "<<"
            | ">>"
            | ">>>"
            | ">="
            | ">"
            | "<="
            | "<"
            | "&"
            | "^"
            | "|"
    )
}

pub fn is_ternary_operator(value: &str) -> bool {
    value == "[]="
}

pub fn is_minus_operator(value: &str) -> bool {
    value == "-"
}

/// `correspondingPublicName`.
pub fn corresponding_public_name(identifier: &str) -> Option<String> {
    let units: Vec<u16> = identifier.encode_utf16().collect();
    if units[0] as i32 != C_UNDERSCORE {
        return None;
    }
    if units.len() == 1 {
        return None;
    }
    let first_character = units[1] as i32;
    if first_character == C_UNDERSCORE {
        return None;
    }
    if is_digit(first_character) {
        return None;
    }
    let public_name = String::from_utf16_lossy(&units[1..]);
    if let Some(keyword) = Keyword::keywords(&public_name)
        && keyword.keyword_style == KeywordStyle::reserved
    {
        return None;
    }
    Some(public_name)
}
