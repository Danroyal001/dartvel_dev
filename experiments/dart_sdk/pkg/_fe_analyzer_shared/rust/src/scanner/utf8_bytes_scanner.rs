// Port of lib/src/scanner/utf8_bytes_scanner.dart.
//
// Scans UTF-8 bytes. Offsets into the bytes are scan offsets; token offsets
// are string offsets, the UTF-16 offsets the same text would have as a Dart
// `String`, which the slack fields below keep track of.
//
// Upstream unrolls `passIdentifierCharAllowDollar`, `scanUntilLineEnd` and
// `skipSpaces` ten bytes at a time to save bounds checks. Each unrolled loop
// stops at the same byte with the same result as the plain loop it falls
// back to, so here each is the plain loop over a slice.

use std::rc::Rc;

use super::abstract_scanner::{
    AbstractScanner, LanguageVersionChanged, ScannerConfiguration, ScannerSubclass,
};
use super::characters::*;
use super::internal_utils::is_identifier_char_allow_dollar_table_lookup;
use super::string_canonicalizer::{decode_string, utf16_length_of_utf8_allow_malformed};
use super::token::{Lexeme, SourceText, TokenId, TokenStore, TokenType};

/// `unicodeReplacementCharacter` (scanner.dart).
const UNICODE_REPLACEMENT_CHARACTER: i32 = 0xFFFD;

/// Scanner that reads from a UTF-8 encoded list of bytes.
pub struct Utf8BytesScanner {
    /// The file content.
    bytes: Rc<[u8]>,
    bytes_length_minus_one: i32,

    /// Points to the offset of the last byte returned by `advance`.
    pub byte_offset: i32,

    /// The `scanOffset` slack after a multi-byte code point was decoded at
    /// `scan_slack_offset`.
    pub scan_slack: i32,
    pub scan_slack_offset: i32,

    /// The difference between the byte offset and the string offset.
    pub utf8_slack: i32,

    pub last_unicode_offset: i32,

    pub string_offset_slack_offset: i32,
}

impl Utf8BytesScanner {
    /// `new Utf8BytesScanner(bytes, configuration: ..., includeComments: ...,
    /// languageVersionChanged: ..., allowLazyStrings: ...)`.
    pub fn new(
        bytes: Rc<[u8]>,
        configuration: Option<ScannerConfiguration>,
        include_comments: bool,
        language_version_changed: Option<LanguageVersionChanged>,
        allow_lazy_strings: bool,
    ) -> AbstractScanner<Utf8BytesScanner> {
        let bytes_length_minus_one = bytes.len() as i32 - 1;
        let mut sub = Utf8BytesScanner {
            bytes,
            bytes_length_minus_one,
            byte_offset: -1,
            scan_slack: 0,
            scan_slack_offset: -1,
            utf8_slack: 0,
            last_unicode_offset: -1,
            string_offset_slack_offset: -2,
        };
        if sub.contains_bom_at(/* offset = */ 0) {
            sub.byte_offset += 3;
            sub.utf8_slack += 3;
        }
        AbstractScanner::new(
            sub,
            configuration,
            include_comments,
            language_version_changed,
            allow_lazy_strings,
        )
    }

    pub fn contains_bom_at(&self, offset: i32) -> bool {
        const BOM_UTF8: [u8; 3] = [0xEF, 0xBB, 0xBF];
        let offset = offset as usize;
        offset + 2 < self.bytes.len()
            && self.bytes[offset] == BOM_UTF8[0]
            && self.bytes[offset + 1] == BOM_UTF8[1]
            && self.bytes[offset + 2] == BOM_UTF8[2]
    }

    /// `_isEolChar`: `$LF` or `$CR`.
    #[inline(always)]
    fn is_eol_char(next: u8) -> bool {
        next == C_LF as u8 || next == C_CR as u8
    }

