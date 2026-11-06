// Port of lib/src/scanner/string_scanner.dart.
//
// The source is a Dart `String`, so here it is UTF-16 code units, and every
// offset is a code-unit offset, as upstream's are.

use std::rc::Rc;

use super::abstract_scanner::{
    AbstractScanner, LanguageVersionChanged, ScannerConfiguration, ScannerSubclass,
};
use super::characters::*;
use super::internal_utils::is_identifier_char;
use super::token::{Lexeme, SourceText, TokenId, TokenStore, TokenType};

/// Scanner that reads from a String and creates tokens that point to
/// substrings.
pub struct StringScanner {
    /// The file content.
    string: Rc<[u16]>,
    string_length_minus_one: i32,

    /// The current offset in [string].
    pub scan_offset: i32,
}

impl StringScanner {
    /// `new StringScanner(string, configuration: ..., includeComments: ...,
    /// languageVersionChanged: ...)`.
    pub fn new(
        string: Rc<[u16]>,
        configuration: Option<ScannerConfiguration>,
        include_comments: bool,
        language_version_changed: Option<LanguageVersionChanged>,
    ) -> AbstractScanner<StringScanner> {
        let string_length_minus_one = string.len() as i32 - 1;
        let sub = StringScanner {
            string,
            string_length_minus_one,
            scan_offset: -1,
        };
        AbstractScanner::new(
            sub,
            configuration,
            include_comments,
            language_version_changed,
            true,
        )
    }

    /// `StringScanner.isLegalIdentifier`.
    pub fn is_legal_identifier(identifier: &str) -> bool {
        let units: Rc<[u16]> = identifier.encode_utf16().collect();
        let mut scanner = StringScanner::new(units, None, false, None);
        let start_token = scanner.tokenize();
        let store = &scanner.store;
        !store.runtime_type(start_token).is_error_token() && store.is_eof(store.next(start_token))
    }

    #[inline(always)]
    fn code_unit_at(&self, index: i32) -> i32 {
        self.string[index as usize] as i32
    }
}

impl ScannerSubclass for StringScanner {
    #[inline(always)]
    fn advance(&mut self) -> i32 {
        self.scan_offset += 1;
        if self.scan_offset > self.string_length_minus_one {
            return C_EOF;
        }
        self.code_unit_at(self.scan_offset)
    }

    fn current(&self) -> i32 {
        if self.scan_offset < 0 || self.scan_offset > self.string_length_minus_one {
            return C_EOF;
        }
        self.code_unit_at(self.scan_offset)
    }

    fn pass_identifier_char_allow_dollar(&mut self) -> i32 {
        loop {
            let next = self.advance();
            if !is_identifier_char(next, /* allowDollar = */ true) {
                return next;
            }
        }
    }

    fn scan_until_line_end(&mut self) -> bool {
        let mut ascii_only = true;
        let mut next = self.advance();
        loop {
            if next > 127 {
                ascii_only = false;
            }
            if C_LF == next || C_CR == next || C_EOF == next {
                return ascii_only;
            }
            next = self.advance();
        }
    }

    #[inline(always)]
    fn skip_spaces(&mut self) -> i32 {
        let mut next = self.advance();
        while next == C_SPACE {
            next = self.advance();
        }
        next
    }

    fn peek(&self) -> i32 {
        let next = self.scan_offset + 1;
        if next > self.string_length_minus_one {
            return C_EOF;
        }
        self.code_unit_at(next)
    }

    #[inline(always)]
    fn scan_offset(&self) -> i32 {
        self.scan_offset
    }

    #[inline(always)]
    fn string_offset(&self) -> i32 {
        self.scan_offset
    }

    fn current_as_unicode(&mut self, next: i32) -> i32 {
        next
    }

    fn handle_unicode(&mut self, _start_scan_offset: i32) {}

    fn source(&self) -> SourceText {
        SourceText::Utf16(self.string.clone())
    }

    fn number_of_bytes_hint(&self) -> usize {
        self.string.len()
    }

    fn create_substring_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        _ascii_only: bool,
        extra_offset: i32,
        _allow_lazy: bool,
        token_start: i32,
        comments: TokenId,
    ) -> TokenId {
        store.string_token_impl_from_substring(
            type_,
            start,
            self.scan_offset + extra_offset,
            token_start,
            comments,
        )
    }

    fn create_synthetic_substring_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        _ascii_only: bool,
        synthetic_chars: &str,
        token_start: i32,
    ) -> TokenId {
        let length = self.scan_offset - start;
        let value = if synthetic_chars.is_empty() {
            Lexeme::Utf16 {
                start: start as u32,
                end: self.scan_offset as u32,
            }
        } else {
            let mut units = self.string[start as usize..self.scan_offset as usize].to_vec();
            units.extend(synthetic_chars.encode_utf16());
            Lexeme::Owned(store.add_string(units))
        };
        store.synthetic_string_token(type_, value, token_start, Some(length))
    }

    fn create_comment_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        _ascii_only: bool,
        extra_offset: i32,
        token_start: i32,
    ) -> TokenId {
        store.comment_token_impl_from_substring(
            type_,
            start,
            self.scan_offset + extra_offset,
            token_start,
            false,
        )
    }

    fn create_dart_doc_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        _ascii_only: bool,
        extra_offset: i32,
        token_start: i32,
    ) -> TokenId {
        store.comment_token_impl_from_substring(
            type_,
            start,
            self.scan_offset + extra_offset,
            token_start,
            true,
        )
    }

    fn create_language_version_token(
        &self,
        store: &mut TokenStore,
        start: i32,
        major: i64,
        minor: i64,
        token_start: i32,
    ) -> TokenId {
        store.language_version_token_impl_from_substring(
            start,
            self.scan_offset,
            token_start,
            major,
            minor,
        )
    }

    fn at_end_of_file(&self) -> bool {
        self.scan_offset > self.string_length_minus_one
    }

    /// `StringScanner.recoveryOptionScanner`.
    fn create_recovery_option_scanner(&self) -> StringScanner {
        StringScanner {
            string: self.string.clone(),
            string_length_minus_one: self.string_length_minus_one,
            scan_offset: self.scan_offset,
        }
    }
}
