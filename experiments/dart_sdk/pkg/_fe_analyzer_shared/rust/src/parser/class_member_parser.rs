// Port of lib/src/parser/class_member_parser.dart.
//
// `ClassMemberParser extends Parser` is a `Parser` whose `kind` is
// `ParserKind::ClassMemberParser`; the methods it overrides
// (`allowedToShortcutParseExpression`, `parseExpression`,
// `parseIdentifierExpression`, `parseArgumentsOpt`, `parseFunctionBody`,
// `parseInvalidBlock`) check the kind in parser_impl.rs and come here.
//
// Upstream's `skipParser` is a second, full `Parser` over the same tokens
// whose listener is an `ErrorDelegationListener` forwarding errors to this
// parser's listener. Here the same parser switches to that state for the
// call: the listener is wrapped, the kind is `Parser`, and the state the skip
// parser keeps between calls is swapped in and out.

use crate::parser::error_delegation_listener::ErrorDelegationListener;
use crate::parser::experimental_features::ExperimentalFeatures;
use crate::parser::forwarding_listener::NullListener;
use crate::parser::listener::Listener;
use crate::parser::parser_impl::{Parser, ParserKind, SkipParserState};
use crate::scanner::token::{TokenId, TokenStore};

/// Parser similar to [TopLevelParser] but also parses class members (excluding
/// their bodies).
pub fn class_member_parser(
    listener: Box<dyn Listener>,
    tokens: TokenStore,
    use_implicit_creation_expression: bool,
    experimental_features: Box<dyn ExperimentalFeatures>,
) -> Parser {
    let mut parser = Parser::new(
        listener,
        tokens,
        use_implicit_creation_expression,
        experimental_features,
    );
    parser.kind = ParserKind::ClassMemberParser;
    parser
}

impl Parser {
    pub fn skip_expression(&mut self, token: TokenId) -> TokenId {
        // TODO(askesc): We listen to errors occurring during expression parsing,
        // since the parser may rewrite the token stream such that the error is
        // not triggered during the second parse.
        // When the parser supports not doing token stream rewriting, use that
        // feature together with a no-op listener instead.
        let state = self.skip_parser_state.take().unwrap_or(SkipParserState {
            cached_rewriter: None,
            is_last_pattern_allowed_inside_unary_pattern: false,
            statement_depth: 0,
            expression_depth: 0,
            recover_at_precedence_level: false,
            currently_recovering: false,
        });
        let own = self.swap_skip_state(state);
        let kind = std::mem::replace(&mut self.kind, ParserKind::Parser);
        let listener = std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
        self.listener = Box::new(ErrorDelegationListener::new(listener));

        let result = self.parse_expression(token);

        let delegate = std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
        let any: Box<dyn std::any::Any> = delegate;
        self.listener = any
            .downcast::<ErrorDelegationListener>()
            .expect("skip parser listener")
            .delegate;
        self.kind = kind;
        let state = self.swap_skip_state(own);
        self.skip_parser_state = Some(state);
        result
    }

    /// Exchanges the state a skip parser keeps with [state], returning the
    /// state that was in place.
    fn swap_skip_state(&mut self, state: SkipParserState) -> SkipParserState {
        SkipParserState {
            cached_rewriter: std::mem::replace(&mut self.cached_rewriter, state.cached_rewriter),
            is_last_pattern_allowed_inside_unary_pattern: std::mem::replace(
                &mut self.is_last_pattern_allowed_inside_unary_pattern,
                state.is_last_pattern_allowed_inside_unary_pattern,
            ),
            statement_depth: std::mem::replace(&mut self.statement_depth, state.statement_depth),
            expression_depth: std::mem::replace(&mut self.expression_depth, state.expression_depth),
            recover_at_precedence_level: self
                .swap_recover_at_precedence_level(state.recover_at_precedence_level),
            currently_recovering: self.swap_currently_recovering(state.currently_recovering),
        }
    }
}
