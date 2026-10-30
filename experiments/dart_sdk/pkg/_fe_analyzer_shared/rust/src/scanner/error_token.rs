// Port of lib/src/scanner/error_token.dart.
//
// Each `ErrorToken` subclass is a `TokenRuntimeType`, built by a
// `TokenStore` constructor of the same name. What the scanner decides is
// the message's code and its arguments, so that is what `ScannerMessage` and
// the getters below carry; `assertion_message_of` builds upstream's
// `assertionMessage` from them.
// `errorCode` is the code's name, as upstream's `errorCode.name` is.

use super::recover::{close_brace_for, close_quote_for};
use super::token::{Lexeme, NO_TOKEN, TokenId, TokenRuntimeType, TokenStore, TokenType};
use crate::messages::codes::Message;
use crate::messages::diagnostic as diag;

/// The codes `UnterminatedToken` is created with.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(i32)]
pub enum ScannerMessage {
    UnexpectedSeparatorInNumber,
    ExpectedHexDigit,
    MissingExponent,
    UnterminatedComment,
    UnexpectedDollarInString,
}

impl ScannerMessage {
    fn from_index(index: i32) -> ScannerMessage {
        match index {
            0 => ScannerMessage::UnexpectedSeparatorInNumber,
            1 => ScannerMessage::ExpectedHexDigit,
            2 => ScannerMessage::MissingExponent,
            3 => ScannerMessage::UnterminatedComment,
            4 => ScannerMessage::UnexpectedDollarInString,
            _ => unreachable!(),
        }
    }

    /// The message code's name (`diag.<code>.code.name`).
    pub fn code_name(self) -> &'static str {
        match self {
            ScannerMessage::UnexpectedSeparatorInNumber => "UnexpectedSeparatorInNumber",
            ScannerMessage::ExpectedHexDigit => "ExpectedHexDigit",
            ScannerMessage::MissingExponent => "MissingExponent",
            ScannerMessage::UnterminatedComment => "UnterminatedComment",
            ScannerMessage::UnexpectedDollarInString => "UnexpectedDollarInString",
        }
    }
}

/// `unicodeReplacementCharacter` (scanner.dart).
const UNICODE_REPLACEMENT_CHARACTER: i32 = 0xFFFD;

/// `buildUnexpectedCharacterToken`.
pub fn build_unexpected_character_token(
    store: &mut TokenStore,
    character: i32,
    char_offset: i32,
) -> TokenId {
    if character < 0x1f {
        return store.error_token_with_character(
            TokenRuntimeType::AsciiControlCharacterToken,
            character,
            char_offset,
        );
    }
    match character {
        UNICODE_REPLACEMENT_CHARACTER => store.error_token(TokenRuntimeType::EncodingErrorToken, char_offset),
        0x00A0 // No-break space.
        | 0x1680 // Ogham space mark.
        | 0x180E // Mongolian vowel separator.
        | 0x2000 // En quad.
        | 0x2001 // Em quad.
        | 0x2002 // En space.
        | 0x2003 // Em space.
        | 0x2004 // Three-per-em space.
        | 0x2005 // Four-per-em space.
        | 0x2006 // Six-per-em space.
        | 0x2007 // Figure space.
        | 0x2008 // Punctuation space.
        | 0x2009 // Thin space.
        | 0x200A // Hair space.
        | 0x200B // Zero width space.
        | 0x2028 // Line separator.
        | 0x2029 // Paragraph separator.
        | 0x202F // Narrow no-break space.
        | 0x205F // Medium mathematical space.
        | 0x3000 // Ideographic space.
        | 0xFEFF // Zero width no-break space.
        => store.error_token_with_character(TokenRuntimeType::NonAsciiWhitespaceToken, character, char_offset),
        _ => store.error_token_with_character(TokenRuntimeType::NonAsciiIdentifierToken, character, char_offset),
    }
}

impl TokenStore {
    /// `ErrorToken(offset)`: `SimpleToken(TokenType.BAD_INPUT, offset, null)`.
    fn error_token(&mut self, runtime_type: TokenRuntimeType, offset: i32) -> TokenId {
        debug_assert!(runtime_type.is_error_token());
        self.push(
            runtime_type,
            TokenType::BAD_INPUT,
            offset,
            NO_TOKEN,
            Lexeme::Fixed,
        )
    }

    fn error_token_with_character(
        &mut self,
        runtime_type: TokenRuntimeType,
        character: i32,
        offset: i32,
    ) -> TokenId {
        let id = self.error_token(runtime_type, offset);
        self.data_mut(id).a = character;
        id
    }

    /// `new UnsupportedOperator(token, charOffset)`.
    pub fn unsupported_operator(&mut self, token: TokenId, char_offset: i32) -> TokenId {
        let id = self.error_token(TokenRuntimeType::UnsupportedOperator, char_offset);
        self.data_mut(id).a = token as i32;
        id
    }

    /// `new UnterminatedString(start, charOffset, endOffset)`.
    pub fn unterminated_string(
        &mut self,
        start: &str,
        char_offset: i32,
        end_offset: i32,
    ) -> TokenId {
        let index = self.add_string(start.encode_utf16().collect());
        let id = self.error_token(TokenRuntimeType::UnterminatedString, char_offset);
        let data = self.data_mut(id);
        data.a = end_offset;
        data.b = index as i32;
        id
    }

    /// `new UnterminatedToken(assertionMessage, charOffset, endOffset)`.
    pub fn unterminated_token(
        &mut self,
        message: ScannerMessage,
        char_offset: i32,
        end_offset: i32,
    ) -> TokenId {
        let id = self.error_token(TokenRuntimeType::UnterminatedToken, char_offset);
        let data = self.data_mut(id);
        data.a = end_offset;
        data.b = message as i32;
        id
    }

