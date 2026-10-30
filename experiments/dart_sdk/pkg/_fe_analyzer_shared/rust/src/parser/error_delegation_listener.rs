// Port of lib/src/parser/error_delegation_listener.dart.

use crate::messages::codes::Message;
use crate::parser::listener::Listener;
use crate::scanner::token::{TokenId, TokenStore};

/// A listener which forwards error reports to another listener but ignores
/// all other events.
pub struct ErrorDelegationListener {
    pub delegate: Box<dyn Listener>,
}

impl ErrorDelegationListener {
    pub fn new(delegate: Box<dyn Listener>) -> ErrorDelegationListener {
        ErrorDelegationListener { delegate }
    }
}

impl Listener for ErrorDelegationListener {
    fn handle_recoverable_error(
        &mut self,
        tokens: &TokenStore,
        message: &Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        self.delegate
            .handle_recoverable_error(tokens, message, start_token, end_token);
    }
}
