// Port of lib/src/parser/identifier_context_impl.dart.
//
// Each upstream subclass's `ensureIdentifier` (and, where overridden,
// `ensureIdentifierPotentiallyRecovered`) is an arm of the match on the
// context's kind. The recovery tail most subclasses repeat verbatim (use a
// keyword as the identifier, or consume the token and insert a synthetic
// identifier) is `recover_keyword_or_insert`.

use crate::messages::codes::Message;
use crate::messages::diagnostic as diag;
use crate::parser::identifier_context::{
    IdentifierContext, IdentifierContextKind as K, is_ok_next_value_in_formal_parameter,
    looks_like_statement_start,
};
use crate::parser::parser_impl::Parser;
use crate::parser::type_info::is_valid_non_record_type_reference;
use crate::parser::util::{is_any_of, kw};
use crate::scanner::token::{NO_TOKEN, TokenId, TokenStore, TokenType};
use crate::scanner::token_constants::{IDENTIFIER_TOKEN, STRING_TOKEN};

/// `diag.expectedIdentifier.withArguments(lexeme: token)`.
fn expected_identifier(tokens: &TokenStore, token: TokenId) -> Message {
    (diag::expectedIdentifier.with_arguments)(tokens, token)
}

/// The `else` branch most contexts end with:
///
/// ```dart
/// if (!identifier.isKeywordOrIdentifier) {
///   parser.reportRecoverableErrorWithToken(identifier, diag.expectedIdentifier);
///   // When in doubt, consume the token to ensure we make progress
///   // but insert a synthetic identifier to satisfy listeners.
///   identifier = parser.rewriter.insertSyntheticIdentifier(identifier);
/// } else {
///   // Use the keyword as the identifier.
///   parser.reportRecoverableErrorWithToken(
///       identifier, diag.expectedIdentifierButGotKeyword);
/// }
/// ```text
fn recover_keyword_or_insert(parser: &mut Parser, identifier: TokenId) -> TokenId {
    if !parser.tokens.is_keyword_or_identifier(identifier) {
        parser.report_recoverable_error_with_token(identifier, diag::expectedIdentifier);
        parser.rewriter().insert_synthetic_identifier(identifier)
    } else {
        parser
            .report_recoverable_error_with_token(identifier, diag::expectedIdentifierButGotKeyword);
        identifier
    }
}

/// `parser.insertSyntheticIdentifier(token, this, message:
/// diag.expectedIdentifier.withArguments(lexeme: identifier))`.
fn insert_expected(
    parser: &mut Parser,
    token: TokenId,
    context: &'static IdentifierContext,
    identifier: TokenId,
) -> TokenId {
    let message = expected_identifier(&parser.tokens, identifier);
    parser.insert_synthetic_identifier(token, context, Some(message), NO_TOKEN)
}