    /// `new UnmatchedToken(begin)`.
    pub fn unmatched_token(&mut self, begin: TokenId) -> TokenId {
        let offset = self.char_offset(begin);
        let id = self.error_token(TokenRuntimeType::UnmatchedToken, offset);
        self.data_mut(id).a = begin as i32;
        id
    }

    // -- ErrorToken getters ---------------------------------------------------

    /// `ErrorToken.errorCode.name`.
    pub fn error_code(&self, token: TokenId) -> &'static str {
        use TokenRuntimeType::*;
        match self.runtime_type(token) {
            EncodingErrorToken => "Encoding",
            NonAsciiIdentifierToken => "NonAsciiIdentifier",
            NonAsciiWhitespaceToken => "NonAsciiWhitespace",
            AsciiControlCharacterToken => "AsciiControlCharacter",
            UnsupportedOperator => "UnsupportedOperator",
            UnterminatedString => "UnterminatedString",
            UnterminatedToken => self.assertion_message(token).unwrap().code_name(),
            UnmatchedToken => "UnmatchedToken",
            other => panic!("{} is not an ErrorToken", other.name()),
        }
    }

    /// `UnterminatedToken.assertionMessage`, as its code.
    pub fn assertion_message(&self, token: TokenId) -> Option<ScannerMessage> {
        match self.runtime_type(token) {
            TokenRuntimeType::UnterminatedToken => {
                Some(ScannerMessage::from_index(self.data(token).b))
            }
            _ => None,
        }
    }

    /// `ErrorToken.character`.
    pub fn character(&self, token: TokenId) -> Option<i32> {
        use TokenRuntimeType::*;
        match self.runtime_type(token) {
            NonAsciiIdentifierToken | NonAsciiWhitespaceToken | AsciiControlCharacterToken => {
                Some(self.data(token).a)
            }
            _ => None,
        }
    }

    /// `ErrorToken.start`.
    pub fn start(&self, token: TokenId) -> Option<&[u16]> {
        match self.runtime_type(token) {
            TokenRuntimeType::UnterminatedString => {
                Some(&self.strings[self.data(token).b as usize])
            }
            _ => None,
        }
    }

    /// `ErrorToken.endOffset`.
    pub fn end_offset(&self, token: TokenId) -> Option<i32> {
        match self.runtime_type(token) {
            TokenRuntimeType::UnterminatedString | TokenRuntimeType::UnterminatedToken => {
                Some(self.data(token).a)
            }
            _ => None,
        }
    }

    /// `ErrorToken.begin`.
    pub fn begin(&self, token: TokenId) -> TokenId {
        match self.runtime_type(token) {
            TokenRuntimeType::UnmatchedToken => self.data(token).a as TokenId,
            _ => NO_TOKEN,
        }
    }

    /// `UnsupportedOperator.token`.
    pub fn unsupported_operator_token(&self, token: TokenId) -> TokenId {
        match self.runtime_type(token) {
            TokenRuntimeType::UnsupportedOperator => self.data(token).a as TokenId,
            _ => NO_TOKEN,
        }
    }
}

impl TokenStore {
    /// `ErrorToken.assertionMessage`, as the `Message` upstream builds.
    pub fn assertion_message_of(&self, token: TokenId) -> Message {
        use TokenRuntimeType::*;
        match self.runtime_type(token) {
            EncodingErrorToken => diag::encoding.message(),
            NonAsciiIdentifierToken => {
                let character = self.data(token).a;
                (diag::nonAsciiIdentifier.with_arguments)(
                    &String::from_utf16_lossy(&code_point_to_utf16(character)),
                    character as i64,
                )
            }
            NonAsciiWhitespaceToken => {
                (diag::nonAsciiWhitespace.with_arguments)(self.data(token).a as i64)
            }
            AsciiControlCharacterToken => {
                (diag::asciiControlCharacter.with_arguments)(self.data(token).a as i64)
            }
            UnsupportedOperator => (diag::unsupportedOperator.with_arguments)(
                self,
                self.unsupported_operator_token(token),
            ),
            UnterminatedString => {
                let start = String::from_utf16_lossy(self.start(token).unwrap());
                (diag::unterminatedString.with_arguments)(&start, close_quote_for(&start))
            }
            UnterminatedToken => match self.assertion_message(token).unwrap() {
                ScannerMessage::UnexpectedSeparatorInNumber => {
                    diag::unexpectedSeparatorInNumber.message()
                }
                ScannerMessage::ExpectedHexDigit => diag::expectedHexDigit.message(),
                ScannerMessage::MissingExponent => diag::missingExponent.message(),
                ScannerMessage::UnterminatedComment => diag::unterminatedComment.message(),
                ScannerMessage::UnexpectedDollarInString => {
                    diag::unexpectedDollarInString.message()
                }
            },
            UnmatchedToken => {
                let begin = self.begin(token);
                let lexeme = self.lexeme_string(begin);
                (diag::unmatchedToken.with_arguments)(self, close_brace_for(&lexeme), begin)
            }
            other => panic!("{} is not an ErrorToken", other.name()),
        }
    }
}

/// `new String.fromCharCodes([character])`.
fn code_point_to_utf16(character: i32) -> Vec<u16> {
    match char::from_u32(character as u32) {
        Some(c) => c.encode_utf16(&mut [0; 2]).to_vec(),
        None => vec![character as u16],
    }
}
