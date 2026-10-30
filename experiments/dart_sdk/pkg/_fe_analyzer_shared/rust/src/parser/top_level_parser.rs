// Port of lib/src/parser/top_level_parser.dart.
//
// `TopLevelParser extends ClassMemberParser` is a `Parser` whose `kind` is
// `ParserKind::TopLevelParser`; it also overrides
// `parseClassOrMixinOrExtensionBody`, which checks the kind in
// parser_impl.rs.

use crate::parser::experimental_features::ExperimentalFeatures;
use crate::parser::listener::Listener;
use crate::parser::parser_impl::{Parser, ParserKind};
use crate::scanner::token::TokenStore;

/// Parser which only parses top-level elements, but ignores their bodies.
/// Use [Parser] to parse everything.
pub fn top_level_parser(
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
    parser.kind = ParserKind::TopLevelParser;
    parser
}
