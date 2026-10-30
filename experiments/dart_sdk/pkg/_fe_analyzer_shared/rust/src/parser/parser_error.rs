// Port of lib/src/parser/parser_error.dart.

use crate::messages::codes::Message;
use crate::scanner::token::{TokenId, TokenStore};

#[derive(Debug, Clone)]
pub struct ParserError {
    /// Character offset from the beginning of file where this error starts.
    pub begin_offset: i32,

    /// Character offset from the beginning of file where this error ends.
    pub end_offset: i32,

    pub message: Message,
}

impl ParserError {
    pub fn new(begin_offset: i32, end_offset: i32, message: Message) -> ParserError {
        ParserError {
            begin_offset,
            end_offset,
            message,
        }
    }

    pub fn from_tokens(
        tokens: &TokenStore,
        begin: TokenId,
        end: TokenId,
        message: Message,
    ) -> ParserError {
        ParserError::new(
            tokens.char_offset(begin),
            tokens.char_offset(end) + tokens.char_count(end),
            message,
        )
    }
}

impl std::fmt::Display for ParserError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let correction = match &self.message.correction_message {
            Some(correction) => correction.to_string(),
            None => "null".to_string(),
        };
        write!(
            f,
            "@{}: {}\n{}",
            self.begin_offset, self.message.problem_message, correction
        )
    }
}