    pub fn next_code_point(&mut self, start_offset: i32, next_byte: i32) -> i32 {
        let code_point = self.decode_utf8_code_point(next_byte);
        let extra_bytes_read = self.byte_offset - start_offset;
        if code_point < 0x10000 {
            self.utf8_slack += extra_bytes_read;
            self.scan_slack = extra_bytes_read;
            self.scan_slack_offset = self.byte_offset;
            return code_point;
        }
        // A code point above U+FFFF is two UTF-16 code units.
        self.utf8_slack += extra_bytes_read - 1;
        self.scan_slack = extra_bytes_read;
        self.scan_slack_offset = self.byte_offset;
        self.string_offset_slack_offset = self.byte_offset;
        code_point
    }

    fn decode_utf8_code_point(&mut self, mut byte: i32) -> i32 {
        let mut code_point;
        let bytes_needed;
        let mut lower_boundary = 0x80;
        let mut upper_boundary = 0xBF;
        if (0x00..=0x7F).contains(&byte) {
            return byte; // 3.1
        } else if (0xC2..=0xDF).contains(&byte) {
            bytes_needed = 1;
            code_point = byte & 0x1F;
        } else if (0xE0..=0xEF).contains(&byte) {
            if byte == 0xE0 {
                lower_boundary = 0xA0;
            } else if byte == 0xED {
                upper_boundary = 0x9F;
            }
            bytes_needed = 2;
            code_point = byte & 0xF;
        } else if (0xF0..=0xF4).contains(&byte) {
            if byte == 0xF0 {
                lower_boundary = 0x90;
            }
            if byte == 0xF4 {
                upper_boundary = 0x8F;
            }
            bytes_needed = 3;
            code_point = byte & 0x7;
        } else {
            return UNICODE_REPLACEMENT_CHARACTER;
        }
        let mut bytes_seen = 0;
        loop {
            if self.byte_offset >= self.bytes_length_minus_one {
                return UNICODE_REPLACEMENT_CHARACTER;
            }
            byte = self.advance();
            if byte < lower_boundary || byte > upper_boundary {
                self.byte_offset -= 1;
                return UNICODE_REPLACEMENT_CHARACTER;
            }
            lower_boundary = 0x80;
            upper_boundary = 0xBF;
            code_point = (code_point << 6) | (byte & 0x3F);
            bytes_seen += 1;
            if bytes_seen != bytes_needed {
                continue;
            }
            return code_point;
        }
    }
}

impl ScannerSubclass for Utf8BytesScanner {
    #[inline(always)]
    fn advance(&mut self) -> i32 {
        self.byte_offset += 1;
        if self.byte_offset > self.bytes_length_minus_one {
            return C_EOF;
        }
        self.bytes[self.byte_offset as usize] as i32
    }

    fn current(&self) -> i32 {
        if self.byte_offset < 0 || self.byte_offset > self.bytes_length_minus_one {
            return C_EOF;
        }
        self.bytes[self.byte_offset as usize] as i32
    }

    #[inline]
    fn pass_identifier_char_allow_dollar(&mut self) -> i32 {
        let from = (self.byte_offset + 1) as usize;
        match self.bytes[from.min(self.bytes.len())..]
            .iter()
            .position(|&b| !is_identifier_char_allow_dollar_table_lookup(b as i32))
        {
            Some(i) => {
                self.byte_offset = (from + i) as i32;
                self.bytes[from + i] as i32
            }
            None => {
                self.byte_offset = (from as i32).max(self.bytes.len() as i32);
                C_EOF
            }
        }
    }

    #[inline]
    fn scan_until_line_end(&mut self) -> bool {
        let from = (self.byte_offset + 1) as usize;
        let rest = &self.bytes[from.min(self.bytes.len())..];
        let end = rest
            .iter()
            .position(|&b| Utf8BytesScanner::is_eol_char(b))
            .unwrap_or(rest.len());
        let ascii_only = rest[..end].is_ascii();
        // At the end of the input, upstream's last `advance` leaves
        // byteOffset one past the last byte.
        self.byte_offset = (from + end) as i32;
        ascii_only
    }

    #[inline]
    fn skip_spaces(&mut self) -> i32 {
        let from = (self.byte_offset + 1) as usize;
        match self.bytes[from.min(self.bytes.len())..]
            .iter()
            .position(|&b| b != C_SPACE as u8)
        {
            Some(i) => {
                self.byte_offset = (from + i) as i32;
                self.bytes[from + i] as i32
            }
            None => {
                self.byte_offset = (from as i32).max(self.bytes.len() as i32);
                C_EOF
            }
        }
    }

