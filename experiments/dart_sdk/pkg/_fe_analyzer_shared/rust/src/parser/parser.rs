// Port of lib/src/parser/parser.dart.
//
// The library's re-exports are the modules of `crate::parser`.

use crate::messages::codes::Message;
use crate::messages::diagnostic as diag;
use crate::parser::experimental_features::ExperimentalFeatures;
use crate::parser::listener::Listener;
use crate::parser::parser_error::ParserError;
use crate::parser::parser_impl::Parser;
use crate::scanner::token::{TokenId, TokenStore};

#[derive(Default)]
pub struct ErrorCollectingListener {
    pub recoverable_errors: Vec<ParserError>,
}

impl Listener for ErrorCollectingListener {
    fn handle_recoverable_error(
        &mut self,
        tokens: &mut TokenStore,
        message: &Message,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        // TODO(danrubel): Ignore this error until we deprecate `native` support.
        if message.code.name == diag::nativeClauseShouldBeAnnotation.name {
            return;
        }
        self.recoverable_errors.push(ParserError::from_tokens(
            tokens,
            start_token,
            end_token,
            message.clone(),
        ));
    }
}

pub fn parse(
    tokens: TokenStore,
    first: TokenId,
    experimental_features: Box<dyn ExperimentalFeatures>,
    use_implicit_creation_expression: bool,
) -> Vec<ParserError> {
    let listener = Box::new(ErrorCollectingListener::default());
    let mut parser = Parser::new(
        listener,
        tokens,
        use_implicit_creation_expression,
        experimental_features,
    );
    parser.parse_unit(first);
    std::mem::take(
        &mut parser
            .listener_as::<ErrorCollectingListener>()
            .recoverable_errors,
    )
}