impl IdentifierContext {
    /// Ensure that the next token is an identifier (or keyword which should be
    /// treated as an identifier) and return that identifier.
    /// Report errors as necessary via [parser].
    pub fn ensure_identifier(&'static self, token: TokenId, parser: &mut Parser) -> TokenId {
        let t = &parser.tokens;
        let mut identifier = t.next(token);
        debug_assert!(t.kind(identifier) != IDENTIFIER_TOKEN || self.kind == K::TypeReference);
        match self.kind {
            K::CatchParameter => {
                if t.is_identifier(identifier) {
                    check_async_await_yield_as_identifier(identifier, parser);
                    return identifier;
                }

                // Recovery
                parser.report_recoverable_error(identifier, diag::catchSyntax);
                let t = &parser.tokens;
                if looks_like_statement_start(t, identifier)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(identifier, TokenType::EOF)
                {
                    return parser.rewriter().insert_synthetic_identifier(token);
                } else if !t.is_keyword_or_identifier(identifier) {
                    // When in doubt, consume the token to ensure we make progress
                    // but insert a synthetic identifier to satisfy listeners.
                    return parser.rewriter().insert_synthetic_identifier(identifier);
                }
                identifier
            }
            K::ClassOrMixinOrExtension => {
                if t.type_(identifier).is_pseudo() {
                    return identifier;
                }

                // Recovery
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::LT)
                        || t.is_a(token, TokenType::OPEN_CURLY_BRACKET)
                        || t.is_a(token, kw::EXTENDS)
                        || t.is_a(token, kw::WITH)
                        || t.is_a(token, kw::IMPLEMENTS)
                        || t.is_a(token, kw::ON)
                        || t.is_a(token, TokenType::EQ)
                        || t.is_a(token, TokenType::OPEN_PAREN)
                        || t.is_a(token, TokenType::PERIOD)
                        || t.is_a(token, TokenType::EOF)
                };
                let next = t.next(identifier);
                if t.is_eof(identifier)
                    || (looks_like_start_of_next_top_level_declaration(t, identifier)
                        && (next == NO_TOKEN || !following(t, next)))
                    || (following(t, identifier) && (next == NO_TOKEN || !following(t, next)))
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else if t.type_(identifier).is_built_in() {
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::builtInIdentifierInDeclaration,
                    );
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::Combinator => {
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::SEMICOLON)
                        || t.is_a(token, TokenType::COMMA)
                        || t.is_a(token, kw::IF)
                        || t.is_a(token, kw::AS)
                        || t.is_a(token, kw::SHOW)
                        || t.is_a(token, kw::HIDE)
                        || t.is_a(token, TokenType::EOF)
                };
                if t.is_identifier(identifier)
                    && (!looks_like_start_of_next_top_level_declaration(t, identifier)
                        || following(t, t.next(identifier)))
                {
                    return identifier;
                }
                // Although this is a valid identifier name, the import declaration
                // is invalid and this looks like the start of the next declaration.
                // In this situation, fall through to insert a synthetic identifier.