    fn peek(&self) -> i32 {
        let next = self.byte_offset + 1;
        if next > self.bytes_length_minus_one {
            return C_EOF;
        }
        self.bytes[next as usize] as i32
    }

    #[inline(always)]
    fn scan_offset(&self) -> i32 {
        if self.byte_offset == self.scan_slack_offset {
            self.byte_offset - self.scan_slack
        } else {
            self.byte_offset
        }
    }

    fn current_as_unicode(&mut self, next: i32) -> i32 {
        if next < 128 {
            return next;
        }
        // Check if currentAsUnicode was already invoked.
        if self.byte_offset == self.last_unicode_offset {
            return next;
        }
        let res = self.next_code_point(self.byte_offset, next);
        self.last_unicode_offset = self.byte_offset;
        res
    }

    fn handle_unicode(&mut self, start_scan_offset: i32) {
        let end = self.byte_offset;
        let length = utf16_length_of_utf8_allow_malformed(
            &self.bytes[start_scan_offset as usize..end as usize],
        );
        self.utf8_slack += (end - start_scan_offset) - length as i32;
    }

    #[inline(always)]
    fn string_offset(&self) -> i32 {
        if self.string_offset_slack_offset == self.byte_offset {
            self.byte_offset - self.utf8_slack - 1
        } else {
            self.byte_offset - self.utf8_slack
        }
    }

    fn source(&self) -> SourceText {
        SourceText::Utf8(self.bytes.clone())
    }

    fn number_of_bytes_hint(&self) -> usize {
        self.bytes.len()
    }

    #[inline(always)]
    fn create_substring_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
        _allow_lazy: bool,
        token_start: i32,
        comments: TokenId,
    ) -> TokenId {
        store.string_token_impl_from_utf8_bytes(
            type_,
            start,
            self.byte_offset + extra_offset,
            ascii_only,
            token_start,
            comments,
        )
    }

    fn create_synthetic_substring_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        synthetic_chars: &str,
        token_start: i32,
    ) -> TokenId {
        let mut value = decode_string(
            &self.bytes,
            start as usize,
            self.byte_offset as usize,
            ascii_only,
        );
        let length = value.len() as i32;
        let lexeme = if synthetic_chars.is_empty() {
            Lexeme::Utf8 {
                start: start as u32,
                end: self.byte_offset as u32,
                ascii_only,
            }
        } else {
            value.extend(synthetic_chars.encode_utf16());
            Lexeme::Owned(store.add_string(value))
        };
        store.synthetic_string_token(type_, lexeme, token_start, Some(length))
    }

    fn create_comment_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
        token_start: i32,
    ) -> TokenId {
        store.comment_token_impl_from_utf8_bytes(
            type_,
            start,
            self.byte_offset + extra_offset,
            ascii_only,
            token_start,
            false,
        )
    }

    fn create_dart_doc_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
        token_start: i32,
    ) -> TokenId {
        store.comment_token_impl_from_utf8_bytes(
            type_,
            start,
            self.byte_offset + extra_offset,
            ascii_only,
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
        store.language_version_token_impl_from_utf8_bytes(
            start,
            self.byte_offset,
            token_start,
            major,
            minor,
        )
    }

    fn at_end_of_file(&self) -> bool {
        self.byte_offset > self.bytes_length_minus_one
    }

    /// `Utf8BytesScanner.createRecoveryOptionScanner`: `lastUnicodeOffset`
    /// and `stringOffsetSlackOffset` are not copied upstream, so they start
    /// from their initial values.
    fn create_recovery_option_scanner(&self) -> Utf8BytesScanner {
        Utf8BytesScanner {
            bytes: self.bytes.clone(),
            bytes_length_minus_one: self.bytes_length_minus_one,
            byte_offset: self.byte_offset,
            scan_slack: self.scan_slack,
            scan_slack_offset: self.scan_slack_offset,
            utf8_slack: self.utf8_slack,
            last_unicode_offset: -1,
            string_offset_slack_offset: -2,
        }
    }
}