                // Recovery
                let next = t.next(identifier);
                if following(t, identifier) {
                    identifier = insert_expected(parser, token, self, identifier);
                } else if looks_like_start_of_next_top_level_declaration(t, identifier)
                    && (next == NO_TOKEN || !following(t, next))
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::ConstructorReference
            | K::LiteralSymbol
            | K::MetadataReference
            | K::LabelDeclaration
            | K::LabelReference
            | K::LocalFunctionDeclaration
            | K::NamedArgumentReference
            | K::NamedRecordFieldReference
            | K::LocalVariableDeclaration
            | K::FormalParameterDeclaration
            | K::RecordFieldDeclaration => self.ensure_simple(token, identifier, parser),
            K::DottedName => {
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::PERIOD)
                        || t.is_a(token, TokenType::EQ_EQ)
                        || t.is_a(token, TokenType::CLOSE_PAREN)
                        || t.is_a(token, TokenType::EOF)
                };
                if t.is_identifier(identifier) {
                    // DottedNameIdentifierContext are only used in conditional import
                    // expressions. Although some top level keywords such as `import` can be
                    // used as identifiers, they are more likely the start of the next
                    // directive or declaration.
                    if !t.is_top_level_keyword(identifier) || following(t, t.next(identifier)) {
                        return identifier;
                    }
                }

                // Recovery
                if looks_like_start_of_next_top_level_declaration(t, identifier)
                    || following(t, identifier)
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::EnumDeclaration => {
                if t.type_(identifier).is_pseudo() {
                    return identifier;
                }

                // Recovery
                if looks_like_start_of_next_top_level_declaration(t, identifier)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else if t.type_(identifier).is_built_in() {
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::builtInIdentifierInDeclaration,
                    );
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::EnumValueDeclaration => {
                if t.is_identifier(identifier) {
                    return identifier;
                }

                // Recovery
                if looks_like_start_of_next_top_level_declaration(t, identifier)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
                {
                    parser
                        .report_recoverable_error_with_token(identifier, diag::expectedIdentifier);
                    parser.rewriter().insert_synthetic_identifier(token)
                } else if !t.is_keyword_or_identifier(identifier) {
                    parser
                        .report_recoverable_error_with_token(identifier, diag::expectedIdentifier);
                    // When in doubt, consume the token to ensure we make progress
                    // but insert a synthetic identifier to satisfy listeners.
                    parser.rewriter().insert_synthetic_identifier(identifier)
                } else {
                    // Use the keyword as the identifier.
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::expectedIdentifierButGotKeyword,
                    );
                    identifier
                }
            }
            K::Expression => self.ensure_expression(token, identifier, parser),
            K::FieldDeclaration => {
                if t.is_identifier(identifier) {
                    return identifier;
                }

                // Recovery
                if t.is_a(identifier, TokenType::SEMICOLON)
                    || t.is_a(identifier, TokenType::EQ)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
                    || looks_like_start_of_next_class_member(t, identifier)
                {
                    // TODO(jensj): Why aren't an error reported here?
                    parser.insert_synthetic_identifier(token, self, None, NO_TOKEN)
                } else if !t.is_keyword_or_identifier(identifier) {
                    // When in doubt, consume the token to ensure we make progress
                    // but insert a synthetic identifier to satisfy listeners.
                    let message = expected_identifier(t, identifier);
                    parser.insert_synthetic_identifier(identifier, self, Some(message), identifier)
                } else {
                    // Use the keyword as the identifier.
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::expectedIdentifierButGotKeyword,
                    );
                    identifier
                }
            }
            K::FieldInitializer => {
                debug_assert!(t.is_a(token, TokenType::PERIOD));
                if t.is_identifier(identifier) {
                    return identifier;
                }

                // Recovery
                parser.report_recoverable_error_with_token(identifier, diag::expectedIdentifier);
                // Insert a synthetic identifier to satisfy listeners.
                parser.rewriter().insert_synthetic_identifier(token)
            }
            K::ImportPrefix => {
                if t.type_(identifier).is_pseudo() {
                    return identifier;
                }
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::SEMICOLON)
                        || t.is_a(token, kw::IF)
                        || t.is_a(token, kw::SHOW)
                        || t.is_a(token, kw::HIDE)
                        || t.is_a(token, kw::DEFERRED)
                        || t.is_a(token, kw::AS)
                        || t.is_a(token, TokenType::EOF)
                };

                // Recovery
                let next = t.next(identifier);
                if t.type_(identifier).is_built_in() && following(t, next) {
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::builtInIdentifierInDeclaration,
                    );
                } else if looks_like_start_of_next_top_level_declaration(t, identifier)
                    && (next == NO_TOKEN || !following(t, next))
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else if following(t, identifier) {
                    identifier = insert_expected(parser, token, self, identifier);
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::Library => {
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::PERIOD)
                        || t.is_a(token, TokenType::SEMICOLON)
                        || t.is_a(token, TokenType::EOF)
                };
                if t.is_identifier(identifier) {
                    let next = t.next(identifier);
                    if !looks_like_start_of_next_top_level_declaration(t, identifier)
                        || following(t, next)
                    {
                        return identifier;
                    }
                    // Although this is a valid library name, the library declaration
                    // is invalid and this looks like the start of the next declaration.
                    // In this situation, fall through to insert a synthetic library name.
                }

                // Recovery
                let next = t.next(identifier);
                if following(t, identifier) {
                    identifier = insert_expected(parser, token, self, identifier);
                } else if looks_like_start_of_next_top_level_declaration(t, identifier)
                    && (next == NO_TOKEN || !following(t, next))
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::MethodDeclaration => {
                if t.is_identifier(identifier) {
                    return identifier;
                }

                // Recovery
                if t.is_user_definable_operator(identifier) && !self.is_continuation {
                    parser.insert_synthetic_identifier(
                        identifier,
                        self,
                        Some(diag::missingOperatorKeyword.message()),
                        identifier,
                    )
                } else if t.is_a(identifier, TokenType::PERIOD)
                    || t.is_a(identifier, TokenType::OPEN_PAREN)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::FUNCTION)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
                    || looks_like_start_of_next_class_member(t, identifier)
                {
                    parser.insert_synthetic_identifier(token, self, None, NO_TOKEN)
                } else if !t.is_keyword_or_identifier(identifier) {
                    // When in doubt, consume the token to ensure we make progress
                    // but insert a synthetic identifier to satisfy listeners.
                    let message = expected_identifier(t, identifier);
                    parser.insert_synthetic_identifier(identifier, self, Some(message), identifier)
                } else {
                    // Use the keyword as the identifier.
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::expectedIdentifierButGotKeyword,
                    );
                    identifier
                }
            }
            K::TopLevelDeclaration => {
                if t.is_identifier(identifier) {
                    let next = t.next(identifier);
                    if !looks_like_start_of_next_top_level_declaration(t, identifier)
                        || is_any_of(t, next, self.following_values)
                    {
                        return identifier;
                    }
                    // Although this is a valid top level name, the declaration
                    // is invalid and this looks like the start of the next declaration.
                    // In this situation, fall through to insert a synthetic name.
                }

                // Recovery
                if looks_like_start_of_next_top_level_declaration(t, identifier)
                    || is_any_of(t, identifier, self.following_values)
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else if t.type_(identifier).is_built_in() {
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::builtInIdentifierInDeclaration,
                    );
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::TypedefDeclaration => {
                if t.type_(identifier).is_pseudo() {
                    if t.is_a(identifier, kw::FUNCTION) {
                        parser.report_recoverable_error_with_token(
                            identifier,
                            diag::expectedIdentifierButGotKeyword,
                        );
                    }
                    return identifier;
                }
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::OPEN_PAREN)
                        || t.is_a(token, TokenType::LT)
                        || t.is_a(token, TokenType::EQ)
                        || t.is_a(token, TokenType::SEMICOLON)
                        || t.is_a(token, TokenType::EOF)
                };

                // Recovery
                if t.type_(identifier).is_built_in() && following(t, t.next(identifier)) {
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::builtInIdentifierInDeclaration,
                    );
                } else if looks_like_start_of_next_top_level_declaration(t, identifier)
                    || following(t, identifier)
                {
                    identifier = insert_expected(parser, token, self, identifier);
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
            K::TypeReference => {
                let mut token = token;
                let mut next = identifier;
                if is_valid_non_record_type_reference(t, next) {
                    return next;
                } else if t.is_keyword_or_identifier(next) {
                    if t.is_a(next, kw::VOID) {
                        parser.report_recoverable_error(next, diag::invalidVoid);
                    } else if t.type_(next).is_built_in() {
                        if !self.is_built_in_identifier_allowed {
                            parser.report_recoverable_error_with_token(
                                next,
                                diag::builtInIdentifierAsType,
                            );
                        }
                    } else if t.is_a(next, kw::VAR) {
                        parser.report_recoverable_error(next, diag::varAsTypeName);
                    } else {
                        parser.report_recoverable_error_with_token(next, diag::expectedType);
                    }
                    return next;
                }
                parser.report_recoverable_error_with_token(next, diag::expectedType);
                let t = &parser.tokens;
                if !(t.is_a(next, TokenType::LT)
                    || t.is_a(next, TokenType::GT)
                    || t.is_a(next, TokenType::GT_GT)
                    || t.is_a(next, TokenType::GT_GT_GT)
                    || t.is_a(next, TokenType::CLOSE_PAREN)
                    || t.is_a(next, TokenType::OPEN_SQUARE_BRACKET)
                    || t.is_a(next, TokenType::CLOSE_SQUARE_BRACKET)
                    || t.is_a(next, TokenType::INDEX)
                    || t.is_a(next, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(next, TokenType::COMMA)
                    || t.is_a(next, TokenType::SEMICOLON)
                    || t.is_a(next, TokenType::EOF))
                {
                    token = next;
                    next = t.next(token);
                }
                let _ = next;
                // Insert a synthetic identifier to satisfy listeners.
                parser.rewriter().insert_synthetic_identifier(token)
            }
            K::TypeVariableDeclaration => {
                if t.type_(identifier).is_pseudo() {
                    return identifier;
                }
                let following = |t: &TokenStore, token: TokenId| {
                    t.is_a(token, TokenType::LT)
                        || t.is_a(token, TokenType::GT)
                        || t.is_a(token, TokenType::GT_GT)
                        || t.is_a(token, TokenType::GT_GT_GT)
                        || t.is_a(token, TokenType::SEMICOLON)
                        || t.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
                        || t.is_a(token, kw::EXTENDS)
                        || t.is_a(token, kw::SUPER)
                        // If currently adding type variables to a typedef this could easily
                        // occur and we don't want to 'eat' the equal sign.
                        || t.is_a(token, TokenType::EQ)
                        || t.is_a(token, TokenType::GT_EQ)
                        // Also EOF.
                        || t.is_a(token, TokenType::EOF)
                };

                // Recovery: If the next token  (the one currently in 'identifier') is any
                // of these values we don't "eat" the it but instead insert an identifier
                // between "token" and "token.next" and return that as the last consumed
                // token. Otherwise such a token would be consumed: an identifier would be
                // inserted after "token.next" and that would be returned as the last
                // consumed token, effectively skipping the token.
                if looks_like_start_of_next_top_level_declaration(t, identifier)
                    || looks_like_start_of_next_class_member(t, identifier)
                    || looks_like_statement_start(t, identifier)
                    || following(t, identifier)
                {
                    parser
                        .report_recoverable_error_with_token(identifier, diag::expectedIdentifier);
                    identifier = parser.rewriter().insert_synthetic_identifier(token);
                } else if t.type_(identifier).is_built_in() {
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::builtInIdentifierInDeclaration,
                    );
                } else {
                    identifier = recover_keyword_or_insert(parser, identifier);
                }
                identifier
            }
        }
    }

    /// The contexts whose `ensureIdentifier` accepts any identifier (after
    /// `checkAsyncAwaitYieldAsIdentifier`, where upstream calls it) and
    /// differ only in which tokens make them insert a synthetic identifier.
    fn ensure_simple(
        &'static self,
        token: TokenId,
        mut identifier: TokenId,
        parser: &mut Parser,
    ) -> TokenId {
        let t = &parser.tokens;
        if t.is_identifier(identifier) {
            if self.kind != K::LiteralSymbol {
                check_async_await_yield_as_identifier(identifier, parser);
            }
            return identifier;
        }

        // Recovery
        let insert = match self.kind {
            K::ConstructorReference | K::LiteralSymbol => {
                if !t.is_keyword_or_identifier(identifier) {
                    identifier = insert_expected(parser, token, self, identifier);
                } else {
                    // Use the keyword as the identifier.
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::expectedIdentifierButGotKeyword,
                    );
                }
                return identifier;
            }
            K::FormalParameterDeclaration => {
                ((looks_like_start_of_next_top_level_declaration(t, identifier)
                    || looks_like_start_of_next_class_member(t, identifier)
                    || looks_like_statement_start(t, identifier))
                    && !is_ok_next_value_in_formal_parameter(t, t.next(identifier)))
                    || t.is_a(identifier, TokenType::COLON)
                    || t.is_a(identifier, TokenType::EQ)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::OPEN_PAREN)
                    || t.is_a(identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(identifier, TokenType::OPEN_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
            }
            K::RecordFieldDeclaration => {
                ((looks_like_start_of_next_top_level_declaration(t, identifier)
                    || looks_like_start_of_next_class_member(t, identifier)
                    || looks_like_statement_start(t, identifier))
                    && !is_ok_next_value_in_formal_parameter(t, t.next(identifier)))
                    || t.is_a(identifier, TokenType::COLON)
                    || t.is_a(identifier, TokenType::EQ)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::OPEN_PAREN)
                    || t.is_a(identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(identifier, TokenType::OPEN_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
            }
            K::LocalFunctionDeclaration => {
                t.is_a(identifier, TokenType::PERIOD)
                    || t.is_a(identifier, TokenType::OPEN_PAREN)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::FUNCTION)
                    || t.is_a(identifier, TokenType::EOF)
                    || looks_like_statement_start(t, identifier)
            }
            K::LabelDeclaration => {
                t.is_a(identifier, TokenType::COLON)
                    || t.is_a(identifier, TokenType::EOF)
                    || looks_like_statement_start(t, identifier)
            }
            K::LabelReference => {
                t.is_a(identifier, TokenType::SEMICOLON) || t.is_a(identifier, TokenType::EOF)
            }
            K::LocalVariableDeclaration => {
                t.is_a(identifier, TokenType::SEMICOLON)
                    || t.is_a(identifier, TokenType::EQ)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(identifier, TokenType::EOF)
                    || looks_like_statement_start(t, identifier)
                    || t.kind(identifier) == STRING_TOKEN
            }
            K::MetadataReference => {
                t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::OPEN_PAREN)
                    || t.is_a(identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(identifier, TokenType::CLOSE_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::EOF)
                    || looks_like_start_of_next_top_level_declaration(t, identifier)
                    || looks_like_start_of_next_class_member(t, identifier)
                    || looks_like_statement_start(t, identifier)
            }
            K::NamedArgumentReference | K::NamedRecordFieldReference => {
                t.is_a(identifier, TokenType::COLON) || t.is_a(identifier, TokenType::EOF)
            }
            _ => unreachable!(),
        };
        if insert {
            identifier = insert_expected(parser, token, self, identifier);
        } else {
            identifier = recover_keyword_or_insert(parser, identifier);
        }
        identifier
    }

    fn ensure_expression(
        &'static self,
        mut token: TokenId,
        mut identifier: TokenId,
        parser: &mut Parser,
    ) -> TokenId {
        let t = &parser.tokens;
        if t.is_identifier(identifier) {
            if t.is_a(identifier, kw::AWAIT) && t.is_identifier(t.next(identifier)) {
                // Although the `await` can be used in an expression,
                // it is followed by another identifier which does not form
                // a valid expression. Report an error on the `await` token
                // rather than the token following it.
                parser.report_recoverable_error_with_token(identifier, diag::unexpectedToken);

                // TODO(danrubel) Consider a new listener event so that analyzer
                // can represent this as an await expression in a context that does
                // not allow await.
                return parser.tokens.next(identifier);
            } else {
                check_async_await_yield_as_identifier(identifier, parser);
            }
            return identifier;
        }

        // Recovery
        let report_error_at = identifier;
        if t.is_a(token, TokenType::STRING_INTERPOLATION_IDENTIFIER)
            && t.is_keyword(identifier)
            && t.kind(t.next(identifier)) == STRING_TOKEN
        {
            // Keyword used as identifier in string interpolation
            parser.report_recoverable_error_with_token(
                identifier,
                diag::expectedIdentifierButGotKeyword,
            );
            return identifier;
        } else if !looks_like_statement_start(t, identifier) {
            if t.is_keyword_or_identifier(identifier) {
                if self.is_continuation
                    || !(t.is_a(identifier, kw::AS)
                        || t.is_a(identifier, kw::IS)
                        || t.is_a(identifier, TokenType::EOF))
                {
                    // Use the keyword as the identifier.
                    parser.report_recoverable_error_with_token(
                        identifier,
                        diag::expectedIdentifierButGotKeyword,
                    );
                    return identifier;
                }
            } else if !t.is_operator(identifier)
                && !(t.is_a(identifier, TokenType::PERIOD)
                    || t.is_a(identifier, TokenType::COMMA)
                    || t.is_a(identifier, TokenType::OPEN_PAREN)
                    || t.is_a(identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(identifier, TokenType::OPEN_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_SQUARE_BRACKET)
                    || t.is_a(identifier, TokenType::OPEN_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(identifier, TokenType::QUESTION)
                    || t.is_a(identifier, TokenType::COLON)
                    || t.is_a(identifier, TokenType::SEMICOLON)
                    || t.is_a(identifier, TokenType::EOF))
            {
                // When in doubt, consume the token to ensure we make progress
                token = identifier;
                identifier = t.next(token);
            }
        }
        let _ = identifier;

        parser.report_recoverable_error_with_token(report_error_at, diag::expectedIdentifier);

        // Insert a synthetic identifier to satisfy listeners.
        parser.rewriter().insert_synthetic_identifier(token)
    }

    /// Ensure that the next token is an identifier (or keyword which should be
    /// treated as an identifier) and return that identifier.
    /// Report errors as necessary via [parser].
    /// If [isRecovered] is true, the parser has already recovered, and a
    /// keyword is used as the identifier without further recovery.
    pub fn ensure_identifier_potentially_recovered(
        &'static self,
        token: TokenId,
        parser: &mut Parser,
        is_recovered: bool,
    ) -> TokenId {
        let t = &parser.tokens;
        match self.kind {
            K::FieldDeclaration | K::MethodDeclaration | K::TopLevelDeclaration => {
                // Fast path good case.
                let identifier = t.next(token);
                debug_assert!(t.kind(identifier) != IDENTIFIER_TOKEN);
                if t.is_identifier(identifier) {
                    if self.kind != K::TopLevelDeclaration {
                        return identifier;
                    }
                    let next = t.next(identifier);
                    if !looks_like_start_of_next_top_level_declaration(t, identifier)
                        || is_any_of(t, next, self.following_values)
                    {
                        return identifier;
                    }
                }

                // If not recovered, recover as normal.
                if !is_recovered || !t.is_keyword_or_identifier(identifier) {
                    return self.ensure_identifier(token, parser);
                }

                // If already recovered, use the given token.
                parser.report_recoverable_error_with_token(
                    identifier,
                    diag::expectedIdentifierButGotKeyword,
                );
                identifier
            }
            K::TypedefDeclaration => {
                // Fast path good case.
                let identifier = t.next(token);
                debug_assert!(t.kind(identifier) != IDENTIFIER_TOKEN);
                if t.type_(identifier).is_pseudo() {
                    if t.is_a(identifier, kw::FUNCTION) {
                        parser.report_recoverable_error_with_token(
                            identifier,
                            diag::expectedIdentifierButGotKeyword,
                        );
                    }
                    return identifier;
                }

                // If not recovered, recover as normal.
                if !is_recovered || !t.is_keyword_or_identifier(identifier) {
                    return self.ensure_identifier(token, parser);
                }

                // If already recovered, use the given token.
                parser.report_recoverable_error_with_token(
                    identifier,
                    diag::expectedIdentifierButGotKeyword,
                );
                identifier
            }
            _ => self.ensure_identifier(token, parser),
        }
    }
}

pub fn check_async_await_yield_as_identifier(identifier: TokenId, parser: &mut Parser) {
    let t = &parser.tokens;
    if !parser.in_plain_sync() && t.type_(identifier).is_pseudo() {
        if t.is_a(identifier, kw::AWAIT) {
            parser.report_recoverable_error(identifier, diag::awaitAsIdentifier);
        } else if t.is_a(identifier, kw::YIELD) {
            parser.report_recoverable_error(identifier, diag::yieldAsIdentifier);
        }
    }
}

pub fn looks_like_start_of_next_class_member(t: &TokenStore, token: TokenId) -> bool {
    t.is_modifier(token)
        || t.is_a(token, TokenType::AT)
        || t.is_a(token, kw::GET)
        || t.is_a(token, kw::SET)
        || t.is_a(token, kw::VOID)
        || t.is_a(token, TokenType::EOF)
}

pub fn looks_like_start_of_next_top_level_declaration(t: &TokenStore, token: TokenId) -> bool {
    t.is_top_level_keyword(token)
        || t.is_a(token, kw::CONST)
        || t.is_a(token, kw::GET)
        || t.is_a(token, kw::FINAL)
        || t.is_a(token, kw::SET)
        || t.is_a(token, kw::VAR)
        || t.is_a(token, kw::VOID)
        || t.is_a(token, TokenType::EOF)
}
