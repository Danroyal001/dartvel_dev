// Port of lib/src/parser/parser_impl.dart.
//
// The parser owns the `TokenStore` it parses (upstream's tokens are objects
// the parser rewrites in place) and the listener it reports to, which every
// event receives the store with. `Token` and `Token?` are `TokenId`s,
// `NO_TOKEN` standing for null. Upstream's subclasses `ClassMemberParser`
// and `TopLevelParser` override a few methods; here they are a `ParserKind`
// those methods dispatch on (see class_member_parser.rs).
#![allow(
    non_camel_case_types,
    unused_assignments,
    clippy::collapsible_else_if,
    clippy::collapsible_if,
    clippy::too_many_arguments
)]

use std::any::Any;

use crate::experiments::flags::ExperimentalFlag;
use crate::messages::codes::{Message, MessageCode};
use crate::messages::diagnostic as diag;
use crate::parser::assert::Assert;
use crate::parser::async_modifier::AsyncModifier;
use crate::parser::block_kind::{BlockKind, LexemeTemplate};
use crate::parser::constructor_reference_context::ConstructorReferenceContext;
use crate::parser::declaration_kind::{DeclarationHeaderKind, DeclarationKind};
use crate::parser::directive_context::DirectiveContext;
use crate::parser::experimental_features::ExperimentalFeatures;
use crate::parser::formal_parameter_kind::FormalParameterKind;
use crate::parser::forwarding_listener::{ForwardingListener, NullListener};
use crate::parser::identifier_context::{
    IdentifierContext, is_ok_next_value_in_formal_parameter, looks_like_expression_start,
    looks_like_pattern_start,
};
use crate::parser::identifier_context_impl::looks_like_start_of_next_top_level_declaration;
use crate::parser::listener::Listener;
use crate::parser::literal_entry_info::{
    LiteralEntryInfo, compute_literal_entry, looks_like_literal_entry, simpleEntry,
};
use crate::parser::loop_state::LoopState;
use crate::parser::member_kind::MemberKind;
use crate::parser::modifier_context::{ModifierContext, is_modifier};
use crate::parser::recovery_listeners::{
    DeclarationHeaderRecoveryListener, ImportRecoveryListener, MixinHeaderRecoveryListener,
    Recovery,
};
use crate::parser::token_stream_rewriter::{
    Rewriter, TokenStreamRewriter, TokenStreamRewriterImpl, UndoableTokenStreamRewriter,
};
use crate::parser::type_info::{
    TypeInfo, TypeParamOrArgInfo, compute_method_type_arguments, compute_type,
    compute_type_param_or_arg, compute_variable_pattern_type, illegalPatternIdentifiers,
    is_valid_non_record_type_reference, noType, noTypeParamOrArg,
};
use crate::parser::type_info_impl::looks_like_name;
use crate::parser::util::{
    find_non_zero_length_token, find_previous_non_zero_length_token, is_any_of, kw,
};
use crate::scanner::token::{
    ASSIGNMENT_PRECEDENCE, BITWISE_OR_PRECEDENCE, CASCADE_PRECEDENCE, EQUALITY_PRECEDENCE, Keyword,
    MULTIPLICATIVE_PRECEDENCE, NO_TOKEN, POSTFIX_PRECEDENCE, PREFIX_PRECEDENCE,
    RELATIONAL_PRECEDENCE, SELECTOR_PRECEDENCE, TokenId, TokenStore, TokenType,
};
use crate::scanner::token_constants::{
    BANG_EQ_EQ_TOKEN, COMMA_TOKEN, DOUBLE_TOKEN, EOF_TOKEN, EQ_EQ_EQ_TOKEN, EQ_TOKEN,
    FUNCTION_TOKEN, HASH_TOKEN, HEXADECIMAL_TOKEN, IDENTIFIER_TOKEN, INT_TOKEN, KEYWORD_TOKEN,
    LT_TOKEN, OPEN_CURLY_BRACKET_TOKEN, OPEN_PAREN_TOKEN, OPEN_SQUARE_BRACKET_TOKEN,
    SEMICOLON_TOKEN, STRING_INTERPOLATION_IDENTIFIER_TOKEN, STRING_INTERPOLATION_TOKEN,
    STRING_TOKEN,
};

/// Which upstream class a parser is.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ParserKind {
    Parser,
    ClassMemberParser,
    TopLevelParser,
}

/// An event generating parser of Dart programs. This parser expects all tokens
/// in a linked list (aka a token stream).
pub struct Parser {
    pub listener: Box<dyn Listener>,

    /// The tokens being parsed (not a field upstream: each token is an
    /// object).
    pub tokens: TokenStore,

    pub kind: ParserKind,

    pub may_parse_function_expressions: bool,

    /// Represents parser state: what asynchronous syntax is allowed in the
    /// function being currently parsed. In rare situations, this can be set by
    /// external clients, for example, to parse an expression outside a function.
    pub async_state: AsyncModifier,

    /// Represents parser state: whether parsing outside a loop,
    /// inside a loop, or inside a switch. This is used to determine whether
    /// break and continue statements are allowed.
    pub loop_state: LoopState,

    /// A rewriter for inserting synthetic tokens.
    /// Access using [rewriter] for lazy initialization.
    pub cached_rewriter: Option<AnyRewriter>,

    /// If `true`, syntax like `foo<bar>.baz()` is parsed like an implicit
    /// creation expression. Otherwise it is parsed as a explicit instantiation
    /// followed by an invocation.
    pub use_implicit_creation_expression: bool,

    /// The experiments currently enabled.
    pub experimental_features: Box<dyn ExperimentalFeatures>,

    /// `true` if the 'patterns' feature is enabled.
    pub is_patterns_feature_enabled: bool,

    /// `true` if the 'enhanced-parts' feature is enabled.
    is_enhanced_parts_feature_enabled: bool,

    /// `true` if the 'primary-constructors' feature is enabled.
    pub is_primary_constructors_feature_enabled: bool,

    /// `true` if the 'anonymous-methods' feature is enabled.
    is_anonymous_methods_feature_enabled: bool,

    /// Indicates whether the last pattern parsed is allowed inside unary
    /// patterns.  This is set by [parsePrimaryPattern] and [parsePattern].
    pub is_last_pattern_allowed_inside_unary_pattern: bool,

    /// `true` if the 'augmentations' feature is enabled.
    pub is_augmentations_feature_enabled: bool,

    /// `true` if the 'single-combinators' feature is enabled.
    is_single_combinators_feature_enabled: bool,

    pub statement_depth: i32,

    pub expression_depth: i32,

    recover_at_precedence_level: bool,
    currently_recovering: bool,

    /// `ClassMemberParser.skipParser`'s state: the state upstream keeps in a
    /// second parser that shares this one's listener (see
    /// class_member_parser.rs).
    pub(crate) skip_parser_state: Option<SkipParserState>,
}

/// What a `ClassMemberParser`'s `skipParser` keeps between calls.
#[derive(Debug)]
pub(crate) struct SkipParserState {
    pub(crate) cached_rewriter: Option<AnyRewriter>,
    pub(crate) is_last_pattern_allowed_inside_unary_pattern: bool,
    pub(crate) statement_depth: i32,
    pub(crate) expression_depth: i32,
    pub(crate) recover_at_precedence_level: bool,
    pub(crate) currently_recovering: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AwaitOrYieldContext {
    Statement,
    UnaryExpression,
}

#[derive(Debug)]
pub struct ForPartsContext {
    pub pattern_keyword: TokenId,
}

impl ForPartsContext {
    pub fn new() -> ForPartsContext {
        ForPartsContext {
            pattern_keyword: NO_TOKEN,
        }
    }
}

impl Default for ForPartsContext {
    fn default() -> Self {
        ForPartsContext::new()
    }
}

/// The context in which a pattern is being parsed.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PatternContext {
    /// The pattern is part of a localVariableDeclaration or forLoopParts,
    /// meaning it is not refutable.
    declaration,

    /// The pattern is part of a guardedPattern inside an if-case, switch
    /// expression, or switch statement, meaning it is refutable.
    matching,

    /// The pattern is part of a pattern assignment.
    assignment,
}

impl PatternContext {
    pub fn is_refutable(self) -> bool {
        match self {
            PatternContext::declaration => false,
            PatternContext::matching => true,
            PatternContext::assignment => false,
        }
    }
}

/// Enum describing the different contexts in which a constant pattern is
/// parsed.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ConstantPatternContext {
    /// The constant pattern is not parsed as a constant pattern.
    none,

    /// A constant pattern without a preceding `const` keyword.
    implicit,

    /// A constant pattern with a preceding `const` keyword.
    explicit,

    /// A constant pattern prefixed with `-`, which must be a numeric literal.
    numericLiteralOnly,
}

impl Parser {
    pub fn new(
        listener: Box<dyn Listener>,
        tokens: TokenStore,
        use_implicit_creation_expression: bool,
        experimental_features: Box<dyn ExperimentalFeatures>,
    ) -> Parser {
        let is_patterns_feature_enabled =
            experimental_features.is_experiment_enabled(ExperimentalFlag::patterns);
        let is_enhanced_parts_feature_enabled =
            experimental_features.is_experiment_enabled(ExperimentalFlag::enhancedParts);
        let is_primary_constructors_feature_enabled =
            experimental_features.is_experiment_enabled(ExperimentalFlag::primaryConstructors);
        let is_anonymous_methods_feature_enabled =
            experimental_features.is_experiment_enabled(ExperimentalFlag::anonymousMethods);
        let is_augmentations_feature_enabled =
            experimental_features.is_experiment_enabled(ExperimentalFlag::augmentations);
        let is_single_combinators_feature_enabled =
            experimental_features.is_experiment_enabled(ExperimentalFlag::singleCombinators);
        Parser {
            listener,
            tokens,
            kind: ParserKind::Parser,
            may_parse_function_expressions: true,
            async_state: AsyncModifier::Sync,
            loop_state: LoopState::OutsideLoop,
            cached_rewriter: None,
            use_implicit_creation_expression,
            experimental_features,
            is_patterns_feature_enabled,
            is_enhanced_parts_feature_enabled,
            is_primary_constructors_feature_enabled,
            is_anonymous_methods_feature_enabled,
            is_last_pattern_allowed_inside_unary_pattern: false,
            is_augmentations_feature_enabled,
            is_single_combinators_feature_enabled,
            statement_depth: 0,
            expression_depth: 0,
            recover_at_precedence_level: false,
            currently_recovering: false,
            skip_parser_state: None,
        }
    }

    /// The listener, as its concrete type.
    pub fn listener_as<L: Listener>(&mut self) -> &mut L {
        let any: &mut dyn Any = &mut *self.listener;
        any.downcast_mut::<L>().expect("listener type")
    }

    /// `Parser.rewriter`.
    pub fn rewriter(&mut self) -> Rewriter<'_, AnyRewriter> {
        let rewriter = self
            .cached_rewriter
            .get_or_insert(AnyRewriter::Impl(TokenStreamRewriterImpl));
        Rewriter {
            rewriter,
            tokens: &mut self.tokens,
        }
    }

    /// Whether the parser is allowed to shortcut certain [parseExpression] calls.
    ///
    /// Should be false if [parseExpression] is customized, e.g. if skipping
    /// expressions.
    pub fn allowed_to_shortcut_parse_expression(&self) -> bool {
        self.kind == ParserKind::Parser
    }

    pub fn in_generator(&self) -> bool {
        self.async_state == AsyncModifier::AsyncStar || self.async_state == AsyncModifier::SyncStar
    }

    pub fn in_async(&self) -> bool {
        self.async_state == AsyncModifier::Async || self.async_state == AsyncModifier::AsyncStar
    }

    pub fn in_plain_sync(&self) -> bool {
        self.async_state == AsyncModifier::Sync
    }

    pub fn is_break_allowed(&self) -> bool {
        self.loop_state != LoopState::OutsideLoop
    }

    pub fn is_continue_allowed(&self) -> bool {
        self.loop_state == LoopState::InsideLoop
    }

    pub fn is_continue_with_label_allowed(&self) -> bool {
        self.loop_state != LoopState::OutsideLoop
    }

    // Short forms of token getters used throughout.

    #[inline(always)]
    fn next(&self, token: TokenId) -> TokenId {
        self.tokens.next(token)
    }

    #[inline(always)]
    fn is_a(&self, token: TokenId, type_: &TokenType) -> bool {
        self.tokens.is_a(token, type_)
    }

    #[inline(always)]
    fn sv(&self, token: TokenId) -> Option<&'static str> {
        self.tokens.string_value(token)
    }

    // -- Error reporting (upstream near the end of the class) ---------------

    pub fn report_recoverable_error(&mut self, token: TokenId, message: impl Into<Message>) {
        // Find a non-synthetic token on which to report the error.
        let token = find_non_zero_length_token(&self.tokens, token);
        let message = message.into();
        self.listener
            .handle_recoverable_error(&mut self.tokens, &message, token, token);
    }

    pub fn report_recoverable_error_with_end(
        &mut self,
        start_token: TokenId,
        end_token: TokenId,
        message: impl Into<Message>,
    ) {
        let message = message.into();
        self.listener
            .handle_recoverable_error(&mut self.tokens, &message, start_token, end_token);
    }

    pub fn report_experiment_not_enabled(
        &mut self,
        experimental_flag: ExperimentalFlag,
        start_token: TokenId,
        end_token: TokenId,
    ) {
        self.listener.handle_experiment_not_enabled(
            &mut self.tokens,
            experimental_flag,
            start_token,
            end_token,
        );
    }

    pub fn report_recoverable_error_with_token(
        &mut self,
        token: TokenId,
        template: LexemeTemplate,
    ) {
        // Find a non-synthetic token on which to report the error.
        let token = find_non_zero_length_token(&self.tokens, token);
        let message = (template.with_arguments)(&self.tokens, token);
        self.listener
            .handle_recoverable_error(&mut self.tokens, &message, token, token);
    }

    pub fn report_all_error_tokens(&mut self, mut token: TokenId) -> TokenId {
        while self.tokens.runtime_type(token).is_error_token() {
            self.listener.handle_error_token(&mut self.tokens, token);
            token = self.next(token);
        }
        token
    }

    pub fn skip_error_tokens(&self, mut token: TokenId) -> TokenId {
        while self.tokens.runtime_type(token).is_error_token() {
            token = self.next(token);
        }
        token
    }
}

impl Parser {
    /// Parse a compilation unit.
    ///
    /// This method is only invoked from outside the parser. As a result, this
    /// method takes the next token to be consumed rather than the last consumed
    /// token and returns the token after the last consumed token rather than the
    /// last consumed token.
    pub fn parse_unit(&mut self, mut token: TokenId) -> TokenId {
        // Skip over error tokens and report them at the end
        // so that the parser has the chance to adjust the error location.
        let error_token = token;
        token = self.skip_error_tokens(error_token);

        self.listener
            .begin_compilation_unit(&mut self.tokens, token);
        let mut count = 0;
        let mut directive_state = DirectiveContext::new(self.is_enhanced_parts_feature_enabled);
        token = self.synthetic_previous_token(token);
        if self.tokens.type_(self.next(token)) == TokenType::SCRIPT_TAG {
            let next = self.next(token);
            directive_state.check_script_tag(self, next);
            token = self.parse_script(token);
        }
        while !self.tokens.is_eof(self.next(token)) {
            let start = self.next(token);
            token = self.parse_top_level_declaration_impl(token, Some(&mut directive_state));
            self.listener
                .end_top_level_declaration(&mut self.tokens, token);
            count += 1;
            if start == self.next(token) {
                // Recovery:
                // If progress has not been made reaching the end of the token stream,
                // then report an error and skip the current token.
                token = self.next(token);
                self.listener.begin_metadata_star(&mut self.tokens, token);
                self.listener.end_metadata_star(&mut self.tokens, 0);
                self.report_recoverable_error_with_token(token, diag::expectedDeclaration);
                self.listener
                    .handle_invalid_top_level_declaration(&mut self.tokens, token);
                self.listener
                    .end_top_level_declaration(&mut self.tokens, token);
                count += 1;
            }
        }
        token = self.next(token);
        debug_assert!(self.tokens.is_eof(token));
        self.report_all_error_tokens(error_token);
        self.listener
            .end_compilation_unit(&mut self.tokens, count, token);
        // Clear fields that could lead to memory leak.
        self.cached_rewriter = None;
        token
    }

    /// This method exists for analyzer compatibility only
    /// and will be removed once analyzer/fasta integration is complete.
    ///
    /// Similar to [parseUnit], this method parses a compilation unit,
    /// but stops when it reaches the first declaration or EOF.
    pub fn parse_directives(&mut self, mut token: TokenId) -> TokenId {
        token = self.skip_error_tokens(token);
        self.listener
            .begin_compilation_unit(&mut self.tokens, token);
        let count = 0;
        let mut directive_state = DirectiveContext::new(self.is_enhanced_parts_feature_enabled);
        token = self.synthetic_previous_token(token);
        while !self.tokens.is_eof(self.next(token)) {
            let start = self.next(token);
            let next_value = self.sv(self.next(start));

            // If a built-in keyword is being used as an identifier,
            // then stop parsing directives and return.
            if next_value == Some(".") || next_value == Some("<") || next_value == Some("(") {
                break;
            }

            let mut report_top_level_declaration_end = true;
            if self.tokens.type_(self.next(token)) == TokenType::SCRIPT_TAG {
                let next = self.next(token);
                directive_state.check_script_tag(self, next);
                token = self.parse_script(token);
                report_top_level_declaration_end = false;
            } else {
                token = self.parse_metadata_star(token);
                let keyword = self.next(token);
                let value = self.sv(keyword);
                if value == Some("import") {
                    directive_state.check_import(self, keyword);
                    token = self.parse_import(keyword);
                } else if value == Some("export") {
                    directive_state.check_export(self, keyword);
                    token = self.parse_export(keyword);
                } else if value == Some("library") {
                    directive_state.check_library(self, keyword);
                    token = self.parse_library_name(keyword);
                } else if value == Some("part") {
                    token = self.parse_part_or_part_of(keyword, Some(&mut directive_state));
                } else if value == Some(";") {
                    token = start;
                    self.listener.handle_directives_only(&mut self.tokens);
                    report_top_level_declaration_end = false;
                } else {
                    self.listener.handle_directives_only(&mut self.tokens);
                    report_top_level_declaration_end = false;
                    break;
                }
            }
            if report_top_level_declaration_end {
                self.listener
                    .end_top_level_declaration(&mut self.tokens, token);
            }
        }
        token = self.next(token);
        self.listener
            .end_compilation_unit(&mut self.tokens, count, token);
        // Clear fields that could lead to memory leak.
        self.cached_rewriter = None;
        token
    }

    /// Parse a top-level declaration.
    ///
    /// This method is only invoked from outside the parser. As a result, this
    /// method takes the next token to be consumed rather than the last consumed
    /// token and returns the token after the last consumed token rather than the
    /// last consumed token.
    pub fn parse_top_level_declaration(&mut self, token: TokenId) -> TokenId {
        let previous = self.synthetic_previous_token(token);
        let token = self.parse_top_level_declaration_impl(previous, None);
        self.listener
            .end_top_level_declaration(&mut self.tokens, token);
        self.next(token)
    }

    pub fn parse_top_level_declaration_impl(
        &mut self,
        mut token: TokenId,
        mut directive_state: Option<&mut DirectiveContext>,
    ) -> TokenId {
        token = self.parse_metadata_star(token);
        let mut next = self.next(token);
        if self.tokens.is_top_level_keyword(next) {
            return self.parse_top_level_keyword_declaration(
                self.next(token),
                token,
                next,
                NO_TOKEN,
                NO_TOKEN,
                NO_TOKEN,
                directive_state,
            );
        }
        let begin_token = self.next(token);
        let mut modifier_start = token;
        // Skip modifiers to find a top level keyword or identifier
        if self.tokens.is_modifier(next) {
            if self.is_a(next, kw::VAR)
                || self.is_a(next, kw::LATE)
                || (self.is_a(next, kw::FINAL)
                    && (!self.is_a(self.next(next), kw::CLASS)
                        && !self.is_a(self.next(next), kw::MIXIN)
                        && !self.is_a(self.next(next), kw::ENUM)))
                // Ignore using 'final' as a modifier for a class, a mixin, or an
                // enum, but allow in other contexts.
                || (self.is_a(next, kw::CONST) && !self.is_a(self.next(next), kw::CLASS))
            {
                // Top level `const class` is an error, so we handle the
                // `const` as a modifier rather than a top-level declaration.
                if let Some(d) = directive_state.as_deref_mut() {
                    d.check_declaration();
                }
                return self.parse_top_level_member_impl(token);
            }
            while self.tokens.is_modifier(self.next(token)) {
                token = self.next(token);
            }
        }
        next = self.next(token);
        let mut sealed_token = NO_TOKEN;
        let mut base_token = NO_TOKEN;
        let mut interface_token = NO_TOKEN;
        let t = &self.tokens;
        let class_mixin_or_enum = |t: &TokenStore, n: TokenId| {
            t.is_a(n, kw::CLASS) || t.is_a(n, kw::MIXIN) || t.is_a(n, kw::ENUM)
        };
        if t.is_identifier(next) && t.is_a(next, kw::SEALED) {
            sealed_token = next;
            if class_mixin_or_enum(t, t.next(next)) {
                next = t.next(next);
            } else if t.is_a(t.next(next), kw::ABSTRACT) && t.is_a(t.next(t.next(next)), kw::CLASS)
            {
                // Recovery: Handle `sealed abstract class` by treating `abstract`
                // as a modifier.
                modifier_start = next;
                next = t.next(t.next(next));
            }
        } else if t.is_identifier(next) && t.is_a(next, kw::BASE) {
            base_token = next;
            if class_mixin_or_enum(t, t.next(next)) {
                next = t.next(next);
            }
        } else if t.is_identifier(next) && t.is_a(next, kw::INTERFACE) {
            interface_token = next;
            if class_mixin_or_enum(t, t.next(next)) {
                next = t.next(next);
            }
            // TODO(kallentu): Handle incorrect ordering of modifiers.
        }
        if t.is_top_level_keyword(next) {
            return self.parse_top_level_keyword_declaration(
                begin_token,
                modifier_start,
                next,
                sealed_token,
                base_token,
                interface_token,
                directive_state,
            );
        } else if t.is_keyword_or_identifier(next)
            || t.next(modifier_start) != next
            // record type
            || t.is_a(next, TokenType::OPEN_PAREN)
        {
            // TODO(danrubel): improve parseTopLevelMember
            // so that we don't parse modifiers twice.
            if let Some(d) = directive_state {
                d.check_declaration();
            }
            return self.parse_top_level_member_impl(modifier_start);
        }
        // Recovery
        if t.is_operator(next) && t.is_a(t.next(next), TokenType::OPEN_PAREN) {
            // This appears to be a top level operator declaration, which is invalid.
            self.report_recoverable_error(next, diag::topLevelOperator);
            // Insert a synthetic identifier
            // and continue parsing as a top level function.
            let name = format!("#synthetic_function_{}", self.tokens.char_offset(next));
            self.rewriter()
                .insert_synthetic_identifier_with_value(next, &name);
            return self.parse_top_level_member_impl(next);
        }
        // Ignore any preceding modifiers and just report the unexpected token
        self.listener.begin_top_level_member(&mut self.tokens, next);
        self.parse_invalid_top_level_declaration(token)
    }

    /// Parse the modifiers before the `class` keyword.
    /// Return the first `abstract` modifier or `null` if not found.
    fn parse_top_level_keyword_declaration(
        &mut self,
        begin_token: TokenId,
        modifier_start: TokenId,
        keyword: TokenId,
        sealed_token: TokenId,
        base_token: TokenId,
        interface_token: TokenId,
        mut directive_state: Option<&mut DirectiveContext>,
    ) -> TokenId {
        debug_assert!(self.tokens.is_top_level_keyword(keyword));
        let value = self.sv(keyword);
        macro_rules! check_declaration {
            () => {
                if let Some(d) = directive_state.as_deref_mut() {
                    d.check_declaration();
                }
            };
        }
        if value == Some("class") {
            return self.handle_modifiers_for_class_declaration(
                begin_token,
                modifier_start,
                keyword,
                sealed_token,
                base_token,
                interface_token,
                NO_TOKEN,
                directive_state,
            );
        } else if value == Some("enum") {
            check_declaration!();
            let mut context = ModifierContext::new();
            context.parse_enum_modifiers(self, modifier_start, keyword);
            if base_token != NO_TOKEN {
                self.report_recoverable_error(base_token, diag::baseEnum);
            }
            if context.final_token != NO_TOKEN {
                self.report_recoverable_error(context.final_token, diag::finalEnum);
            }
            if interface_token != NO_TOKEN {
                self.report_recoverable_error(interface_token, diag::interfaceEnum);
            }
            if sealed_token != NO_TOKEN {
                self.report_recoverable_error(sealed_token, diag::sealedEnum);
            }
            return self.parse_enum(begin_token, context.augment_token, keyword);
        } else {
            // The remaining top level keywords are built-in keywords
            // and can be used in a top level declaration
            // as an identifier such as "abstract<T>() => 0;"
            // or as a prefix such as "abstract.A b() => 0;".
            // This also means that `typedef ({int? j}) => {}` should
            // be parsed as a function and not a typedef.
            let next_value = self.sv(self.next(keyword));
            let mut typedef_with_record = false;
            if value == Some("typedef") && next_value == Some("(") {
                let end_paren = self.tokens.end_group(self.next(keyword));
                if end_paren != NO_TOKEN
                    && self.is_identifier_or_question_identifier(self.next(end_paren))
                {
                    // Looks like a typedef with a record.
                    let type_info = compute_type(&mut self.tokens, keyword, false, false, false);
                    if let TypeInfo::Complex(info) = &type_info {
                        if info.borrow().is_record_type {
                            typedef_with_record = true;
                        }
                    }
                }
            }

            if (next_value == Some("(") || next_value == Some(".")) && !typedef_with_record {
                check_declaration!();
                return self.parse_top_level_member_impl(modifier_start);
            } else if next_value == Some("<") {
                if value == Some("extension") {
                    // The name in an extension declaration is optional:
                    // `extension<T> on ...`
                    let end_group = self.tokens.end_group(self.next(keyword));
                    if end_group != NO_TOKEN && self.is_a(self.next(end_group), kw::ON) {
                        check_declaration!();
                        let mut context = ModifierContext::new();
                        context.parse_extension_modifiers(self, modifier_start, keyword);
                        return self.parse_extension(begin_token, context.augment_token, keyword);
                    }
                } else if value == Some("typedef") {
                    let end_group = self.tokens.end_group(self.next(keyword));
                    if end_group != NO_TOKEN
                        && self.next(end_group) != NO_TOKEN
                        && self.is_a(self.next(end_group), TokenType::EQ)
                    {
                        let mut context = ModifierContext::new();
                        context.parse_typedef_modifiers(self, modifier_start, keyword);
                        check_declaration!();
                        return self.parse_typedef(context.augment_token, keyword);
                    }
                }
                check_declaration!();
                return self.parse_top_level_member_impl(modifier_start);
            } else {
                let mut context = ModifierContext::new();
                if value == Some("import") {
                    context.parse_top_level_keyword_modifiers(self, modifier_start, keyword);
                    if let Some(d) = directive_state.as_deref_mut() {
                        d.check_import(self, keyword);
                    }
                    return self.parse_import(keyword);
                } else if value == Some("export") {
                    context.parse_top_level_keyword_modifiers(self, modifier_start, keyword);
                    if let Some(d) = directive_state.as_deref_mut() {
                        d.check_export(self, keyword);
                    }
                    return self.parse_export(keyword);
                } else if value == Some("typedef") {
                    context.parse_typedef_modifiers(self, modifier_start, keyword);
                    check_declaration!();
                    return self.parse_typedef(context.augment_token, keyword);
                } else if value == Some("mixin") {
                    if next_value == Some("class") {
                        let class_keyword = self.next(keyword);
                        return self.handle_modifiers_for_class_declaration(
                            begin_token,
                            modifier_start,
                            class_keyword,
                            sealed_token,
                            base_token,
                            interface_token,
                            keyword,
                            directive_state,
                        );
                    }
                    context.parse_mixin_modifiers(self, modifier_start, keyword);
                    if context.final_token != NO_TOKEN {
                        self.report_recoverable_error(context.final_token, diag::finalMixin);
                    }
                    if interface_token != NO_TOKEN {
                        self.report_recoverable_error(interface_token, diag::interfaceMixin);
                    }
                    if sealed_token != NO_TOKEN {
                        self.report_recoverable_error(sealed_token, diag::sealedMixin);
                    }
                    check_declaration!();
                    return self.parse_mixin(
                        begin_token,
                        context.augment_token,
                        base_token,
                        keyword,
                    );
                } else if value == Some("extension") {
                    context.parse_extension_modifiers(self, modifier_start, keyword);
                    check_declaration!();
                    let begin = self.next(modifier_start);
                    return self.parse_extension(begin, context.augment_token, keyword);
                } else if value == Some("part") {
                    context.parse_top_level_keyword_modifiers(self, modifier_start, keyword);
                    return self.parse_part_or_part_of(keyword, directive_state);
                } else if value == Some("library") {
                    if let Some(d) = directive_state {
                        d.check_library(self, keyword);
                    }
                    context.parse_library_directive_modifiers(self, modifier_start, keyword);
                    if context.augment_token != NO_TOKEN {
                        return self.parse_library_augmentation(context.augment_token, keyword);
                    } else {
                        return self.parse_library_name(keyword);
                    }
                }
            }
        }

        panic!("Internal error: Unhandled top level keyword '{value:?}'.");
    }

    fn handle_modifiers_for_class_declaration(
        &mut self,
        begin_token: TokenId,
        modifier_start: TokenId,
        class_keyword: TokenId,
        sealed_token: TokenId,
        base_token: TokenId,
        interface_token: TokenId,
        mixin_token: TokenId,
        directive_state: Option<&mut DirectiveContext>,
    ) -> TokenId {
        if let Some(d) = directive_state {
            d.check_declaration();
        }
        let mut context = ModifierContext::new();
        if mixin_token != NO_TOKEN {
            context.parse_class_modifiers(self, modifier_start, mixin_token);

            // Mixin classes can't have any modifier other than a base modifier.
            if context.final_token != NO_TOKEN {
                self.report_recoverable_error(context.final_token, diag::finalMixinClass);
            }
            if interface_token != NO_TOKEN {
                self.report_recoverable_error(interface_token, diag::interfaceMixinClass);
            }
            if sealed_token != NO_TOKEN {
                self.report_recoverable_error(sealed_token, diag::sealedMixinClass);
            }
        } else {
            context.parse_class_modifiers(self, modifier_start, class_keyword);
        }
        self.parse_class_or_named_mixin_application(
            begin_token,
            context.abstract_token,
            sealed_token,
            base_token,
            interface_token,
            context.final_token,
            context.augment_token,
            mixin_token,
            class_keyword,
        )
    }

    fn is_identifier_or_question_identifier(&self, token: TokenId) -> bool {
        if self.tokens.is_identifier(token) {
            return true;
        }
        if self.is_a(token, TokenType::QUESTION) {
            return self.tokens.is_identifier(self.next(token));
        }
        false
    }

    /// ```text
    /// libraryAugmentationDirective:
    ///   'augment' 'library' uri ';'
    /// ;
    /// ```
    pub fn parse_library_augmentation(
        &mut self,
        augment_keyword: TokenId,
        library_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(augment_keyword, kw::AUGMENT));
        debug_assert!(self.is_a(library_keyword, kw::LIBRARY));
        self.listener
            .begin_uncategorized_top_level_declaration(&mut self.tokens, library_keyword);
        self.listener.begin_library_augmentation(
            &mut self.tokens,
            augment_keyword,
            library_keyword,
        );
        let start = library_keyword;
        let token = self.ensure_literal_string(start);
        let semicolon = self.ensure_semicolon(token);
        self.listener.end_library_augmentation(
            &mut self.tokens,
            augment_keyword,
            library_keyword,
            semicolon,
        );
        semicolon
    }

    /// ```text
    /// libraryDirective:
    ///   'library' qualified? ';'
    /// ;
    /// ```
    pub fn parse_library_name(&mut self, library_keyword: TokenId) -> TokenId {
        debug_assert!(self.is_a(library_keyword, kw::LIBRARY));
        self.listener
            .begin_uncategorized_top_level_declaration(&mut self.tokens, library_keyword);
        self.listener
            .begin_library_name(&mut self.tokens, library_keyword);
        let mut token = self.next(library_keyword);
        let has_name = !self.is_a(token, TokenType::SEMICOLON);
        if has_name {
            token = self.parse_qualified(
                library_keyword,
                IdentifierContext::libraryName,
                IdentifierContext::libraryNameContinuation,
            );
            token = self.ensure_semicolon(token);
        } else {
            token = self.ensure_semicolon(library_keyword);
        }
        self.listener
            .end_library_name(&mut self.tokens, library_keyword, token, has_name);
        token
    }

    /// ```text
    /// importPrefix:
    ///   'deferred'? 'as' identifier
    /// ;
    /// ```
    pub fn parse_import_prefix_opt(&mut self, mut token: TokenId) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, kw::DEFERRED) && self.is_a(self.next(next), kw::AS) {
            let deferred_token = next;
            let as_keyword = self.next(next);
            token = self.ensure_identifier(as_keyword, IdentifierContext::importPrefixDeclaration);
            self.listener
                .handle_import_prefix(&mut self.tokens, deferred_token, as_keyword);
        } else if self.is_a(next, kw::AS) {
            let as_keyword = next;
            token = self.ensure_identifier(next, IdentifierContext::importPrefixDeclaration);
            self.listener
                .handle_import_prefix(&mut self.tokens, NO_TOKEN, as_keyword);
        } else {
            self.listener
                .handle_import_prefix(&mut self.tokens, NO_TOKEN, NO_TOKEN);
        }
        token
    }

    /// ```text
    /// importDirective:
    ///   'import' uri ('if' '(' test ')' uri)* importPrefix? combinator* ';'
    /// ;
    /// ```
    pub fn parse_import(&mut self, import_keyword: TokenId) -> TokenId {
        debug_assert!(self.is_a(import_keyword, kw::IMPORT));
        self.listener
            .begin_uncategorized_top_level_declaration(&mut self.tokens, import_keyword);
        self.listener.begin_import(&mut self.tokens, import_keyword);
        let start = import_keyword;
        let mut token = self.ensure_literal_string(start);
        let uri = token;
        token = self.parse_conditional_uri_star(token);
        token = self.parse_import_prefix_opt(token);
        token = self.parse_combinator_star(token);
        token = self.next(token);
        if self.is_a(token, TokenType::SEMICOLON) {
            self.listener
                .end_import(&mut self.tokens, import_keyword, token);
            token
        } else {
            // Recovery
            self.listener
                .end_import(&mut self.tokens, import_keyword, NO_TOKEN);
            self.parse_import_recovery(uri)
        }
    }
}

impl Parser {
    /// Installs a recovery listener (a `ForwardingListener` that forwards
    /// nowhere yet) and returns the listener it replaces.
    fn install_recovery_listener(&mut self, recovery: Recovery) -> Box<dyn Listener> {
        let mut recovery_listener = ForwardingListener::new(None);
        recovery_listener.recovery = Some(recovery);
        std::mem::replace(&mut self.listener, Box::new(recovery_listener))
    }

    /// The installed recovery listener's `listener`.
    fn recovery_listener(&mut self) -> &mut ForwardingListener {
        self.listener_as::<ForwardingListener>()
    }

    fn import_recovery(&mut self) -> &mut ImportRecoveryListener {
        match self.recovery_listener().recovery.as_mut() {
            Some(Recovery::Import(r)) => r,
            _ => unreachable!("not an ImportRecoveryListener"),
        }
    }

    fn declaration_header_recovery(&mut self) -> &mut DeclarationHeaderRecoveryListener {
        match self.recovery_listener().recovery.as_mut() {
            Some(Recovery::DeclarationHeader(r)) => r,
            _ => unreachable!("not a DeclarationHeaderRecoveryListener"),
        }
    }

    fn mixin_header_recovery(&mut self) -> &mut MixinHeaderRecoveryListener {
        match self.recovery_listener().recovery.as_mut() {
            Some(Recovery::MixinHeader(r)) => r,
            _ => unreachable!("not a MixinHeaderRecoveryListener"),
        }
    }

    /// Recover given out-of-order clauses in an import directive where [token] is
    /// the import keyword.
    pub fn parse_import_recovery(&mut self, mut token: TokenId) -> TokenId {
        let primary_listener =
            self.install_recovery_listener(Recovery::Import(ImportRecoveryListener::default()));

        // Reparse to determine which clauses have already been parsed
        // but intercept the events so they are not sent to the primary listener
        token = self.parse_conditional_uri_star(token);
        token = self.parse_import_prefix_opt(token);
        token = self.parse_combinator_star(token);

        let state = self.import_recovery().clone();
        let mut first_deferred_keyword = state.deferred_keyword;
        let mut has_prefix = state.as_keyword != NO_TOKEN;
        let mut has_combinator = state.has_combinator;

        // Update the recovery listener to forward subsequent events
        // to the primary listener
        self.recovery_listener().listener = Some(primary_listener);

        // Parse additional out-of-order clauses.
        // Note: upstream leaves the recovery listener installed afterwards.
        let mut semicolon;
        loop {
            let start = self.next(token);

            // Check for extraneous token in the middle of an import statement.
            token = self
                .skip_unexpected_token_opt(token, &["if", "deferred", "as", "hide", "show", ";"]);

            // During recovery, clauses are parsed in the same order
            // and generate the same events as in the parseImport method above.
            self.import_recovery().clear();
            token = self.parse_conditional_uri_star(token);
            if self.import_recovery().if_keyword != NO_TOKEN {
                if first_deferred_keyword != NO_TOKEN {
                    // TODO(danrubel): report error indicating conditional should
                    // be moved before deferred keyword
                } else if has_prefix {
                    // TODO(danrubel): report error indicating conditional should
                    // be moved before prefix clause
                } else if has_combinator {
                    // TODO(danrubel): report error indicating conditional should
                    // be moved before combinators
                }
            }

            if self.is_a(self.next(token), kw::DEFERRED)
                && !self.is_a(self.next(self.next(token)), kw::AS)
            {
                let next = self.next(token);
                self.listener
                    .handle_import_prefix(&mut self.tokens, next, NO_TOKEN);
                token = next;
            } else {
                token = self.parse_import_prefix_opt(token);
            }
            let deferred_keyword = self.import_recovery().deferred_keyword;
            if deferred_keyword != NO_TOKEN {
                if first_deferred_keyword != NO_TOKEN {
                    self.report_recoverable_error(deferred_keyword, diag::duplicateDeferred);
                } else {
                    if has_prefix {
                        self.report_recoverable_error(deferred_keyword, diag::deferredAfterPrefix);
                    }
                    first_deferred_keyword = deferred_keyword;
                }
            }
            let as_keyword = self.import_recovery().as_keyword;
            if as_keyword != NO_TOKEN {
                if has_prefix {
                    self.report_recoverable_error(as_keyword, diag::duplicatePrefix);
                } else {
                    if has_combinator {
                        self.report_recoverable_error(as_keyword, diag::prefixAfterCombinator);
                    }
                    has_prefix = true;
                }
            }

            token = self.parse_combinator_star(token);
            has_combinator = has_combinator || self.import_recovery().has_combinator;

            semicolon = NO_TOKEN;
            if self.is_a(self.next(token), TokenType::SEMICOLON) {
                semicolon = self.next(token);
            } else if start == self.next(token) {
                // If no forward progress was made, insert ';' so that we exit loop.
                semicolon = self.ensure_semicolon(token);
            }
            self.listener
                .handle_recover_import(&mut self.tokens, semicolon);
            if semicolon != NO_TOKEN {
                break;
            }
        }

        if first_deferred_keyword != NO_TOKEN && !has_prefix {
            self.report_recoverable_error(
                first_deferred_keyword,
                diag::missingPrefixInDeferredImport,
            );
        }

        semicolon
    }

    /// ```text
    /// conditionalUris:
    ///   conditionalUri*
    /// ;
    /// ```
    pub fn parse_conditional_uri_star(&mut self, mut token: TokenId) -> TokenId {
        let next_38 = self.tokens.next(token);
        self.listener
            .begin_conditional_uris(&mut self.tokens, next_38);
        let mut count = 0;
        while self.is_a(self.next(token), kw::IF) {
            count += 1;
            token = self.parse_conditional_uri(token);
        }
        self.listener.end_conditional_uris(&mut self.tokens, count);
        token
    }

    /// ```text
    /// conditionalUri:
    ///   'if' '(' dottedName ('==' literalString)? ')' uri
    /// ;
    /// ```
    pub fn parse_conditional_uri(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let if_keyword = token;
        debug_assert!(self.is_a(token, kw::IF));
        self.listener.begin_conditional_uri(&mut self.tokens, token);
        let mut left_paren = self.next(token);
        if !self.is_a(left_paren, TokenType::OPEN_PAREN) {
            self.report_recoverable_error(left_paren, (diag::expectedButGot.with_arguments)("("));
            left_paren = self.rewriter().insert_parens(token, true);
        }
        token = self.parse_dotted_name(left_paren);
        let mut next = self.next(token);
        let mut equality_sign = NO_TOKEN;
        if self.is_a(next, TokenType::EQ_EQ) {
            equality_sign = next;
            token = self.ensure_literal_string(next);
            next = self.next(token);
        }
        if next != self.tokens.end_group(left_paren) {
            let end_group = self.tokens.end_group(left_paren);
            if self.tokens.is_synthetic(end_group) {
                // The scanner did not place the synthetic ')' correctly, so move it.
                next = self.rewriter().move_synthetic(token, end_group);
            } else {
                self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                next = end_group;
            }
        }
        token = next;
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));

        token = self.ensure_literal_string(token);
        self.listener
            .end_conditional_uri(&mut self.tokens, if_keyword, left_paren, equality_sign);
        token
    }

    /// ```text
    /// dottedName:
    ///   identifier ('.' identifier)*
    /// ;
    /// ```
    pub fn parse_dotted_name(&mut self, mut token: TokenId) -> TokenId {
        token = self.ensure_identifier(token, IdentifierContext::dottedName);
        let first_identifier = token;
        let mut count = 1;
        while self.is_a(self.next(token), TokenType::PERIOD) {
            let next = self.next(token);
            token = self.ensure_identifier(next, IdentifierContext::dottedNameContinuation);
            count += 1;
        }
        self.listener
            .handle_dotted_name(&mut self.tokens, count, first_identifier);
        token
    }

    /// ```text
    /// exportDirective:
    ///   'export' uri conditional-uris* combinator* ';'
    /// ;
    /// ```
    pub fn parse_export(&mut self, export_keyword: TokenId) -> TokenId {
        debug_assert!(self.is_a(export_keyword, kw::EXPORT));
        self.listener
            .begin_uncategorized_top_level_declaration(&mut self.tokens, export_keyword);
        self.listener.begin_export(&mut self.tokens, export_keyword);
        let mut token = self.ensure_literal_string(export_keyword);
        token = self.parse_conditional_uri_star(token);
        token = self.parse_combinator_star(token);
        token = self.ensure_semicolon(token);
        self.listener
            .end_export(&mut self.tokens, export_keyword, token);
        token
    }

    /// ```text
    /// combinators:
    ///   (hideCombinator | showCombinator)*
    /// ;
    /// ```
    pub fn parse_combinator_star(&mut self, mut token: TokenId) -> TokenId {
        let mut next = self.next(token);
        self.listener.begin_combinators(&mut self.tokens, next);
        let mut count = 0;
        loop {
            let value = self.sv(next);
            if value == Some("hide") {
                if count > 0 && self.is_single_combinators_feature_enabled {
                    self.report_recoverable_error(next, diag::multipleCombinators);
                }
                token = self.parse_hide(token);
            } else if value == Some("show") {
                if count > 0 && self.is_single_combinators_feature_enabled {
                    self.report_recoverable_error(next, diag::multipleCombinators);
                }
                token = self.parse_show(token);
            } else {
                self.listener.end_combinators(&mut self.tokens, count);
                break;
            }
            next = self.next(token);
            count += 1;
        }
        token
    }

    /// ```text
    /// hideCombinator:
    ///   'hide' identifierList
    /// ;
    /// ```
    pub fn parse_hide(&mut self, token: TokenId) -> TokenId {
        let hide_keyword = self.next(token);
        debug_assert!(self.is_a(hide_keyword, kw::HIDE));
        self.listener.begin_hide(&mut self.tokens, hide_keyword);
        let token = self.parse_identifier_list(hide_keyword);
        self.listener.end_hide(&mut self.tokens, hide_keyword);
        token
    }

    /// ```text
    /// showCombinator:
    ///   'show' identifierList
    /// ;
    /// ```
    pub fn parse_show(&mut self, token: TokenId) -> TokenId {
        let show_keyword = self.next(token);
        debug_assert!(self.is_a(show_keyword, kw::SHOW));
        self.listener.begin_show(&mut self.tokens, show_keyword);
        let token = self.parse_identifier_list(show_keyword);
        self.listener.end_show(&mut self.tokens, show_keyword);
        token
    }

    /// ```text
    /// identifierList:
    ///   identifier (',' identifier)*
    /// ;
    /// ```
    pub fn parse_identifier_list(&mut self, mut token: TokenId) -> TokenId {
        token = self.ensure_identifier(token, IdentifierContext::combinator);
        let mut count = 1;
        while self.is_a(self.next(token), TokenType::COMMA) {
            let next = self.next(token);
            token = self.ensure_identifier(next, IdentifierContext::combinator);
            count += 1;
        }
        self.listener
            .handle_identifier_list(&mut self.tokens, count);
        token
    }

    /// ```text
    /// typeList:
    ///   type (',' type)*
    /// ;
    /// ```
    pub fn parse_type_list(&mut self, mut token: TokenId) -> TokenId {
        let next_37 = self.tokens.next(token);
        self.listener.begin_type_list(&mut self.tokens, next_37);
        token = compute_type(&mut self.tokens, token, true, false, false)
            .ensure_type_or_void(token, self);
        let mut count = 1;
        while self.is_a(self.next(token), TokenType::COMMA) {
            let next = self.next(token);
            token = compute_type(&mut self.tokens, next, true, false, false)
                .ensure_type_or_void(next, self);
            count += 1;
        }
        self.listener.end_type_list(&mut self.tokens, count);
        token
    }

    pub fn parse_part_or_part_of(
        &mut self,
        part_keyword: TokenId,
        directive_state: Option<&mut DirectiveContext>,
    ) -> TokenId {
        debug_assert!(self.is_a(part_keyword, kw::PART));
        self.listener
            .begin_uncategorized_top_level_declaration(&mut self.tokens, part_keyword);
        if self.is_a(self.next(part_keyword), kw::OF) {
            if let Some(d) = directive_state {
                d.check_part_of(self, part_keyword);
            }
            self.parse_part_of(part_keyword)
        } else {
            if let Some(d) = directive_state {
                d.check_part(self, part_keyword);
            }
            self.parse_part(part_keyword)
        }
    }

    /// ```text
    /// partDirective:
    ///   'part' uri ';'
    /// ;
    /// ```
    pub fn parse_part(&mut self, part_keyword: TokenId) -> TokenId {
        debug_assert!(self.is_a(part_keyword, kw::PART));
        self.listener.begin_part(&mut self.tokens, part_keyword);
        let mut token = self.ensure_literal_string(part_keyword);
        token = self.ensure_semicolon(token);
        self.listener
            .end_part(&mut self.tokens, part_keyword, token);
        token
    }

    /// ```text
    /// partOfDirective:
    ///   'part' 'of' (qualified | uri) ';'
    /// ;
    /// ```
    pub fn parse_part_of(&mut self, part_keyword: TokenId) -> TokenId {
        let of_keyword = self.next(part_keyword);
        debug_assert!(self.is_a(part_keyword, kw::PART));
        debug_assert!(self.is_a(of_keyword, kw::OF));
        self.listener.begin_part_of(&mut self.tokens, part_keyword);
        let has_name = self.tokens.is_identifier(self.next(of_keyword));
        let mut token = if has_name {
            self.parse_qualified(
                of_keyword,
                IdentifierContext::partName,
                IdentifierContext::partNameContinuation,
            )
        } else {
            self.ensure_literal_string(of_keyword)
        };
        token = self.ensure_semicolon(token);
        self.listener
            .end_part_of(&mut self.tokens, part_keyword, of_keyword, token, has_name);
        token
    }

    /// ```text
    /// metadata:
    ///   annotation*
    /// ;
    /// ```
    pub fn parse_metadata_star(&mut self, mut token: TokenId) -> TokenId {
        let next_36 = self.tokens.next(token);
        self.listener.begin_metadata_star(&mut self.tokens, next_36);
        let mut count = 0;
        while self.is_a(self.next(token), TokenType::AT) {
            token = self.parse_metadata(token);
            count += 1;
        }
        self.listener.end_metadata_star(&mut self.tokens, count);
        token
    }

    /// ```text
    /// <metadata> ::= (‘@’ <metadatum>)*
    /// <metadatum> ::= <identifier>
    ///   | <qualifiedName>
    ///   | <constructorDesignation> <arguments>
    /// ```
    pub fn parse_metadata(&mut self, mut token: TokenId) -> TokenId {
        let at_token = self.next(token);
        debug_assert!(self.is_a(at_token, TokenType::AT));
        self.listener.begin_metadata(&mut self.tokens, at_token);
        token = self.ensure_identifier(at_token, IdentifierContext::metadataReference);
        token = self.parse_qualified_rest_opt(token, IdentifierContext::metadataContinuation);
        let has_type_arguments = self.is_a(self.next(token), TokenType::LT);
        token = compute_type_param_or_arg(&mut self.tokens, token, false, false)
            .parse_arguments(token, self);
        let mut period = NO_TOKEN;
        if self.is_a(self.next(token), TokenType::PERIOD) {
            period = self.next(token);
            token = self.ensure_identifier(
                period,
                IdentifierContext::metadataContinuationAfterTypeArguments,
            );
        }
        if has_type_arguments && !self.is_a(self.next(token), TokenType::OPEN_PAREN) {
            self.report_recoverable_error(token, diag::metadataTypeArgumentsUninstantiated);
        }
        token = self.parse_arguments_opt_metadata(token, has_type_arguments);
        self.listener
            .end_metadata(&mut self.tokens, at_token, period, token);
        token
    }

    /// ```text
    /// scriptTag:
    ///   '#!' (˜NEWLINE)* NEWLINE
    /// ;
    /// ```
    pub fn parse_script(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.tokens.type_(token) == TokenType::SCRIPT_TAG);
        self.listener.handle_script(&mut self.tokens, token);
        token
    }

    /// ```text
    /// typeAlias:
    ///   metadata 'typedef' typeAliasBody |
    ///   metadata 'typedef' identifier typeParameters? '=' functionType ';'
    /// ;
    /// ```
    pub fn parse_typedef(&mut self, augment_token: TokenId, typedef_keyword: TokenId) -> TokenId {
        debug_assert!(self.is_a(typedef_keyword, kw::TYPEDEF));
        if augment_token != NO_TOKEN {
            self.report_recoverable_error(augment_token, diag::typedefAugmentation);
        }
        self.listener
            .begin_uncategorized_top_level_declaration(&mut self.tokens, typedef_keyword);
        self.listener
            .begin_typedef(&mut self.tokens, typedef_keyword);
        let type_info = compute_type(&mut self.tokens, typedef_keyword, false, false, false);
        let mut token = type_info.skip_type(&mut self.tokens, typedef_keyword);
        let mut next = self.next(token);
        let mut equals = NO_TOKEN;
        let mut type_param = compute_type_param_or_arg(&mut self.tokens, next, true, false);
        // Allow recovery from:
        // typedef F<T> = ... ;
        // typedef F<T>() ... ;
        let mut new_style = false;
        let mut new_style_parse_as_recovered = false;
        if type_info == noType {
            let mut skip = type_param.skip(&mut self.tokens, next);
            if self.is_a(self.next(skip), TokenType::EQ) {
                // typedef F<T> = ...;
                new_style = true;
                new_style_parse_as_recovered = true;
            } else if self.is_a(skip, TokenType::EQ) {
                // typedef = ...;
                new_style = true;
                new_style_parse_as_recovered = false;
            } else if self.is_a(skip, TokenType::LT) {
                // typedef <T> = ...;
                let end_group = self.tokens.end_group(skip);
                if end_group != NO_TOKEN
                    && self.next(end_group) != NO_TOKEN
                    && self.is_a(self.next(end_group), TokenType::EQ)
                {
                    let new_type_param =
                        compute_type_param_or_arg(&mut self.tokens, token, true, false);
                    skip = new_type_param.skip(&mut self.tokens, token);
                    if self.is_a(self.next(skip), TokenType::EQ) {
                        type_param = new_type_param;
                        new_style = true;
                        new_style_parse_as_recovered = false;
                    }
                }
            }
        }
        if new_style {
            // New style typedef, e.g. typedef F<T> = Function(T);
            token = self.ensure_identifier_potentially_recovered(
                token,
                IdentifierContext::typedefDeclaration,
                new_style_parse_as_recovered,
            );
            token = type_param.parse_variables(token, self);
            next = self.next(token);
            // parseVariables rewrites so even though we checked in the if,
            // we might not have an equal here now.
            if !self.is_a(next, TokenType::EQ) && self.is_a(self.next(next), TokenType::EQ) {
                // Recovery after recovery: A token was inserted, but we'll skip it now
                // to get more in line with what we thought in the if before.
                next = self.next(next);
            }
            if self.is_a(next, TokenType::EQ) {
                equals = next;
                let mut type_ = compute_type(&mut self.tokens, equals, true, false, false);
                if !type_.is_function_type() {
                    // Recovery: In certain cases insert missing 'Function' and missing
                    // parens.
                    let skipped_type = type_.skip_type(&mut self.tokens, equals);
                    let after = self.next(skipped_type);
                    if self.is_a(after, TokenType::OPEN_PAREN)
                        && self.tokens.end_group(after) != NO_TOKEN
                        && self.is_a(
                            self.next(self.tokens.end_group(after)),
                            TokenType::SEMICOLON,
                        )
                    {
                        // Turn "<return type>? '(' <whatever> ')';"
                        // into "<return type>? Function '(' <whatever> ')';".
                        // Assume the type is meant as the return type.
                        let function_token = self
                            .rewriter()
                            .insert_synthetic_keyword(skipped_type, Keyword::FUNCTION);
                        self.report_recoverable_error(
                            function_token,
                            (diag::expectedButGot.with_arguments)("Function"),
                        );
                        type_ = compute_type(&mut self.tokens, equals, true, false, false);
                    } else if type_ == noType
                        && self.is_a(after, TokenType::LT)
                        && self.tokens.end_group(after) != NO_TOKEN
                    {
                        // Recover from this:
                        // typedef foo = <TypeParam>(...);
                        let end_group = self.tokens.end_group(after);
                        let mut recover = false;
                        if self.is_a(self.next(end_group), TokenType::SEMICOLON) {
                            // Missing parenthesis. Insert them.
                            // Turn "<whatever>;" in to "<whatever>();"
                            // Insert missing 'Function' below.
                            let message =
                                self.missing_parameter_message(MemberKind::FunctionTypeAlias);
                            self.report_recoverable_error(end_group, message);
                            self.rewriter().insert_parens(end_group, false);
                            recover = true;
                        } else {
                            let after_group = self.next(end_group);
                            if self.is_a(after_group, TokenType::OPEN_PAREN)
                                && self.tokens.end_group(after_group) != NO_TOKEN
                                && self.is_a(
                                    self.next(self.tokens.end_group(after_group)),
                                    TokenType::SEMICOLON,
                                )
                            {
                                // "<whatever>(<whatever>);". Insert missing 'Function' below.
                                recover = true;
                            }
                        }

                        if recover {
                            // Assume the '<' indicates type arguments to the function.
                            // Insert 'Function' before them.
                            let function_token = self
                                .rewriter()
                                .insert_synthetic_keyword(equals, Keyword::FUNCTION);
                            self.report_recoverable_error(
                                function_token,
                                (diag::expectedButGot.with_arguments)("Function"),
                            );
                            type_ = compute_type(&mut self.tokens, equals, true, false, false);
                        }
                    } else {
                        // E.g. "typedef j = foo;" -- don't attempt any recovery.
                    }
                }
                token = type_.ensure_type_or_void(equals, self);
            } else {
                // A rewrite caused the = to disappear
                token =
                    self.parse_formal_parameters_required_opt(next, MemberKind::FunctionTypeAlias);
            }
        } else {
            // Old style typedef, e.g. typedef int F<T>();
            token = type_info.parse_type(typedef_keyword, self);
            next = self.next(token);
            let mut is_identifier_recovered = false;
            if self.tokens.kind(next) != IDENTIFIER_TOKEN {
                let skipped = type_param.skip(&mut self.tokens, next);
                if self.is_a(self.next(skipped), TokenType::OPEN_PAREN) {
                    // Recovery: Not a valid identifier, but is used as such.
                    is_identifier_recovered = true;
                }
            }
            token = self.ensure_identifier_potentially_recovered(
                token,
                IdentifierContext::typedefDeclaration,
                is_identifier_recovered,
            );
            token = type_param.parse_variables(token, self);
            token = self.parse_formal_parameters_required_opt(token, MemberKind::FunctionTypeAlias);
        }
        token = self.ensure_semicolon(token);
        self.listener.end_typedef(
            &mut self.tokens,
            augment_token,
            typedef_keyword,
            equals,
            token,
        );
        token
    }

    /// Parse a mixin application starting from `with`. Assumes that the first
    /// type has already been parsed.
    pub fn parse_mixin_application_rest(&mut self, token: TokenId) -> TokenId {
        let mut with_keyword = self.next(token);
        if !self.is_a(with_keyword, kw::WITH) {
            // Recovery: Report an error and insert synthetic `with` clause.
            self.report_recoverable_error(
                with_keyword,
                (diag::expectedButGot.with_arguments)("with"),
            );
            with_keyword = self
                .rewriter()
                .insert_synthetic_keyword(token, Keyword::WITH);
            if !is_valid_non_record_type_reference(&self.tokens, self.next(with_keyword)) {
                self.rewriter().insert_synthetic_identifier(with_keyword);
            }
        }
        let token = self.parse_type_list(with_keyword);
        self.listener
            .handle_named_mixin_application_with_clause(&mut self.tokens, with_keyword);
        token
    }

    pub fn parse_class_with_clause_opt(&mut self, mut token: TokenId) -> TokenId {
        // <mixins> ::= with <typeNotVoidList>
        let with_keyword = self.next(token);
        if self.is_a(with_keyword, kw::WITH) {
            token = self.parse_type_list(with_keyword);
            self.listener
                .handle_class_with_clause(&mut self.tokens, with_keyword);
        } else {
            self.listener.handle_class_no_with_clause(&mut self.tokens);
        }
        token
    }

    pub fn parse_enum_with_clause_opt(&mut self, mut token: TokenId) -> TokenId {
        // <mixins> ::= with <typeNotVoidList>
        let with_keyword = self.next(token);
        if self.is_a(with_keyword, kw::WITH) {
            token = self.parse_type_list(with_keyword);
            self.listener
                .handle_enum_with_clause(&mut self.tokens, with_keyword);
        } else {
            self.listener.handle_enum_no_with_clause(&mut self.tokens);
        }
        token
    }

    /// Parse the formal parameters of a getter (which shouldn't have parameters)
    /// or function or method.
    pub fn parse_getter_or_formal_parameters(
        &mut self,
        mut token: TokenId,
        mut name: TokenId,
        is_getter: bool,
        kind: MemberKind,
    ) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_PAREN) {
            if is_getter {
                self.report_recoverable_error(next, diag::getterWithFormals);
            }
            token = self.parse_formal_parameters(token, kind);
        } else if is_getter {
            self.listener
                .handle_no_formal_parameters(&mut self.tokens, next, kind);
        } else {
            // Recovery
            if self.is_a(name, kw::OPERATOR) {
                let next = self.next(name);
                if self.tokens.is_operator(next) {
                    name = next;
                } else if self.is_unary_minus(next) {
                    name = self.next(next);
                }
            }
            let message = self.missing_parameter_message(kind);
            self.report_recoverable_error(name, message);
            token = self.rewriter().insert_parens(token, false);
            token = self.parse_formal_parameters_rest(token, kind);
        }
        token
    }

    pub fn parse_formal_parameters_opt(&mut self, mut token: TokenId, kind: MemberKind) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_PAREN) {
            token = self.parse_formal_parameters(token, kind);
        } else {
            self.listener
                .handle_no_formal_parameters(&mut self.tokens, next, kind);
        }
        token
    }

    pub fn skip_formal_parameters(&mut self, token: TokenId, kind: MemberKind) -> TokenId {
        let next = self.next(token);
        self.skip_formal_parameters_rest(next, kind)
    }

    pub fn skip_formal_parameters_rest(&mut self, token: TokenId, kind: MemberKind) -> TokenId {
        debug_assert!(self.is_a(token, TokenType::OPEN_PAREN));
        // TODO(ahe): Shouldn't this be `beginFormalParameters`?
        self.listener
            .begin_optional_formal_parameters(&mut self.tokens, token);
        let close_brace = self.tokens.end_group(token);
        debug_assert!(self.is_a(close_brace, TokenType::CLOSE_PAREN));
        self.listener
            .end_formal_parameters(&mut self.tokens, 0, token, close_brace, kind);
        close_brace
    }

    /// Parses the formal parameter list of a record type.
    pub fn parse_record_type(
        &mut self,
        start: TokenId,
        mut token: TokenId,
        is_question_mark_part_of_type: bool,
    ) -> TokenId {
        token = self.next(token);
        debug_assert!(self.is_a(token, TokenType::OPEN_PAREN));

        self.listener.begin_record_type(&mut self.tokens, start);

        let begin = token;

        // Parse the record type fields.
        let mut parameter_count = 0;
        let mut has_named_fields = false;
        let mut saw_comma = false;
        let mut illegal_trailing_comma = NO_TOKEN;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_PAREN) {
                token = next;
                break;
            } else if parameter_count == 0
                && self.is_a(next, TokenType::COMMA)
                && self.is_a(self.next(next), TokenType::CLOSE_PAREN)
            {
                illegal_trailing_comma = next;
                token = self.next(next);
                break;
            }
            parameter_count += 1;
            let value = self.sv(next);
            if value == Some("{") {
                has_named_fields = true;
                token = self.parse_record_type_named_fields(token);
                token = self.ensure_close_paren(token, begin);
                break;
            }
            token = self.parse_record_type_field(token, true);
            next = self.next(token);
            if !self.is_a(next, TokenType::COMMA) {
                let next = self.next(token);
                if self.is_a(next, TokenType::CLOSE_PAREN) {
                    token = next;
                } else {
                    // Recovery
                    let end_group = self.tokens.end_group(begin);
                    if self.tokens.is_synthetic(end_group) {
                        // Scanner has already reported a missing `)` error,
                        // but placed the `)` in the wrong location, so move it.
                        token = self.rewriter().move_synthetic(token, end_group);
                    } else if self.tokens.kind(next) == IDENTIFIER_TOKEN
                        && self.tokens.kind(self.next(next)) == IDENTIFIER_TOKEN
                    {
                        // Looks like a missing comma
                        let offset = self.tokens.char_offset(next);
                        let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                        token = self.rewrite_and_recover(
                            token,
                            (diag::expectedButGot.with_arguments)(","),
                            comma,
                        );
                        continue;
                    } else {
                        token = self.ensure_close_paren(token, begin);
                    }
                }
                break;
            } else {
                saw_comma = true;
            }
            token = next;
        }
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));

        if parameter_count == 0 && illegal_trailing_comma != NO_TOKEN {
            // Empty record type with a comma `(,)`.
            self.report_recoverable_error(
                illegal_trailing_comma,
                diag::recordTypeZeroFieldsButTrailingComma,
            );
        } else if parameter_count == 1 && !has_named_fields && !saw_comma {
            // Single non-named element without trailing comma.
            self.report_recoverable_error(token, diag::recordTypeOnePositionalFieldNoTrailingComma);
        }

        // Only consume the `?` if it is part of the type.
        let mut question_mark = self.next(token);
        if self.is_a(question_mark, TokenType::QUESTION) && is_question_mark_part_of_type {
            token = question_mark;
        } else {
            question_mark = NO_TOKEN;
        }
        self.listener.end_record_type(
            &mut self.tokens,
            start,
            question_mark,
            parameter_count,
            has_named_fields,
        );

        token
    }

    pub fn parse_record_type_field(
        &mut self,
        mut token: TokenId,
        identifier_is_optional: bool,
    ) -> TokenId {
        self.listener.begin_record_type_entry(&mut self.tokens);
        token = self.parse_metadata_star(token);
        token = compute_type(&mut self.tokens, token, true, false, false)
            .ensure_type_or_void(token, self);
        if self.tokens.is_identifier(self.next(token)) || !identifier_is_optional {
            token = self.ensure_identifier(token, IdentifierContext::recordFieldDeclaration);
        } else {
            // Name is optional and is not provided.
            let next_35 = self.tokens.next(token);
            self.listener.handle_no_name(&mut self.tokens, next_35);
        }
        self.listener.end_record_type_entry(&mut self.tokens);
        token
    }

    pub fn parse_record_type_named_fields(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let begin = token;
        debug_assert!(self.is_a(token, TokenType::OPEN_CURLY_BRACKET));
        self.listener
            .begin_record_type_named_fields(&mut self.tokens, begin);
        let mut parameter_count = 0;
        let mut next;
        loop {
            next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
                break;
            }
            token = self.parse_record_type_field(token, false);
            next = self.next(token);
            parameter_count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                if !self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
                    // Recovery
                    self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("}"));
                    // Scanner guarantees a closing bracket.
                    next = self.tokens.end_group(begin);
                }
                break;
            }
            token = next;
        }
        token = next;
        debug_assert!(self.is_a(token, TokenType::CLOSE_CURLY_BRACKET));
        if parameter_count == 0 {
            self.report_recoverable_error(token, diag::emptyRecordTypeNamedFieldsList);
        }
        self.listener
            .end_record_type_named_fields(&mut self.tokens, parameter_count, begin);
        token
    }

    pub fn parse_formal_parameters_required_opt(
        &mut self,
        token: TokenId,
        kind: MemberKind,
    ) -> TokenId {
        let mut next = self.next(token);
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            let message = self.missing_parameter_message(kind);
            self.report_recoverable_error(next, message);
            next = self.rewriter().insert_parens(token, false);
        }
        self.parse_formal_parameters_rest(next, kind)
    }

    /// Parses the formal parameter list of a function.
    ///
    /// If `kind == MemberKind.GeneralizedFunctionType`, then names may be
    /// omitted (except for named arguments). Otherwise, types may be omitted.
    pub fn parse_formal_parameters(&mut self, token: TokenId, kind: MemberKind) -> TokenId {
        let next = self.next(token);
        self.parse_formal_parameters_rest(next, kind)
    }

    /// Parses the formal parameter list of a function given that the left
    /// parenthesis is known to exist.
    pub fn parse_formal_parameters_rest(
        &mut self,
        mut token: TokenId,
        kind: MemberKind,
    ) -> TokenId {
        let begin = token;
        debug_assert!(self.is_a(token, TokenType::OPEN_PAREN));
        self.listener
            .begin_formal_parameters(&mut self.tokens, begin, kind);
        let mut parameter_count = 0;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_PAREN) {
                token = next;
                break;
            }
            parameter_count += 1;
            let value = self.sv(next);
            if value == Some("[") {
                token = self.parse_optional_positional_parameters(token, kind);
                token = self.ensure_close_paren(token, begin);
                break;
            } else if value == Some("{") {
                token = self.parse_optional_named_parameters(token, kind);
                token = self.ensure_close_paren(token, begin);
                break;
            } else if value == Some("[]") {
                // Recovery
                token = self.rewrite_square_brackets(token);
                token = self.parse_optional_positional_parameters(token, kind);
                token = self.ensure_close_paren(token, begin);
                break;
            }
            token =
                self.parse_formal_parameter(token, FormalParameterKind::requiredPositional, kind);
            next = self.next(token);
            if !self.is_a(next, TokenType::COMMA) {
                let next = self.next(token);
                if self.is_a(next, TokenType::CLOSE_PAREN) {
                    token = next;
                } else {
                    // Recovery
                    let end_group = self.tokens.end_group(begin);
                    if self.tokens.is_synthetic(end_group) {
                        // Scanner has already reported a missing `)` error,
                        // but placed the `)` in the wrong location, so move it.
                        token = self.rewriter().move_synthetic(token, end_group);
                    } else if self.tokens.kind(next) == IDENTIFIER_TOKEN
                        && self.tokens.kind(self.next(next)) == IDENTIFIER_TOKEN
                    {
                        // Looks like a missing comma
                        let offset = self.tokens.char_offset(next);
                        let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                        token = self.rewrite_and_recover(
                            token,
                            (diag::expectedButGot.with_arguments)(","),
                            comma,
                        );
                        continue;
                    } else {
                        token = self.ensure_close_paren(token, begin);
                    }
                }
                break;
            }
            token = next;
        }
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        self.listener
            .end_formal_parameters(&mut self.tokens, parameter_count, begin, token, kind);
        token
    }

    /// Return the message that should be produced when the formal parameters are
    /// missing.
    pub fn missing_parameter_message(&self, kind: MemberKind) -> MessageCode {
        match kind {
            MemberKind::FunctionTypeAlias => diag::missingTypedefParameters,
            MemberKind::StaticMethod | MemberKind::NonStaticMethod => diag::missingMethodParameters,
            MemberKind::TopLevelMethod
            | MemberKind::ExtensionNonStaticMethod
            | MemberKind::ExtensionStaticMethod
            | MemberKind::ExtensionTypeNonStaticMethod
            | MemberKind::ExtensionTypeStaticMethod
            | MemberKind::Catch
            | MemberKind::Factory
            | MemberKind::FunctionTypedParameter
            | MemberKind::GeneralizedFunctionType
            | MemberKind::Local
            | MemberKind::AnonymousMethod
            | MemberKind::NonStaticField
            | MemberKind::StaticField
            | MemberKind::TopLevelField
            | MemberKind::PrimaryConstructor => diag::missingFunctionParameters,
        }
    }

    /// ```text
    /// normalFormalParameter:
    ///   functionFormalParameter |
    ///   fieldFormalParameter |
    ///   simpleFormalParameter
    /// ;
    /// ```
    pub fn parse_formal_parameter(
        &mut self,
        mut token: TokenId,
        mut parameter_kind: FormalParameterKind,
        member_kind: MemberKind,
    ) -> TokenId {
        token = self.parse_metadata_star(token);

        let skipped_non_required_required = NO_TOKEN;
        let mut next = self.next(token);
        let start = next;

        let in_function_type = member_kind == MemberKind::GeneralizedFunctionType;

        let mut required_token = NO_TOKEN;
        let mut covariant_token = NO_TOKEN;
        let mut var_final_or_const = NO_TOKEN;
        if is_modifier(&self.tokens, next) {
            if self.is_a(next, kw::REQUIRED) {
                if parameter_kind == FormalParameterKind::optionalNamed {
                    parameter_kind = FormalParameterKind::requiredNamed;
                    token = next;
                    required_token = token;
                    next = self.next(token);
                }
            }

            if is_modifier(&self.tokens, next) {
                if self.is_a(next, kw::COVARIANT) {
                    match member_kind {
                        MemberKind::StaticMethod
                        | MemberKind::TopLevelMethod
                        | MemberKind::ExtensionNonStaticMethod
                        | MemberKind::ExtensionStaticMethod
                        | MemberKind::ExtensionTypeNonStaticMethod
                        | MemberKind::ExtensionTypeStaticMethod
                        | MemberKind::PrimaryConstructor => {}
                        MemberKind::Catch
                        | MemberKind::Factory
                        | MemberKind::FunctionTypeAlias
                        | MemberKind::FunctionTypedParameter
                        | MemberKind::GeneralizedFunctionType
                        | MemberKind::Local
                        | MemberKind::AnonymousMethod
                        | MemberKind::NonStaticMethod
                        | MemberKind::NonStaticField
                        | MemberKind::StaticField
                        | MemberKind::TopLevelField => {
                            token = next;
                            covariant_token = token;
                            next = self.next(token);
                        }
                    }
                }

                if is_modifier(&self.tokens, next) {
                    if !in_function_type {
                        if self.is_a(next, kw::VAR) || self.is_a(next, kw::FINAL) {
                            token = next;
                            var_final_or_const = token;
                            next = self.next(token);
                        }
                    }

                    if is_modifier(&self.tokens, next) {
                        // Recovery
                        let mut context = ModifierContext::new();
                        context.covariant_token = covariant_token;
                        context.required_token = required_token;
                        context.set_var_final_or_const(&self.tokens, var_final_or_const);

                        token = context.parse_formal_parameter_modifiers(
                            self,
                            token,
                            parameter_kind,
                            member_kind,
                        );
                        next = self.next(token);

                        covariant_token = context.covariant_token;
                        required_token = context.required_token;
                        var_final_or_const = context.var_final_or_const();
                    }
                }
            }
        }

        if required_token == NO_TOKEN {
            // `required` was used as a modifier in non-nnbd mode. An error has been
            // emitted. Still use it as a required token for the remainder in an
            // attempt to avoid cascading errors (and for passing to the listener).
            required_token = skipped_non_required_required;
        }

        self.listener.begin_formal_parameter(
            &mut self.tokens,
            start,
            member_kind,
            required_token,
            covariant_token,
            var_final_or_const,
        );

        // Type is required in a generalized function type, but optional otherwise.
        let before_type = token;
        let mut type_info = compute_type(&mut self.tokens, token, in_function_type, false, true);
        token = type_info.skip_type(&mut self.tokens, token);
        next = self.next(token);
        if type_info == noType
            && (self.is_a(next, TokenType::PERIOD)
                || (self.tokens.is_identifier(next)
                    && self.is_a(self.next(next), TokenType::PERIOD)))
        {
            // Recovery: Malformed type reference.
            type_info = compute_type(&mut self.tokens, before_type, true, false, false);
            token = type_info.skip_type(&mut self.tokens, before_type);
            next = self.next(token);
        }

        let mut this_keyword = NO_TOKEN;
        let mut super_keyword = NO_TOKEN;
        let mut period_after_this_or_super = NO_TOKEN;
        let mut name_context = IdentifierContext::formalParameterDeclaration;

        if !in_function_type && (self.is_a(next, kw::THIS) || self.is_a(next, kw::SUPER)) {
            let original_token = token;
            if self.is_a(next, kw::THIS) {
                token = next;
                this_keyword = token;
            } else {
                token = next;
                super_keyword = token;
            }
            next = self.next(token);
            if !self.is_a(next, TokenType::PERIOD) {
                if is_ok_next_value_in_formal_parameter(&self.tokens, next) {
                    // Recover by not parsing as 'this' --- an error will be given
                    // later that it's not an allowed identifier.
                    token = original_token;
                    next = self.next(token);
                    this_keyword = NO_TOKEN;
                    super_keyword = NO_TOKEN;
                } else {
                    // Recover from a missing period by inserting one.
                    let offset = self.tokens.char_offset(next);
                    let period = self.tokens.synthetic_token(TokenType::PERIOD, offset);
                    next = self.rewrite_and_recover(
                        token,
                        (diag::expectedButGot.with_arguments)("."),
                        period,
                    );
                    token = next;
                    period_after_this_or_super = token;
                    next = self.next(token);
                    name_context = IdentifierContext::fieldInitializer;
                }
            } else {
                token = next;
                period_after_this_or_super = token;
                next = self.next(token);
                name_context = IdentifierContext::fieldInitializer;
            }
        }

        if member_kind == MemberKind::PrimaryConstructor {
            if var_final_or_const != NO_TOKEN && !self.is_a(var_final_or_const, kw::CONST) {
                if this_keyword != NO_TOKEN {
                    self.report_recoverable_error(
                        this_keyword,
                        diag::initializingDeclaringParameter,
                    );
                } else if super_keyword != NO_TOKEN {
                    self.report_recoverable_error(
                        super_keyword,
                        diag::superInitializingDeclaringParameter,
                    );
                }
            }
        }

        if self.tokens.is_identifier(next) {
            token = next;
            next = self.next(token);
        }
        let mut before_inline_function_type = NO_TOKEN;
        let mut type_param = noTypeParamOrArg;
        if self.is_a(next, TokenType::LT) {
            type_param = compute_type_param_or_arg(&mut self.tokens, token, false, false);
            if type_param != noTypeParamOrArg {
                let closer = type_param.skip(&mut self.tokens, token);
                if self.is_a(self.next(closer), TokenType::OPEN_PAREN) {
                    if var_final_or_const != NO_TOKEN {
                        self.report_function_typed_parameter_var(member_kind, var_final_or_const);
                    }
                    before_inline_function_type = token;
                    token = self.tokens.end_group(self.next(closer));
                    next = self.next(token);
                }
            }
        } else if self.is_a(next, TokenType::OPEN_PAREN) {
            if var_final_or_const != NO_TOKEN {
                self.report_function_typed_parameter_var(member_kind, var_final_or_const);
            }
            before_inline_function_type = token;
            token = self.tokens.end_group(next);
            next = self.next(token);
        }

        let mut var_or_final = NO_TOKEN;
        if var_final_or_const != NO_TOKEN {
            if self.is_a(var_final_or_const, kw::VAR) {
                if self.is_primary_constructors_feature_enabled
                    && member_kind != MemberKind::PrimaryConstructor
                {
                    self.report_recoverable_error_with_token(
                        var_final_or_const,
                        diag::extraneousModifier,
                    );
                }
                var_or_final = var_final_or_const;
                if type_info != noType {
                    if member_kind != MemberKind::PrimaryConstructor {
                        self.report_recoverable_error(var_final_or_const, diag::typeAfterVar);
                    } else if !self.is_primary_constructors_feature_enabled {
                        self.report_experiment_not_enabled(
                            ExperimentalFlag::primaryConstructors,
                            var_or_final,
                            var_or_final,
                        );
                    }
                }
            } else if self.is_a(var_final_or_const, kw::FINAL) {
                if self.is_primary_constructors_feature_enabled
                    && member_kind != MemberKind::PrimaryConstructor
                {
                    self.report_recoverable_error_with_token(
                        var_final_or_const,
                        diag::extraneousModifier,
                    );
                }
                var_or_final = var_final_or_const;
            }
        }

        let mut end_inline_function_type = NO_TOKEN;
        if before_inline_function_type != NO_TOKEN {
            end_inline_function_type =
                type_param.parse_variables(before_inline_function_type, self);
            let next_34 = self.tokens.next(before_inline_function_type);
            self.listener
                .begin_function_typed_formal_parameter(&mut self.tokens, next_34);
            token = type_info.parse_type(before_type, self);
            end_inline_function_type = self.parse_formal_parameters_required_opt(
                end_inline_function_type,
                MemberKind::FunctionTypedParameter,
            );
            let mut question = NO_TOKEN;
            if self.is_a(self.next(end_inline_function_type), TokenType::QUESTION) {
                end_inline_function_type = self.next(end_inline_function_type);
                question = end_inline_function_type;
            }
            self.listener.end_function_typed_formal_parameter(
                &mut self.tokens,
                before_inline_function_type,
                question,
            );

            // Generalized function types don't allow inline function types.
            // The following isn't allowed:
            //    int Function(int bar(String x)).
            if in_function_type {
                let next = self.next(before_inline_function_type);
                self.report_recoverable_error(next, diag::invalidInlineFunctionType);
            }
        } else if in_function_type {
            token = type_info.ensure_type_or_void(before_type, self);
        } else {
            token = type_info.parse_type(before_type, self);
        }

        let name_token;
        if period_after_this_or_super != NO_TOKEN {
            token = period_after_this_or_super;
        }
        let is_named_parameter = parameter_kind.is_named();
        next = self.next(token);
        if in_function_type
            && !is_named_parameter
            && !self.tokens.is_keyword_or_identifier(next)
            && before_inline_function_type == NO_TOKEN
        {
            name_token = self.next(token);
            self.listener.handle_no_name(&mut self.tokens, name_token);
        } else {
            token = self.ensure_identifier(token, name_context);
            name_token = token;
        }
        if end_inline_function_type != NO_TOKEN {
            token = end_inline_function_type;
        }
        next = self.next(token);

        let value = self.sv(next);
        let mut initializer_start = NO_TOKEN;
        let mut initializer_end = NO_TOKEN;
        if value == Some("=") || value == Some(":") {
            let equal = next;
            initializer_start = self.next(equal);
            self.listener
                .begin_formal_parameter_default_value_expression(&mut self.tokens);
            token = self.parse_expression(equal);
            initializer_end = token;
            next = self.next(token);
            self.listener
                .end_formal_parameter_default_value_expression(&mut self.tokens);
            // TODO(danrubel): Consider removing the last parameter from the
            // handleValuedFormalParameter event... it appears to be unused.
            self.listener.handle_valued_formal_parameter(
                &mut self.tokens,
                equal,
                next,
                parameter_kind,
            );
            if parameter_kind.is_required_positional() {
                self.report_recoverable_error(equal, diag::requiredParameterWithDefault);
            } else if parameter_kind.is_optional_positional() && value == Some(":") {
                self.report_recoverable_error(equal, diag::positionalParameterWithEquals);
            } else if in_function_type
                || member_kind == MemberKind::FunctionTypeAlias
                || member_kind == MemberKind::FunctionTypedParameter
            {
                self.report_recoverable_error(equal, diag::functionTypeDefaultValue);
            }
        } else {
            self.listener
                .handle_formal_parameter_without_value(&mut self.tokens, next);
        }
        self.listener.end_formal_parameter(
            &mut self.tokens,
            var_or_final,
            this_keyword,
            super_keyword,
            period_after_this_or_super,
            name_token,
            initializer_start,
            initializer_end,
            parameter_kind,
            member_kind,
        );
        token
    }

    /// The error upstream reports, inline twice in [parseFormalParameter],
    /// for `var` or `final` before a function-typed parameter.
    fn report_function_typed_parameter_var(
        &mut self,
        member_kind: MemberKind,
        var_final_or_const: TokenId,
    ) {
        if member_kind != MemberKind::PrimaryConstructor {
            self.report_recoverable_error(var_final_or_const, diag::functionTypedParameterVar);
        } else if !self.is_primary_constructors_feature_enabled {
            self.report_experiment_not_enabled(
                ExperimentalFlag::primaryConstructors,
                var_final_or_const,
                var_final_or_const,
            );
        }
    }

    /// ```text
    /// defaultFormalParameter:
    ///   normalFormalParameter ('=' expression)?
    /// ;
    /// ```
    pub fn parse_optional_positional_parameters(
        &mut self,
        token: TokenId,
        kind: MemberKind,
    ) -> TokenId {
        self.parse_optional_parameters(
            token,
            kind,
            TokenType::OPEN_SQUARE_BRACKET,
            TokenType::CLOSE_SQUARE_BRACKET,
            FormalParameterKind::optionalPositional,
            "]",
            diag::emptyOptionalParameterList,
        )
    }

    /// ```text
    /// defaultNamedParameter:
    ///   normalFormalParameter ('=' expression)? |
    ///   normalFormalParameter (':' expression)?
    /// ;
    /// ```
    pub fn parse_optional_named_parameters(&mut self, token: TokenId, kind: MemberKind) -> TokenId {
        self.parse_optional_parameters(
            token,
            kind,
            TokenType::OPEN_CURLY_BRACKET,
            TokenType::CLOSE_CURLY_BRACKET,
            FormalParameterKind::optionalNamed,
            "}",
            diag::emptyNamedParameterList,
        )
    }

    /// The body upstream's [parseOptionalPositionalParameters] and
    /// [parseOptionalNamedParameters] both repeat.
    fn parse_optional_parameters(
        &mut self,
        mut token: TokenId,
        kind: MemberKind,
        open: &TokenType,
        close: &TokenType,
        parameter_kind: FormalParameterKind,
        close_lexeme: &str,
        empty_message: MessageCode,
    ) -> TokenId {
        token = self.next(token);
        let begin = token;
        debug_assert!(self.is_a(token, open));
        self.listener
            .begin_optional_formal_parameters(&mut self.tokens, begin);
        let mut parameter_count = 0;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, close) {
                break;
            }
            token = self.parse_formal_parameter(token, parameter_kind, kind);
            next = self.next(token);
            parameter_count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                if !self.is_a(next, close) {
                    // Recovery
                    self.report_recoverable_error(
                        next,
                        (diag::expectedButGot.with_arguments)(close_lexeme),
                    );
                    // Scanner guarantees a closing bracket.
                    next = self.tokens.end_group(begin);
                    while self.next(token) != next {
                        token = self.next(token);
                    }
                }
                break;
            }
            token = next;
        }
        if parameter_count == 0 {
            let offset = self.tokens.char_offset(self.next(token));
            let index = self.tokens.add_string(Vec::new());
            let identifier = self.tokens.synthetic_string_token(
                TokenType::IDENTIFIER,
                crate::scanner::token::Lexeme::Owned(index),
                offset,
                Some(0),
            );
            self.rewrite_and_recover(token, empty_message, identifier);
            token = self.parse_formal_parameter(token, parameter_kind, kind);
            parameter_count += 1;
        }
        token = self.next(token);
        debug_assert!(self.is_a(token, close));
        self.listener.end_optional_formal_parameters(
            &mut self.tokens,
            parameter_count,
            begin,
            token,
            kind,
        );
        token
    }

    /// ```text
    /// qualified:
    ///   identifier qualifiedRest*
    /// ;
    /// ```
    pub fn parse_qualified(
        &mut self,
        mut token: TokenId,
        context: &'static IdentifierContext,
        continuation_context: &'static IdentifierContext,
    ) -> TokenId {
        token = self.ensure_identifier(token, context);
        while self.is_a(self.next(token), TokenType::PERIOD) {
            token = self.parse_qualified_rest(token, continuation_context);
        }
        token
    }

    /// ```text
    /// qualifiedRestOpt:
    ///   qualifiedRest?
    /// ;
    /// ```
    pub fn parse_qualified_rest_opt(
        &mut self,
        token: TokenId,
        continuation_context: &'static IdentifierContext,
    ) -> TokenId {
        if self.is_a(self.next(token), TokenType::PERIOD) {
            self.parse_qualified_rest(token, continuation_context)
        } else {
            token
        }
    }

    /// ```text
    /// qualifiedRest:
    ///   '.' identifier
    /// ;
    /// ```
    pub fn parse_qualified_rest(
        &mut self,
        token: TokenId,
        context: &'static IdentifierContext,
    ) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.is_a(token, TokenType::PERIOD));
        self.try_rewrite_new_to_identifier(token, context);
        let period = token;
        let token = self.ensure_identifier(token, context);
        self.listener.handle_qualified(&mut self.tokens, period);
        token
    }

    pub fn skip_block(&mut self, token: TokenId) -> TokenId {
        // The scanner ensures that `{` always has a closing `}`.
        let block = self.ensure_block(token, None);
        self.tokens.end_group(block)
    }

    /// ```text
    /// enumType:
    ///   metadata 'enum' id typeParameters? mixins? interfaces? '{'
    ///      enumEntry (',' enumEntry)* (',')? (';'
    ///      (metadata classMemberDefinition)*
    ///      )?
    ///   '}'
    ///
    /// enumEntry:
    ///     metadata id argumentPart?
    ///   | metadata id typeArguments? '.' id arguments
    /// ```
    pub fn parse_enum(
        &mut self,
        begin_token: TokenId,
        augment_token: TokenId,
        enum_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(enum_keyword, kw::ENUM));
        self.listener
            .begin_enum_declaration_prelude(&mut self.tokens, enum_keyword);
        let mut token = enum_keyword;
        let mut const_token = NO_TOKEN;
        if self.is_a(self.next(token), kw::CONST) {
            token = self.next(token);
            const_token = token;
        }
        token = self.ensure_identifier(token, IdentifierContext::enumDeclaration);
        let name_token = token;
        let name = self.tokens.lexeme_string(name_token);
        token = compute_type_param_or_arg(&mut self.tokens, token, true, true)
            .parse_variables(token, self);
        self.listener.begin_enum_declaration(
            &mut self.tokens,
            begin_token,
            augment_token,
            enum_keyword,
            name_token,
        );
        token = self.parse_primary_constructor_opt(DeclarationKind::Enum, token, const_token, true);
        token = self.parse_enum_header_opt(token, enum_keyword);
        let mut left_brace = self.next(token);
        let mut element_count = 0;
        let mut member_count = 0;
        if self.is_a(left_brace, TokenType::SEMICOLON) {
            if !self.is_primary_constructors_feature_enabled {
                self.report_experiment_not_enabled(
                    ExperimentalFlag::primaryConstructors,
                    left_brace,
                    left_brace,
                );
            }
            self.listener.handle_enum_header(
                &mut self.tokens,
                augment_token,
                enum_keyword,
                left_brace,
            );
            self.listener
                .handle_no_enum_body(&mut self.tokens, left_brace);
            token = left_brace;
        } else if self.is_a(left_brace, TokenType::OPEN_CURLY_BRACKET) {
            self.listener.handle_enum_header(
                &mut self.tokens,
                augment_token,
                enum_keyword,
                left_brace,
            );
            self.listener.begin_enum_body(&mut self.tokens, left_brace);
            token = left_brace;
            loop {
                let mut next = self.next(token);
                if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                    || self.is_a(next, TokenType::SEMICOLON)
                {
                    token = next;
                    break;
                }
                token = self.parse_enum_element(token);
                next = self.next(token);
                element_count += 1;
                if self.is_a(next, TokenType::COMMA) {
                    token = next;
                } else if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                    || self.is_a(next, TokenType::SEMICOLON)
                {
                    token = next;
                    break;
                } else {
                    // Recovery
                    let end_group = self.tokens.end_group(left_brace);
                    if self.tokens.is_synthetic(end_group) {
                        // The scanner did not place the synthetic '}' correctly.
                        token = self.rewriter().move_synthetic(token, end_group);
                        break;
                    } else if self.tokens.is_identifier(next) {
                        // If the next token is an identifier, assume a missing comma.
                        // TODO(danrubel): Consider improved recovery for missing `}`
                        // both here and when the scanner inserts a synthetic `}`
                        // for situations such as `enum Letter {a, b   Letter e;`.
                        self.report_recoverable_error(
                            next,
                            (diag::expectedButGot.with_arguments)(","),
                        );
                    } else {
                        // Otherwise assume a missing `}` and exit the loop
                        self.report_recoverable_error(
                            next,
                            (diag::expectedButGot.with_arguments)("}"),
                        );
                        token = self.tokens.end_group(left_brace);
                        break;
                    }
                }
            }
            self.listener
                .handle_enum_elements(&mut self.tokens, token, element_count);
            if self.is_a(token, TokenType::SEMICOLON) {
                while self.not_eof_or_type(TokenType::CLOSE_CURLY_BRACKET, self.next(token)) {
                    token = self.parse_class_or_mixin_or_extension_or_enum_member_impl(
                        token,
                        DeclarationKind::Enum,
                        Some(&name),
                    );
                    member_count += 1;
                }
                token = self.next(token);
                debug_assert!(
                    self.tokens.is_eof(token) || self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
                );
            }
            self.listener
                .end_enum_body(&mut self.tokens, left_brace, token);
        } else {
            // TODO(johnniwinther): Avoid parsing the `enum` body in this case.
            left_brace = self.ensure_block(token, Some(BlockKind::enumDeclaration));
            self.listener.handle_enum_header(
                &mut self.tokens,
                augment_token,
                enum_keyword,
                left_brace,
            );
            self.listener.begin_enum_body(&mut self.tokens, left_brace);
            self.listener
                .handle_enum_elements(&mut self.tokens, token, element_count);
            token = self.tokens.end_group(left_brace);
            self.listener
                .end_enum_body(&mut self.tokens, left_brace, token);
        }
        debug_assert!(
            self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
                || self.is_a(token, TokenType::SEMICOLON)
        );
        self.listener.end_enum_declaration(
            &mut self.tokens,
            begin_token,
            enum_keyword,
            left_brace,
            member_count,
            token,
        );
        token
    }

    pub fn parse_enum_header_opt(&mut self, mut token: TokenId, _enum_keyword: TokenId) -> TokenId {
        let look_for_next: &[&TokenType] =
            &[TokenType::OPEN_CURLY_BRACKET, kw::WITH, kw::IMPLEMENTS];

        if !is_any_of(&self.tokens, self.next(token), look_for_next) {
            // Recovery: Possible unexpected tokens before any clauses.
            let skip_token = self.recovery_small_look_ahead_skip_tokens(token, look_for_next);
            if skip_token != NO_TOKEN {
                token = skip_token;
            }
        }

        let before_with = token;
        token = self.parse_enum_with_clause_opt(token);

        let is_one_of_following_values = |t: &TokenStore, token: TokenId| {
            t.is_a(token, TokenType::OPEN_CURLY_BRACKET) || t.is_a(token, kw::IMPLEMENTS)
        };
        while !is_one_of_following_values(&self.tokens, self.next(token)) {
            // Recovery: Skip unexpected tokens and more with clauses.
            // Note that if we find a "with" we've seen one already (otherwise the
            // parseEnumWithClauseOpt call above would have found this 'with').
            let mut skip_token = self.recovery_enum_with(
                token,
                (diag::multipleClauses.with_arguments)("enum", "with"),
            );
            if skip_token == NO_TOKEN {
                skip_token = self.recovery_small_look_ahead_skip_tokens(token, look_for_next);
            }
            if skip_token != NO_TOKEN {
                // Skipped tokens.
                token = skip_token;
            } else {
                break;
            }
        }

        token = self.parse_class_or_mixin_or_enum_implements_opt(token);

        let mut has_with_clauses: Option<bool> = None;
        while !self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) {
            if has_with_clauses.is_none() {
                has_with_clauses = Some(self.is_a(self.next(before_with), kw::WITH));
            }

            // Recovery: Skip unexpected tokens and more with/implements clauses.
            let message = if has_with_clauses == Some(true) {
                (diag::multipleClauses.with_arguments)("enum", "with")
            } else {
                (diag::outOfOrderClauses.with_arguments)("with", "implements")
            };
            let mut skip_token = self.recovery_enum_with(token, message);
            if skip_token != NO_TOKEN {
                has_with_clauses = Some(true);
            }
            if skip_token == NO_TOKEN {
                skip_token = self.recovery_enum_implements(
                    token,
                    (diag::multipleClauses.with_arguments)("enum", "implements"),
                );
            }
            if skip_token == NO_TOKEN {
                skip_token = self.recovery_small_look_ahead_skip_tokens(token, look_for_next);
            }
            if skip_token != NO_TOKEN {
                // Skipped tokens.
                token = skip_token;
            } else {
                break;
            }
        }

        token
    }

    pub fn recovery_enum_with(&mut self, mut token: TokenId, message: Message) -> TokenId {
        if self.is_a(self.next(token), kw::WITH) {
            let next = self.next(token);
            self.report_recoverable_error(next, message);
            let original_listener =
                std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
            token = self.parse_enum_with_clause_opt(token);
            self.listener = original_listener;
            return token;
        }
        NO_TOKEN
    }

    pub fn recovery_enum_implements(&mut self, mut token: TokenId, message: Message) -> TokenId {
        if self.is_a(self.next(token), kw::IMPLEMENTS) {
            let next = self.next(token);
            self.report_recoverable_error(next, message);
            let original_listener =
                std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
            token = self.parse_class_or_mixin_or_enum_implements_opt(token);
            self.listener = original_listener;
            return token;
        }
        NO_TOKEN
    }

    /// Allow a small lookahead (currently up to 3 tokens) trying to find any in
    /// [lookFor].
    ///
    /// If any wanted token is found an error is issued about unexpected tokens,
    /// and the last skipped token is returned.
    /// Otherwise null is returned.
    pub fn recovery_small_look_ahead_skip_tokens(
        &mut self,
        token: TokenId,
        look_for: &[&TokenType],
    ) -> TokenId {
        // Recovery: Allow a small lookahead for '{'. E.g. the user might be in
        // the middle of writing 'with' or 'implements'.
        let mut skip_token = self.next(token);
        let mut found_wanted = false;

        if looks_like_start_of_next_top_level_declaration(&self.tokens, skip_token) {
            return NO_TOKEN;
        }

        let mut skipped = 0;
        while skipped < 3 {
            skipped += 1;
            if is_any_of(&self.tokens, self.next(skip_token), look_for) {
                found_wanted = true;
                break;
            }

            skip_token = self.next(skip_token);
            if looks_like_start_of_next_top_level_declaration(&self.tokens, skip_token) {
                return NO_TOKEN;
            }
        }

        if found_wanted {
            // Give error and skip the tokens.
            if skipped == 1 {
                let message = (diag::unexpectedToken.with_arguments)(&self.tokens, skip_token);
                self.report_recoverable_error(skip_token, message);
            } else {
                let next = self.next(token);
                self.report_recoverable_error_with_end(next, skip_token, diag::unexpectedTokens);
            }
            return skip_token;
        }

        NO_TOKEN
    }

    pub fn parse_enum_element(&mut self, mut token: TokenId) -> TokenId {
        let begin_token = token;
        token = self.parse_metadata_star(token);

        let mut augment_token = NO_TOKEN;
        if self.is_a(self.next(token), kw::AUGMENT) {
            augment_token = self.next(token);
            token = self.next(token);
        }

        token = self.ensure_identifier(token, IdentifierContext::enumValueDeclaration);
        let mut has_type_arguments_or_dot = false;
        {
            // This is almost a verbatim copy of [parseConstructorReference] inserted
            // to provide better recovery.
            let start = token;
            let next_33 = self.tokens.next(token);
            self.listener
                .handle_no_type_name_in_constructor_reference(&mut self.tokens, next_33);
            self.listener
                .begin_constructor_reference(&mut self.tokens, start);
            let type_arg = compute_type_param_or_arg(&mut self.tokens, token, false, false);
            if type_arg != noTypeParamOrArg {
                has_type_arguments_or_dot = true;
            }
            token = type_arg.parse_arguments(token, self);
            let mut period = NO_TOKEN;
            if self.is_a(self.next(token), TokenType::PERIOD) {
                has_type_arguments_or_dot = true;
                period = self.next(token);
                token = self.ensure_identifier(
                    period,
                    IdentifierContext::constructorReferenceContinuationAfterTypeArguments,
                );
            } else {
                self.listener
                    .handle_no_constructor_reference_continuation_after_type_arguments(
                        &mut self.tokens,
                        token,
                    );
            }
            self.listener.end_constructor_reference(
                &mut self.tokens,
                start,
                period,
                token,
                ConstructorReferenceContext::Const,
            );
        }
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_PAREN) || has_type_arguments_or_dot {
            token = self.parse_constructor_invocation_arguments(token);
        } else {
            self.listener.handle_no_arguments(&mut self.tokens, token);
        }
        self.listener
            .handle_enum_element(&mut self.tokens, begin_token, augment_token);
        token
    }

    pub fn parse_class_or_named_mixin_application(
        &mut self,
        begin_token: TokenId,
        abstract_token: TokenId,
        sealed_token: TokenId,
        base_token: TokenId,
        interface_token: TokenId,
        final_token: TokenId,
        augment_token: TokenId,
        mixin_token: TokenId,
        class_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(class_keyword, kw::CLASS));
        self.listener
            .begin_class_or_mixin_or_named_mixin_application_prelude(&mut self.tokens, begin_token);
        let mut token = class_keyword;
        let mut const_token = NO_TOKEN;
        if self.is_a(self.next(token), kw::CONST) {
            token = self.next(token);
            const_token = token;
        }
        let name =
            self.ensure_identifier(token, IdentifierContext::classOrMixinOrExtensionDeclaration);
        token = compute_type_param_or_arg(&mut self.tokens, name, true, true)
            .parse_variables(name, self);
        if abstract_token != NO_TOKEN {
            if sealed_token != NO_TOKEN {
                self.report_recoverable_error(sealed_token, diag::abstractSealedClass);
            } else if final_token != NO_TOKEN {
                if base_token != NO_TOKEN {
                    self.report_recoverable_error_with_end(
                        final_token,
                        base_token,
                        diag::abstractFinalBaseClass,
                    );
                } else if interface_token != NO_TOKEN {
                    self.report_recoverable_error_with_end(
                        final_token,
                        interface_token,
                        diag::abstractFinalInterfaceClass,
                    );
                }
            }
        }
        if self.is_a(self.next(token), TokenType::EQ) {
            if const_token != NO_TOKEN {
                self.report_recoverable_error(const_token, diag::constWithoutPrimaryConstructor);
            }
            if augment_token != NO_TOKEN {
                self.report_recoverable_error(
                    augment_token,
                    diag::mixinApplicationClassAugmentation,
                );
            }
            self.listener.begin_named_mixin_application(
                &mut self.tokens,
                begin_token,
                abstract_token,
                sealed_token,
                base_token,
                interface_token,
                final_token,
                augment_token,
                mixin_token,
                name,
            );
            self.parse_named_mixin_application(token, begin_token, class_keyword)
        } else {
            self.listener.begin_class_declaration(
                &mut self.tokens,
                begin_token,
                abstract_token,
                sealed_token,
                base_token,
                interface_token,
                final_token,
                augment_token,
                mixin_token,
                name,
            );
            let class_name = self.tokens.lexeme_string(name);
            self.parse_class(token, begin_token, class_keyword, const_token, &class_name)
        }
    }

    pub fn parse_named_mixin_application(
        &mut self,
        mut token: TokenId,
        begin: TokenId,
        class_keyword: TokenId,
    ) -> TokenId {
        token = self.next(token);
        let equals = token;
        debug_assert!(self.is_a(equals, TokenType::EQ));
        token = compute_type(&mut self.tokens, token, true, false, false)
            .ensure_type_not_void(token, self);
        token = self.parse_mixin_application_rest(token);
        let mut implements_keyword = NO_TOKEN;
        if self.is_a(self.next(token), kw::IMPLEMENTS) {
            implements_keyword = self.next(token);
            token = self.parse_type_list(implements_keyword);
        }
        token = self.ensure_semicolon(token);
        self.listener.end_named_mixin_application(
            &mut self.tokens,
            begin,
            class_keyword,
            equals,
            implements_keyword,
            token,
        );
        token
    }

    /// Parse the portion of a class declaration (not a mixin application) that
    /// follows the end of the type parameters.
    pub fn parse_class(
        &mut self,
        mut token: TokenId,
        begin_token: TokenId,
        class_keyword: TokenId,
        const_token: TokenId,
        class_name: &str,
    ) -> TokenId {
        token =
            self.parse_primary_constructor_opt(DeclarationKind::Class, token, const_token, true);
        let header_start = token;
        token = self.parse_class_header_opt(token, begin_token, class_keyword);
        if self.is_a(self.next(token), TokenType::SEMICOLON) {
            token = self.next(token);
            let semicolon_token = token;
            if !self.is_primary_constructors_feature_enabled {
                self.report_experiment_not_enabled(
                    ExperimentalFlag::primaryConstructors,
                    semicolon_token,
                    semicolon_token,
                );
            }
            self.listener
                .handle_no_class_body(&mut self.tokens, semicolon_token);
        } else {
            if !self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) {
                // Recovery
                token = self.parse_class_header_recovery(header_start, begin_token, class_keyword);
                self.ensure_block(token, Some(BlockKind::classDeclaration));
            }
            token = self.parse_class_or_mixin_or_extension_body(
                token,
                DeclarationKind::Class,
                Some(class_name),
            );
        }
        self.listener
            .end_class_declaration(&mut self.tokens, begin_token, token);
        token
    }

    pub fn parse_class_header_opt(
        &mut self,
        mut token: TokenId,
        begin: TokenId,
        class_keyword: TokenId,
    ) -> TokenId {
        token = self.parse_class_extends_opt(token, DeclarationHeaderKind::Class);
        token = self.parse_class_with_clause_opt(token);
        token = self.parse_class_or_mixin_or_enum_implements_opt(token);
        let mut native_token = NO_TOKEN;
        if self.is_a(self.next(token), kw::NATIVE) {
            native_token = self.next(token);
            token = self.parse_native_clause(token);
        }
        self.listener
            .handle_class_header(&mut self.tokens, begin, class_keyword, native_token);
        token
    }

    /// Recover given out-of-order clauses in a class header.
    pub fn parse_class_header_recovery(
        &mut self,
        token: TokenId,
        begin: TokenId,
        class_keyword: TokenId,
    ) -> TokenId {
        self.parse_declaration_header_recovery_internal(
            token,
            begin,
            class_keyword,
            DeclarationHeaderKind::Class,
        )
    }

    /// Recover given out-of-order clauses in an extension type header.
    pub fn parse_extension_type_header_recovery(
        &mut self,
        token: TokenId,
        extension_keyword: TokenId,
    ) -> TokenId {
        self.parse_declaration_header_recovery_internal(
            token,
            extension_keyword,
            extension_keyword,
            DeclarationHeaderKind::ExtensionType,
        )
    }

    pub fn parse_declaration_header_recovery_internal(
        &mut self,
        mut token: TokenId,
        begin: TokenId,
        declaration_keyword: TokenId,
        kind: DeclarationHeaderKind,
    ) -> TokenId {
        let primary_listener = self.install_recovery_listener(Recovery::DeclarationHeader(
            DeclarationHeaderRecoveryListener::default(),
        ));

        // Reparse to determine which clauses have already been parsed
        // but intercept the events so they are not sent to the primary listener.
        match kind {
            DeclarationHeaderKind::Class => {
                token = self.parse_class_header_opt(token, begin, declaration_keyword)
            }
            DeclarationHeaderKind::ExtensionType => {
                token = self.parse_class_or_mixin_or_enum_implements_opt(token)
            }
        }
        let state = self.declaration_header_recovery().clone();
        let mut has_extends = state.extends_keyword != NO_TOKEN;
        let mut has_implements = state.implements_keyword != NO_TOKEN;
        let mut has_with = state.with_keyword != NO_TOKEN;

        // Update the recovery listener to forward subsequent events
        // to the primary listener.
        self.recovery_listener().listener = Some(primary_listener);

        let mut start;
        loop {
            start = token;

            // Check for extraneous token in the middle of a declaration header.
            token = self.skip_unexpected_token_opt(token, &["extends", "with", "implements", "{"]);

            // During recovery, clauses are parsed in the same order
            // and generate the same events as in the parseClassHeader method above.
            self.declaration_header_recovery().clear();

            let next = self.next(token);
            if self.tokens.is_keyword_or_identifier(next) && {
                let lexeme = self.tokens.lexeme_string(next);
                lexeme == "extend" || lexeme == "on"
            } {
                self.report_recoverable_error(
                    next,
                    (diag::expectedInstead.with_arguments)("extends"),
                );
                token = self.parse_class_extends_seen_extends_clause(next, token, kind);
            } else {
                token = self.parse_class_extends_opt(token, kind);
            }

            let extends_keyword = self.declaration_header_recovery().extends_keyword;
            if extends_keyword != NO_TOKEN {
                match kind {
                    DeclarationHeaderKind::Class => {
                        if has_extends {
                            self.report_recoverable_error(extends_keyword, diag::multipleExtends);
                        } else {
                            if has_with {
                                self.report_recoverable_error(
                                    extends_keyword,
                                    diag::withBeforeExtends,
                                );
                            } else if has_implements {
                                self.report_recoverable_error(
                                    extends_keyword,
                                    diag::implementsBeforeExtends,
                                );
                            }
                            has_extends = true;
                        }
                    }
                    DeclarationHeaderKind::ExtensionType => {
                        self.report_recoverable_error(extends_keyword, diag::extensionTypeExtends);
                    }
                }
            }

            token = self.parse_class_with_clause_opt(token);

            let with_keyword = self.declaration_header_recovery().with_keyword;
            if with_keyword != NO_TOKEN {
                match kind {
                    DeclarationHeaderKind::Class => {
                        if has_with {
                            self.report_recoverable_error(with_keyword, diag::multipleWith);
                        } else {
                            if has_implements {
                                self.report_recoverable_error(
                                    with_keyword,
                                    diag::implementsBeforeWith,
                                );
                            }
                            has_with = true;
                        }
                    }
                    DeclarationHeaderKind::ExtensionType => {
                        self.report_recoverable_error(with_keyword, diag::extensionTypeWith);
                    }
                }
            }

            token = self.parse_class_or_mixin_or_enum_implements_opt(token);

            let implements_keyword = self.declaration_header_recovery().implements_keyword;
            if implements_keyword != NO_TOKEN {
                if has_implements {
                    self.report_recoverable_error(implements_keyword, diag::multipleImplements);
                } else {
                    has_implements = true;
                }
            }

            self.listener
                .handle_recover_declaration_header(&mut self.tokens, kind);

            // Exit if a declaration body is detected, or if no progress has been made
            if self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) || start == token {
                break;
            }
        }

        let primary = self.recovery_listener().listener.take().unwrap();
        self.listener = primary;
        token
    }

    /// ```text
    /// classExtendsClause:
    ///   'extends' type
    /// ;
    /// ```
    pub fn parse_class_extends_opt(
        &mut self,
        mut token: TokenId,
        kind: DeclarationHeaderKind,
    ) -> TokenId {
        // extends <typeNotVoid>
        let next = self.next(token);
        if self.is_a(next, kw::EXTENDS) {
            token = self.parse_class_extends_seen_extends_clause(next, token, kind);
        } else {
            self.listener.handle_no_type(&mut self.tokens, token);
            self.listener
                .handle_class_extends(&mut self.tokens, NO_TOKEN, 1);
        }
        token
    }

    pub fn parse_class_extends_seen_extends_clause(
        &mut self,
        extends_keyword: TokenId,
        mut token: TokenId,
        kind: DeclarationHeaderKind,
    ) -> TokenId {
        let mut next = extends_keyword;
        token = compute_type(&mut self.tokens, next, true, false, false)
            .ensure_type_not_void(next, self);
        let mut count = 1;

        // Error recovery: extends <typeNotVoid>, <typeNotVoid> [...]
        if self.is_a(self.next(token), TokenType::COMMA) {
            match kind {
                DeclarationHeaderKind::Class => {
                    let next = self.next(token);
                    self.report_recoverable_error(next, diag::multipleExtends);
                }
                DeclarationHeaderKind::ExtensionType => {
                    // This is reported by the [DeclarationHeaderRecoveryListener].
                }
            }

            while self.is_a(self.next(token), TokenType::COMMA) {
                next = self.next(token);
                token = compute_type(&mut self.tokens, next, true, false, false)
                    .ensure_type_not_void(next, self);
                count += 1;
            }
        }

        self.listener
            .handle_class_extends(&mut self.tokens, extends_keyword, count);
        token
    }

    /// ```text
    /// implementsClause:
    ///   'implements' typeName (',' typeName)*
    /// ;
    /// ```
    pub fn parse_class_or_mixin_or_enum_implements_opt(&mut self, mut token: TokenId) -> TokenId {
        let mut implements_keyword = NO_TOKEN;
        let mut interfaces_count = 0;
        if self.is_a(self.next(token), kw::IMPLEMENTS) {
            implements_keyword = self.next(token);
            loop {
                let next = self.next(token);
                token = compute_type(&mut self.tokens, next, true, false, false)
                    .ensure_type_not_void(next, self);
                interfaces_count += 1;
                if !self.is_a(self.next(token), TokenType::COMMA) {
                    break;
                }
            }
        }
        self.listener
            .handle_implements(&mut self.tokens, implements_keyword, interfaces_count);
        token
    }

    /// Parse a mixin declaration.
    ///
    /// ```text
    /// mixinDeclaration:
    ///   metadata? 'augment'? 'base'? 'mixin' [SimpleIdentifier]
    ///        [TypeParameterList]? [OnClause]? [ImplementsClause]?
    ///        '{' [ClassMember]* '}'
    /// ;
    /// ```
    pub fn parse_mixin(
        &mut self,
        begin_token: TokenId,
        augment_token: TokenId,
        base_token: TokenId,
        mixin_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(mixin_keyword, kw::MIXIN));
        self.listener
            .begin_class_or_mixin_or_named_mixin_application_prelude(
                &mut self.tokens,
                mixin_keyword,
            );
        let mut token = mixin_keyword;
        let mut const_keyword = NO_TOKEN;
        if self.is_a(self.next(token), kw::CONST) {
            token = self.next(token);
            const_keyword = token;
        }
        let name =
            self.ensure_identifier(token, IdentifierContext::classOrMixinOrExtensionDeclaration);
        let header_start = compute_type_param_or_arg(&mut self.tokens, name, true, true)
            .parse_variables(name, self);
        self.listener.begin_mixin_declaration(
            &mut self.tokens,
            begin_token,
            augment_token,
            base_token,
            mixin_keyword,
            name,
        );
        token = self.parse_mixin_header_opt(
            header_start,
            const_keyword,
            mixin_keyword,
            augment_token != NO_TOKEN,
        );
        if self.is_a(self.next(token), TokenType::SEMICOLON) {
            token = self.next(token);
            let semicolon_token = token;
            if !self.is_primary_constructors_feature_enabled {
                self.report_experiment_not_enabled(
                    ExperimentalFlag::primaryConstructors,
                    semicolon_token,
                    semicolon_token,
                );
            }
            self.listener
                .handle_no_mixin_body(&mut self.tokens, semicolon_token);
        } else {
            if !self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) {
                token = self.parse_mixin_header_recovery(
                    token,
                    mixin_keyword,
                    header_start,
                    augment_token != NO_TOKEN,
                );
                self.ensure_block(token, Some(BlockKind::mixinDeclaration));
            }
            let name_lexeme = self.tokens.lexeme_string(name);
            token = self.parse_class_or_mixin_or_extension_body(
                token,
                DeclarationKind::Mixin,
                Some(&name_lexeme),
            );
        }
        self.listener
            .end_mixin_declaration(&mut self.tokens, begin_token, token);
        token
    }

    pub fn parse_mixin_header_opt(
        &mut self,
        mut token: TokenId,
        const_keyword: TokenId,
        mixin_keyword: TokenId,
        is_augmentation: bool,
    ) -> TokenId {
        token =
            self.parse_primary_constructor_opt(DeclarationKind::Mixin, token, const_keyword, true);
        token = self.parse_mixin_on_opt(token, is_augmentation);
        token = self.parse_class_or_mixin_or_enum_implements_opt(token);
        self.listener
            .handle_mixin_header(&mut self.tokens, mixin_keyword);
        token
    }

    pub fn parse_mixin_header_recovery(
        &mut self,
        mut token: TokenId,
        mixin_keyword: TokenId,
        header_start: TokenId,
        is_augmentation: bool,
    ) -> TokenId {
        let primary_listener = self.install_recovery_listener(Recovery::MixinHeader(
            MixinHeaderRecoveryListener::default(),
        ));

        // Reparse to determine which clauses have already been parsed
        // but intercept the events so they are not sent to the primary listener.
        token = self.parse_mixin_header_opt(header_start, NO_TOKEN, mixin_keyword, false);
        let state = self.mixin_header_recovery().clone();
        let mut has_on = state.on_keyword != NO_TOKEN;
        let mut has_implements = state.implements_keyword != NO_TOKEN;

        // Update the recovery listener to forward subsequent events
        // to the primary listener.
        self.recovery_listener().listener = Some(primary_listener);

        let mut start;
        loop {
            start = token;

            // Check for extraneous token in the middle of a class header.
            token = self.skip_unexpected_token_opt(token, &["on", "implements", "{"]);

            // During recovery, clauses are parsed in the same order and
            // generate the same events as in the parseMixinHeaderOpt method above.
            self.mixin_header_recovery().clear();

            let next = self.next(token);
            if self.tokens.is_keyword_or_identifier(next) && {
                let lexeme = self.tokens.lexeme_string(next);
                lexeme == "extend" || lexeme == "extends"
            } {
                self.report_recoverable_error(next, (diag::expectedInstead.with_arguments)("on"));
                token = self.parse_mixin_on(token);
            } else {
                token = self.parse_mixin_on_opt(token, is_augmentation);
            }

            let on_keyword = self.mixin_header_recovery().on_keyword;
            if on_keyword != NO_TOKEN {
                if has_on {
                    self.report_recoverable_error(on_keyword, diag::multipleOnClauses);
                } else {
                    if has_implements {
                        self.report_recoverable_error(on_keyword, diag::implementsBeforeOn);
                    }
                    has_on = true;
                }
            }

            token = self.parse_class_or_mixin_or_enum_implements_opt(token);

            let implements_keyword = self.mixin_header_recovery().implements_keyword;
            if implements_keyword != NO_TOKEN {
                if has_implements {
                    self.report_recoverable_error(implements_keyword, diag::multipleImplements);
                } else {
                    has_implements = true;
                }
            }

            if self.is_a(self.next(token), kw::WITH) {
                let with_keyword = self.next(token);
                self.report_recoverable_error(with_keyword, diag::mixinWithClause);
                token = self.parse_type_list(with_keyword);
                self.listener
                    .handle_mixin_with_clause(&mut self.tokens, with_keyword);
            }

            self.listener.handle_recover_mixin_header(&mut self.tokens);

            // Exit if a mixin body is detected, or if no progress has been made
            if self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) || start == token {
                break;
            }
        }

        let primary = self.recovery_listener().listener.take().unwrap();
        self.listener = primary;
        token
    }

    /// ```text
    /// onClause:
    ///   'on' typeName (',' typeName)*
    /// ;
    /// ```
    pub fn parse_mixin_on_opt(&mut self, token: TokenId, is_augmentation: bool) -> TokenId {
        let on_keyword = self.next(token);
        if !self.is_a(on_keyword, kw::ON) {
            self.listener.handle_mixin_on(&mut self.tokens, NO_TOKEN, 0);
            return token;
        }
        if is_augmentation {
            self.report_recoverable_error(on_keyword, diag::mixinAugmentationHasOnClause);
        }
        self.parse_mixin_on(token)
    }

    pub fn parse_mixin_on(&mut self, mut token: TokenId) -> TokenId {
        let on_keyword = self.next(token);
        // During recovery, the [onKeyword] can be "extend" or "extends"
        debug_assert!(
            self.is_a(on_keyword, kw::ON)
                || self.is_a(on_keyword, kw::EXTENDS)
                || self.tokens.lexeme_equals(on_keyword, "extend")
        );
        let mut type_count = 0;
        loop {
            let next = self.next(token);
            token = compute_type(&mut self.tokens, next, true, false, false)
                .ensure_type_not_void(next, self);
            type_count += 1;
            if !self.is_a(self.next(token), TokenType::COMMA) {
                break;
            }
        }
        self.listener
            .handle_mixin_on(&mut self.tokens, on_keyword, type_count);
        token
    }

    /// ```text
    /// 'extension' <identifier>? <typeParameters>?
    ///     (('.' <identifier>)? <implementsClause>) | ('on' <type> '?'?)
    //   `{'
    //     <memberDeclaration>*
    //   `}'
    /// ```
    pub fn parse_extension(
        &mut self,
        begin_token: TokenId,
        augment_token: TokenId,
        extension_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(extension_keyword, kw::EXTENSION));
        let token = extension_keyword;
        self.listener
            .begin_extension_declaration_prelude(&mut self.tokens, extension_keyword);
        let next = self.next(token);
        if self.tokens.is_identifier(next) && self.tokens.lexeme_equals(next, "type") {
            let type_keyword = next;
            self.parse_extension_type_declaration(
                begin_token,
                next,
                augment_token,
                extension_keyword,
                type_keyword,
            )
        } else {
            self.parse_extension_declaration(begin_token, token, augment_token, extension_keyword)
        }
    }

    pub fn parse_extension_declaration(
        &mut self,
        begin_token: TokenId,
        mut token: TokenId,
        augment_token: TokenId,
        extension_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(extension_keyword, kw::EXTENSION));
        let mut const_keyword = NO_TOKEN;
        if self.is_a(self.next(token), kw::CONST) {
            token = self.next(token);
            const_keyword = token;
        }
        let mut name = self.next(token);
        if self.tokens.is_identifier(name) && !self.is_a(name, kw::ON) {
            token = name;
            if self.tokens.type_(name).is_built_in() {
                self.report_recoverable_error_with_token(
                    token,
                    diag::builtInIdentifierInDeclaration,
                );
            }
        } else {
            if augment_token != NO_TOKEN {
                self.report_recoverable_error(
                    augment_token,
                    diag::extensionAugmentationWithoutName,
                );
            }
            name = NO_TOKEN;
        }
        token = compute_type_param_or_arg(&mut self.tokens, token, true, false)
            .parse_variables(token, self);
        self.listener.begin_extension_declaration(
            &mut self.tokens,
            augment_token,
            extension_keyword,
            name,
        );
        token = self.parse_primary_constructor_opt(
            DeclarationKind::Extension,
            token,
            const_keyword,
            true,
        );
        let mut on_keyword = self.next(token);
        if augment_token != NO_TOKEN {
            if !self.is_a(on_keyword, kw::ON) {
                on_keyword = NO_TOKEN;
            } else {
                self.report_recoverable_error(on_keyword, diag::extensionAugmentationHasOnClause);
                let type_info = compute_type(&mut self.tokens, on_keyword, true, false, false);
                token = type_info.ensure_type_or_void(on_keyword, self);
            }
        } else {
            if !self.is_a(on_keyword, kw::ON) {
                // Recovery
                if self.is_a(on_keyword, kw::EXTENDS)
                    || self.is_a(on_keyword, kw::IMPLEMENTS)
                    || self.is_a(on_keyword, kw::WITH)
                {
                    self.report_recoverable_error(
                        on_keyword,
                        (diag::expectedInstead.with_arguments)("on"),
                    );
                } else {
                    self.report_recoverable_error(
                        token,
                        (diag::expectedAfterButGot.with_arguments)("on"),
                    );
                    on_keyword = self.rewriter().insert_synthetic_keyword(token, Keyword::ON);
                }
            }
            let type_info = compute_type(&mut self.tokens, on_keyword, true, false, false);
            token = type_info.ensure_type_or_void(on_keyword, self);
        }
        if self.is_a(self.next(token), TokenType::SEMICOLON) {
            token = self.next(token);
            let semicolon_token = token;
            if !self.is_primary_constructors_feature_enabled {
                self.report_experiment_not_enabled(
                    ExperimentalFlag::primaryConstructors,
                    semicolon_token,
                    semicolon_token,
                );
            }
            self.listener
                .handle_no_extension_body(&mut self.tokens, semicolon_token);
        } else {
            if !self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) {
                // Recovery
                let mut next = self.next(token);
                while !self.tokens.is_eof(next) {
                    if self.is_a(next, TokenType::COMMA)
                        || self.is_a(next, kw::EXTENDS)
                        || self.is_a(next, kw::IMPLEMENTS)
                        || self.is_a(next, kw::ON)
                        || self.is_a(next, kw::WITH)
                    {
                        // Report an error and skip `,` or specific keyword
                        // optionally followed by an identifier
                        self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                        token = next;
                        next = self.next(token);
                        if self.tokens.is_identifier(next) {
                            token = next;
                            next = self.next(token);
                        }
                    } else {
                        break;
                    }
                }
                self.ensure_block(token, Some(BlockKind::extensionDeclaration));
            }
            let name_lexeme = if name == NO_TOKEN {
                None
            } else {
                Some(self.tokens.lexeme_string(name))
            };
            token = self.parse_class_or_mixin_or_extension_body(
                token,
                DeclarationKind::Extension,
                name_lexeme.as_deref(),
            );
        }
        self.listener.end_extension_declaration(
            &mut self.tokens,
            begin_token,
            extension_keyword,
            on_keyword,
            token,
        );
        token
    }

    pub fn parse_primary_constructor_opt(
        &mut self,
        kind: DeclarationKind,
        mut token: TokenId,
        const_keyword: TokenId,
        allow_extension_type_representation: bool,
    ) -> TokenId {
        debug_assert!(
            allow_extension_type_representation || kind == DeclarationKind::ExtensionType
        );
        if self.is_a(self.next(token), TokenType::OPEN_PAREN)
            || self.is_a(self.next(token), TokenType::PERIOD)
        {
            let begin_primary_constructor = self.next(token);
            let const_or_begin = if const_keyword != NO_TOKEN {
                const_keyword
            } else {
                begin_primary_constructor
            };
            match kind {
                DeclarationKind::TopLevel => {
                    debug_assert!(false, "Unexpected primary constructor kind: {kind}");
                }
                DeclarationKind::Mixin => {
                    if self.is_primary_constructors_feature_enabled {
                        self.report_recoverable_error(
                            const_or_begin,
                            diag::mixinPrimaryConstructor,
                        );
                    } else {
                        let message =
                            (diag::unexpectedToken.with_arguments)(&self.tokens, const_or_begin);
                        self.report_recoverable_error(const_or_begin, message);
                    }
                }
                DeclarationKind::Extension => {
                    if self.is_primary_constructors_feature_enabled {
                        self.report_recoverable_error(
                            const_or_begin,
                            diag::extensionPrimaryConstructor,
                        );
                    } else {
                        let message =
                            (diag::unexpectedToken.with_arguments)(&self.tokens, const_or_begin);
                        self.report_recoverable_error(const_or_begin, message);
                    }
                }
                DeclarationKind::Class => {}
                DeclarationKind::ExtensionType => {
                    if !allow_extension_type_representation {
                        self.report_recoverable_error(
                            const_or_begin,
                            diag::extensionTypeAugmentationSpecifiesRepresentationField,
                        );
                    }
                }
                DeclarationKind::Enum => {}
            }

            self.listener
                .begin_primary_constructor(&mut self.tokens, begin_primary_constructor);
            let has_constructor_name = self.is_a(begin_primary_constructor, TokenType::PERIOD);
            if has_constructor_name {
                token = self.ensure_identifier(
                    begin_primary_constructor,
                    IdentifierContext::primaryConstructorDeclaration,
                );
            }
            if self.is_a(self.next(token), TokenType::OPEN_PAREN) {
                token = self.parse_formal_parameters(token, MemberKind::PrimaryConstructor);
            } else {
                let report_missing_parameters = match kind {
                    DeclarationKind::Class | DeclarationKind::Enum => true,
                    DeclarationKind::ExtensionType => allow_extension_type_representation,
                    _ => false,
                };
                if report_missing_parameters {
                    self.report_recoverable_error(token, diag::missingPrimaryConstructorParameters);
                }
                self.listener.handle_no_formal_parameters(
                    &mut self.tokens,
                    token,
                    MemberKind::PrimaryConstructor,
                );
            }
            self.listener.end_primary_constructor(
                &mut self.tokens,
                kind,
                begin_primary_constructor,
                token,
                const_keyword,
                has_constructor_name,
            );
        } else {
            if kind == DeclarationKind::ExtensionType && allow_extension_type_representation {
                self.report_recoverable_error(token, diag::missingPrimaryConstructor);
            } else if const_keyword != NO_TOKEN {
                if self.is_primary_constructors_feature_enabled {
                    match kind {
                        DeclarationKind::TopLevel => {
                            debug_assert!(false, "Unexpected primary constructor kind: {kind}");
                        }
                        DeclarationKind::Mixin => {
                            self.report_recoverable_error(
                                const_keyword,
                                diag::mixinPrimaryConstructor,
                            );
                        }
                        DeclarationKind::Extension => {
                            self.report_recoverable_error(
                                const_keyword,
                                diag::extensionPrimaryConstructor,
                            );
                        }
                        DeclarationKind::Class
                        | DeclarationKind::ExtensionType
                        | DeclarationKind::Enum => {
                            self.report_recoverable_error(
                                const_keyword,
                                diag::constWithoutPrimaryConstructor,
                            );
                        }
                    }
                } else {
                    let message =
                        (diag::unexpectedToken.with_arguments)(&self.tokens, const_keyword);
                    self.report_recoverable_error(const_keyword, message);
                }
            }
            self.listener.handle_no_primary_constructor(
                &mut self.tokens,
                kind,
                token,
                const_keyword,
            );
        }
        token
    }

    pub fn parse_primary_constructor_body(
        &mut self,
        mut token: TokenId,
        augment_token: TokenId,
    ) -> TokenId {
        let begin_token = if augment_token != NO_TOKEN {
            augment_token
        } else {
            token
        };
        let this_token = token;
        self.listener
            .begin_primary_constructor_body(&mut self.tokens, token, augment_token);
        let mut before_initializers = token;
        token = self.parse_initializers_opt(before_initializers);
        if token == before_initializers {
            before_initializers = NO_TOKEN;
        }
        let next = self.next(token);
        if self.is_a(next, kw::ASYNC) || self.is_a(next, kw::SYNC) {
            let mut modifier = self.tokens.lexeme_string(next);
            if self.is_a(self.next(next), TokenType::STAR) {
                modifier.push('*');
            }
            self.report_recoverable_error(
                next,
                (diag::primaryConstructorBodyWithModifier.with_arguments)(&modifier),
            );
        }
        token = self.parse_async_modifier_opt(token);
        let allow_abstract = self.in_plain_sync();
        token = self.parse_function_body(token, false, allow_abstract);
        let after_initializers = if before_initializers == NO_TOKEN {
            NO_TOKEN
        } else {
            self.next(before_initializers)
        };
        self.listener.end_primary_constructor_body(
            &mut self.tokens,
            begin_token,
            this_token,
            after_initializers,
            token,
        );
        token
    }

    /// ```text
    /// 'extension' 'type' 'const'? <identifier> <typeParameters>?
    ///     <representationDeclaration> <interfaces>?
    ///   `{'
    ///     <memberDeclaration>*
    ///   `}'
    /// ```
    pub fn parse_extension_type_declaration(
        &mut self,
        begin_token: TokenId,
        mut token: TokenId,
        augment_token: TokenId,
        extension_keyword: TokenId,
        type_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(
            self.tokens.is_identifier(token) && self.tokens.lexeme_equals(token, "type")
        );
        let mut const_keyword = NO_TOKEN;
        if self.is_a(self.next(token), kw::CONST) {
            token = self.next(token);
            const_keyword = token;
        }
        let name;
        if self.tokens.is_identifier(self.next(token)) {
            name = self.next(token);
            if self.tokens.type_(name).is_built_in() {
                self.report_recoverable_error_with_token(
                    token,
                    diag::builtInIdentifierInDeclaration,
                );
            }
        } else {
            name = IdentifierContext::classOrMixinOrExtensionDeclaration
                .ensure_identifier(token, self);
        }
        token = name;
        token = compute_type_param_or_arg(&mut self.tokens, token, true, false)
            .parse_variables(token, self);
        self.listener.begin_extension_type_declaration(
            &mut self.tokens,
            augment_token,
            extension_keyword,
            name,
        );
        token = self.parse_primary_constructor_opt(
            DeclarationKind::ExtensionType,
            token,
            const_keyword,
            augment_token == NO_TOKEN,
        );
        let start = token;
        token = self.parse_class_or_mixin_or_enum_implements_opt(token);
        if self.is_a(self.next(token), TokenType::SEMICOLON) {
            token = self.next(token);
            let semicolon_token = token;
            if !self.is_primary_constructors_feature_enabled {
                self.report_experiment_not_enabled(
                    ExperimentalFlag::primaryConstructors,
                    semicolon_token,
                    semicolon_token,
                );
            }
            self.listener
                .handle_no_extension_type_body(&mut self.tokens, semicolon_token);
        } else {
            if !self.is_a(self.next(token), TokenType::OPEN_CURLY_BRACKET) {
                token = self.parse_extension_type_header_recovery(start, extension_keyword);
                self.ensure_block(token, Some(BlockKind::extensionTypeDeclaration));
            }
            let name_lexeme = self.tokens.lexeme_string(name);
            token = self.parse_class_or_mixin_or_extension_body(
                token,
                DeclarationKind::ExtensionType,
                Some(&name_lexeme),
            );
        }
        self.listener.end_extension_type_declaration(
            &mut self.tokens,
            begin_token,
            augment_token,
            extension_keyword,
            type_keyword,
            token,
        );
        token
    }

    pub fn parse_string_part(&mut self, token: TokenId) -> TokenId {
        let mut next = self.next(token);
        if self.tokens.kind(next) != STRING_TOKEN {
            self.report_recoverable_error_with_token(next, diag::expectedString);
            let offset = self.tokens.char_offset(next);
            let index = self.tokens.add_string(Vec::new());
            let string = self.tokens.synthetic_string_token(
                TokenType::STRING,
                crate::scanner::token::Lexeme::Owned(index),
                offset,
                None,
            );
            next = self.rewriter().insert_token(token, string);
        }
        self.listener.handle_string_part(&mut self.tokens, next);
        next
    }

    /// Insert a synthetic identifier after the given [token] and create an error
    /// message based on the given [context]. Return the synthetic identifier.
    pub fn insert_synthetic_identifier(
        &mut self,
        token: TokenId,
        context: &'static IdentifierContext,
        message: Option<Message>,
        message_on_token: TokenId,
    ) -> TokenId {
        let next = self.next(token);
        let message = match message {
            Some(message) => message,
            None => (context.recovery_template.with_arguments)(&self.tokens, next),
        };
        let at = if message_on_token != NO_TOKEN {
            message_on_token
        } else {
            next
        };
        self.report_recoverable_error(at, message);
        self.rewriter().insert_synthetic_identifier(token)
    }

    /// Parse a simple identifier at the given [token], and return the identifier
    /// that was parsed.
    ///
    /// If the token is not an identifier, or is not appropriate for use as an
    /// identifier in the given [context], create a synthetic identifier, report
    /// an error, and return the synthetic identifier.
    pub fn ensure_identifier(
        &mut self,
        token: TokenId,
        context: &'static IdentifierContext,
    ) -> TokenId {
        self.try_rewrite_new_to_identifier(token, context);
        let mut identifier = self.next(token);
        if self.tokens.kind(identifier) != IDENTIFIER_TOKEN {
            identifier = context.ensure_identifier(token, self);
            debug_assert!(self.tokens.is_keyword_or_identifier(identifier));
        }
        self.listener
            .handle_identifier(&mut self.tokens, identifier, context);
        identifier
    }

    /// Returns `true` if [token] is either an identifier or a `new` token.  This
    /// can be used to match identifiers in contexts where a constructor name can
    /// appear, since `new` can be used to refer to the unnamed constructor.
    fn is_new_or_identifier(&self, token: TokenId) -> bool {
        if self.tokens.is_identifier(token) {
            return true;
        }
        if self.tokens.kind(token) == KEYWORD_TOKEN {
            let value = self.sv(token);
            if value == Some("new") {
                return true;
            }
        }
        false
    }

    /// If the token following [token] is a `new` keyword, and [context] allows
    /// `new` to be used as an identifier, then rewrite it as an identifier.
    #[inline]
    fn try_rewrite_new_to_identifier(
        &mut self,
        token: TokenId,
        context: &'static IdentifierContext,
    ) {
        if !context.allows_new_as_identifier() {
            return;
        }
        self.try_rewrite_new_to_identifier_impl(token);
    }

    fn try_rewrite_new_to_identifier_impl(&mut self, token: TokenId) {
        let identifier = self.next(token);
        if self.tokens.kind(identifier) != KEYWORD_TOKEN {
            return;
        }
        let value = self.sv(identifier);
        if value != Some("new") {
            return;
        }
        // `new` after `.` is treated as an identifier so that it can represent
        // the unnamed constructor.
        let lexeme = self.tokens.lexeme(identifier);
        let offset = self.tokens.char_offset(identifier);
        let string = self
            .tokens
            .string_token(TokenType::IDENTIFIER, lexeme, offset);
        let replacement_token = self.rewriter().replace_token_following(token, string);
        self.listener
            .handle_new_as_identifier(&mut self.tokens, replacement_token);
    }

    /// Parse a simple identifier at the given [token], and return the identifier
    /// that was parsed.
    ///
    /// If the token is not an identifier, or is not appropriate for use as an
    /// identifier in the given [context], create a synthetic identifier, report
    /// an error, and return the synthetic identifier.
    /// [isRecovered] is passed to [context] which - in some cases - allows a
    /// keyword to be used as an identifier.
    pub fn ensure_identifier_potentially_recovered(
        &mut self,
        token: TokenId,
        context: &'static IdentifierContext,
        is_recovered: bool,
    ) -> TokenId {
        let mut identifier = self.next(token);
        if self.tokens.kind(identifier) != IDENTIFIER_TOKEN {
            identifier = context.ensure_identifier_potentially_recovered(token, self, is_recovered);
            debug_assert!(self.tokens.is_keyword_or_identifier(identifier));
        }
        self.listener
            .handle_identifier(&mut self.tokens, identifier, context);
        identifier
    }

    pub fn not_eof_or_type(&self, type_: &TokenType, token: TokenId) -> bool {
        !self.is_a(token, TokenType::EOF) && !self.is_a(token, type_)
    }

    pub fn parse_type_variables_opt(&mut self, token: TokenId) -> TokenId {
        compute_type_param_or_arg(&mut self.tokens, token, true, false).parse_variables(token, self)
    }

    /// Parse a top level field or function.
    ///
    /// This method is only invoked from outside the parser. As a result, this
    /// method takes the next token to be consumed rather than the last consumed
    /// token and returns the token after the last consumed token rather than the
    /// last consumed token.
    pub fn parse_top_level_member(&mut self, token: TokenId) -> TokenId {
        let previous = self.synthetic_previous_token(token);
        let token = self.parse_metadata_star(previous);
        let token = self.parse_top_level_member_impl(token);
        self.next(token)
    }

    pub fn parse_top_level_member_impl(&mut self, mut token: TokenId) -> TokenId {
        let before_start = token;
        let mut next = self.next(token);
        self.listener.begin_top_level_member(&mut self.tokens, next);

        let skipped_non_late_late = NO_TOKEN;

        let mut abstract_token = NO_TOKEN;
        let mut external_token = NO_TOKEN;
        let mut augment_token = NO_TOKEN;
        let mut late_token = NO_TOKEN;
        let mut var_final_or_const = NO_TOKEN;

        if is_modifier(&self.tokens, next) {
            if self.is_a(next, kw::EXTERNAL) {
                token = next;
                external_token = token;
                next = self.next(token);
            } else if self.is_a(next, kw::AUGMENT) {
                token = next;
                augment_token = token;
                next = self.next(token);
            }
            if is_modifier(&self.tokens, next) {
                if self.is_a(next, kw::FINAL)
                    || self.is_a(next, kw::VAR)
                    || self.is_a(next, kw::CONST)
                {
                    token = next;
                    var_final_or_const = token;
                    next = self.next(token);
                } else if self.is_a(next, kw::LATE) {
                    token = next;
                    late_token = token;
                    next = self.next(token);
                    if is_modifier(&self.tokens, next) && self.is_a(next, kw::FINAL) {
                        token = next;
                        var_final_or_const = token;
                        next = self.next(token);
                    }
                }
                if is_modifier(&self.tokens, next) {
                    // Recovery
                    if var_final_or_const != NO_TOKEN
                        && (self.is_a(next, kw::FINAL)
                            || self.is_a(next, kw::VAR)
                            || self.is_a(next, kw::CONST))
                    {
                        // If another `var`, `final`, or `const` then fall through
                        // to parse that as part of the next top level declaration.
                    } else {
                        let mut context = ModifierContext::new();
                        context.external_token = external_token;
                        context.augment_token = augment_token;
                        context.late_token = late_token;
                        context.set_var_final_or_const(&self.tokens, var_final_or_const);

                        token = context.parse_top_level_member_modifiers(self, token);
                        next = self.next(token);

                        abstract_token = context.abstract_token;
                        augment_token = context.augment_token;
                        external_token = context.external_token;
                        late_token = context.late_token;
                        var_final_or_const = context.var_final_or_const();
                    }
                }
            }
        }
        if late_token == NO_TOKEN {
            // `late` was used as a modifier in non-nnbd mode. An error has been
            // emitted. Still use it as a late token for the remainder in an attempt
            // to avoid cascading errors (and for passing to the listener).
            late_token = skipped_non_late_late;
        }

        let before_type = token;
        if var_final_or_const != NO_TOKEN && !self.is_a(var_final_or_const, kw::CONST) {
            let after_outer_pattern = self.skip_outer_pattern(before_type);
            if after_outer_pattern != NO_TOKEN
                && self.is_a(self.next(after_outer_pattern), TokenType::EQ)
            {
                let start = self.next(before_type);
                self.report_recoverable_error_with_end(
                    start,
                    after_outer_pattern,
                    diag::patternVariableDeclarationOutsideFunctionOrMethod,
                );
                let synthetic_name = self.rewriter().insert_synthetic_identifier(before_type);
                let after = self.next(after_outer_pattern);
                self.rewriter().drop_range(synthetic_name, after);
                return self.parse_fields(
                    before_start,
                    abstract_token,
                    augment_token,
                    external_token,
                    NO_TOKEN,
                    NO_TOKEN,
                    late_token,
                    var_final_or_const,
                    before_type,
                    noType,
                    synthetic_name,
                    DeclarationKind::TopLevel,
                    None,
                    true,
                );
            }
        }

        let mut type_info = compute_type(&mut self.tokens, token, false, true, false);
        token = type_info.skip_type(&mut self.tokens, token);
        next = self.next(token);

        let mut get_or_set = NO_TOKEN;
        let mut value = self.sv(next);
        if value == Some("get") || value == Some("set") {
            if self.tokens.is_identifier(self.next(next)) {
                token = next;
                get_or_set = token;
                next = self.next(token);
            }
        }

        let mut name_is_recovered = false;
        if type_info == noType
            && var_final_or_const == NO_TOKEN
            && self.is_reserved_keyword(self.next(next))
            && self.indicates_method_or_field(self.next(self.next(next)))
        {
            // Recovery: Use the reserved keyword despite that not being legal.
            type_info = compute_type(&mut self.tokens, token, true, true, false);
            token = type_info.skip_type(&mut self.tokens, token);
            next = self.next(token);
            name_is_recovered = true;
        }

        if self.tokens.type_(next) != TokenType::IDENTIFIER {
            value = self.sv(next);
            if value == Some("factory") || value == Some("operator") {
                // `factory` and `operator` can be used as an identifier.
                value = self.sv(self.next(next));
                if get_or_set == NO_TOKEN
                    && value != Some("(")
                    && value != Some("{")
                    && value != Some("<")
                    && value != Some("=>")
                    && value != Some("=")
                    && value != Some(";")
                    && value != Some(",")
                {
                    // Recovery
                    value = self.sv(next);
                    if value == Some("factory") {
                        self.report_recoverable_error(next, diag::factoryTopLevelDeclaration);
                    } else {
                        self.report_recoverable_error(next, diag::topLevelOperator);
                        if self.tokens.is_operator(self.next(next)) {
                            token = next;
                            next = self.next(token);
                            if self.is_a(self.next(next), TokenType::OPEN_PAREN) {
                                // This appears to be a top level operator declaration, which
                                // is invalid. Reset the 'operator' token to an identifier
                                let name = format!(
                                    "#synthetic_identifier_{}",
                                    self.tokens.char_offset(next)
                                );
                                self.rewriter()
                                    .insert_synthetic_identifier_with_value(next, &name);
                            }
                        }
                    }
                    // Ignore any preceding modifiers and just report the unexpected token
                    self.listener
                        .handle_invalid_top_level_declaration(&mut self.tokens, next);
                    return next;
                }
                // Fall through and continue parsing
            } else if !self.tokens.is_identifier(next) {
                // Recovery
                if self.tokens.is_keyword(next) {
                    // Fall through to parse the keyword as the identifier.
                    // ensureIdentifier will report the error.
                } else if token == before_start {
                    // Ensure we make progress.
                    return self.parse_invalid_top_level_declaration(token);
                } else {
                    // Looks like a declaration missing an identifier.
                    // Insert synthetic identifier and fall through.
                    self.insert_synthetic_identifier(
                        token,
                        IdentifierContext::methodDeclaration,
                        None,
                        NO_TOKEN,
                    );
                    next = self.next(token);
                }
            }
        }
        // At this point, `token` is beforeName.

        // Recovery: Inserted ! after method name.
        if self.is_a(self.next(next), TokenType::BANG) {
            next = self.next(next);
        }

        next = self.next(next);
        value = self.sv(next);
        if get_or_set != NO_TOKEN
            || value == Some("(")
            || value == Some("{")
            || value == Some("<")
            || value == Some(".")
            || value == Some("=>")
        {
            if var_final_or_const != NO_TOKEN {
                if self.is_a(var_final_or_const, kw::VAR) {
                    self.report_recoverable_error(var_final_or_const, diag::varReturnType);
                } else {
                    self.report_recoverable_error_with_token(
                        var_final_or_const,
                        diag::extraneousModifier,
                    );
                }
            } else if late_token != NO_TOKEN {
                self.report_recoverable_error_with_token(late_token, diag::extraneousModifier);
            }
            if abstract_token != NO_TOKEN {
                self.report_recoverable_error_with_token(abstract_token, diag::extraneousModifier);
            }
            let name = self.next(token);
            return self.parse_top_level_method(
                before_start,
                augment_token,
                external_token,
                before_type,
                type_info,
                get_or_set,
                name,
                name_is_recovered,
            );
        }

        if get_or_set != NO_TOKEN {
            self.report_recoverable_error_with_token(get_or_set, diag::extraneousModifier);
        }
        if !self.is_augmentations_feature_enabled && abstract_token != NO_TOKEN {
            self.report_recoverable_error_with_token(abstract_token, diag::extraneousModifier);
        }
        let name = self.next(token);
        self.parse_fields(
            before_start,
            abstract_token,
            augment_token,
            external_token,
            NO_TOKEN,
            NO_TOKEN,
            late_token,
            var_final_or_const,
            before_type,
            type_info,
            name,
            DeclarationKind::TopLevel,
            None,
            name_is_recovered,
        )
    }

    pub fn parse_fields(
        &mut self,
        before_start: TokenId,
        abstract_token: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        mut covariant_token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        before_type: TokenId,
        type_info: TypeInfo,
        mut name: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
        name_is_recovered: bool,
    ) -> TokenId {
        self.listener.begin_fields(
            &mut self.tokens,
            kind,
            augment_token,
            abstract_token,
            external_token,
            static_token,
            covariant_token,
            late_token,
            var_final_or_const,
            before_start,
        );

        // Covariant affects only the setter and final fields do not have a setter,
        // unless it's a late field (dartbug.com/40805).
        // Field that are covariant late final with initializers are checked further
        // down.
        if covariant_token != NO_TOKEN && late_token == NO_TOKEN {
            if var_final_or_const != NO_TOKEN && self.is_a(var_final_or_const, kw::FINAL) {
                self.report_recoverable_error(covariant_token, diag::finalAndCovariant);
                covariant_token = NO_TOKEN;
            }
        }
        if type_info == noType {
            if var_final_or_const == NO_TOKEN {
                self.report_recoverable_error(name, diag::missingConstFinalVarOrType);
            }
        } else {
            if var_final_or_const != NO_TOKEN && self.is_a(var_final_or_const, kw::VAR) {
                self.report_recoverable_error(var_final_or_const, diag::typeAfterVar);
            }
        }
        if abstract_token != NO_TOKEN && external_token != NO_TOKEN {
            self.report_recoverable_error(abstract_token, diag::abstractExternalField);
        }

        let mut token = type_info.parse_type(before_type, self);
        debug_assert!(self.next(token) == name || self.tokens.is_eof(self.next(token)));

        let context = if kind == DeclarationKind::TopLevel {
            IdentifierContext::topLevelVariableDeclaration
        } else {
            IdentifierContext::fieldDeclaration
        };
        name = self.ensure_identifier_potentially_recovered(token, context, name_is_recovered);
        let first_name = name;

        // Covariant affects only the setter and final fields do not have a setter,
        // unless it's a late field (dartbug.com/40805).
        // Field that are covariant late final with initializers are checked here.
        if covariant_token != NO_TOKEN && late_token != NO_TOKEN {
            if var_final_or_const != NO_TOKEN && self.is_a(var_final_or_const, kw::FINAL) {
                let next = self.next(name);
                if self.is_a(next, TokenType::EQ) {
                    self.report_recoverable_error(
                        covariant_token,
                        diag::finalAndCovariantLateWithInitializer,
                    );
                    covariant_token = NO_TOKEN;
                }
            }
        }

        let mut field_count = 1;
        token = self.parse_field_initializer_opt(
            name,
            name,
            late_token,
            abstract_token,
            augment_token,
            external_token,
            var_final_or_const,
            kind,
            enclosing_declaration_name,
        );
        while self.is_a(self.next(token), TokenType::COMMA) {
            let next = self.next(token);
            name = self.ensure_identifier(next, context);
            token = self.parse_field_initializer_opt(
                name,
                name,
                late_token,
                abstract_token,
                augment_token,
                external_token,
                var_final_or_const,
                kind,
                enclosing_declaration_name,
            );
            field_count += 1;
        }
        let semicolon = self.next(token);
        if self.is_a(semicolon, TokenType::SEMICOLON) {
            token = semicolon;
        } else {
            // Recovery
            token = self.ensure_semicolon(token);
        }

        match kind {
            DeclarationKind::TopLevel => {}
            DeclarationKind::Class | DeclarationKind::Mixin | DeclarationKind::Enum => {}
            DeclarationKind::Extension => {
                if abstract_token != NO_TOKEN {
                    self.report_recoverable_error(first_name, diag::abstractExtensionField);
                }
                if static_token == NO_TOKEN && external_token == NO_TOKEN {
                    self.report_recoverable_error(first_name, diag::extensionDeclaresInstanceField);
                }
            }
            DeclarationKind::ExtensionType => {
                if static_token == NO_TOKEN && external_token == NO_TOKEN {
                    self.report_recoverable_error(
                        first_name,
                        diag::extensionTypeDeclaresInstanceField,
                    );
                }
            }
        }

        let begin = self.next(before_start);
        if kind == DeclarationKind::TopLevel {
            self.listener.end_top_level_fields(
                &mut self.tokens,
                augment_token,
                abstract_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                field_count,
                begin,
                token,
            );
        } else {
            self.listener.end_fields(
                &mut self.tokens,
                kind,
                abstract_token,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                field_count,
                begin,
                token,
            );
        }
        token
    }

    pub fn parse_top_level_method(
        &mut self,
        before_start: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        before_type: TokenId,
        type_info: TypeInfo,
        get_or_set: TokenId,
        mut name: TokenId,
        name_is_recovered: bool,
    ) -> TokenId {
        self.listener.begin_top_level_method(
            &mut self.tokens,
            before_start,
            augment_token,
            external_token,
        );

        let mut token = type_info.parse_type(before_type, self);
        debug_assert!(
            self.next(token)
                == (if get_or_set != NO_TOKEN {
                    get_or_set
                } else {
                    name
                })
                || self.tokens.is_eof(self.next(token))
        );
        name = self.ensure_identifier_potentially_recovered(
            if get_or_set != NO_TOKEN {
                get_or_set
            } else {
                token
            },
            IdentifierContext::topLevelFunctionDeclaration,
            name_is_recovered,
        );

        let mut is_getter = false;
        if get_or_set == NO_TOKEN {
            token = self.parse_method_type_var(name);
        } else {
            is_getter = self.is_a(get_or_set, kw::GET);
            token = name;
            let next_32 = self.tokens.next(token);
            self.listener
                .handle_no_type_variables(&mut self.tokens, next_32);
        }
        token = self.parse_getter_or_formal_parameters(
            token,
            name,
            is_getter,
            MemberKind::TopLevelMethod,
        );
        let saved_async_modifier = self.async_state;
        let async_token = self.next(token);
        token = self.parse_async_modifier_opt(token);
        if get_or_set != NO_TOKEN && !self.in_plain_sync() && self.is_a(get_or_set, kw::SET) {
            self.report_recoverable_error(async_token, diag::setterNotSync);
        }
        let is_external = external_token != NO_TOKEN;
        if is_external && !self.is_a(self.next(token), TokenType::SEMICOLON) {
            self.report_recoverable_error(external_token, diag::externalMethodWithBody);
        }
        let allow_abstract = is_external || self.is_augmentations_feature_enabled;
        token = self.parse_function_body(token, false, allow_abstract);
        self.async_state = saved_async_modifier;
        let begin = self.next(before_start);
        self.listener
            .end_top_level_method(&mut self.tokens, begin, get_or_set, token);
        token
    }

    pub fn parse_method_type_var(&mut self, mut name: TokenId) -> TokenId {
        if self.is_a(self.next(name), TokenType::BANG) {
            // Recovery
            name = self.next(name);
            self.report_recoverable_error_with_token(name, diag::unexpectedToken);
        }
        if !self.is_a(self.next(name), TokenType::LT) {
            return noTypeParamOrArg.parse_variables(name, self);
        }
        let type_var = compute_type_param_or_arg(&mut self.tokens, name, true, false);
        let mut token = type_var.parse_variables(name, self);
        if self.is_a(self.next(token), TokenType::EQ) {
            // Recovery
            token = self.next(token);
            self.report_recoverable_error_with_token(token, diag::unexpectedToken);
        }
        token
    }

    pub fn parse_field_initializer_opt(
        &mut self,
        mut token: TokenId,
        name: TokenId,
        late_token: TokenId,
        abstract_token: TokenId,
        _augment_token: TokenId,
        external_token: TokenId,
        var_final_or_const: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
    ) -> TokenId {
        if Some(self.tokens.lexeme_string(name).as_str()) == enclosing_declaration_name {
            self.report_recoverable_error(name, diag::memberWithSameNameAsClass);
        }
        let next = self.next(token);
        if self.is_a(next, TokenType::EQ) {
            let assignment = next;
            self.listener
                .begin_field_initializer(&mut self.tokens, next);
            token = self.parse_expression(next);
            self.listener
                .end_field_initializer(&mut self.tokens, assignment, token);
        } else {
            if var_final_or_const != NO_TOKEN && !self.tokens.is_synthetic(name) {
                if self.is_a(var_final_or_const, kw::CONST) {
                    let message = (diag::constFieldWithoutInitializer.with_arguments)(
                        &self.tokens.lexeme_string(name),
                    );
                    self.report_recoverable_error(name, message);
                } else if kind == DeclarationKind::TopLevel
                    && self.is_a(var_final_or_const, kw::FINAL)
                    && late_token == NO_TOKEN
                    && abstract_token == NO_TOKEN
                    && external_token == NO_TOKEN
                {
                    let message = (diag::finalFieldWithoutInitializer.with_arguments)(
                        &self.tokens.lexeme_string(name),
                    );
                    self.report_recoverable_error(name, message);
                }
            }
            let next_31 = self.tokens.next(token);
            self.listener
                .handle_no_field_initializer(&mut self.tokens, next_31);
        }
        token
    }

    pub fn parse_variable_initializer_opt(&mut self, mut token: TokenId) -> TokenId {
        if self.is_a(self.next(token), TokenType::EQ) {
            let assignment = self.next(token);
            self.listener
                .begin_variable_initializer(&mut self.tokens, assignment);
            token = self.parse_expression(assignment);
            self.listener
                .end_variable_initializer(&mut self.tokens, assignment);
        } else {
            self.listener
                .handle_no_variable_initializer(&mut self.tokens, token);
        }
        token
    }

    pub fn parse_initializers_opt(&mut self, token: TokenId) -> TokenId {
        if self.is_a(self.next(token), TokenType::COLON) {
            let next = self.next(token);
            self.parse_initializers(next)
        } else {
            self.listener.handle_no_initializers(&mut self.tokens);
            token
        }
    }

    /// ```text
    /// initializers:
    ///   ':' initializerListEntry (',' initializerListEntry)*
    /// ;
    /// ```
    pub fn parse_initializers(&mut self, mut token: TokenId) -> TokenId {
        let begin = token;
        debug_assert!(self.is_a(begin, TokenType::COLON));
        self.listener.begin_initializers(&mut self.tokens, begin);
        let mut count = 0;
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = false;
        let mut next = begin;
        loop {
            token = self.parse_initializer(next);
            count += 1;
            next = self.next(token);
            if !self.is_a(next, TokenType::COMMA) {
                // Recovery: Found an identifier which could be
                // 1) missing preceding `,` thus it's another initializer, or
                // 2) missing preceding `;` thus it's a class member, or
                // 3) missing preceding '{' thus it's a statement
                if self.is_a(next, kw::ASSERT) {
                    next = self.next(next);
                    if !self.is_a(next, TokenType::OPEN_PAREN) {
                        break;
                    }
                    // Looks like assert expression ... fall through to insert comma
                } else if self.is_a(next, kw::THIS) || self.is_a(next, kw::SUPER) {
                    next = self.next(next);
                    if !self.is_a(next, TokenType::OPEN_PAREN)
                        && !self.is_a(next, TokenType::PERIOD)
                    {
                        break;
                    }
                    // `this` or `super` followed by either `.` or `(`.
                    // Fall through to insert comma.
                } else if self.tokens.is_identifier(next) {
                    next = self.next(next);
                    if !self.is_a(next, TokenType::EQ) {
                        break;
                    }
                    // Looks like field assignment... fall through to insert comma
                } else {
                    break;
                }
                // TODO(danrubel): Consider enhancing this to indicate that we are
                // expecting one of `,` or `;` or `{`
                self.report_recoverable_error(
                    token,
                    (diag::expectedAfterButGot.with_arguments)(","),
                );
                next = self
                    .rewriter()
                    .insert_synthetic_token(token, TokenType::COMMA);
            }
        }
        self.may_parse_function_expressions = old;
        self.listener
            .end_initializers(&mut self.tokens, count, begin, token);
        token
    }

    /// ```text
    /// initializerListEntry:
    ///   'super' ('.' identifier)? arguments |
    ///   fieldInitializer |
    ///   assertion
    /// ;
    ///
    /// fieldInitializer:
    ///   ('this' '.')? identifier '=' conditionalExpression cascadeSection*
    /// ;
    /// ```
    pub fn parse_initializer(&mut self, mut token: TokenId) -> TokenId {
        let mut next = self.next(token);
        self.listener.begin_initializer(&mut self.tokens, next);
        let before_expression = token;
        if self.is_a(next, kw::ASSERT) {
            token = self.parse_assert(token, Assert::Initializer);
            self.listener.end_initializer(&mut self.tokens, token);
            return token;
        } else if self.is_a(next, kw::SUPER) {
            return self.parse_super_initializer_expression(token);
        } else if self.is_a(next, kw::THIS) {
            token = next;
            next = self.next(token);
            if self.is_a(next, TokenType::PERIOD) {
                token = next;
                let after_identifier = self.next(self.next(token));
                if after_identifier != NO_TOKEN
                    && self.is_a(after_identifier, TokenType::OPEN_PAREN)
                {
                    // Assume `this.new(...)` is a redirecting constructor call.
                    self.try_rewrite_new_to_identifier(token, IdentifierContext::fieldInitializer);
                }
                next = self.next(token);
                if self.tokens.is_identifier(next) {
                    token = next;
                } else {
                    // Recovery
                    token = self.insert_synthetic_identifier(
                        token,
                        IdentifierContext::fieldInitializer,
                        None,
                        NO_TOKEN,
                    );
                }
                next = self.next(token);
                if self.is_a(next, TokenType::EQ) {
                    return self.parse_initializer_expression_rest(before_expression);
                }
            }
            if self.is_a(next, TokenType::OPEN_PAREN) {
                token = self.parse_initializer_expression_rest(before_expression);
                next = self.next(token);
                if self.is_a(next, TokenType::OPEN_CURLY_BRACKET)
                    || self.is_a(next, TokenType::FUNCTION)
                {
                    // Recovery
                    self.report_recoverable_error(next, diag::redirectingConstructorWithBody);
                }
                return token;
            }
            // Recovery
            if self.is_a(token, kw::THIS) {
                // TODO(danrubel): Consider a better error message indicating that
                // `this.<fieldname>=` is expected.
                self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("."));
                self.rewriter()
                    .insert_synthetic_token(token, TokenType::PERIOD);
                let after = self.next(token);
                token = self.rewriter().insert_synthetic_identifier(after);
                next = self.next(token);
            }
            // Fall through to recovery
        } else if self.tokens.is_identifier(next) {
            let next2 = self.next(next);
            if self.is_a(next2, TokenType::EQ) {
                return self.parse_initializer_expression_rest(token);
            }
            // Recovery: If this looks like an expression,
            // then fall through to insert the LHS and `=` of the assignment,
            // otherwise insert an `=` and synthetic identifier.
            if !self.tokens.is_operator(next2) && !self.is_a(next2, TokenType::PERIOD) {
                token = self.rewriter().insert_synthetic_token(next, TokenType::EQ);
                token = self.insert_synthetic_identifier(
                    token,
                    IdentifierContext::expression,
                    Some(diag::missingAssignmentInInitializer.message()),
                    next,
                );
                return self.parse_initializer_expression_rest(before_expression);
            }
        } else {
            // Recovery: Insert a synthetic assignment.
            token = self.insert_synthetic_identifier(
                token,
                IdentifierContext::fieldInitializer,
                Some(diag::expectedAnInitializer.message()),
                token,
            );
            token = self.rewriter().insert_synthetic_token(token, TokenType::EQ);
            token = self.rewriter().insert_synthetic_identifier(token);
            return self.parse_initializer_expression_rest(before_expression);
        }
        let _ = next;
        // Recovery:
        // Insert a sythetic identifier and assignment operator
        // to ensure that the expression is indeed an assignment.
        // Failing to do so causes this test to fail:
        // pkg/front_end/testcases/regress/issue_31192.dart
        // TODO(danrubel): Investigate better recovery.
        token = self.insert_synthetic_identifier(
            before_expression,
            IdentifierContext::fieldInitializer,
            Some(diag::missingAssignmentInInitializer.message()),
            NO_TOKEN,
        );
        self.rewriter().insert_synthetic_token(token, TokenType::EQ);
        self.parse_initializer_expression_rest(before_expression)
    }

    /// Parse the `super` initializer:
    /// ```text
    ///   'super' ('.' identifier)? arguments ;
    /// ```
    pub fn parse_super_initializer_expression(&mut self, start: TokenId) -> TokenId {
        let mut token = self.next(start);
        debug_assert!(self.is_a(token, kw::SUPER));
        let mut next = self.next(token);
        if self.is_a(next, TokenType::PERIOD) {
            token = next;
            self.try_rewrite_new_to_identifier(
                token,
                IdentifierContext::constructorReferenceContinuation,
            );
            next = self.next(token);
            if self.tokens.kind(next) != IDENTIFIER_TOKEN {
                next = IdentifierContext::expressionContinuation.ensure_identifier(token, self);
            }
            token = next;
            next = self.next(token);
        }
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            // Recovery
            if self.is_a(next, TokenType::QUESTION_PERIOD) {
                // An error for `super?.` is reported in parseSuperExpression.
                token = next;
                next = self.next(token);
                if !self.tokens.is_identifier(next) {
                    // Insert a synthetic identifier but don't report another error.
                    next = self.rewriter().insert_synthetic_identifier(token);
                }
                token = next;
                next = self.next(token);
            }
            if self.is_a(next, TokenType::EQ) {
                if self.is_a(token, kw::SUPER) {
                    // parseExpression will report error on assignment to super
                } else {
                    self.report_recoverable_error(
                        token,
                        diag::fieldInitializedOutsideDeclaringClass,
                    );
                }
            } else if !self.is_a(next, TokenType::OPEN_PAREN) {
                self.report_recoverable_error(
                    next,
                    (diag::expectedAfterButGot.with_arguments)("("),
                );
                self.rewriter().insert_parens(token, false);
            }
        }
        self.parse_initializer_expression_rest(start)
    }

    pub fn parse_initializer_expression_rest(&mut self, token: TokenId) -> TokenId {
        let token = self.parse_expression(token);
        self.listener.end_initializer(&mut self.tokens, token);
        token
    }

    /// If the next token is an opening curly brace, return it. Otherwise, use the
    /// given [missingBlockKind] to report an error, insert an opening and a
    /// closing curly brace, and return the newly inserted opening curly brace. If
    /// [missingBlockKind] is `null`, then use a generic error message.
    pub fn ensure_block(
        &mut self,
        token: TokenId,
        missing_block_kind: Option<BlockKind>,
    ) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_CURLY_BRACKET) {
            return next;
        }
        let template = missing_block_kind.and_then(|k| k.template);
        match template {
            None => {
                let message = missing_block_kind.and_then(|k| k.message);
                match message {
                    None => self
                        .report_recoverable_error(next, (diag::expectedButGot.with_arguments)("{")),
                    Some(message) => self.report_recoverable_error(token, message),
                }
            }
            Some(template) => {
                let message = (template.with_arguments)(&self.tokens, next);
                self.report_recoverable_error(next, message);
            }
        }
        self.insert_block(token)
    }

    pub fn insert_block(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        let offset = self.tokens.offset(next);
        let begin =
            self.tokens
                .synthetic_begin_token(TokenType::OPEN_CURLY_BRACKET, offset, NO_TOKEN);
        let begin_group = self.rewriter().insert_token(token, begin);
        let end = self
            .tokens
            .synthetic_token(TokenType::CLOSE_CURLY_BRACKET, offset);
        let end_group = self.rewriter().insert_token(begin_group, end);
        self.tokens.set_end_group(begin_group, end_group);
        begin_group
    }

    /// If the next token is a closing parenthesis, return it.
    /// Otherwise, report an error and return the closing parenthesis
    /// associated with the specified open parenthesis.
    pub fn ensure_close_paren(&mut self, token: TokenId, open_paren: TokenId) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, TokenType::CLOSE_PAREN) {
            return next;
        }
        let end_group = self.tokens.end_group(open_paren);
        if self.tokens.is_synthetic(end_group) {
            // Scanner has already reported a missing `)` error,
            // but placed the `)` in the wrong location, so move it.
            return self.rewriter().move_synthetic(token, end_group);
        }
        self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)(")"));
        end_group
    }

    /// If the next token is a colon, return it. Otherwise, report an
    /// error, insert a synthetic colon, and return the inserted colon.
    pub fn ensure_colon(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, TokenType::COLON) {
            return next;
        }
        let message = (diag::expectedButGot.with_arguments)(":");
        let offset = self.tokens.char_offset(next);
        let new_token = self.tokens.synthetic_token(TokenType::COLON, offset);
        self.rewrite_and_recover(token, message, new_token)
    }

    /// If the next token is the function arrow, return it. Otherwise, report an
    /// error, insert a synthetic function arrow, and return the inserted arrow.
    pub fn ensure_function_arrow(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        if self.is_a(next, TokenType::FUNCTION) {
            return next;
        }
        let message = (diag::expectedButGot.with_arguments)("=>");
        let offset = self.tokens.char_offset(next);
        let new_token = self.tokens.synthetic_token(TokenType::FUNCTION, offset);
        self.rewrite_and_recover(token, message, new_token)
    }

    /// If the token after [token] is a not literal string,
    /// then insert a synthetic literal string.
    /// Call `parseLiteralString` and return the result.
    pub fn ensure_literal_string(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        if self.tokens.kind(next) != STRING_TOKEN {
            let message = (diag::expectedString.with_arguments)(&self.tokens, next);
            let offset = self.tokens.char_offset(next);
            let index = self.tokens.add_string("\"\"".encode_utf16().collect());
            let new_token = self.tokens.synthetic_string_token(
                TokenType::STRING,
                crate::scanner::token::Lexeme::Owned(index),
                offset,
                Some(0),
            );
            self.rewrite_and_recover(token, message, new_token);
        }
        self.parse_literal_string(token)
    }

    /// If the token after [token] is a semi-colon, return it.
    /// Otherwise, report an error, insert a synthetic semi-colon,
    /// and return the inserted semi-colon.
    pub fn ensure_semicolon(&mut self, token: TokenId) -> TokenId {
        // TODO(danrubel): Once all expect(';'...) call sites have been converted
        // to use this method, remove similar semicolon recovery code
        // from the handleError method in element_listener.dart.
        let next = self.next(token);
        if self.is_a(next, TokenType::SEMICOLON) {
            return next;
        }

        // Find a token on the same line as where the ';' should be inserted.
        // Reporting the error on this token makes it easier
        // for users to understand and fix the error.
        let at = find_previous_non_zero_length_token(&self.tokens, token);
        self.report_recoverable_error(at, (diag::expectedAfterButGot.with_arguments)(";"));
        self.rewriter()
            .insert_synthetic_token(token, TokenType::SEMICOLON)
    }

    /// Report an error at the token after [token] that has the given [message].
    /// Insert the [newToken] after [token] and return [newToken].
    pub fn rewrite_and_recover(
        &mut self,
        token: TokenId,
        message: impl Into<Message>,
        new_token: TokenId,
    ) -> TokenId {
        let next = self.next(token);
        self.report_recoverable_error(next, message);
        self.rewriter().insert_token(token, new_token)
    }

    /// Replace the token after [token] with `[` followed by `]`
    /// and return [token].
    pub fn rewrite_square_brackets(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        debug_assert!(self.is_a(next, TokenType::INDEX));
        let offset = self.tokens.offset(next);
        let comments = self.tokens.preceding_comments(next);
        let replacement = if self.tokens.is_synthetic(next) {
            let begin =
                self.tokens
                    .synthetic_begin_token(TokenType::OPEN_SQUARE_BRACKET, offset, comments);
            let end = self
                .tokens
                .synthetic_token(TokenType::CLOSE_SQUARE_BRACKET, offset);
            self.link(begin, end)
        } else {
            let begin = self
                .tokens
                .begin_token(TokenType::OPEN_SQUARE_BRACKET, offset, comments);
            let end =
                self.tokens
                    .simple_token(TokenType::CLOSE_SQUARE_BRACKET, offset + 1, NO_TOKEN);
            self.link(begin, end)
        };
        self.rewriter().replace_token_following(token, replacement);
        token
    }

    /// Report the given token as unexpected and return the next token if the next
    /// token is one of the [expectedNext], otherwise just return the given token.
    pub fn skip_unexpected_token_opt(&mut self, token: TokenId, expected_next: &[&str]) -> TokenId {
        let next = self.next(token);
        if self.tokens.keyword(next).is_none() {
            let next_value = self.sv(self.next(next));
            for expected_value in expected_next {
                if next_value == Some(*expected_value) {
                    self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                    return next;
                }
            }
        }
        token
    }

    pub fn parse_native_clause(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let native_token = token;
        debug_assert!(self.is_a(native_token, kw::NATIVE));
        let mut has_name = false;
        if self.tokens.kind(self.next(token)) == STRING_TOKEN {
            has_name = true;
            token = self.parse_literal_string(token);
        }
        self.listener
            .handle_native_clause(&mut self.tokens, native_token, has_name);
        self.report_recoverable_error(native_token, diag::nativeClauseShouldBeAnnotation);
        token
    }

    pub fn skip_class_or_mixin_or_extension_body(&mut self, token: TokenId) -> TokenId {
        // The scanner ensures that `{` always has a closing `}`.
        self.ensure_block(token, None)
    }

    /// ```text
    /// classBody:
    ///   '{' classMember* '}'
    /// ;
    /// ```
    pub fn parse_class_or_mixin_or_extension_body(
        &mut self,
        mut token: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
    ) -> TokenId {
        if self.kind == ParserKind::TopLevelParser {
            return self.skip_class_or_mixin_or_extension_body(token);
        }
        token = self.next(token);
        let begin = token;
        debug_assert!(self.is_a(token, TokenType::OPEN_CURLY_BRACKET));
        self.listener
            .begin_class_or_mixin_or_extension_body(&mut self.tokens, kind, token);
        let mut count = 0;
        while self.not_eof_or_type(TokenType::CLOSE_CURLY_BRACKET, self.next(token)) {
            token = self.parse_class_or_mixin_or_extension_or_enum_member_impl(
                token,
                kind,
                enclosing_declaration_name,
            );
            count += 1;
        }
        token = self.next(token);
        debug_assert!(
            self.tokens.is_eof(token) || self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
        );
        self.listener.end_class_or_mixin_or_extension_body(
            &mut self.tokens,
            kind,
            count,
            begin,
            token,
        );
        token
    }

    pub fn is_unary_minus(&self, token: TokenId) -> bool {
        self.tokens.kind(token) == IDENTIFIER_TOKEN
            && self.tokens.lexeme_equals(token, "unary")
            && self.is_a(self.next(token), TokenType::MINUS)
    }

    /// Parse a class member.
    ///
    /// This method is only invoked from outside the parser. As a result, this
    /// method takes the next token to be consumed rather than the last consumed
    /// token and returns the token after the last consumed token rather than the
    /// last consumed token.
    pub fn parse_class_member(&mut self, token: TokenId, class_name: Option<&str>) -> TokenId {
        let previous = self.synthetic_previous_token(token);
        let token = self.parse_class_or_mixin_or_extension_or_enum_member_impl(
            previous,
            DeclarationKind::Class,
            class_name,
        );
        self.next(token)
    }

    /// Parse a mixin member.
    pub fn parse_mixin_member(&mut self, token: TokenId, mixin_name: &str) -> TokenId {
        let previous = self.synthetic_previous_token(token);
        let token = self.parse_class_or_mixin_or_extension_or_enum_member_impl(
            previous,
            DeclarationKind::Mixin,
            Some(mixin_name),
        );
        self.next(token)
    }

    /// Parse an extension member.
    pub fn parse_extension_member(&mut self, token: TokenId, extension_name: &str) -> TokenId {
        let previous = self.synthetic_previous_token(token);
        let token = self.parse_class_or_mixin_or_extension_or_enum_member_impl(
            previous,
            DeclarationKind::Extension,
            Some(extension_name),
        );
        self.next(token)
    }

    pub fn link(&mut self, begin_token: TokenId, end_token: TokenId) -> TokenId {
        self.tokens.set_next(begin_token, end_token);
        self.tokens.set_end_group(begin_token, end_token);
        begin_token
    }

    pub fn synthetic_previous_token(&mut self, token: TokenId) -> TokenId {
        // Return the previous token if there is one so that any token inserted
        // before `token` will be properly inserted into the token stream.
        // TODO(danrubel): remove this once all methods have been converted to
        // use and return the last token consumed and the `previous` field
        // has been removed.
        if self.tokens.previous(token) != NO_TOKEN {
            return self.tokens.previous(token);
        }
        let before = self.tokens.eof(-1, NO_TOKEN);
        self.tokens.set_next_field(before, token);
        before
    }

    pub fn is_reserved_keyword(&self, token: TokenId) -> bool {
        if !self.tokens.is_keyword(token) {
            return false;
        }
        self.tokens.type_(token).is_reserved_word()
    }

    pub fn indicates_method_or_field(&self, token: TokenId) -> bool {
        let value = self.sv(token);
        value == Some(";")
            || value == Some("=")
            || value == Some("(")
            || value == Some("{")
            || value == Some("=>")
            || value == Some("<")
    }

    /// ```text
    /// classMember:
    ///   fieldDeclaration |
    ///   constructorDeclaration |
    ///   methodDeclaration
    /// ;
    ///
    /// mixinMember:
    ///   fieldDeclaration |
    ///   methodDeclaration
    /// ;
    ///
    /// extensionMember:
    ///   staticFieldDeclaration |
    ///   methodDeclaration
    /// ;
    /// ```
    pub fn parse_class_or_mixin_or_extension_or_enum_member_impl(
        &mut self,
        token: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
    ) -> TokenId {
        let mut token = self.parse_metadata_star(token);
        let before_start = token;

        let skipped_non_late_late = NO_TOKEN;
        let mut covariant_token = NO_TOKEN;
        let mut abstract_token = NO_TOKEN;
        let mut augment_token = NO_TOKEN;
        let mut external_token = NO_TOKEN;
        let mut late_token = NO_TOKEN;
        let mut static_token = NO_TOKEN;
        let mut var_final_or_const = NO_TOKEN;

        let mut next = self.next(token);
        if is_modifier(&self.tokens, next) {
            if self.is_a(next, kw::EXTERNAL) {
                token = next;
                external_token = token;
                next = self.next(token);
            } else if self.is_a(next, kw::AUGMENT) {
                token = next;
                augment_token = token;
                next = self.next(token);
            } else if self.is_a(next, kw::ABSTRACT) {
                token = next;
                abstract_token = token;
                next = self.next(token);
            }
            if is_modifier(&self.tokens, next) {
                if self.is_a(next, kw::STATIC) && abstract_token == NO_TOKEN {
                    token = next;
                    static_token = token;
                    next = self.next(token);
                } else if self.is_a(next, kw::COVARIANT) {
                    token = next;
                    covariant_token = token;
                    next = self.next(token);
                }
                if is_modifier(&self.tokens, next) {
                    if self.is_a(next, kw::FINAL)
                        || self.is_a(next, kw::VAR)
                        || (self.is_a(next, kw::CONST) && covariant_token == NO_TOKEN)
                    {
                        token = next;
                        var_final_or_const = token;
                        next = self.next(token);
                    } else if self.is_a(next, kw::LATE) {
                        token = next;
                        late_token = token;
                        next = self.next(token);
                        if is_modifier(&self.tokens, next) && self.is_a(next, kw::FINAL) {
                            token = next;
                            var_final_or_const = token;
                            next = self.next(token);
                        }
                    }
                    if is_modifier(&self.tokens, next) {
                        let mut context = ModifierContext::new();
                        context.covariant_token = covariant_token;
                        context.augment_token = augment_token;
                        context.external_token = external_token;
                        context.late_token = late_token;
                        context.static_token = static_token;
                        context.set_var_final_or_const(&self.tokens, var_final_or_const);
                        context.abstract_token = abstract_token;

                        token = context.parse_class_member_modifiers(self, token);
                        next = self.next(token);

                        covariant_token = context.covariant_token;
                        external_token = context.external_token;
                        late_token = context.late_token;
                        static_token = context.static_token;
                        var_final_or_const = context.var_final_or_const();
                        abstract_token = context.abstract_token;
                    }
                }
            }
        }

        if late_token == NO_TOKEN {
            // `late` was used as a modifier in non-nnbd mode. An error has been
            // emitted. Still use it as a late token for the remainder in an attempt
            // to avoid cascading errors (and for passing to the listener).
            late_token = skipped_non_late_late;
        }

        self.listener.begin_member(&mut self.tokens);

        let before_type = token;
        if var_final_or_const != NO_TOKEN && !self.is_a(var_final_or_const, kw::CONST) {
            let after_outer_pattern = self.skip_outer_pattern(before_type);
            if after_outer_pattern != NO_TOKEN
                && self.is_a(self.next(after_outer_pattern), TokenType::EQ)
            {
                let start = self.next(before_type);
                self.report_recoverable_error_with_end(
                    start,
                    after_outer_pattern,
                    diag::patternVariableDeclarationOutsideFunctionOrMethod,
                );
                let synthetic_name = self.rewriter().insert_synthetic_identifier(before_type);
                let after = self.next(after_outer_pattern);
                self.rewriter().drop_range(synthetic_name, after);
                token = self.parse_fields(
                    before_start,
                    abstract_token,
                    augment_token,
                    external_token,
                    static_token,
                    covariant_token,
                    late_token,
                    var_final_or_const,
                    before_type,
                    noType,
                    synthetic_name,
                    kind,
                    enclosing_declaration_name,
                    true,
                );
                self.listener.end_member(&mut self.tokens);
                return token;
            }
        }

        let mut type_info = compute_type(&mut self.tokens, token, false, true, false);
        token = type_info.skip_type(&mut self.tokens, token);
        next = self.next(token);

        let mut new_token = NO_TOKEN;
        let mut get_or_set = NO_TOKEN;
        let mut name_is_recovered = false;
        if self.is_a(next, kw::NEW) {
            new_token = next;
            if !self.is_primary_constructors_feature_enabled {
                self.report_experiment_not_enabled(
                    ExperimentalFlag::primaryConstructors,
                    new_token,
                    new_token,
                );
            }
        } else if self.tokens.type_(next) != TokenType::IDENTIFIER {
            let value = self.sv(next);
            if value == Some("get") || value == Some("set") {
                if self.tokens.is_identifier(self.next(next)) {
                    token = next;
                    get_or_set = token;
                    next = self.next(token);
                } else if self.is_reserved_keyword(self.next(next))
                    && self.indicates_method_or_field(self.next(self.next(next)))
                {
                    // Recovery: Getter or setter with a reserved keyword as name.
                    token = next;
                    get_or_set = token;
                    next = self.next(token);
                    name_is_recovered = true;
                }
            } else if value == Some("factory") {
                let next2 = self.next(next);
                if self.tokens.is_identifier(next2)
                    || self.tokens.is_modifier(next2)
                    || self.is_a(next2, kw::NEW)
                {
                    if before_type != token {
                        self.report_recoverable_error(token, diag::typeBeforeFactory);
                    }
                    if abstract_token != NO_TOKEN {
                        self.report_recoverable_error(abstract_token, diag::abstractClassMember);
                    }
                    let static_or_covariant = if static_token != NO_TOKEN {
                        static_token
                    } else {
                        covariant_token
                    };
                    token = self.parse_factory_method(
                        token,
                        kind,
                        before_start,
                        augment_token,
                        external_token,
                        static_or_covariant,
                        var_final_or_const,
                        true,
                    );
                    self.listener.end_member(&mut self.tokens);
                    return token;
                } else if self.is_primary_constructors_feature_enabled
                    && self.is_a(next2, TokenType::OPEN_PAREN)
                {
                    if type_info == noType
                        && covariant_token == NO_TOKEN
                        && late_token == NO_TOKEN
                        && static_token == NO_TOKEN
                        && (var_final_or_const == NO_TOKEN
                            || self.is_a(var_final_or_const, kw::CONST))
                        && abstract_token == NO_TOKEN
                    {
                        let static_or_covariant = if static_token != NO_TOKEN {
                            static_token
                        } else {
                            covariant_token
                        };
                        token = self.parse_factory_method(
                            token,
                            kind,
                            before_start,
                            augment_token,
                            external_token,
                            static_or_covariant,
                            var_final_or_const,
                            false,
                        );
                        self.listener.end_member(&mut self.tokens);
                        return token;
                    }
                }
                // Fall through to continue parsing `factory` as an identifier.
            } else if value == Some("operator") {
                let next2 = self.next(next);
                let type_param = compute_type_param_or_arg(&mut self.tokens, next, false, false);
                // `operator` can be used as an identifier as in
                // `int operator<T>()` or `int operator = 2`
                if self.tokens.is_user_definable_operator(next2) && type_param == noTypeParamOrArg {
                    let name = self.next(token);
                    token = self.parse_method(
                        before_start,
                        abstract_token,
                        augment_token,
                        external_token,
                        static_token,
                        covariant_token,
                        late_token,
                        var_final_or_const,
                        before_type,
                        type_info,
                        get_or_set,
                        new_token,
                        name,
                        kind,
                        enclosing_declaration_name,
                        name_is_recovered,
                    );
                    self.listener.end_member(&mut self.tokens);
                    return token;
                } else if self.is_a(next2, TokenType::EQ_EQ_EQ)
                    || self.is_a(next2, TokenType::BANG_EQ_EQ)
                    || (self.tokens.is_operator(next2)
                        && !self.is_a(next2, TokenType::EQ)
                        && !self.is_a(next2, TokenType::LT))
                {
                    // Recovery: Invalid operator
                    return self.parse_invalid_operator_declaration(
                        before_start,
                        abstract_token,
                        augment_token,
                        external_token,
                        static_token,
                        covariant_token,
                        late_token,
                        var_final_or_const,
                        before_type,
                        kind,
                        enclosing_declaration_name,
                    );
                } else if self.is_unary_minus(next2) {
                    // Recovery
                    let name = self.next(token);
                    token = self.parse_method(
                        before_start,
                        abstract_token,
                        augment_token,
                        external_token,
                        static_token,
                        covariant_token,
                        late_token,
                        var_final_or_const,
                        before_type,
                        type_info,
                        get_or_set,
                        new_token,
                        name,
                        kind,
                        enclosing_declaration_name,
                        name_is_recovered,
                    );
                    self.listener.end_member(&mut self.tokens);
                    return token;
                }
                // Fall through to continue parsing `operator` as an identifier.
            } else if value == Some("this") {
                let next2 = self.next(next);
                if self.is_a(next2, TokenType::COLON)
                    || self.is_a(next2, TokenType::SEMICOLON)
                    || self.is_a(next2, TokenType::OPEN_CURLY_BRACKET)
                    || self.is_a(next2, TokenType::FUNCTION) // =>
                    || self.is_a(next2, kw::ASYNC)
                    || self.is_a(next2, kw::SYNC)
                {
                    if !self.is_primary_constructors_feature_enabled {
                        self.report_experiment_not_enabled(
                            ExperimentalFlag::primaryConstructors,
                            next,
                            next,
                        );
                    }
                    for modifier in [
                        var_final_or_const,
                        external_token,
                        static_token,
                        covariant_token,
                        late_token,
                    ] {
                        if modifier != NO_TOKEN {
                            self.report_recoverable_error_with_token(
                                modifier,
                                diag::extraneousModifier,
                            );
                        }
                    }
                    token = self.parse_primary_constructor_body(next, augment_token);
                    self.listener.end_member(&mut self.tokens);
                    return token;
                }
            } else if !self.tokens.is_identifier(next)
                || (value == Some("typedef")
                    && token == before_start
                    && self.tokens.is_identifier(self.next(next)))
            {
                if abstract_token != NO_TOKEN {
                    self.report_recoverable_error(abstract_token, diag::abstractClassMember);
                }
                return self.recover_from_invalid_member(
                    token,
                    before_start,
                    abstract_token,
                    augment_token,
                    external_token,
                    static_token,
                    covariant_token,
                    late_token,
                    var_final_or_const,
                    before_type,
                    type_info,
                    get_or_set,
                    new_token,
                    kind,
                    enclosing_declaration_name,
                );
            }
        } else if type_info == noType && var_final_or_const == NO_TOKEN {
            let next2 = self.next(next);
            if self.tokens.is_user_definable_operator(next2)
                && self.tokens.end_group(next2) == NO_TOKEN
            {
                let value = self.sv(self.next(next2));
                if value == Some("(") || value == Some("{") || value == Some("=>") {
                    // Recovery: Missing `operator` keyword
                    return self.parse_invalid_operator_declaration(
                        before_start,
                        abstract_token,
                        augment_token,
                        external_token,
                        static_token,
                        covariant_token,
                        late_token,
                        var_final_or_const,
                        before_type,
                        kind,
                        enclosing_declaration_name,
                    );
                }
            } else if self.is_reserved_keyword(next2)
                && self.indicates_method_or_field(self.next(next2))
            {
                // Recovery: Use the reserved keyword despite that not being legal.
                type_info = compute_type(&mut self.tokens, token, true, true, false);
                token = type_info.skip_type(&mut self.tokens, token);
                next = self.next(token);
                name_is_recovered = true;
            }
        }

        // At this point, `token` is beforeName.

        next = self.next(next);
        let value = self.sv(next);
        let name = self.next(token);
        if get_or_set != NO_TOKEN
            || new_token != NO_TOKEN
            || value == Some("(")
            || value == Some("{")
            || value == Some("<")
            || value == Some(".")
            || value == Some("=>")
        {
            token = self.parse_method(
                before_start,
                abstract_token,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                before_type,
                type_info,
                get_or_set,
                new_token,
                name,
                kind,
                enclosing_declaration_name,
                name_is_recovered,
            );
        } else {
            if get_or_set != NO_TOKEN {
                self.report_recoverable_error_with_token(get_or_set, diag::extraneousModifier);
            }
            token = self.parse_fields(
                before_start,
                abstract_token,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                before_type,
                type_info,
                name,
                kind,
                enclosing_declaration_name,
                name_is_recovered,
            );
        }
        self.listener.end_member(&mut self.tokens);
        token
    }

    fn is_constructor(
        &self,
        name: TokenId,
        get_or_set: TokenId,
        new_token: TokenId,
        enclosing_declaration_name: Option<&str>,
        is_operator: bool,
    ) -> bool {
        if new_token != NO_TOKEN {
            return true;
        }
        let mut after_name = if self.tokens.is_keyword_or_identifier(name) {
            self.next(name)
        } else {
            name
        };
        if self.is_a(after_name, TokenType::PERIOD) {
            return true;
        }
        if is_operator {
            if self.tokens.is_operator(after_name) {
                after_name = self.next(after_name);
            } else if self.is_unary_minus(after_name) {
                after_name = self.next(self.next(after_name));
            }
        }
        if self.is_a(after_name, TokenType::BANG) {
            // Recovery: Inserted ! after method name.
            after_name = self.next(after_name);
        }
        if self.is_a(after_name, TokenType::LT) {
            // Recovery: Type parameters on constructor, e.g. `Foo<T>() {}`.
            if self.tokens.end_group(after_name) != NO_TOKEN {
                after_name = self.next(self.tokens.end_group(after_name));
                if self.is_a(after_name, TokenType::EQ) {
                    // Recovery: `Foo<T>=`.
                    after_name = self.next(after_name);
                }
            }
        }
        if self.is_a(after_name, TokenType::OPEN_PAREN) {
            let after_paren = self.next(self.tokens.end_group(after_name));
            if self.is_a(after_paren, TokenType::COLON) {
                return true;
            }
        } else if self.is_a(after_name, TokenType::COLON) {
            // Recovery: Missing parameters.
            return true;
        }
        if get_or_set != NO_TOKEN {
            return false;
        }
        Some(self.tokens.lexeme_string(name).as_str()) == enclosing_declaration_name
    }

    pub fn parse_method(
        &mut self,
        before_start: TokenId,
        abstract_token: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        mut static_token: TokenId,
        mut covariant_token: TokenId,
        late_token: TokenId,
        mut var_final_or_const: TokenId,
        before_type: TokenId,
        type_info: TypeInfo,
        get_or_set: TokenId,
        new_token: TokenId,
        name: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
        name_is_recovered: bool,
    ) -> TokenId {
        if abstract_token != NO_TOKEN {
            self.report_recoverable_error(abstract_token, diag::abstractClassMember);
        }
        if late_token != NO_TOKEN {
            self.report_recoverable_error_with_token(late_token, diag::extraneousModifier);
        }
        let mut is_operator = false;
        if get_or_set == NO_TOKEN && self.is_a(name, kw::OPERATOR) {
            let operator = self.next(name);
            if self.tokens.is_operator(operator)
                || self.tokens.kind(operator) == EQ_EQ_EQ_TOKEN
                || self.tokens.kind(operator) == BANG_EQ_EQ_TOKEN
                || self.is_unary_minus(operator)
            {
                is_operator = true;
                if self.is_a(operator, TokenType::GT_GT)
                    && self.is_a(self.next(operator), TokenType::GT)
                    && self.tokens.char_end(operator)
                        == self.tokens.char_offset(self.next(operator))
                {
                    // Special case use of triple-shift in cases where it isn't
                    // enabled.
                    let next = self.next(operator);
                    self.report_experiment_not_enabled(
                        ExperimentalFlag::tripleShift,
                        operator,
                        next,
                    );
                    self.rewriter().replace_next_tokens_with_synthetic_token(
                        name,
                        2,
                        TokenType::GT_GT_GT,
                    );
                }
            }
        }

        let is_constructor = self.is_constructor(
            name,
            get_or_set,
            new_token,
            enclosing_declaration_name,
            is_operator,
        );

        if static_token != NO_TOKEN {
            if is_operator {
                self.report_recoverable_error(static_token, diag::staticOperator);
                static_token = NO_TOKEN;
            }
        } else if covariant_token != NO_TOKEN {
            if get_or_set == NO_TOKEN || self.is_a(get_or_set, kw::GET) {
                self.report_recoverable_error(covariant_token, diag::covariantMember);
                covariant_token = NO_TOKEN;
            }
        }
        if var_final_or_const != NO_TOKEN {
            if self.is_a(var_final_or_const, kw::CONST) {
                if get_or_set != NO_TOKEN {
                    self.report_recoverable_error_with_token(
                        var_final_or_const,
                        diag::extraneousModifier,
                    );
                    var_final_or_const = NO_TOKEN;
                }
            } else if self.is_a(var_final_or_const, kw::VAR) {
                self.report_recoverable_error(var_final_or_const, diag::varReturnType);
                var_final_or_const = NO_TOKEN;
            } else {
                debug_assert!(self.is_a(var_final_or_const, kw::FINAL));
                self.report_recoverable_error_with_token(
                    var_final_or_const,
                    diag::extraneousModifier,
                );
                var_final_or_const = NO_TOKEN;
            }
        }

        // TODO(danrubel): Consider parsing the name before calling beginMethod
        // rather than passing the name token into beginMethod.
        if is_constructor {
            self.listener.begin_constructor(
                &mut self.tokens,
                kind,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                var_final_or_const,
                get_or_set,
                new_token,
                name,
                enclosing_declaration_name,
            );
        } else {
            self.listener.begin_method(
                &mut self.tokens,
                kind,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                var_final_or_const,
                get_or_set,
                name,
                enclosing_declaration_name,
            );
        }

        let mut token = type_info.parse_type(before_type, self);
        if get_or_set != NO_TOKEN {
            token = get_or_set;
        }

        let mut has_qualified_name = false;
        if is_operator {
            token = self.parse_operator_name(token);
        } else if new_token != NO_TOKEN {
            token = self.next(token);
            let next = self.next(token);
            if self.tokens.is_identifier(next) {
                token = next;
                let identifier = token;
                self.listener.handle_identifier(
                    &mut self.tokens,
                    identifier,
                    IdentifierContext::methodDeclaration,
                );
                let qualified = self.parse_qualified_rest_opt(
                    token,
                    IdentifierContext::methodDeclarationContinuation,
                );
                if token != qualified {
                    has_qualified_name = true;
                    self.report_recoverable_error(token, diag::newConstructorQualifiedName);
                }
                token = qualified;
            } else if self.is_a(next, kw::NEW) {
                token = next;
                let identifier = token;
                self.report_recoverable_error(identifier, diag::newConstructorNewName);
                self.listener.handle_identifier(
                    &mut self.tokens,
                    identifier,
                    IdentifierContext::methodDeclaration,
                );
            } else if self.is_a(next, TokenType::PERIOD)
                && self.tokens.is_identifier(self.next(next))
            {
                let dot = next;
                self.report_recoverable_error(dot, diag::newConstructorDotName);
                token = self.next(dot);
                let identifier = token;
                self.listener.handle_identifier(
                    &mut self.tokens,
                    identifier,
                    IdentifierContext::methodDeclaration,
                );
                let qualified = self.parse_qualified_rest_opt(
                    token,
                    IdentifierContext::methodDeclarationContinuation,
                );
                if token != qualified {
                    has_qualified_name = true;
                    self.report_recoverable_error(token, diag::newConstructorQualifiedName);
                }
                token = qualified;
            } else {
                self.listener.handle_no_identifier(
                    &mut self.tokens,
                    token,
                    IdentifierContext::methodDeclaration,
                );
            }
        } else {
            token = self.ensure_identifier_potentially_recovered(
                token,
                IdentifierContext::methodDeclaration,
                name_is_recovered,
            );
            let qualified = self
                .parse_qualified_rest_opt(token, IdentifierContext::methodDeclarationContinuation);
            if token != qualified {
                has_qualified_name = true;
            }
            token = qualified;
        }

        let mut is_considered_getter = false;
        if get_or_set == NO_TOKEN {
            token = self.parse_method_type_var(token);
        } else {
            is_considered_getter = self.is_a(get_or_set, kw::GET);
            let next_30 = self.tokens.next(token);
            self.listener
                .handle_no_type_variables(&mut self.tokens, next_30);

            // If it becomes considered a constructor below, don't consider it a
            // getter now (this also enforces parenthesis (and thus parameters)).
            if has_qualified_name {
                is_considered_getter = false;
            } else if is_considered_getter && self.is_a(self.next(token), TokenType::COLON) {
                is_considered_getter = false;
            }
        }

        let member_kind = match kind {
            DeclarationKind::TopLevel
            | DeclarationKind::Class
            | DeclarationKind::Mixin
            | DeclarationKind::Enum => {
                if static_token != NO_TOKEN {
                    MemberKind::StaticMethod
                } else {
                    MemberKind::NonStaticMethod
                }
            }
            DeclarationKind::Extension => {
                if static_token != NO_TOKEN {
                    MemberKind::ExtensionStaticMethod
                } else {
                    MemberKind::ExtensionNonStaticMethod
                }
            }
            DeclarationKind::ExtensionType => {
                if static_token != NO_TOKEN {
                    MemberKind::ExtensionTypeStaticMethod
                } else {
                    MemberKind::ExtensionTypeNonStaticMethod
                }
            }
        };
        let before_param = token;
        let mut before_initializers =
            self.parse_getter_or_formal_parameters(token, name, is_considered_getter, member_kind);
        token = self.parse_initializers_opt(before_initializers);
        if token == before_initializers {
            before_initializers = NO_TOKEN;
        }

        let saved_async_modifier = self.async_state;
        let async_token = self.next(token);
        token = self.parse_async_modifier_opt(token);
        if get_or_set != NO_TOKEN && !self.in_plain_sync() && self.is_a(get_or_set, kw::SET) {
            self.report_recoverable_error(async_token, diag::setterNotSync);
        }
        // TODO(danrubel): consider parsing body as part of `beginMethod`
        let body_start = self.next(token);
        if external_token != NO_TOKEN {
            if !self.is_a(body_start, TokenType::SEMICOLON) {
                self.report_recoverable_error(body_start, diag::externalMethodWithBody);
            }
        }
        if self.is_a(body_start, TokenType::EQ) {
            self.report_recoverable_error(body_start, diag::redirectionInNonFactory);
            token = self.parse_redirecting_factory_body(token);
        } else {
            let allow_abstract = (static_token == NO_TOKEN
                || external_token != NO_TOKEN
                || self.is_augmentations_feature_enabled)
                && self.in_plain_sync();
            token = self.parse_function_body(token, false, allow_abstract);
        }
        self.async_state = saved_async_modifier;

        let name_lexeme = self.tokens.lexeme_string(name);
        let after_initializers = if before_initializers == NO_TOKEN {
            NO_TOKEN
        } else {
            self.next(before_initializers)
        };
        if is_constructor {
            if new_token == NO_TOKEN && Some(name_lexeme.as_str()) != enclosing_declaration_name {
                self.report_recoverable_error(name, diag::constructorWithWrongName);
            }
            if static_token != NO_TOKEN {
                self.report_recoverable_error(static_token, diag::staticConstructor);
            }
            if get_or_set != NO_TOKEN {
                if self.is_a(get_or_set, kw::GET) {
                    self.report_recoverable_error(get_or_set, diag::getterConstructor);
                } else {
                    self.report_recoverable_error(get_or_set, diag::setterConstructor);
                }
            }
            if type_info != noType {
                let next = self.next(before_type);
                self.report_recoverable_error(next, diag::constructorWithReturnType);
            }
            if before_initializers != NO_TOKEN && external_token != NO_TOKEN {
                self.report_recoverable_error(
                    after_initializers,
                    diag::externalConstructorWithInitializer,
                );
            }

            match kind {
                DeclarationKind::Mixin => {
                    self.report_recoverable_error(name, diag::mixinDeclaresConstructor)
                }
                DeclarationKind::Extension => {
                    self.report_recoverable_error(name, diag::extensionDeclaresConstructor)
                }
                DeclarationKind::Class | DeclarationKind::ExtensionType | DeclarationKind::Enum => {
                }
                DeclarationKind::TopLevel => panic!("Internal error: TopLevel constructor."),
            }
            let begin = self.next(before_start);
            let param = self.next(before_param);
            self.listener.end_constructor(
                &mut self.tokens,
                kind,
                begin,
                new_token,
                param,
                after_initializers,
                token,
            );
        } else {
            if Some(name_lexeme.as_str()) == enclosing_declaration_name && get_or_set != NO_TOKEN {
                self.report_recoverable_error(name, diag::memberWithSameNameAsClass);
            }
            if var_final_or_const != NO_TOKEN {
                debug_assert!(self.is_a(var_final_or_const, kw::CONST));
                self.report_recoverable_error(var_final_or_const, diag::constMethod);
            }
            let begin = self.next(before_start);
            let param = self.next(before_param);
            self.listener.end_method(
                &mut self.tokens,
                kind,
                get_or_set,
                begin,
                param,
                after_initializers,
                token,
            );
        }
        token
    }

    pub fn parse_factory_method(
        &mut self,
        mut token: TokenId,
        kind: DeclarationKind,
        before_start: TokenId,
        augment_token: TokenId,
        mut external_token: TokenId,
        mut static_or_covariant: TokenId,
        mut var_final_or_const: TokenId,
        has_name: bool,
    ) -> TokenId {
        token = self.next(token);
        let factory_keyword = token;
        debug_assert!(self.is_a(factory_keyword, kw::FACTORY));
        if !is_valid_non_record_type_reference(&self.tokens, self.next(token)) {
            // Recovery
            let mut context = ModifierContext::new();
            context.external_token = external_token;
            context.set_static_or_covariant(&self.tokens, static_or_covariant);
            context.set_var_final_or_const(&self.tokens, var_final_or_const);

            token = context.parse_modifiers_after_factory(self, token);

            external_token = context.external_token;
            static_or_covariant = if context.static_token != NO_TOKEN {
                context.static_token
            } else {
                context.covariant_token
            };
            var_final_or_const = context.var_final_or_const();
        }

        if static_or_covariant != NO_TOKEN {
            self.report_recoverable_error_with_token(static_or_covariant, diag::extraneousModifier);
        }
        if var_final_or_const != NO_TOKEN && !self.is_a(var_final_or_const, kw::CONST) {
            self.report_recoverable_error_with_token(var_final_or_const, diag::extraneousModifier);
            var_final_or_const = NO_TOKEN;
        }

        self.listener.begin_factory(
            &mut self.tokens,
            kind,
            before_start,
            augment_token,
            external_token,
            var_final_or_const,
        );
        if !has_name {
            self.listener.handle_no_identifier(
                &mut self.tokens,
                token,
                IdentifierContext::methodDeclaration,
            );
        } else if self.is_a(self.next(token), kw::NEW)
            && !self.is_a(self.next(self.next(token)), TokenType::PERIOD)
        {
            token = self.next(token);
            let identifier = token;
            self.report_recoverable_error(identifier, diag::factoryConstructorNewName);
            self.listener.handle_identifier(
                &mut self.tokens,
                identifier,
                IdentifierContext::methodDeclaration,
            );
        } else {
            token = self.ensure_identifier(token, IdentifierContext::methodDeclaration);
            token = self
                .parse_qualified_rest_opt(token, IdentifierContext::methodDeclarationContinuation);
        }
        token = self.parse_method_type_var(token);
        token = self.parse_formal_parameters_required_opt(token, MemberKind::Factory);
        let async_token = self.next(token);
        token = self.parse_async_modifier_opt(token);
        let next = self.next(token);
        if !self.in_plain_sync() {
            self.report_recoverable_error(async_token, diag::factoryNotSync);
        }
        if self.is_a(next, TokenType::EQ) {
            if external_token != NO_TOKEN {
                self.report_recoverable_error(next, diag::externalFactoryRedirection);
            }
            token = self.parse_redirecting_factory_body(token);
        } else if external_token != NO_TOKEN {
            if !self.is_a(next, TokenType::SEMICOLON) {
                self.report_recoverable_error(next, diag::externalFactoryWithBody);
            }
            token = self.parse_function_body(token, false, true);
        } else {
            if var_final_or_const != NO_TOKEN && !self.is_a(next, kw::NATIVE) {
                if self.is_a(var_final_or_const, kw::CONST) {
                    self.listener
                        .handle_const_factory(&mut self.tokens, var_final_or_const);
                }
            }
            let allow_abstract = self.is_augmentations_feature_enabled;
            token = self.parse_function_body(token, false, allow_abstract);
        }
        match kind {
            DeclarationKind::Class | DeclarationKind::Enum | DeclarationKind::ExtensionType => {}
            DeclarationKind::Mixin => {
                self.report_recoverable_error(factory_keyword, diag::mixinDeclaresConstructor)
            }
            DeclarationKind::Extension => {
                self.report_recoverable_error(factory_keyword, diag::extensionDeclaresConstructor)
            }
            DeclarationKind::TopLevel => panic!("Internal error: TopLevel factory."),
        }
        let begin = self.next(before_start);
        self.listener
            .end_factory(&mut self.tokens, kind, begin, factory_keyword, token);
        token
    }

    pub fn parse_operator_name(&mut self, mut token: TokenId) -> TokenId {
        let before_token = token;
        token = self.next(token);
        debug_assert!(self.is_a(token, kw::OPERATOR));
        let mut next = self.next(token);
        if self.tokens.is_user_definable_operator(next) {
            if compute_type_param_or_arg(&mut self.tokens, token, false, false) != noTypeParamOrArg
            {
                // `operator` is being used as an identifier.
                // For example: `int operator<T>(foo) => 0;`
                self.listener.handle_identifier(
                    &mut self.tokens,
                    token,
                    IdentifierContext::methodDeclaration,
                );
                token
            } else {
                self.listener
                    .handle_operator_name(&mut self.tokens, token, next);
                next
            }
        } else if self.is_a(next, TokenType::OPEN_PAREN) {
            self.ensure_identifier(before_token, IdentifierContext::operatorName)
        } else if self.is_unary_minus(next) {
            // Recovery
            self.report_recoverable_error_with_token(next, diag::unexpectedToken);
            next = self.next(next);
            self.listener
                .handle_operator_name(&mut self.tokens, token, next);
            next
        } else {
            // Recovery
            // Report an error for invalid operator names
            // (unless it's one of the triple-equal operators,
            // which are reported elsewhere).
            if self.tokens.type_(next) != TokenType::EQ_EQ_EQ
                && self.tokens.type_(next) != TokenType::BANG_EQ_EQ
            {
                self.report_recoverable_error_with_token(next, diag::invalidOperator);
            }
            self.listener
                .handle_invalid_operator_name(&mut self.tokens, token, next);
            next
        }
    }

    pub fn parse_function_expression(&mut self, mut token: TokenId) -> TokenId {
        let begin_token = self.next(token);
        self.listener
            .begin_function_expression(&mut self.tokens, begin_token);
        token = self.parse_formal_parameters_required_opt(token, MemberKind::Local);
        token = self.parse_async_opt_body(token, true, false);
        self.listener
            .end_function_expression(&mut self.tokens, begin_token, token);
        token
    }

    pub fn parse_function_literal(
        &mut self,
        start: TokenId,
        before_name: TokenId,
        name: TokenId,
        type_info: TypeInfo,
        type_param: TypeParamOrArgInfo,
        _context: &'static IdentifierContext,
    ) -> TokenId {
        let formals = type_param.parse_variables(name, self);
        let next_29 = self.tokens.next(start);
        self.listener
            .begin_named_function_expression(&mut self.tokens, next_29);
        type_info.parse_type(start, self);
        let begin = self.next(start);
        self.parse_named_function_rest(before_name, begin, formals, true)
    }

    /// Parses the rest of a named function declaration starting from its [name]
    /// but then skips any type parameters and continue parsing from [formals]
    /// (the formal parameters).
    ///
    /// If [isFunctionExpression] is true, this method parses the rest of named
    /// function expression which isn't legal syntax in Dart.  Useful for
    /// recovering from JavaScript code being pasted into a Dart program, as it
    /// will interpret `function foo() {}` as a named function expression with
    /// return type `function`.
    pub fn parse_named_function_rest(
        &mut self,
        before_name: TokenId,
        begin: TokenId,
        formals: TokenId,
        is_function_expression: bool,
    ) -> TokenId {
        let mut token = self.next(before_name);
        self.listener.begin_function_name(&mut self.tokens, token);
        token = self.ensure_identifier(before_name, IdentifierContext::localFunctionDeclaration);
        token = self.next(token);
        if is_function_expression {
            let next = self.next(before_name);
            self.report_recoverable_error(next, diag::namedFunctionExpression);
        }
        self.listener
            .end_function_name(&mut self.tokens, begin, token, is_function_expression);
        token = self.parse_formal_parameters_required_opt(formals, MemberKind::Local);
        token = self.parse_initializers_opt(token);
        token = self.parse_async_opt_body(token, is_function_expression, false);
        if is_function_expression {
            self.listener
                .end_named_function_expression(&mut self.tokens, token);
        } else {
            self.listener
                .end_local_function_declaration(&mut self.tokens, token);
        }
        token
    }

    /// Parses a function body optionally preceded by an async modifier (see
    /// [parseAsyncModifierOpt]).  This method is used in both expression context
    /// (when [ofFunctionExpression] is true) and statement context. In statement
    /// context (when [ofFunctionExpression] is false), and if the function body
    /// is on the form `=> expression`, a trailing semicolon is required.
    ///
    /// It's an error if there's no function body unless [allowAbstract] is true.
    pub fn parse_async_opt_body(
        &mut self,
        mut token: TokenId,
        of_function_expression: bool,
        allow_abstract: bool,
    ) -> TokenId {
        let saved_async_modifier = self.async_state;
        token = self.parse_async_modifier_opt(token);
        token = self.parse_function_body(token, of_function_expression, allow_abstract);
        self.async_state = saved_async_modifier;
        token
    }

    pub fn parse_constructor_reference(
        &mut self,
        token: TokenId,
        constructor_reference_context: ConstructorReferenceContext,
        type_arg: Option<TypeParamOrArgInfo>,
    ) -> TokenId {
        // Note that there's an almost verbatim copy in [parseEnumElement] so
        // any change here should be added there too.
        let start = self.ensure_identifier(token, IdentifierContext::constructorReference);
        self.listener
            .begin_constructor_reference(&mut self.tokens, start);
        let mut token = self
            .parse_qualified_rest_opt(start, IdentifierContext::constructorReferenceContinuation);
        let type_arg = match type_arg {
            Some(type_arg) => type_arg,
            None => compute_type_param_or_arg(&mut self.tokens, token, false, false),
        };
        token = type_arg.parse_arguments(token, self);
        let mut period = NO_TOKEN;
        if self.is_a(self.next(token), TokenType::PERIOD) {
            period = self.next(token);
            token = self.ensure_identifier(
                period,
                IdentifierContext::constructorReferenceContinuationAfterTypeArguments,
            );
        } else {
            self.listener
                .handle_no_constructor_reference_continuation_after_type_arguments(
                    &mut self.tokens,
                    token,
                );
        }
        self.listener.end_constructor_reference(
            &mut self.tokens,
            start,
            period,
            token,
            constructor_reference_context,
        );
        token
    }

    pub fn parse_redirecting_factory_body(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        debug_assert!(self.is_a(token, TokenType::EQ));
        self.listener
            .begin_redirecting_factory_body(&mut self.tokens, token);
        let equals = token;
        token = self.parse_constructor_reference(
            token,
            ConstructorReferenceContext::RedirectingFactory,
            None,
        );
        token = self.ensure_semicolon(token);
        self.listener
            .end_redirecting_factory_body(&mut self.tokens, equals, token);
        token
    }

    pub fn skip_function_body(
        &mut self,
        mut token: TokenId,
        is_expression: bool,
        allow_abstract: bool,
    ) -> TokenId {
        debug_assert!(!is_expression);
        token = self.skip_async_modifier(token);
        let mut next = self.next(token);
        if self.is_a(next, kw::NATIVE) {
            let native_token = next;
            // TODO(danrubel): skip the native clause rather than parsing it
            // or remove this code completely when we remove support
            // for the `native` clause.
            token = self.parse_native_clause(token);
            next = self.next(token);
            if self.is_a(next, TokenType::SEMICOLON) {
                self.listener.handle_native_function_body_skipped(
                    &mut self.tokens,
                    native_token,
                    next,
                );
                return self.next(token);
            }
            self.listener
                .handle_native_function_body_ignored(&mut self.tokens, native_token, next);
            // Fall through to recover and skip function body
        }
        let value = self.sv(next);
        if value == Some(";") {
            token = next;
            if !allow_abstract {
                self.report_recoverable_error(token, diag::expectedBody);
            }
            self.listener
                .handle_no_function_body(&mut self.tokens, token);
        } else if value == Some("=>") {
            let begin_token = next;
            token = self.parse_expression(next);
            if self.is_a(self.next(token), TokenType::SEMICOLON) {
                token = self.next(token);
            }
            self.listener
                .handle_function_body_skipped(&mut self.tokens, begin_token, token, true);
        } else if value == Some("=") {
            token = next;
            let begin_token = token;
            // Recover from a bad factory method.
            self.report_recoverable_error(token, diag::expectedBody);
            token = self.parse_expression(token);
            if self.is_a(self.next(token), TokenType::SEMICOLON) {
                token = self.next(token);
            }
            self.listener
                .handle_function_body_skipped(&mut self.tokens, begin_token, token, true);
        } else {
            let begin_token = self.next(token);
            token = self.skip_block(token);
            self.listener
                .handle_function_body_skipped(&mut self.tokens, begin_token, token, false);
        }
        token
    }

    /// Parses a function body.  This method is used in both expression context
    /// (when [ofFunctionExpression] is true) and statement context. In statement
    /// context (when [ofFunctionExpression] is false), and if the function body
    /// is on the form `=> expression`, a trailing semicolon is required.
    ///
    /// It's an error if there's no function body unless [allowAbstract] is true.
    pub fn parse_function_body(
        &mut self,
        mut token: TokenId,
        of_function_expression: bool,
        allow_abstract: bool,
    ) -> TokenId {
        if self.kind != ParserKind::Parser {
            return self.skip_function_body(token, of_function_expression, allow_abstract);
        }
        let mut next = self.next(token);
        if self.is_a(next, kw::NATIVE) {
            let native_token = next;
            token = self.parse_native_clause(token);
            next = self.next(token);
            if self.is_a(next, TokenType::SEMICOLON) {
                self.listener
                    .handle_native_function_body(&mut self.tokens, native_token, next);
                return next;
            }
            self.report_recoverable_error(next, diag::externalMethodWithBody);
            self.listener
                .handle_native_function_body_ignored(&mut self.tokens, native_token, next);
            // Fall through to recover and parse function body
        }
        if self.is_a(next, TokenType::SEMICOLON) {
            if !allow_abstract {
                self.report_recoverable_error(next, diag::expectedBody);
            }
            self.listener
                .handle_empty_function_body(&mut self.tokens, next);
            return next;
        } else if self.is_a(next, TokenType::FUNCTION) {
            return self.parse_expression_function_body(next, of_function_expression);
        } else if self.is_a(next, TokenType::EQ) {
            // Recover from a bad factory method.
            self.report_recoverable_error(next, diag::expectedBody);
            let offset = self.tokens.char_offset(self.next(next));
            let arrow = self.tokens.synthetic_token(TokenType::FUNCTION, offset);
            next = self.rewriter().insert_token(next, arrow);
            let begin = next;
            token = self.parse_expression(next);
            if !of_function_expression {
                token = self.ensure_semicolon(token);
                self.listener
                    .handle_expression_function_body(&mut self.tokens, begin, token);
            } else {
                self.listener
                    .handle_expression_function_body(&mut self.tokens, begin, NO_TOKEN);
            }
            return token;
        }
        let mut begin = next;
        let mut statement_count = 0;
        if !self.is_a(next, TokenType::OPEN_CURLY_BRACKET) {
            // Recovery
            // If the next token is a `return` statement, assume the user forgot `=>`.
            if self.is_a(next, kw::RETURN) {
                self.report_recoverable_error(next, diag::expectedBody);
                let offset = self.tokens.char_offset(self.next(next));
                let arrow = self.tokens.synthetic_token(TokenType::FUNCTION, offset);
                next = self.rewriter().insert_token(next, arrow);
                return self.parse_expression_function_body(next, of_function_expression);
            }

            // If there is a stray simple identifier in the function expression
            // because the user is typing (e.g. `() asy => null;`)
            // then report an error, skip the token, and continue parsing.
            if self.tokens.is_keyword_or_identifier(next)
                && self.is_a(self.next(next), TokenType::FUNCTION)
            {
                self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                let arrow = self.next(next);
                return self.parse_expression_function_body(arrow, of_function_expression);
            }
            if self.tokens.is_keyword_or_identifier(next)
                && self.is_a(self.next(next), TokenType::OPEN_CURLY_BRACKET)
            {
                self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                token = next;
                next = self.next(token);
                begin = next;
                // Fall through to parse the block.
            } else {
                token = self.ensure_block(token, Some(BlockKind::functionBody));
                self.listener
                    .handle_invalid_function_body(&mut self.tokens, token);
                return self.tokens.end_group(token);
            }
        }

        let saved_loop_state = self.loop_state;
        self.loop_state = LoopState::OutsideLoop;
        self.listener
            .begin_block_function_body(&mut self.tokens, begin);
        token = next;
        while self.not_eof_or_type(TokenType::CLOSE_CURLY_BRACKET, self.next(token)) {
            let start_token = self.next(token);
            token = self.parse_statement(token);
            if self.next(token) == start_token {
                // No progress was made, so report an error and skip the token.
                let message = (diag::unexpectedToken.with_arguments)(&self.tokens, token);
                self.report_recoverable_error(token, message);
                token = self.next(token);
            }
            statement_count += 1;
        }
        token = self.next(token);
        debug_assert!(
            self.tokens.is_eof(token) || self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
        );
        self.listener
            .end_block_function_body(&mut self.tokens, statement_count, begin, token);
        self.loop_state = saved_loop_state;
        token
    }

    pub fn parse_expression_function_body(
        &mut self,
        mut token: TokenId,
        of_function_expression: bool,
    ) -> TokenId {
        debug_assert!(self.is_a(token, TokenType::FUNCTION));
        let begin = token;
        token = self.parse_expression(token);
        if !of_function_expression {
            token = self.ensure_semicolon(token);
            self.listener
                .handle_expression_function_body(&mut self.tokens, begin, token);
        } else {
            self.listener
                .handle_expression_function_body(&mut self.tokens, begin, NO_TOKEN);
        }
        if self.in_generator() {
            let message = diag::generatorReturnsValue.message();
            self.listener
                .handle_invalid_statement(&mut self.tokens, begin, &message);
        }
        token
    }

    pub fn skip_async_modifier(&self, mut token: TokenId) -> TokenId {
        let value = self.sv(self.next(token));
        if value == Some("async") || value == Some("sync") {
            token = self.next(token);
            if self.sv(self.next(token)) == Some("*") {
                token = self.next(token);
            }
        }
        token
    }

    pub fn parse_async_modifier_opt(&mut self, mut token: TokenId) -> TokenId {
        let mut async_ = NO_TOKEN;
        let mut star = NO_TOKEN;
        self.async_state = AsyncModifier::Sync;
        let mut next = self.next(token);
        if self.is_a(next, kw::ASYNC) {
            token = next;
            async_ = token;
            next = self.next(token);
            if self.is_a(next, TokenType::STAR) {
                self.async_state = AsyncModifier::AsyncStar;
                star = next;
                token = next;
            } else {
                self.async_state = AsyncModifier::Async;
            }
        } else if self.is_a(next, kw::SYNC) {
            token = next;
            async_ = token;
            next = self.next(token);
            if self.is_a(next, TokenType::STAR) {
                self.async_state = AsyncModifier::SyncStar;
                star = next;
                token = next;
            } else {
                self.report_recoverable_error(async_, diag::invalidSyncModifier);
            }
        }
        self.listener
            .handle_async_modifier(&mut self.tokens, async_, star);
        if !self.in_plain_sync() && self.is_a(self.next(token), TokenType::SEMICOLON) {
            let next = self.next(token);
            self.report_recoverable_error(next, diag::abstractNotSync);
        }
        token
    }

    pub fn parse_statement(&mut self, token: TokenId) -> TokenId {
        let depth = self.statement_depth;
        self.statement_depth += 1;
        if depth > 500 {
            return self.recover_from_stack_overflow(token);
        }
        let result = self.parse_statement_x(token);
        self.statement_depth -= 1;
        result
    }

    pub fn parse_statement_x(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        if self.tokens.kind(next) == IDENTIFIER_TOKEN {
            if self.is_a(self.next(next), TokenType::COLON) {
                return self.parse_labeled_statement(token);
            }
            return self.parse_expression_statement_or_declaration_after_modifiers(
                token, token, NO_TOKEN, NO_TOKEN, None, None,
            );
        }
        let value = self.sv(next);
        if value == Some("{") {
            // The scanner ensures that `{` always has a closing `}`.
            if self.is_patterns_feature_enabled
                && self.is_a(self.next(self.tokens.end_group(next)), TokenType::EQ)
            {
                // Expression statement beginning with a pattern assignment
                return self.parse_expression_statement(token);
            } else {
                return self.parse_block(token, BlockKind::statement);
            }
        } else if value == Some("return") {
            return self.parse_return_statement(token);
        } else if value == Some("var") || value == Some("final") {
            let var_or_final = next;
            if !is_modifier(&self.tokens, self.next(var_or_final)) {
                return self.parse_expression_statement_or_declaration_after_modifiers(
                    var_or_final,
                    token,
                    NO_TOKEN,
                    var_or_final,
                    None,
                    None,
                );
            }
            return self.parse_expression_statement_or_declaration(token, None);
        } else if value == Some("if") {
            return self.parse_if_statement(token);
        } else if value == Some("await") && self.is_a(self.next(next), kw::FOR) {
            return self.parse_for_statement(next, next);
        } else if value == Some("for") {
            return self.parse_for_statement(token, NO_TOKEN);
        } else if value == Some("rethrow") {
            return self.parse_rethrow_statement(token);
        } else if value == Some("while") {
            return self.parse_while_statement(token);
        } else if value == Some("do") {
            return self.parse_do_while_statement(token);
        } else if value == Some("try") {
            return self.parse_try_statement(token);
        } else if value == Some("switch") {
            return self.parse_switch_statement(token);
        } else if value == Some("break") {
            return self.parse_break_statement(token);
        } else if value == Some("continue") {
            return self.parse_continue_statement(token);
        } else if value == Some("assert") {
            return self.parse_assert_statement(token);
        } else if value == Some(";") {
            return self.parse_empty_statement(token);
        } else if value == Some("yield") {
            match self.async_state {
                AsyncModifier::Sync => {
                    if self.is_a(self.next(next), TokenType::COLON) {
                        return self.parse_labeled_statement(token);
                    }
                    if self.looks_like_yield_statement(token, AwaitOrYieldContext::Statement) {
                        // Recovery: looks like an expression preceded by `yield` but not
                        // inside an Async or AsyncStar context. parseYieldStatement will
                        // report the error.
                        return self.parse_yield_statement(token);
                    }
                    return self.parse_expression_statement_or_declaration(token, None);
                }
                AsyncModifier::SyncStar | AsyncModifier::AsyncStar | AsyncModifier::Async => {
                    // Recovery: parseYieldStatement will report an error in Async.
                    return self.parse_yield_statement(token);
                }
            }
        } else if value == Some("const") {
            return self.parse_expression_statement_or_const_declaration(token);
        } else if value == Some("await") {
            if self.in_plain_sync() {
                if !self.looks_like_await_expression(token, AwaitOrYieldContext::Statement) {
                    return self.parse_expression_statement_or_declaration(token, None);
                }
                // Recovery: looks like an expression preceded by `await`
                // but not inside an async context.
                // Fall through to parseExpressionStatement
                // and parseAwaitExpression will report the error.
            }
            return self.parse_expression_statement(token);
        } else if value == Some("set") && self.tokens.is_identifier(self.next(next)) {
            // Recovery: invalid use of `set` as a statement.
            self.report_recoverable_error_with_token(next, diag::unexpectedToken);
            return self.parse_statement_x(next);
        } else if self.tokens.is_identifier(next) {
            if self.is_a(self.next(next), TokenType::COLON) {
                return self.parse_labeled_statement(token);
            }
            return self.parse_expression_statement_or_declaration(token, None);
        } else {
            return self.parse_expression_statement_or_declaration(token, None);
        }
    }

    /// ```text
    /// yieldStatement:
    ///   'yield' expression? ';'
    /// ;
    /// ```
    pub fn parse_yield_statement(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let begin = token;
        debug_assert!(self.is_a(token, kw::YIELD));
        self.listener.begin_yield_statement(&mut self.tokens, begin);
        let mut star_token = NO_TOKEN;
        if self.is_a(self.next(token), TokenType::STAR) {
            token = self.next(token);
            star_token = token;
        }
        token = self.parse_expression(token);
        token = self.ensure_semicolon(token);
        if self.in_generator() {
            self.listener
                .end_yield_statement(&mut self.tokens, begin, star_token, token);
        } else {
            self.report_recoverable_error(begin, diag::yieldNotGenerator);
            self.listener.end_invalid_yield_statement(
                &mut self.tokens,
                begin,
                star_token,
                token,
                &diag::yieldNotGenerator,
            );
        }
        token
    }

    /// ```text
    /// returnStatement:
    ///   'return' expression? ';'
    /// ;
    /// ```
    pub fn parse_return_statement(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let begin = token;
        debug_assert!(self.is_a(token, kw::RETURN));
        self.listener
            .begin_return_statement(&mut self.tokens, begin);
        let next = self.next(token);
        if self.is_a(next, TokenType::SEMICOLON) {
            self.listener
                .end_return_statement(&mut self.tokens, false, begin, next);
            return next;
        }
        token = self.parse_expression(token);
        token = self.ensure_semicolon(token);
        self.listener
            .end_return_statement(&mut self.tokens, true, begin, token);
        if self.in_generator() {
            let message = diag::generatorReturnsValue.message();
            self.listener
                .handle_invalid_statement(&mut self.tokens, begin, &message);
        }
        token
    }

    /// ```text
    /// label:
    ///   identifier ':'
    /// ;
    /// ```
    pub fn parse_label(&mut self, token: TokenId) -> TokenId {
        debug_assert!(self.tokens.is_identifier(self.next(token)));
        let token = self.ensure_identifier(token, IdentifierContext::labelDeclaration);
        let token = self.next(token);
        debug_assert!(self.is_a(token, TokenType::COLON));
        self.listener.handle_label(&mut self.tokens, token);
        token
    }

    /// ```text
    /// statement:
    ///   label* nonLabelledStatement
    /// ;
    /// ```
    pub fn parse_labeled_statement(&mut self, mut token: TokenId) -> TokenId {
        let mut next;
        debug_assert!(self.tokens.is_identifier(self.next(token)));
        let mut label_count = 0;
        loop {
            token = self.parse_label(token);
            next = self.next(token);
            label_count += 1;
            if !(self.tokens.is_identifier(next) && self.is_a(self.next(next), TokenType::COLON)) {
                break;
            }
        }
        self.listener
            .begin_labeled_statement(&mut self.tokens, next, label_count);
        token = self.parse_statement(token);
        self.listener
            .end_labeled_statement(&mut self.tokens, label_count);
        token
    }

    /// ```text
    /// expressionStatement:
    ///   expression? ';'
    /// ;
    /// ```
    ///
    /// Note: This method can fail to make progress. If there is neither an
    /// expression nor a semi-colon, then a synthetic identifier and synthetic
    /// semicolon will be inserted before [token] and the semicolon returned.
    pub fn parse_expression_statement(&mut self, mut token: TokenId) -> TokenId {
        // TODO(brianwilkerson): If the next token is not the start of a valid
        // expression, then this method shouldn't report that we have an expression
        // statement.
        let begin_token = self.next(token);
        token = self.parse_expression(token);
        token = self.ensure_semicolon(token);
        self.listener
            .handle_expression_statement(&mut self.tokens, begin_token, token);
        token
    }

    pub fn parse_expression(&mut self, mut token: TokenId) -> TokenId {
        if self.kind != ParserKind::Parser {
            return self.skip_expression(token);
        }
        let depth = self.expression_depth;
        self.expression_depth += 1;
        if depth > 500 {
            // This happens in degenerate programs, for example, with a lot of nested
            // list literals. This is provoked by, for example, the language test
            // deep_nesting1_negative_test.
            let mut next = self.next(token);
            self.report_recoverable_error(next, diag::stackOverflow);

            // Recovery
            let end_group = self.tokens.end_group(next);
            if end_group != NO_TOKEN {
                while !self.tokens.is_eof(next) && next != end_group {
                    token = next;
                    next = self.next(token);
                }
            } else {
                while !(self.is_a(next, TokenType::CLOSE_PAREN)
                    || self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET)
                    || self.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                    || self.is_a(next, TokenType::SEMICOLON))
                {
                    token = next;
                    next = self.next(token);
                }
            }
            if !self.tokens.is_eof(token) {
                token = self.rewriter().insert_synthetic_identifier(token);
                self.listener.handle_identifier(
                    &mut self.tokens,
                    token,
                    IdentifierContext::expression,
                );
            }
        } else {
            token = self.parse_expression_impl(token, true);
        }
        self.expression_depth -= 1;
        token
    }

    pub fn parse_expression_without_cascade(&mut self, token: TokenId) -> TokenId {
        self.parse_expression_impl(token, false)
    }

    /// `_parseExpression`.
    #[inline]
    fn parse_expression_impl(&mut self, token: TokenId, allow_cascades: bool) -> TokenId {
        if self.is_patterns_feature_enabled && self.looks_like_outer_pattern_equals(token) {
            return if allow_cascades {
                self.parse_pattern_assignment(token)
            } else {
                self.parse_pattern_assignment_impl(token, false)
            };
        }
        if self.is_a(self.next(token), kw::THROW) {
            self.parse_throw_expression(token, allow_cascades)
        } else {
            self.parse_precedence_expression(
                token,
                ASSIGNMENT_PRECEDENCE,
                allow_cascades,
                ConstantPatternContext::none,
            )
        }
    }

    pub fn can_parse_as_conditional(&mut self, question: TokenId) -> bool {
        // We want to check if we can parse, not send events and permanently change
        // the token stream. This is set up here and reverted at the end.
        let original_listener =
            std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
        let original_rewriter = self
            .cached_rewriter
            .replace(AnyRewriter::Undoable(UndoableTokenStreamRewriter::default()));

        let mut is_conditional = false;

        let after_expression1 = self.parse_expression_without_cascade(question);
        if !self.listener_as::<NullListener>().has_errors
            && self.is_a(self.next(after_expression1), TokenType::COLON)
        {
            let colon = self.next(after_expression1);
            self.parse_expression_without_cascade(colon);
            if !self.listener_as::<NullListener>().has_errors {
                is_conditional = true;
            }
        }

        // Undo all changes and reset.
        if let Some(AnyRewriter::Undoable(mut undoable)) = self.cached_rewriter.take() {
            undoable.undo(&mut self.tokens);
        }
        self.listener = original_listener;
        self.cached_rewriter = original_rewriter;

        is_conditional
    }

    pub fn parse_conditional_expression_rest(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let question = token;
        debug_assert!(self.is_a(question, TokenType::QUESTION));
        self.listener
            .begin_conditional_expression(&mut self.tokens, token);
        token = self.parse_expression_without_cascade(token);
        let colon = self.ensure_colon(token);
        self.listener
            .handle_conditional_expression_colon(&mut self.tokens);
        token = self.parse_expression_without_cascade(colon);
        self.listener
            .end_conditional_expression(&mut self.tokens, question, colon, token);
        token
    }

    /// Returns `true` if [token] is the start of a dot shorthand.
    fn is_dot_shorthand(&self, token: TokenId) -> bool {
        if self.is_a(token, TokenType::PERIOD)
            && (self.tokens.is_identifier(self.next(token)) || self.is_a(self.next(token), kw::NEW))
        {
            return true;
        }
        if self.is_a(token, kw::CONST) && self.is_a(self.next(token), TokenType::PERIOD) {
            let period = self.next(token);
            if self.tokens.is_identifier(self.next(period)) || self.is_a(self.next(period), kw::NEW)
            {
                return true;
            }
        }
        false
    }

    pub fn parse_precedence_expression(
        &mut self,
        mut token: TokenId,
        precedence: i32,
        allow_cascades: bool,
        constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        debug_assert!(precedence >= 1);
        debug_assert!(precedence <= SELECTOR_PRECEDENCE);

        let next_token = self.next(token);
        let is_dot_shorthand = self.is_dot_shorthand(next_token);
        if !is_dot_shorthand {
            if self.is_a(next_token, kw::CONST)
                && self.is_a(self.next(next_token), TokenType::PERIOD)
            {
                // Recovery: `const .` without an identifier.
                let const_keyword = next_token;
                let dot = self.next(next_token);
                self.listener
                    .begin_const_dot_shorthand(&mut self.tokens, const_keyword);
                token = self.ensure_identifier(dot, IdentifierContext::expressionContinuation);
                self.listener
                    .handle_dot_shorthand_head(&mut self.tokens, dot);
                self.listener
                    .end_const_dot_shorthand(&mut self.tokens, const_keyword);
                self.listener
                    .handle_dot_shorthand_context(&mut self.tokens, dot);
                return token;
            }
            if self.is_a(next_token, TokenType::PERIOD) {
                // Recovery: `.` without an identifier.
                token =
                    self.ensure_identifier(next_token, IdentifierContext::expressionContinuation);
                self.listener
                    .handle_dot_shorthand_head(&mut self.tokens, next_token);
                self.listener
                    .handle_dot_shorthand_context(&mut self.tokens, next_token);
            } else {
                token =
                    self.parse_unary_expression(token, allow_cascades, constant_pattern_context);
            }
        }
        let mut bang_token = token;
        if self.is_a(self.next(token), TokenType::BANG) {
            bang_token = self.next(token);
        }
        let mut type_arg = compute_method_type_arguments(&mut self.tokens, bang_token);
        if type_arg != noTypeParamOrArg {
            // For example a(b)<T>(c), where token is before '<'.
            if self.is_a(bang_token, TokenType::BANG) {
                self.listener
                    .handle_non_null_assert_expression(&mut self.tokens, bang_token);
            }
            token = type_arg.parse_arguments(bang_token, self);
            if !self.is_a(self.next(token), TokenType::OPEN_PAREN) {
                if constant_pattern_context != ConstantPatternContext::none {
                    let next = self.next(bang_token);
                    self.report_recoverable_error(next, diag::invalidConstantPatternGeneric);
                }
                let next_28 = self.tokens.next(bang_token);
                self.listener
                    .handle_type_argument_application(&mut self.tokens, next_28);
                type_arg = noTypeParamOrArg;
            }
        }

        token = self.parse_dot_shorthand(
            token,
            next_token,
            is_dot_shorthand,
            allow_cascades,
            type_arg.clone(),
            constant_pattern_context,
        );

        self.parse_precedence_expression_loop(
            precedence,
            allow_cascades,
            type_arg,
            token,
            constant_pattern_context,
            false,
        )
    }

    /// Parses a dot shorthand when [isDotShorthand] is `true`.
    fn parse_dot_shorthand(
        &mut self,
        mut token: TokenId,
        next_token: TokenId,
        is_dot_shorthand: bool,
        allow_cascades: bool,
        type_arg: TypeParamOrArgInfo,
        constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        if !is_dot_shorthand {
            return token;
        }

        if self.is_a(next_token, kw::CONST) {
            // const .foo() or const .new()
            let dot = self.next(next_token);
            self.listener
                .begin_const_dot_shorthand(&mut self.tokens, next_token);
            token = self.parse_primary(
                dot,
                IdentifierContext::expressionContinuation,
                constant_pattern_context,
            );
            self.listener
                .handle_dot_shorthand_head(&mut self.tokens, dot);
            self.listener
                .end_const_dot_shorthand(&mut self.tokens, next_token);
            token = self.parse_precedence_expression_loop(
                SELECTOR_PRECEDENCE,
                allow_cascades,
                type_arg,
                token,
                constant_pattern_context,
                false,
            );
            self.listener
                .handle_dot_shorthand_context(&mut self.tokens, dot);
        } else {
            // .foo or .new
            let dot = self.next(token);
            token = self.parse_precedence_expression_loop(
                SELECTOR_PRECEDENCE,
                allow_cascades,
                type_arg,
                token,
                constant_pattern_context,
                true,
            );
            let next = self.next(token);
            if self.is_a(next, TokenType::BANG) {
                self.listener
                    .handle_non_null_assert_expression(&mut self.tokens, next);
                token = next;
            }
            self.listener
                .handle_dot_shorthand_context(&mut self.tokens, dot);
        }
        token
    }
}

/// The rewriter a parser uses: upstream assigns either kind to
/// `cachedRewriter`.
#[derive(Debug)]
pub enum AnyRewriter {
    Impl(TokenStreamRewriterImpl),
    Undoable(UndoableTokenStreamRewriter),
}

impl TokenStreamRewriter for AnyRewriter {
    fn set_next(&mut self, s: &mut TokenStore, set_on: TokenId, next_token: TokenId) -> TokenId {
        match self {
            AnyRewriter::Impl(r) => r.set_next(s, set_on, next_token),
            AnyRewriter::Undoable(r) => r.set_next(s, set_on, next_token),
        }
    }

    fn set_end_group(&mut self, s: &mut TokenStore, set_on: TokenId, end_group: TokenId) {
        match self {
            AnyRewriter::Impl(r) => r.set_end_group(s, set_on, end_group),
            AnyRewriter::Undoable(r) => r.set_end_group(s, set_on, end_group),
        }
    }

    fn set_offset(&mut self, s: &mut TokenStore, set_on: TokenId, offset: i32) {
        match self {
            AnyRewriter::Impl(r) => r.set_offset(s, set_on, offset),
            AnyRewriter::Undoable(r) => r.set_offset(s, set_on, offset),
        }
    }

    fn set_preceding_comments(&mut self, s: &mut TokenStore, set_on: TokenId, comment: TokenId) {
        match self {
            AnyRewriter::Impl(r) => r.set_preceding_comments(s, set_on, comment),
            AnyRewriter::Undoable(r) => r.set_preceding_comments(s, set_on, comment),
        }
    }

    fn set_previous(&mut self, s: &mut TokenStore, set_on: TokenId, previous: TokenId) {
        match self {
            AnyRewriter::Impl(r) => r.set_previous(s, set_on, previous),
            AnyRewriter::Undoable(r) => r.set_previous(s, set_on, previous),
        }
    }
}

impl Parser {
    fn parse_precedence_expression_loop(
        &mut self,
        precedence: i32,
        allow_cascades: bool,
        mut type_arg: TypeParamOrArgInfo,
        mut token: TokenId,
        mut constant_pattern_context: ConstantPatternContext,
        mut is_dot_shorthand: bool,
    ) -> TokenId {
        let mut next = self.next(token);
        let mut type_ = self.tokens.type_(next);
        let mut token_level = self.compute_precedence(next, false);
        if constant_pattern_context != ConstantPatternContext::none {
            // For constant patterns we need to stop before `!` and `as` operators,
            // since these have special meaning in patterns.
            if type_ == TokenType::BANG {
                if token_level == POSTFIX_PRECEDENCE {
                    return token;
                } else if self.is_a(self.next(next), TokenType::QUESTION) {
                    return token;
                }
            } else if type_ == TokenType::AS {
                return token;
            }
        }
        constant_pattern_context = self.check_for_invalid_constant_pattern_operator(
            constant_pattern_context,
            precedence,
            token,
            next,
            type_,
            token_level,
        );
        if token_level < precedence {
            if self.recover_at_precedence_level && !self.currently_recovering {
                // Attempt recovery
                if self.attempt_precedence_level_recovery(
                    token,
                    precedence,
                    -1,
                    allow_cascades,
                    type_arg.clone(),
                ) {
                    // Recovered - try again at same level with the replacement token.
                    return self.parse_precedence_expression_loop(
                        precedence,
                        allow_cascades,
                        type_arg,
                        token,
                        ConstantPatternContext::none,
                        false,
                    );
                }
            }
            return token;
        }

        let mut level = token_level;
        let mut last_binary_expression_level = -1;
        let mut last_cascade = NO_TOKEN;
        let mut cascade_section_count = 0;
        loop {
            let mut operator = next;
            if cascade_section_count > 0 && token_level != CASCADE_PRECEDENCE {
                self.listener
                    .handle_cascade_expression_end(&mut self.tokens, cascade_section_count);
                cascade_section_count = 0;
            }
            if token_level == CASCADE_PRECEDENCE {
                if !allow_cascades {
                    return token;
                } else if last_cascade != NO_TOKEN
                    && self.is_a(next, TokenType::QUESTION_PERIOD_PERIOD)
                {
                    self.report_recoverable_error(next, diag::nullAwareCascadeOutOfOrder);
                }
                last_cascade = next;
                token = self.parse_cascade_expression(token);
                cascade_section_count += 1;
            } else if token_level == ASSIGNMENT_PRECEDENCE {
                // Right associative, so we recurse at the same precedence
                // level.
                let mut next = self.next(token);
                if self.is_a(self.next(next), TokenType::GT_EQ) {
                    // Special case use of triple-shift in cases where it isn't
                    // enabled.
                    let after = self.next(next);
                    self.report_experiment_not_enabled(ExperimentalFlag::tripleShift, next, after);
                    debug_assert!(next == operator);
                    next = self.rewriter().replace_next_tokens_with_synthetic_token(
                        token,
                        2,
                        TokenType::GT_GT_GT_EQ,
                    );
                    operator = next;
                }
                token = self.parse_expression_impl(next, allow_cascades);
                self.listener
                    .handle_assignment_expression(&mut self.tokens, operator, token);
            } else if token_level == POSTFIX_PRECEDENCE {
                if type_ == TokenType::PLUS_PLUS || type_ == TokenType::MINUS_MINUS {
                    let next_27 = self.tokens.next(token);
                    self.listener
                        .handle_unary_postfix_assignment_expression(&mut self.tokens, next_27);
                    token = next;
                } else if type_ == TokenType::BANG {
                    self.listener
                        .handle_non_null_assert_expression(&mut self.tokens, next);
                    token = next;
                }
            } else if token_level == SELECTOR_PRECEDENCE {
                if type_ == TokenType::PERIOD || type_ == TokenType::QUESTION_PERIOD {
                    // Left associative, so we recurse at the next higher precedence
                    // level. However, SELECTOR_PRECEDENCE is the highest level, so we
                    // should just call [parseUnaryExpression] directly. However, a
                    // unary expression isn't legal after a period, so we call
                    // [parsePrimary] instead.
                    let dot = self.next(token);
                    let after_dot = self.next(dot);
                    if self.is_anonymous_methods_feature_enabled
                        && self.begins_anonymous_method(after_dot)
                    {
                        token = self.parse_anonymous_method(dot, after_dot);
                    } else {
                        token = self.parse_primary(
                            dot,
                            IdentifierContext::expressionContinuation,
                            constant_pattern_context,
                        );
                        if is_dot_shorthand {
                            self.listener
                                .handle_dot_shorthand_head(&mut self.tokens, dot);
                            is_dot_shorthand = false;
                        } else {
                            self.listener.handle_dot_access(
                                &mut self.tokens,
                                operator,
                                token,
                                type_ == TokenType::QUESTION_PERIOD,
                            );
                        }
                        let mut bang_token = token;
                        if self.is_a(self.next(token), TokenType::BANG) {
                            bang_token = self.next(token);
                        }
                        type_arg = compute_method_type_arguments(&mut self.tokens, bang_token);
                        if type_arg != noTypeParamOrArg {
                            // For example a(b)..<T>(c), where token is '<'.
                            if self.is_a(bang_token, TokenType::BANG) {
                                self.listener.handle_non_null_assert_expression(
                                    &mut self.tokens,
                                    bang_token,
                                );
                            }
                            token = type_arg.parse_arguments(bang_token, self);
                            if !self.is_a(self.next(token), TokenType::OPEN_PAREN) {
                                if constant_pattern_context != ConstantPatternContext::none {
                                    let next = self.next(bang_token);
                                    self.report_recoverable_error(
                                        next,
                                        diag::invalidConstantPatternGeneric,
                                    );
                                }
                                let next_26 = self.tokens.next(bang_token);
                                self.listener
                                    .handle_type_argument_application(&mut self.tokens, next_26);
                                type_arg = noTypeParamOrArg;
                            }
                        }
                    }
                } else if type_ == TokenType::OPEN_PAREN || type_ == TokenType::OPEN_SQUARE_BRACKET
                {
                    token = self.parse_argument_or_index_star(token, type_arg.clone(), false);
                } else if type_ == TokenType::QUESTION {
                    // We have determined selector precedence so this is a null-aware
                    // bracket operator.
                    token = self.parse_argument_or_index_star(token, type_arg.clone(), true);
                } else if type_ == TokenType::INDEX {
                    self.rewrite_square_brackets(token);
                    token = self.parse_argument_or_index_star(token, noTypeParamOrArg, false);
                } else if type_ == TokenType::BANG {
                    let next_25 = self.tokens.next(token);
                    self.listener
                        .handle_non_null_assert_expression(&mut self.tokens, next_25);
                    token = next;
                } else {
                    // Recovery
                    let next = self.next(token);
                    self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                    token = next;
                }
            } else if type_ == TokenType::IS {
                token = self.parse_is_operator_rest(token);
            } else if type_ == TokenType::AS {
                token = self.parse_as_operator_rest(token);
            } else if type_ == TokenType::QUESTION {
                token = self.parse_conditional_expression_rest(token);
            } else {
                if level == EQUALITY_PRECEDENCE || level == RELATIONAL_PRECEDENCE {
                    // We don't allow (a == b == c) or (a < b < c).
                    if last_binary_expression_level == level {
                        // Report an error, then continue parsing as if it is legal.
                        self.report_recoverable_error(next, diag::equalityCannotBeEqualityOperand);
                    } else {
                        // Set a flag to catch subsequent binary expressions of this type.
                        last_binary_expression_level = level;
                    }
                }
                if self.is_a(next, TokenType::GT_GT)
                    && self.tokens.char_end(next) == self.tokens.char_offset(self.next(next))
                {
                    if self.is_a(self.next(next), TokenType::GT) {
                        // Special case use of triple-shift in cases where it isn't
                        // enabled.
                        let after = self.next(next);
                        self.report_experiment_not_enabled(
                            ExperimentalFlag::tripleShift,
                            next,
                            after,
                        );
                        debug_assert!(next == operator);
                        next = self.rewriter().replace_next_tokens_with_synthetic_token(
                            token,
                            2,
                            TokenType::GT_GT_GT,
                        );
                        operator = next;
                    }
                }
                self.listener
                    .begin_binary_expression(&mut self.tokens, next);
                // Left associative, so we recurse at the next higher
                // precedence level.
                let after = self.next(token);
                token = self.parse_precedence_expression(
                    after,
                    level + 1,
                    allow_cascades,
                    ConstantPatternContext::none,
                );
                self.listener
                    .end_binary_expression(&mut self.tokens, operator, token);
            }
            next = self.next(token);
            type_ = self.tokens.type_(next);
            token_level = self.compute_precedence(next, false);
            if constant_pattern_context != ConstantPatternContext::none {
                // For constant patterns we need to stop before `!` and `as` operators,
                // since these have special meaning in patterns.
                if type_ == TokenType::BANG {
                    if token_level == POSTFIX_PRECEDENCE {
                        break;
                    } else if self.is_a(self.next(next), TokenType::QUESTION) {
                        break;
                    }
                } else if type_ == TokenType::AS {
                    break;
                }
            }
            constant_pattern_context = self.check_for_invalid_constant_pattern_operator(
                constant_pattern_context,
                precedence,
                token,
                next,
                type_,
                token_level,
            );
            if self.recover_at_precedence_level && !self.currently_recovering {
                // Attempt recovery
                if self.attempt_precedence_level_recovery(
                    token,
                    precedence,
                    level,
                    allow_cascades,
                    type_arg.clone(),
                ) {
                    // Recovered - try again at same level with the replacement token.
                    next = self.next(token);
                    type_ = self.tokens.type_(next);
                    token_level = self.compute_precedence(next, false);
                }
            }
            if token_level <= level {
                if token_level < precedence {
                    break;
                }
                level = token_level;
            } else {
                break;
            }
        }
        if cascade_section_count > 0 {
            self.listener
                .handle_cascade_expression_end(&mut self.tokens, cascade_section_count);
        }
        token
    }

    /// Checks whether the operator [next] (of [type] and [tokenLevel]) is
    /// valid in a constant pattern, reporting an error if not. Returns the
    /// context to use from here on.
    #[inline]
    fn check_for_invalid_constant_pattern_operator(
        &mut self,
        constant_pattern_context: ConstantPatternContext,
        precedence: i32,
        token: TokenId,
        next: TokenId,
        type_: &TokenType,
        token_level: i32,
    ) -> ConstantPatternContext {
        if constant_pattern_context != ConstantPatternContext::none
            && precedence <= token_level
            && token_level < SELECTOR_PRECEDENCE
        {
            // If we are parsing a constant pattern, only [SELECTOR_PRECEDENCE] is
            // supported but we allow for parsing [precedence] level operators for
            // recovery.
            if constant_pattern_context == ConstantPatternContext::explicit {
                self.report_recoverable_error(token, diag::invalidConstantPatternConstPrefix);
            } else if token_level <= MULTIPLICATIVE_PRECEDENCE {
                self.report_recoverable_error(
                    next,
                    (diag::invalidConstantPatternBinary.with_arguments)(type_.lexeme),
                );
            } else {
                debug_assert!(
                    token_level == POSTFIX_PRECEDENCE || token_level == PREFIX_PRECEDENCE,
                    "Unexpected precedence level for {type_}: {token_level}"
                );
            }
            return ConstantPatternContext::none;
        }
        constant_pattern_context
    }

    /// Returns `true` if [token] begins an anonymous method.
    fn begins_anonymous_method(&self, token: TokenId) -> bool {
        if self.is_a(token, TokenType::OPEN_CURLY_BRACKET) || self.is_a(token, TokenType::FUNCTION)
        {
            return true;
        }
        if self.is_a(token, TokenType::OPEN_PAREN) {
            let matching_parenthesis = self.tokens.end_group(token);
            if matching_parenthesis != NO_TOKEN {
                let after_match = self.next(matching_parenthesis);
                if after_match != NO_TOKEN
                    && (self.is_a(after_match, TokenType::OPEN_CURLY_BRACKET)
                        || self.is_a(after_match, TokenType::FUNCTION))
                {
                    return true;
                }
            }
        }
        false
    }

    /// Parses an anonymous method after [punctuation] (`.`, `?.`, `..` or
    /// `?..`), where [afterPunctuation] is its first token.
    fn parse_anonymous_method(
        &mut self,
        punctuation: TokenId,
        after_punctuation: TokenId,
    ) -> TokenId {
        let mut current_token;
        self.listener
            .begin_anonymous_method_invocation(&mut self.tokens, punctuation);
        if self.is_a(after_punctuation, TokenType::OPEN_PAREN) {
            current_token = self.parse_formal_parameters(punctuation, MemberKind::AnonymousMethod);
        } else {
            self.listener
                .handle_implicit_formal_parameters(&mut self.tokens, punctuation);
            current_token = punctuation;
        }
        let after_parameters = self.next(current_token);
        let mut function_definition = NO_TOKEN;
        let is_expression;
        if self.is_a(after_parameters, TokenType::OPEN_CURLY_BRACKET) {
            is_expression = false;
            current_token = self.parse_block(current_token, BlockKind::functionBody);
        } else if self.is_a(after_parameters, TokenType::FUNCTION) {
            is_expression = true;
            function_definition = after_parameters;
            current_token = self.parse_expression_without_cascade(after_parameters);
        } else {
            // Recovery
            self.report_recoverable_error(
                after_parameters,
                (diag::expectedButGot2.with_arguments)("{", "=>"),
            );
            function_definition = self
                .rewriter()
                .insert_synthetic_token(current_token, TokenType::FUNCTION);
            is_expression = true;
            current_token = self.parse_expression_without_cascade(function_definition);
        }
        self.listener.end_anonymous_method_invocation(
            &mut self.tokens,
            punctuation,
            function_definition,
            current_token,
            is_expression,
        );
        current_token
    }

    /// Attempt a recovery where [token.next] is replaced.
    fn attempt_precedence_level_recovery(
        &mut self,
        token: TokenId,
        precedence: i32,
        current_level: i32,
        allow_cascades: bool,
        type_arg: TypeParamOrArgInfo,
    ) -> bool {
        // Attempt recovery.
        self.recover_at_precedence_level = false;
        let lexeme = self.tokens.lexeme_string(self.next(token));
        let Some(replacements) = token_recovery_replacements(&lexeme) else {
            debug_assert!(false, "Faulty logic for _recoverAtPrecedenceLevel");
            return false;
        };
        for &replacement in replacements {
            if current_level >= 0 {
                // Check that the new precedence and existing precedence matches.
                let new_level = replacement.precedence;
                if new_level > current_level {
                    continue;
                }
            }

            // Errors should've been reported anyway --- we're replacing what isn't
            // tokens that can be consumed.
            self.currently_recovering = true;
            let original_listener =
                std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
            let original_rewriter = self
                .cached_rewriter
                .replace(AnyRewriter::Undoable(UndoableTokenStreamRewriter::default()));
            self.rewriter()
                .replace_next_token_with_synthetic_token(token, replacement);
            let mut accept_recovery = false;
            let after_expression = self.parse_precedence_expression_loop(
                precedence,
                allow_cascades,
                type_arg.clone(),
                token,
                ConstantPatternContext::none,
                false,
            );
            let after_expression_next = self.next(after_expression);

            if !self.listener_as::<NullListener>().has_errors
                && token != after_expression
                && (self.is_a(after_expression_next, TokenType::SEMICOLON)
                    || self.is_a(after_expression_next, TokenType::COMMA)
                    || self.is_a(after_expression_next, TokenType::CLOSE_PAREN)
                    || self.is_a(after_expression_next, TokenType::OPEN_CURLY_BRACKET)
                    || self.is_a(after_expression_next, TokenType::CLOSE_CURLY_BRACKET)
                    || self.is_a(after_expression_next, TokenType::BAR)
                    || self.is_a(after_expression_next, TokenType::BAR_BAR)
                    || self.is_a(after_expression_next, TokenType::AMPERSAND)
                    || self.is_a(after_expression_next, TokenType::AMPERSAND_AMPERSAND)
                    || self.is_a(after_expression_next, TokenType::EOF)
                    || (self.is_a(after_expression_next, TokenType::IDENTIFIER)
                        && token_recovery_replacements(
                            &self.tokens.lexeme_string(after_expression_next),
                        )
                        .is_some()))
            {
                // Seems good!
                accept_recovery = true;
            }

            // Undo all changes and reset.
            self.currently_recovering = false;
            self.recover_at_precedence_level = false;
            if let Some(AnyRewriter::Undoable(mut undoable)) = self.cached_rewriter.take() {
                undoable.undo(&mut self.tokens);
            }
            self.listener = original_listener;
            self.cached_rewriter = original_rewriter;

            if accept_recovery {
                // Report and redo recovery.
                let next = self.next(token);
                let message = (diag::binaryOperatorWrittenOut.with_arguments)(
                    &self.tokens.lexeme_string(next),
                    replacement.lexeme,
                );
                self.report_recoverable_error(next, message);
                self.rewriter()
                    .replace_next_token_with_synthetic_token(token, replacement);
                return true;
            }
        }
        false
    }

    fn compute_precedence(&mut self, token: TokenId, for_pattern: bool) -> i32 {
        let type_ = self.tokens.type_(token);
        if type_ == TokenType::BANG {
            // The '!' has prefix precedence but here it's being used as a
            // postfix operator to assert the expression has a non-null value.
            let next_type = self.tokens.type_(self.next(token));
            if next_type == TokenType::PERIOD
                || next_type == TokenType::QUESTION
                || next_type == TokenType::OPEN_PAREN
                || next_type == TokenType::OPEN_SQUARE_BRACKET
                || next_type == TokenType::QUESTION_PERIOD
            {
                return SELECTOR_PRECEDENCE;
            }
            return POSTFIX_PRECEDENCE;
        } else if type_ == TokenType::GT_GT {
            // ">>" followed by ">=" (with no space between tokens) should be
            // interpreted as ">>>=".
            let next_type = self.tokens.type_(self.next(token));
            if next_type == TokenType::GT_EQ
                && self.tokens.char_end(token) == self.tokens.offset(self.next(token))
            {
                return TokenType::GT_GT_GT_EQ.precedence;
            }
        } else if type_ == TokenType::QUESTION {
            if for_pattern {
                // In a pattern, `?` is a postfix operator.
                return SELECTOR_PRECEDENCE;
            } else if self.is_a(self.next(token), TokenType::OPEN_SQUARE_BRACKET) {
                // If the question mark is followed by an open bracket, then it's
                // either a null-aware index or a conditional expression.
                let is_conditional = self.can_parse_as_conditional(token);
                if !is_conditional {
                    return SELECTOR_PRECEDENCE;
                }
            }
        } else if type_ == TokenType::IDENTIFIER {
            // An identifier is never an operator, but if it's one of the special
            // cases we recover from (e.g. `and` instead of `&&`) we flag it.
            if !for_pattern
                && !self.currently_recovering
                && token_recovery_replacements(&self.tokens.lexeme_string(token)).is_some()
            {
                // Something like "a and b".
                self.recover_at_precedence_level = true;
            }
        }

        type_.precedence
    }
}

/// `Parser._tokenRecoveryReplacements`.
fn token_recovery_replacements(lexeme: &str) -> Option<&'static [&'static TokenType]> {
    match lexeme {
        "xor" => Some(&[TokenType::CARET]),
        "and" => Some(&[TokenType::AMPERSAND, TokenType::AMPERSAND_AMPERSAND]),
        "or" => Some(&[TokenType::BAR, TokenType::BAR_BAR]),
        "shl" => Some(&[TokenType::LT_LT]),
        "shr" => Some(&[TokenType::GT_GT]),
        _ => None,
    }
}

impl Parser {
    pub fn parse_cascade_expression(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let cascade_operator = token;
        debug_assert!(
            self.is_a(cascade_operator, TokenType::PERIOD_PERIOD)
                || self.is_a(cascade_operator, TokenType::QUESTION_PERIOD_PERIOD)
        );
        self.listener
            .begin_cascade(&mut self.tokens, cascade_operator);
        let after_dots = self.next(token);
        if self.is_a(after_dots, TokenType::OPEN_SQUARE_BRACKET) {
            // No access, the cascade is an index expression.
            token = self.parse_argument_or_index_star(token, noTypeParamOrArg, false);
        } else if self.is_anonymous_methods_feature_enabled
            && self.begins_anonymous_method(after_dots)
        {
            token = self.parse_anonymous_method(cascade_operator, after_dots);
        } else {
            token = self.parse_send(
                token,
                IdentifierContext::expressionContinuation,
                ConstantPatternContext::none,
            );
            let is_null_aware = self.is_a(cascade_operator, TokenType::QUESTION_PERIOD_PERIOD);
            self.listener.handle_cascade_access(
                &mut self.tokens,
                cascade_operator,
                token,
                is_null_aware,
            );
        }
        let mut next = self.next(token);
        let mut mark;
        loop {
            mark = token;
            if self.is_a(next, TokenType::PERIOD) || self.is_a(next, TokenType::QUESTION_PERIOD) {
                let is_null_aware = self.is_a(next, TokenType::QUESTION_PERIOD);
                let period = next;
                let after_period = self.next(period);
                if self.is_anonymous_methods_feature_enabled
                    && self.begins_anonymous_method(after_period)
                {
                    token = self.parse_anonymous_method(period, after_period);
                } else {
                    token = self.parse_send(
                        next,
                        IdentifierContext::expressionContinuation,
                        ConstantPatternContext::none,
                    );
                    next = self.next(token);
                    self.listener
                        .handle_dot_access(&mut self.tokens, period, token, is_null_aware);
                }
            } else if self.is_a(next, TokenType::BANG) {
                self.listener
                    .handle_non_null_assert_expression(&mut self.tokens, next);
                token = next;
                next = self.next(token);
            }
            let mut type_arg = compute_method_type_arguments(&mut self.tokens, token);
            if type_arg != noTypeParamOrArg {
                // For example a(b)..<T>(c), where token is '<'.
                token = type_arg.parse_arguments(token, self);
                next = self.next(token);
                if !self.is_a(next, TokenType::OPEN_PAREN) {
                    let next_24 = self.tokens.next(token);
                    self.listener
                        .handle_type_argument_application(&mut self.tokens, next_24);
                    type_arg = noTypeParamOrArg;
                }
            }
            let next_type = self.tokens.type_(next);
            if next_type == TokenType::INDEX {
                // If we don't split the '[]' here we will stop parsing it as a cascade
                // and either split it later (parsing it wrong) or inserting ; before it
                // (also wrong).
                // See also https://github.com/dart-lang/sdk/issues/42267.
                self.rewrite_square_brackets(token);
            }
            token = self.parse_argument_or_index_star(token, type_arg, false);
            next = self.next(token);
            if mark == token {
                break;
            }
        }

        if self.tokens.type_(next).precedence == ASSIGNMENT_PRECEDENCE {
            let assignment = next;
            token = self.parse_expression_without_cascade(next);
            self.listener
                .handle_assignment_expression(&mut self.tokens, assignment, token);
        }
        self.listener.end_cascade(&mut self.tokens);
        token
    }

    pub fn parse_unary_expression(
        &mut self,
        mut token: TokenId,
        allow_cascades: bool,
        mut constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        let value = self.sv(self.next(token));
        // Prefix:
        if value == Some("await") {
            if self.in_plain_sync() {
                if !self.looks_like_await_expression(token, AwaitOrYieldContext::UnaryExpression) {
                    return self.parse_primary(
                        token,
                        IdentifierContext::expression,
                        ConstantPatternContext::none,
                    );
                }
                // Recovery: Looks like an expression preceded by `await`
                // but not inside an async context.
                // Fall through to parseAwaitExpression
                // and it will report the error.
            }
            return self.parse_await_expression(token, allow_cascades);
        } else if value == Some("+") {
            // Dart no longer allows prefix-plus.
            let offset = self.tokens.offset(self.next(token));
            let index = self.tokens.add_string(Vec::new());
            let identifier = self.tokens.synthetic_string_token(
                TokenType::IDENTIFIER,
                crate::scanner::token::Lexeme::Owned(index),
                offset,
                None,
            );
            self.rewrite_and_recover(token, diag::unsupportedPrefixPlus, identifier);
            return self.parse_primary(
                token,
                IdentifierContext::expression,
                constant_pattern_context,
            );
        } else if value == Some("!") || value == Some("~") {
            let operator = self.next(token);
            if constant_pattern_context != ConstantPatternContext::none {
                self.report_recoverable_error(
                    operator,
                    (diag::invalidConstantPatternUnary.with_arguments)(value.unwrap()),
                );
            }
            // Right associative, so we recurse at the same precedence
            // level.
            token = self.parse_precedence_expression(
                operator,
                POSTFIX_PRECEDENCE,
                allow_cascades,
                ConstantPatternContext::none,
            );
            self.listener
                .handle_unary_prefix_expression(&mut self.tokens, operator);
            return token;
        } else if value == Some("-") {
            let operator = self.next(token);
            if constant_pattern_context == ConstantPatternContext::explicit {
                self.report_recoverable_error(operator, diag::invalidConstantPatternConstPrefix);
                constant_pattern_context = ConstantPatternContext::none;
            }
            // Right associative, so we recurse at the same precedence
            // level.
            let context = if constant_pattern_context != ConstantPatternContext::none {
                ConstantPatternContext::numericLiteralOnly
            } else {
                ConstantPatternContext::none
            };
            token = self.parse_precedence_expression(
                operator,
                POSTFIX_PRECEDENCE,
                allow_cascades,
                context,
            );
            self.listener
                .handle_unary_prefix_expression(&mut self.tokens, operator);
            return token;
        } else if value == Some("++") || value == Some("--") {
            // TODO(ahe): Validate this is used correctly.
            let operator = self.next(token);
            // Right associative, so we recurse at the same precedence
            // level.
            token = self.parse_precedence_expression(
                operator,
                POSTFIX_PRECEDENCE,
                allow_cascades,
                ConstantPatternContext::none,
            );
            self.listener
                .handle_unary_prefix_assignment_expression(&mut self.tokens, operator);
            return token;
        } else if self.use_implicit_creation_expression
            && self.tokens.is_identifier(self.next(token))
        {
            let mut identifier = self.next(token);
            if self.is_a(self.next(identifier), TokenType::PERIOD) {
                identifier = self.next(self.next(identifier));
            }
            if self.tokens.is_identifier(identifier) {
                // Looking for `<` after `identifier` or `prefix.identifier`.
                if self.is_a(self.next(identifier), TokenType::LT) {
                    let type_arg =
                        compute_type_param_or_arg(&mut self.tokens, identifier, false, false);
                    if type_arg != noTypeParamOrArg {
                        let end_type_arguments = type_arg.skip(&mut self.tokens, identifier);
                        let after_type_arguments = self.next(end_type_arguments);
                        if self.is_a(after_type_arguments, TokenType::PERIOD) {
                            let after_period = self.next(after_type_arguments);
                            if self.is_new_or_identifier(after_period)
                                && self.is_a(self.next(after_period), TokenType::OPEN_PAREN)
                            {
                                let next = self.next(identifier);
                                return self
                                    .parse_implicit_creation_expression(token, next, type_arg);
                            }
                        }
                    }
                }
            }
        }
        self.parse_primary(
            token,
            IdentifierContext::expression,
            constant_pattern_context,
        )
    }

    pub fn parse_argument_or_index_star(
        &mut self,
        mut token: TokenId,
        mut type_arg: TypeParamOrArgInfo,
        checked_null_aware: bool,
    ) -> TokenId {
        let mut next = self.next(token);
        let begin_token = next;
        loop {
            let mut potential_null_aware = self.is_a(next, TokenType::QUESTION)
                && self.is_a(self.next(next), TokenType::OPEN_SQUARE_BRACKET);
            if potential_null_aware && !checked_null_aware {
                // While it's a potential null aware index it hasn't been checked.
                // It might be a conditional expression.
                debug_assert!(self.is_a(next, TokenType::QUESTION));
                let is_conditional = self.can_parse_as_conditional(next);
                if is_conditional {
                    potential_null_aware = false;
                }
            }

            if self.is_a(next, TokenType::OPEN_SQUARE_BRACKET) || potential_null_aware {
                debug_assert!(type_arg == noTypeParamOrArg);
                let mut open_square_bracket = next;
                let mut question = NO_TOKEN;
                if self.is_a(next, TokenType::QUESTION) {
                    question = next;
                    next = self.next(next);
                    open_square_bracket = next;
                    debug_assert!(self.is_a(open_square_bracket, TokenType::OPEN_SQUARE_BRACKET));
                }
                let old = self.may_parse_function_expressions;
                self.may_parse_function_expressions = true;
                token = self.parse_expression(next);
                next = self.next(token);
                self.may_parse_function_expressions = old;
                if !self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET) {
                    self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("]"));
                    // Scanner ensures a closing ']'
                    let end_group = self.tokens.end_group(open_square_bracket);
                    if self.tokens.is_synthetic(end_group) {
                        // Scanner inserted closing ']' in the wrong place, so move it.
                        next = self.rewriter().move_synthetic(token, end_group);
                    } else {
                        // Skip over unexpected tokens to where the user placed the `]`.
                        next = end_group;
                    }
                }
                self.listener.handle_indexed_expression(
                    &mut self.tokens,
                    question,
                    open_square_bracket,
                    next,
                );
                token = next;
                let mut bang_token = token;
                if self.is_a(self.next(token), TokenType::BANG) {
                    bang_token = self.next(token);
                }
                type_arg = compute_method_type_arguments(&mut self.tokens, bang_token);
                if type_arg != noTypeParamOrArg {
                    // For example a[b]<T>(c), where token is before '<'.
                    if self.is_a(bang_token, TokenType::BANG) {
                        self.listener
                            .handle_non_null_assert_expression(&mut self.tokens, bang_token);
                    }
                    token = type_arg.parse_arguments(bang_token, self);
                    if !self.is_a(self.next(token), TokenType::OPEN_PAREN) {
                        let next_23 = self.tokens.next(bang_token);
                        self.listener
                            .handle_type_argument_application(&mut self.tokens, next_23);
                        type_arg = noTypeParamOrArg;
                    }
                }
                next = self.next(token);
            } else if self.is_a(next, TokenType::OPEN_PAREN) {
                if type_arg == noTypeParamOrArg {
                    self.listener
                        .handle_no_type_arguments(&mut self.tokens, next);
                }
                token = self.parse_arguments(token);
                self.listener
                    .handle_send(&mut self.tokens, begin_token, token);
                let mut bang_token = token;
                if self.is_a(self.next(token), TokenType::BANG) {
                    bang_token = self.next(token);
                }
                type_arg = compute_method_type_arguments(&mut self.tokens, bang_token);
                if type_arg != noTypeParamOrArg {
                    // For example a(b)<T>(c), where token is before '<'.
                    if self.is_a(bang_token, TokenType::BANG) {
                        self.listener
                            .handle_non_null_assert_expression(&mut self.tokens, bang_token);
                    }
                    token = type_arg.parse_arguments(bang_token, self);
                    if !self.is_a(self.next(token), TokenType::OPEN_PAREN) {
                        let next_22 = self.tokens.next(bang_token);
                        self.listener
                            .handle_type_argument_application(&mut self.tokens, next_22);
                        type_arg = noTypeParamOrArg;
                    }
                }
                next = self.next(token);
            } else {
                break;
            }
        }
        token
    }

    pub fn parse_primary(
        &mut self,
        mut token: TokenId,
        context: &'static IdentifierContext,
        constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        self.try_rewrite_new_to_identifier(token, context);
        let next = self.next(token);
        let kind = self.tokens.kind(next);
        if kind == IDENTIFIER_TOKEN {
            if constant_pattern_context == ConstantPatternContext::numericLiteralOnly {
                self.report_recoverable_error(next, diag::invalidConstantPatternNegation);
                // Note: upstream compares here (`==`) rather than assigns.
            }
            return self.parse_send_or_function_literal(token, context, constant_pattern_context);
        } else if kind == INT_TOKEN || kind == HEXADECIMAL_TOKEN {
            if constant_pattern_context == ConstantPatternContext::explicit {
                self.report_recoverable_error(next, diag::invalidConstantPatternConstPrefix);
            }
            let type_ = self.tokens.type_(next);
            if type_ == TokenType::INT_WITH_SEPARATORS
                || type_ == TokenType::HEXADECIMAL_WITH_SEPARATORS
            {
                return self.parse_literal_int_with_separators(token);
            } else {
                return self.parse_literal_int(token);
            }
        } else if kind == DOUBLE_TOKEN {
            if constant_pattern_context == ConstantPatternContext::explicit {
                self.report_recoverable_error(next, diag::invalidConstantPatternConstPrefix);
            }
            if self.tokens.type_(next) == TokenType::DOUBLE_WITH_SEPARATORS {
                return self.parse_literal_double_with_separators(token);
            } else {
                return self.parse_literal_double(token);
            }
        } else if kind == STRING_TOKEN {
            self.report_constant_pattern_literal(next, constant_pattern_context);
            return self.parse_literal_string(token);
        } else if kind == HASH_TOKEN {
            self.report_constant_pattern_literal(next, constant_pattern_context);
            return self.parse_literal_symbol(token);
        } else if kind == KEYWORD_TOKEN {
            let value = self.sv(next);
            if value == Some("true") || value == Some("false") {
                self.report_constant_pattern_literal(next, constant_pattern_context);
                return self.parse_literal_bool(token);
            } else if value == Some("null") {
                self.report_constant_pattern_literal(next, constant_pattern_context);
                return self.parse_literal_null(token);
            } else if value == Some("this") {
                return self.parse_this_expression(token, context);
            } else if value == Some("super") {
                return self.parse_super_expression(token, context);
            } else if value == Some("new") {
                return self.parse_new_expression(token);
            } else if value == Some("const") {
                if constant_pattern_context == ConstantPatternContext::explicit {
                    self.report_recoverable_error(next, diag::invalidConstantPatternDuplicateConst);
                }
                return self.parse_const_expression(token);
            } else if value == Some("void") {
                return self.parse_send_or_function_literal(
                    token,
                    context,
                    constant_pattern_context,
                );
            } else if !self.in_plain_sync() && (value == Some("yield") || value == Some("async")) {
                // Fall through to the recovery code.
            } else if value == Some("assert") {
                return self.parse_assert(token, Assert::Expression);
            } else if self.is_patterns_feature_enabled && value == Some("switch") {
                return self.parse_switch_expression(token);
            } else if self.tokens.is_identifier(next) {
                if constant_pattern_context == ConstantPatternContext::numericLiteralOnly {
                    self.report_recoverable_error(next, diag::invalidConstantPatternNegation);
                    // Note: upstream compares here (`==`) rather than assigns.
                }
                return self.parse_send_or_function_literal(
                    token,
                    context,
                    constant_pattern_context,
                );
            } else if value == Some("return") {
                // Recovery
                token = self.next(token);
                self.report_recoverable_error_with_token(token, diag::unexpectedToken);
                return self.parse_primary(token, context, ConstantPatternContext::none);
            } else {
                // Fall through to the recovery code.
            }
        } else if kind == OPEN_PAREN_TOKEN && !context.is_continuation {
            return self.parse_parenthesized_expression_function_literal_or_record_literal(
                token,
                constant_pattern_context,
            );
        } else if kind == OPEN_SQUARE_BRACKET_TOKEN || self.is_a(self.next(token), TokenType::INDEX)
        {
            let next_21 = self.tokens.next(token);
            self.listener
                .handle_no_type_arguments(&mut self.tokens, next_21);
            return self.parse_literal_list_suffix(token, NO_TOKEN);
        } else if kind == OPEN_CURLY_BRACKET_TOKEN {
            let next_20 = self.tokens.next(token);
            self.listener
                .handle_no_type_arguments(&mut self.tokens, next_20);
            return self.parse_literal_set_or_map_suffix(token, NO_TOKEN);
        } else if kind == LT_TOKEN {
            return self.parse_literal_list_set_map_or_function(token, NO_TOKEN);
        } else {
            // Fall through to the recovery code.
        }
        //
        // Recovery code.
        //
        self.parse_send(token, context, constant_pattern_context)
    }

    /// The check [parsePrimary] repeats before a literal that is not a number.
    fn report_constant_pattern_literal(
        &mut self,
        next: TokenId,
        constant_pattern_context: ConstantPatternContext,
    ) {
        if constant_pattern_context == ConstantPatternContext::explicit {
            self.report_recoverable_error(next, diag::invalidConstantPatternConstPrefix);
        } else if constant_pattern_context == ConstantPatternContext::numericLiteralOnly {
            self.report_recoverable_error(next, diag::invalidConstantPatternNegation);
        }
    }

    pub fn parse_parenthesized_expression_function_literal_or_record_literal(
        &mut self,
        mut token: TokenId,
        constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        let next = self.next(token);
        debug_assert!(self.is_a(next, TokenType::OPEN_PAREN));

        if self.may_parse_function_expressions {
            let next_token = self.next(self.tokens.end_group(next));
            let mut kind = self.tokens.kind(next_token);
            if kind == FUNCTION_TOKEN || kind == OPEN_CURLY_BRACKET_TOKEN {
                self.listener
                    .handle_no_type_variables(&mut self.tokens, next);
                return self.parse_function_expression(token);
            } else if kind == KEYWORD_TOKEN || kind == IDENTIFIER_TOKEN {
                if self.is_a(next_token, kw::ASYNC) || self.is_a(next_token, kw::SYNC) {
                    self.listener
                        .handle_no_type_variables(&mut self.tokens, next);
                    return self.parse_function_expression(token);
                }
                // Recovery
                // If there is a stray simple identifier in the function expression
                // because the user is typing (e.g. `() asy {}`) then continue parsing
                // and allow parseFunctionExpression to report an unexpected token.
                kind = self.tokens.kind(self.next(next_token));
                if kind == FUNCTION_TOKEN || kind == OPEN_CURLY_BRACKET_TOKEN {
                    self.listener
                        .handle_no_type_variables(&mut self.tokens, next);
                    return self.parse_function_expression(token);
                }
            }
        }
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        token = self.parse_parenthesized_expression_or_record_literal(
            token,
            NO_TOKEN,
            constant_pattern_context,
        );
        self.may_parse_function_expressions = old;
        token
    }

    pub fn ensure_parenthesized_condition(&mut self, token: TokenId, allow_case: bool) -> TokenId {
        let mut open_paren = self.next(token);
        if !self.is_a(open_paren, TokenType::OPEN_PAREN) {
            // Recover
            self.report_recoverable_error(open_paren, (diag::expectedToken.with_arguments)("("));
            open_paren = self.rewriter().insert_parens(token, false);
        }
        self.parse_expression_in_parenthesis_rest(open_paren, allow_case)
    }

    /// Parse either a parenthesized expression or a record literal.
    /// If [constKeywordForRecord] is non-null it is forced to be a record
    /// literal and an error will be issued if there is no trailing comma.
    pub fn parse_parenthesized_expression_or_record_literal(
        &mut self,
        mut token: TokenId,
        const_keyword_for_record: TokenId,
        constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        let begin = self.next(token);
        debug_assert!(self.is_a(begin, TokenType::OPEN_PAREN));
        self.listener
            .begin_parenthesized_expression_or_record_literal(&mut self.tokens, begin);

        // Expect them to be parenthesized expressions,
        // and for records to have a trailing comma.
        token = begin;
        let mut count = 0;
        let mut was_record = const_keyword_for_record != NO_TOKEN;
        let mut was_valid_record = false;
        let mut illegal_trailing_comma = NO_TOKEN;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_PAREN) {
                // Empty record literal: `()`.
                if count == 0 {
                    was_record = true;
                }
                break;
            } else if count == 0
                && self.is_a(next, TokenType::COMMA)
                && self.is_a(self.next(next), TokenType::CLOSE_PAREN)
            {
                illegal_trailing_comma = next;
                was_record = true;
                token = next;
                break;
            }
            let mut colon = NO_TOKEN;
            if self.is_a(self.next(next), TokenType::COLON) || /* recovery */ self.is_a(next, TokenType::COLON)
            {
                // Record with named expression.
                was_record = true;
                token = self.ensure_identifier(token, IdentifierContext::namedRecordFieldReference);
                token = self.next(token);
                colon = token;
                was_valid_record = true;
            }
            let begin_expression_token = token;
            token = self.parse_expression(token);
            next = self.next(token);
            if colon != NO_TOKEN {
                self.listener
                    .handle_named_record_field(&mut self.tokens, colon);
            } else {
                let next_19 = self.tokens.next(begin_expression_token);
                self.listener
                    .handle_positional_record_field(&mut self.tokens, next_19);
            }
            count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                break;
            } else {
                // It is a comma, i.e. it's a record.
                was_record = true;
                was_valid_record = true;
            }
            token = next;
        }
        token = self.ensure_close_paren(token, begin);
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        debug_assert!(was_record || count <= 1);

        if was_record {
            if count == 0 && illegal_trailing_comma != NO_TOKEN {
                // Empty record literal with a comma `(,)`.
                self.report_recoverable_error(
                    illegal_trailing_comma,
                    diag::recordLiteralZeroFieldsWithTrailingComma,
                );
            } else if count == 1 && !was_valid_record {
                self.report_recoverable_error(
                    token,
                    diag::recordLiteralOnePositionalFieldNoTrailingComma,
                );
            } else if count == 0 && constant_pattern_context != ConstantPatternContext::none {
                self.report_recoverable_error(
                    begin,
                    diag::invalidConstantPatternEmptyRecordLiteral,
                );
            }
            self.listener.end_record_literal(
                &mut self.tokens,
                begin,
                count,
                const_keyword_for_record,
            );
        } else {
            self.listener
                .end_parenthesized_expression(&mut self.tokens, begin);
        }
        token
    }

    /// Parses an expression inside parentheses that represents the condition part
    /// of an if-statement, if-control-flow, etc.
    pub fn parse_expression_in_parenthesis_rest(
        &mut self,
        mut token: TokenId,
        _allow_case: bool,
    ) -> TokenId {
        debug_assert!(self.is_a(token, TokenType::OPEN_PAREN));
        let begin = token;
        token = self.parse_expression(token);
        let mut next = self.next(token);
        if self.is_patterns_feature_enabled && self.is_a(next, kw::CASE) {
            token = next;
            let case_ = token;
            token = self.parse_pattern(token, PatternContext::matching, 1);
            next = self.next(token);
            let mut when = NO_TOKEN;
            if self.is_a(next, kw::WHEN) {
                token = next;
                when = token;
                self.listener.begin_pattern_guard(&mut self.tokens, when);
                token = self.parse_expression(token);
                self.listener.end_pattern_guard(&mut self.tokens, when);
            }
            token = self.ensure_close_paren(token, begin);
            self.listener
                .handle_parenthesized_condition(&mut self.tokens, begin, case_, when);
        } else {
            token = self.ensure_close_paren(token, begin);
            self.listener.handle_parenthesized_condition(
                &mut self.tokens,
                begin,
                NO_TOKEN,
                NO_TOKEN,
            );
        }
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        token
    }

    pub fn parse_this_expression(
        &mut self,
        mut token: TokenId,
        context: &'static IdentifierContext,
    ) -> TokenId {
        token = self.next(token);
        let this_token = token;
        debug_assert!(self.is_a(this_token, kw::THIS));
        self.listener
            .handle_this_expression(&mut self.tokens, this_token, context);
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_PAREN) {
            // Constructor forwarding.
            self.listener
                .handle_no_type_arguments(&mut self.tokens, next);
            token = self.parse_arguments(token);
            self.listener
                .handle_send(&mut self.tokens, this_token, token);
        }
        token
    }

    pub fn parse_super_expression(
        &mut self,
        mut token: TokenId,
        context: &'static IdentifierContext,
    ) -> TokenId {
        token = self.next(token);
        let super_token = token;
        debug_assert!(self.is_a(token, kw::SUPER));
        self.listener
            .handle_super_expression(&mut self.tokens, super_token, context);
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_PAREN) {
            self.listener
                .handle_no_type_arguments(&mut self.tokens, next);
            token = self.parse_arguments(token);
            self.listener
                .handle_send(&mut self.tokens, super_token, token);
        } else if self.is_a(next, TokenType::QUESTION_PERIOD) {
            self.report_recoverable_error(next, diag::superNullAware);
        }
        token
    }

    /// This method parses the portion of a list literal starting with the left
    /// square bracket.
    pub fn parse_literal_list_suffix(
        &mut self,
        mut token: TokenId,
        const_keyword: TokenId,
    ) -> TokenId {
        let before_token = token;
        token = self.next(token);
        let begin_token = token;
        debug_assert!(
            self.is_a(token, TokenType::OPEN_SQUARE_BRACKET) || self.is_a(token, TokenType::INDEX)
        );
        let mut count = 0;
        if self.is_a(token, TokenType::INDEX) {
            let rewritten = self.rewrite_square_brackets(before_token);
            token = self.next(rewritten);
            let next_18 = self.tokens.next(token);
            self.listener
                .handle_literal_list(&mut self.tokens, 0, token, const_keyword, next_18);
            return self.next(token);
        }
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET) {
                token = next;
                break;
            }
            let mut if_count = 0;
            let mut info = Some(self.compute_literal_entry_impl(token));
            while let Some(mut entry) = info {
                next = self.next(token);
                if entry.has_entry() {
                    if self.is_a(next, TokenType::QUESTION) {
                        let null_aware_token = next;
                        token = next;
                        token = self.parse_expression(token);
                        self.listener
                            .handle_null_aware_element(&mut self.tokens, null_aware_token);
                    } else {
                        token = self.parse_expression(token);
                    }
                } else {
                    token = entry.parse(token, self);
                }
                if_count += entry.if_condition_delta();
                info = self.next_literal_entry(entry, token);
            }
            next = self.next(token);
            count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                if self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET) {
                    token = next;
                    break;
                }
                if !looks_like_literal_entry(&self.tokens, next) {
                    let end_group = self.tokens.end_group(begin_token);
                    if self.tokens.is_synthetic(end_group) {
                        token = self.rewriter().move_synthetic(token, end_group);
                    } else {
                        self.report_recoverable_error(
                            next,
                            (diag::expectedButGot.with_arguments)("]"),
                        );
                        // Scanner ensures a closing ']'
                        token = end_group;
                    }
                    break;
                }
                // Recovery: This looks like an expression.
                // Report an error, insert synthetic comma, and continue parsing.
                let offset = self.tokens.offset(next);
                let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                let message: Message = if if_count > 0 {
                    diag::expectedElseOrComma.message()
                } else {
                    (diag::expectedButGot.with_arguments)(",")
                };
                next = self.rewrite_and_recover(token, message, comma);
            }
            token = next;
        }
        self.may_parse_function_expressions = old;
        self.listener.handle_literal_list(
            &mut self.tokens,
            count,
            begin_token,
            const_keyword,
            token,
        );
        token
    }

    /// This method parses the portion of a set or map literal that starts with
    /// the left curly brace.
    pub fn parse_literal_set_or_map_suffix(
        &mut self,
        mut token: TokenId,
        const_keyword: TokenId,
    ) -> TokenId {
        token = self.next(token);
        let left_brace = token;
        debug_assert!(self.is_a(left_brace, TokenType::OPEN_CURLY_BRACKET));

        let mut next = self.next(token);
        if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
            self.listener.handle_literal_set_or_map(
                &mut self.tokens,
                0,
                left_brace,
                const_keyword,
                next,
                false,
            );
            return next;
        }

        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        let mut count = 0;
        // TODO(danrubel): hasSetEntry parameter exists for replicating existing
        // behavior and will be removed once unified collection has been enabled
        let mut has_set_entry: Option<bool> = None;

        loop {
            let mut if_count = 0;
            let mut info = Some(self.compute_literal_entry_impl(token));
            if info == Some(simpleEntry) {
                // TODO(danrubel): Remove this section and use the while loop below
                // once hasSetEntry is no longer needed.
                token = self.parse_expression(token);
                let is_map_entry = self.is_a(self.next(token), TokenType::COLON);
                if has_set_entry.is_none() {
                    has_set_entry = Some(!is_map_entry);
                }
                if is_map_entry {
                    let colon = self.next(token);
                    token = colon;
                    let next = self.next(token);
                    let mut null_aware_value_token = NO_TOKEN;
                    if self.is_a(next, TokenType::QUESTION_PERIOD) {
                        token = self.split_following_question_period(token);
                        null_aware_value_token = token;
                    } else if self.is_a(next, TokenType::QUESTION) {
                        token = next;
                        null_aware_value_token = token;
                    }
                    token = self.parse_expression(token);
                    let next_17 = self.tokens.next(token);
                    self.listener.handle_literal_map_entry(
                        &mut self.tokens,
                        colon,
                        next_17,
                        NO_TOKEN,
                        null_aware_value_token,
                    );
                }
            } else {
                while let Some(mut entry) = info {
                    if entry.has_entry() {
                        let mut null_aware_key_token = NO_TOKEN;
                        let next = self.next(token);
                        if self.is_a(next, TokenType::QUESTION) {
                            null_aware_key_token = next;
                            token = null_aware_key_token;
                        }
                        token = self.parse_expression(token);
                        if self.is_a(self.next(token), TokenType::COLON) {
                            let colon = self.next(token);
                            token = colon;
                            let mut null_aware_value_token = NO_TOKEN;
                            let next = self.next(token);
                            if self.is_a(next, TokenType::QUESTION_PERIOD) {
                                token = self.split_following_question_period(token);
                                null_aware_value_token = token;
                            } else if self.is_a(next, TokenType::QUESTION) {
                                token = next;
                                null_aware_value_token = token;
                            }
                            token = self.parse_expression(token);
                            let next_16 = self.tokens.next(token);
                            self.listener.handle_literal_map_entry(
                                &mut self.tokens,
                                colon,
                                next_16,
                                null_aware_key_token,
                                null_aware_value_token,
                            );
                        } else if null_aware_key_token != NO_TOKEN {
                            self.listener
                                .handle_null_aware_element(&mut self.tokens, null_aware_key_token);
                        }
                    } else {
                        token = entry.parse(token, self);
                    }
                    if_count += entry.if_condition_delta();
                    info = self.next_literal_entry(entry, token);
                }
            }
            count += 1;
            next = self.next(token);
            let mut comma = NO_TOKEN;
            if self.is_a(next, TokenType::COMMA) {
                token = next;
                comma = token;
                next = self.next(token);
            }
            if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
                self.listener.handle_literal_set_or_map(
                    &mut self.tokens,
                    count,
                    left_brace,
                    const_keyword,
                    next,
                    has_set_entry.unwrap_or(false),
                );
                self.may_parse_function_expressions = old;
                return next;
            }
            if comma == NO_TOKEN {
                // Recovery
                if looks_like_literal_entry(&self.tokens, next) {
                    // If this looks like the start of an expression,
                    // then report an error, insert the comma, and continue parsing.
                    // TODO(danrubel): Consider better error message
                    let offset = self.tokens.offset(next);
                    let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                    let message: Message = if if_count > 0 {
                        diag::expectedElseOrComma.message()
                    } else {
                        (diag::expectedButGot.with_arguments)(",")
                    };
                    token = self.rewrite_and_recover(token, message, comma);
                } else {
                    self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("}"));
                    // Scanner guarantees a closing curly bracket
                    next = self.tokens.end_group(left_brace);
                    self.listener.handle_literal_set_or_map(
                        &mut self.tokens,
                        count,
                        left_brace,
                        const_keyword,
                        next,
                        has_set_entry.unwrap_or(false),
                    );
                    self.may_parse_function_expressions = old;
                    return next;
                }
            }
        }
    }

    /// `_computeLiteralEntry`.
    fn compute_literal_entry_impl(&mut self, token: TokenId) -> LiteralEntryInfo {
        if self.is_a(self.next(token), TokenType::QUESTION_PERIOD) {
            self.split_following_question_period(token);
        }
        compute_literal_entry(&self.tokens, token)
    }

    /// `_nextLiteralEntry`.
    fn next_literal_entry(
        &mut self,
        info: LiteralEntryInfo,
        token: TokenId,
    ) -> Option<LiteralEntryInfo> {
        if self.is_a(self.next(token), TokenType::QUESTION_PERIOD) {
            self.split_following_question_period(token);
        }
        info.compute_next(&self.tokens, token)
    }

    /// Splits the `?.` following [token] into `?` and `.`, returning the `?`.
    fn split_following_question_period(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        debug_assert!(self.is_a(next, TokenType::QUESTION_PERIOD));
        let offset = self.tokens.char_offset(next);
        let question = self
            .tokens
            .simple_token(TokenType::QUESTION, offset, NO_TOKEN);
        let new_next = self.rewriter().replace_token_following(token, question);
        let period = self
            .tokens
            .simple_token(TokenType::PERIOD, offset + 1, NO_TOKEN);
        self.rewriter().insert_token(new_next, period);
        new_next
    }

    pub fn parse_literal_function_suffix(&mut self, token: TokenId) -> TokenId {
        debug_assert!(self.is_a(self.next(token), TokenType::OPEN_PAREN));
        let next = self.next(self.tokens.end_group(self.next(token)));
        let kind = self.tokens.kind(next);
        if kind != FUNCTION_TOKEN
            && kind != OPEN_CURLY_BRACKET_TOKEN
            && (kind != KEYWORD_TOKEN || !self.is_a(next, kw::ASYNC) && !self.is_a(next, kw::SYNC))
        {
            self.report_recoverable_error_with_token(next, diag::unexpectedToken);
        }
        self.parse_function_expression(token)
    }

    /// Parse a literal list, set, map, or function.
    pub fn parse_literal_list_set_map_or_function(
        &mut self,
        start: TokenId,
        const_keyword: TokenId,
    ) -> TokenId {
        debug_assert!(self.is_a(self.next(start), TokenType::LT));
        let type_param_or_arg = compute_type_param_or_arg(&mut self.tokens, start, true, false);
        let mut token = type_param_or_arg.skip(&mut self.tokens, start);
        if self.is_a(self.next(token), TokenType::OPEN_PAREN) {
            if const_keyword != NO_TOKEN {
                self.report_recoverable_error_with_token(const_keyword, diag::unexpectedToken);
            }
            token = type_param_or_arg.parse_variables(start, self);
            return self.parse_literal_function_suffix(token);
        }
        // Note that parseArguments can rewrite the token stream!
        token = type_param_or_arg.parse_arguments(start, self);
        let next = self.next(token);
        if self.is_a(next, TokenType::OPEN_CURLY_BRACKET) {
            if type_param_or_arg.type_argument_count() > 2 {
                let begin = self.next(start);
                self.report_recoverable_error_with_end(
                    begin,
                    token,
                    diag::setOrMapLiteralTooManyTypeArguments,
                );
            }
            return self.parse_literal_set_or_map_suffix(token, const_keyword);
        }
        if !self.is_a(next, TokenType::OPEN_SQUARE_BRACKET) && !self.is_a(next, TokenType::INDEX) {
            // TODO(danrubel): Improve this error message.
            self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("["));
            self.rewriter()
                .insert_synthetic_token(token, TokenType::INDEX);
        }
        self.parse_literal_list_suffix(token, const_keyword)
    }

    /// ```text
    /// mapLiteralEntry:
    ///   expression ':' expression |
    ///   'if' '(' expression ')' mapLiteralEntry ( 'else' mapLiteralEntry )? |
    ///   'await'? 'for' '(' forLoopParts ')' mapLiteralEntry |
    ///   ( '...' | '...?' ) expression
    /// ;
    /// ```
    pub fn parse_map_literal_entry(&mut self, mut token: TokenId) -> TokenId {
        // Assume the listener rejects non-string keys.
        // TODO(brianwilkerson): Change the assumption above by moving error
        // checking into the parser, making it possible to recover.
        let mut info = Some(compute_literal_entry(&self.tokens, token));
        while let Some(mut entry) = info {
            if entry.has_entry() {
                token = self.parse_expression(token);
                let colon = self.ensure_colon(token);
                token = self.parse_expression(colon);
                let next_15 = self.tokens.next(token);
                self.listener.handle_literal_map_entry(
                    &mut self.tokens,
                    colon,
                    next_15,
                    NO_TOKEN,
                    NO_TOKEN,
                );
            } else {
                token = entry.parse(token, self);
            }
            info = entry.compute_next(&self.tokens, token);
        }
        token
    }

    pub fn parse_send_or_function_literal(
        &mut self,
        token: TokenId,
        context: &'static IdentifierContext,
        constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        if !self.may_parse_function_expressions || context.is_continuation {
            return self.parse_send(token, context, constant_pattern_context);
        }
        let type_info = compute_type(&mut self.tokens, token, false, false, false);
        let before_name = type_info.skip_type(&mut self.tokens, token);
        let name = self.next(before_name);
        if self.tokens.is_identifier(name) {
            let type_param = compute_type_param_or_arg(&mut self.tokens, name, false, false);
            let next = self.next_after_skip(&type_param, name);
            if self.is_a(next, TokenType::OPEN_PAREN) {
                let after = self.next(self.tokens.end_group(next));
                if self.looks_like_function_body(after) {
                    return self.parse_function_literal(
                        token,
                        before_name,
                        name,
                        type_info,
                        type_param,
                        context,
                    );
                }
            }
        }
        self.parse_send(token, context, constant_pattern_context)
    }

    pub fn ensure_arguments(&mut self, token: TokenId) -> TokenId {
        let mut next = self.next(token);
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            self.report_recoverable_error(token, (diag::expectedAfterButGot.with_arguments)("("));
            next = self.rewriter().insert_parens(token, false);
        }
        self.parse_arguments_rest(next)
    }

    pub fn parse_constructor_invocation_arguments(&mut self, mut token: TokenId) -> TokenId {
        let mut next = self.next(token);
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            // Recovery: Check for invalid type parameters
            let type_arg = compute_type_param_or_arg(&mut self.tokens, token, false, false);
            if type_arg == noTypeParamOrArg {
                self.report_recoverable_error(
                    token,
                    (diag::expectedAfterButGot.with_arguments)("("),
                );
            } else {
                self.report_recoverable_error(token, diag::constructorWithTypeArguments);
                token = type_arg.parse_arguments(token, self);
                self.listener
                    .handle_invalid_type_arguments(&mut self.tokens, token);
                next = self.next(token);
            }
            if !self.is_a(next, TokenType::OPEN_PAREN) {
                next = self.rewriter().insert_parens(token, false);
            }
        }
        self.parse_arguments_rest(next)
    }

    /// ```text
    /// newExpression:
    ///   'new' type ('.' identifier)? arguments
    /// ;
    /// ```
    pub fn parse_new_expression(&mut self, mut token: TokenId) -> TokenId {
        let new_keyword = self.next(token);
        debug_assert!(self.is_a(new_keyword, kw::NEW));

        let mut potential_type_arg = None;

        let next = self.next(new_keyword);
        if self.tokens.kind(next) == IDENTIFIER_TOKEN {
            let identifier = next;
            let value = self.tokens.lexeme_string(identifier);
            if (value == "Map" || value == "Set")
                && !self.is_a(self.next(identifier), TokenType::PERIOD)
            {
                let type_arg =
                    compute_type_param_or_arg(&mut self.tokens, identifier, false, false);
                let after_token = self.next_after_skip(&type_arg, identifier);
                potential_type_arg = Some(type_arg);
                if self.is_a(after_token, TokenType::OPEN_CURLY_BRACKET) {
                    // Recover by ignoring both the `new` and the `Map`/`Set` and parse as
                    // a literal map/set.
                    let message = (diag::literalWithClassAndNew.with_arguments)(
                        &self.tokens,
                        &value.to_lowercase(),
                        identifier,
                    );
                    self.report_recoverable_error_with_end(new_keyword, identifier, message);
                    return self.parse_primary(
                        identifier,
                        IdentifierContext::expression,
                        ConstantPatternContext::none,
                    );
                }
            } else if value == "List" && !self.is_a(self.next(identifier), TokenType::PERIOD) {
                let type_arg =
                    compute_type_param_or_arg(&mut self.tokens, identifier, false, false);
                let after_token = self.next_after_skip(&type_arg, identifier);
                potential_type_arg = Some(type_arg);
                if self.is_a(after_token, TokenType::OPEN_SQUARE_BRACKET)
                    || self.is_a(after_token, TokenType::INDEX)
                {
                    // Recover by ignoring both the `new` and the `List` and parse as
                    // a literal list.
                    let message = (diag::literalWithClassAndNew.with_arguments)(
                        &self.tokens,
                        &value.to_lowercase(),
                        identifier,
                    );
                    self.report_recoverable_error_with_end(new_keyword, identifier, message);
                    return self.parse_primary(
                        identifier,
                        IdentifierContext::expression,
                        ConstantPatternContext::none,
                    );
                }
            }
        } else {
            // This is probably an error. "Normal" recovery will happen in
            // parseConstructorReference.
            // Do special recovery for literal maps/set/list erroneously prepended
            // with 'new'.
            let not_identifier = next;
            let value = self.tokens.lexeme_string(not_identifier);
            if value == "<" {
                let type_arg =
                    compute_type_param_or_arg(&mut self.tokens, new_keyword, false, false);
                let after_token = self.next_after_skip(&type_arg, new_keyword);
                potential_type_arg = Some(type_arg);
                if self.is_a(after_token, TokenType::OPEN_CURLY_BRACKET)
                    || self.is_a(after_token, TokenType::OPEN_SQUARE_BRACKET)
                    || self.is_a(after_token, TokenType::INDEX)
                {
                    // Recover by ignoring the `new` and parse as a literal map/set/list.
                    self.report_recoverable_error(new_keyword, diag::literalWithNew);
                    return self.parse_primary(
                        new_keyword,
                        IdentifierContext::expression,
                        ConstantPatternContext::none,
                    );
                }
            } else if value == "{" || value == "[" || value == "[]" {
                // Recover by ignoring the `new` and parse as a literal map/set/list.
                self.report_recoverable_error(new_keyword, diag::literalWithNew);
                return self.parse_primary(
                    new_keyword,
                    IdentifierContext::expression,
                    ConstantPatternContext::none,
                );
            }
        }

        self.listener
            .begin_new_expression(&mut self.tokens, new_keyword);
        token = self.parse_constructor_reference(
            new_keyword,
            ConstructorReferenceContext::New,
            potential_type_arg,
        );
        token = self.parse_constructor_invocation_arguments(token);
        self.listener
            .end_new_expression(&mut self.tokens, new_keyword);
        token
    }

    pub fn parse_implicit_creation_expression(
        &mut self,
        mut token: TokenId,
        open_angle_bracket: TokenId,
        type_arg: TypeParamOrArgInfo,
    ) -> TokenId {
        let begin = self.next(token); // This is the class name.
        self.listener
            .begin_implicit_creation_expression(&mut self.tokens, begin);
        token = self.parse_constructor_reference(
            token,
            ConstructorReferenceContext::Implicit,
            Some(type_arg),
        );
        token = self.parse_constructor_invocation_arguments(token);
        self.listener
            .end_implicit_creation_expression(&mut self.tokens, begin, open_angle_bracket);
        token
    }

    /// This method parses a const expression, which may be:
    /// a const literal (list, set, map, record), or a constructor invocation.
    pub fn parse_const_expression(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let const_keyword = token;
        debug_assert!(self.is_a(const_keyword, kw::CONST));
        let next = self.next(token);
        let value = self.sv(next);
        if value == Some("[") || value == Some("[]") {
            self.listener.begin_const_literal(&mut self.tokens, next);
            self.listener
                .handle_no_type_arguments(&mut self.tokens, next);
            token = self.parse_literal_list_suffix(token, const_keyword);
            self.listener.end_const_literal(&mut self.tokens, token);
            return token;
        }
        if value == Some("(") {
            self.listener.begin_const_literal(&mut self.tokens, next);
            token = self.parse_parenthesized_expression_or_record_literal(
                token,
                const_keyword,
                ConstantPatternContext::none,
            );
            self.listener.end_const_literal(&mut self.tokens, token);
            return token;
        }
        if value == Some("{") {
            self.listener.begin_const_literal(&mut self.tokens, next);
            self.listener
                .handle_no_type_arguments(&mut self.tokens, next);
            token = self.parse_literal_set_or_map_suffix(token, const_keyword);
            self.listener.end_const_literal(&mut self.tokens, token);
            return token;
        }
        if value == Some("<") {
            self.listener.begin_const_literal(&mut self.tokens, next);
            token = self.parse_literal_list_set_map_or_function(token, const_keyword);
            self.listener.end_const_literal(&mut self.tokens, token);
            return token;
        }
        let lexeme = self.tokens.lexeme_string(next);
        let next_next = self.next(next);
        let mut potential_type_arg = None;
        if (lexeme == "Map" || lexeme == "Set") && !self.is_a(next_next, TokenType::PERIOD) {
            // Special-case recovery for `const Map<..>{}` and `const Set<..>{}`.
            let type_arg = compute_type_param_or_arg(&mut self.tokens, next, false, false);
            let after_token = self.next_after_skip(&type_arg, next);
            potential_type_arg = Some(type_arg);
            if self.is_a(after_token, TokenType::OPEN_CURLY_BRACKET) {
                let next_value = self.sv(next_next);
                if next_value == Some("{") {
                    // Recover by ignoring the `Map`/`Set` and parse as a literal map/set.
                    let message = (diag::literalWithClass.with_arguments)(
                        &self.tokens,
                        &lexeme.to_lowercase(),
                        next,
                    );
                    self.report_recoverable_error(next, message);
                    self.listener
                        .begin_const_literal(&mut self.tokens, next_next);
                    self.listener
                        .handle_no_type_arguments(&mut self.tokens, next_next);
                    token = self.parse_literal_set_or_map_suffix(next, const_keyword);
                    self.listener.end_const_literal(&mut self.tokens, token);
                    return token;
                }
                if next_value == Some("<") {
                    // Recover by ignoring the `Map`/`Set` and parse as a literal map/set.
                    let message = (diag::literalWithClass.with_arguments)(
                        &self.tokens,
                        &lexeme.to_lowercase(),
                        next,
                    );
                    self.report_recoverable_error(next, message);
                    self.listener
                        .begin_const_literal(&mut self.tokens, next_next);
                    token = self.parse_literal_list_set_map_or_function(next, const_keyword);
                    self.listener.end_const_literal(&mut self.tokens, token);
                    return token;
                }
                debug_assert!(false, "Expected either {{ or < but found neither.");
            }
        } else if lexeme == "List" && !self.is_a(next_next, TokenType::PERIOD) {
            // Special-case recovery for `const List<..>[]`.
            let type_arg = compute_type_param_or_arg(&mut self.tokens, next, false, false);
            let after_token = self.next_after_skip(&type_arg, next);
            potential_type_arg = Some(type_arg);
            if self.is_a(after_token, TokenType::OPEN_SQUARE_BRACKET)
                || self.is_a(after_token, TokenType::INDEX)
            {
                let next_value = self.sv(next_next);
                if next_value == Some("[") || next_value == Some("[]") {
                    // Recover by ignoring the `List` and parse as a literal list.
                    let message = (diag::literalWithClass.with_arguments)(
                        &self.tokens,
                        &lexeme.to_lowercase(),
                        next,
                    );
                    self.report_recoverable_error(next, message);
                    self.listener
                        .begin_const_literal(&mut self.tokens, next_next);
                    self.listener
                        .handle_no_type_arguments(&mut self.tokens, next_next);
                    token = self.parse_literal_list_suffix(next, const_keyword);
                    self.listener.end_const_literal(&mut self.tokens, token);
                    return token;
                }
                if next_value == Some("<") {
                    // Recover by ignoring the `List` and parse as a literal list.
                    let message = (diag::literalWithClass.with_arguments)(
                        &self.tokens,
                        &lexeme.to_lowercase(),
                        next,
                    );
                    self.report_recoverable_error(next, message);
                    self.listener
                        .begin_const_literal(&mut self.tokens, next_next);
                    token = self.parse_literal_list_set_map_or_function(next, const_keyword);
                    self.listener.end_const_literal(&mut self.tokens, token);
                    return token;
                }
                debug_assert!(false, "Expected either [, [] or < but found neither.");
            }
        }

        self.listener
            .begin_const_expression(&mut self.tokens, const_keyword);
        token = self.parse_constructor_reference(
            token,
            ConstructorReferenceContext::Const,
            potential_type_arg,
        );
        token = self.parse_constructor_invocation_arguments(token);
        self.listener
            .end_const_expression(&mut self.tokens, const_keyword);
        token
    }

    /// ```text
    /// intLiteral:
    ///   integer
    /// ;
    /// ```
    pub fn parse_literal_int(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(
            self.tokens.kind(token) == INT_TOKEN || self.tokens.kind(token) == HEXADECIMAL_TOKEN
        );
        self.listener.handle_literal_int(&mut self.tokens, token);
        token
    }

    pub fn parse_literal_int_with_separators(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(
            self.tokens.kind(token) == INT_TOKEN || self.tokens.kind(token) == HEXADECIMAL_TOKEN
        );
        self.listener
            .handle_literal_int_with_separators(&mut self.tokens, token);
        token
    }

    /// ```text
    /// doubleLiteral:
    ///   double
    /// ;
    /// ```
    pub fn parse_literal_double(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.tokens.kind(token) == DOUBLE_TOKEN);
        self.listener.handle_literal_double(&mut self.tokens, token);
        token
    }

    pub fn parse_literal_double_with_separators(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.tokens.kind(token) == DOUBLE_TOKEN);
        self.listener
            .handle_literal_double_with_separators(&mut self.tokens, token);
        token
    }

    /// ```text
    /// stringLiteral:
    ///   (multilineString | singleLineString)+
    /// ;
    /// ```
    pub fn parse_literal_string(&mut self, mut token: TokenId) -> TokenId {
        let start_token = token;
        debug_assert!(self.tokens.kind(self.next(token)) == STRING_TOKEN);
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        token = self.parse_single_literal_string(token);
        let mut count = 1;
        while self.tokens.kind(self.next(token)) == STRING_TOKEN {
            token = self.parse_single_literal_string(token);
            count += 1;
        }
        if count > 1 {
            self.listener
                .handle_adjacent_string_literals(&mut self.tokens, start_token, count);
        }
        self.may_parse_function_expressions = old;
        token
    }

    /// ```text
    /// symbolLiteral:
    ///   '#' (operator | (identifier ('.' identifier)*))
    /// ;
    /// ```
    pub fn parse_literal_symbol(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let hash_token = token;
        debug_assert!(self.is_a(hash_token, TokenType::HASH));
        self.listener
            .begin_literal_symbol(&mut self.tokens, hash_token);
        let next = self.next(token);
        if self.tokens.is_user_definable_operator(next) {
            self.listener.handle_operator(&mut self.tokens, next);
            self.listener
                .end_literal_symbol(&mut self.tokens, hash_token, 1);
            next
        } else if self.is_a(next, kw::VOID) {
            self.listener.handle_symbol_void(&mut self.tokens, next);
            self.listener
                .end_literal_symbol(&mut self.tokens, hash_token, 1);
            next
        } else {
            let mut count = 1;
            token = self.ensure_identifier(token, IdentifierContext::literalSymbol);
            while self.is_a(self.next(token), TokenType::PERIOD) {
                count += 1;
                let next = self.next(token);
                token = self.ensure_identifier(next, IdentifierContext::literalSymbolContinuation);
            }
            self.listener
                .end_literal_symbol(&mut self.tokens, hash_token, count);
            token
        }
    }

    pub fn parse_single_literal_string(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        debug_assert!(self.tokens.kind(token) == STRING_TOKEN);
        self.listener.begin_literal_string(&mut self.tokens, token);
        // Parsing the prefix, for instance 'x of 'x${id}y${id}z'
        let mut interpolation_count = 0;
        let mut next = self.next(token);
        let mut kind = self.tokens.kind(next);
        while kind != EOF_TOKEN {
            if kind == STRING_INTERPOLATION_TOKEN {
                // Parsing ${expression}.
                token = self.parse_expression(next);
                token = self.next(token);
                if !self.is_a(token, TokenType::CLOSE_CURLY_BRACKET) {
                    self.report_recoverable_error(
                        token,
                        (diag::expectedButGot.with_arguments)("}"),
                    );
                    token = self.tokens.end_group(next);
                }
                self.listener
                    .handle_interpolation_expression(&mut self.tokens, next, token);
            } else if kind == STRING_INTERPOLATION_IDENTIFIER_TOKEN {
                // Parsing $identifier.
                token = self.parse_identifier_expression(next);
                self.listener
                    .handle_interpolation_expression(&mut self.tokens, next, NO_TOKEN);
            } else {
                break;
            }
            interpolation_count += 1;
            // Parsing the infix/suffix, for instance y and z' of 'x${id}y${id}z'
            token = self.parse_string_part(token);
            next = self.next(token);
            kind = self.tokens.kind(next);
        }
        self.listener
            .end_literal_string(&mut self.tokens, interpolation_count, token);
        token
    }

    pub fn parse_identifier_expression(&mut self, token: TokenId) -> TokenId {
        if self.kind != ParserKind::Parser {
            // `ClassMemberParser.parseIdentifierExpression`.
            return self.next(token);
        }
        let next = self.next(token);
        if self.tokens.kind(next) == KEYWORD_TOKEN && self.sv(next) == Some("this") {
            self.listener.handle_this_expression(
                &mut self.tokens,
                next,
                IdentifierContext::expression,
            );
            next
        } else {
            self.parse_send(
                token,
                IdentifierContext::expression,
                ConstantPatternContext::none,
            )
        }
    }

    /// ```text
    /// booleanLiteral:
    ///   'true' |
    ///   'false'
    /// ;
    /// ```
    pub fn parse_literal_bool(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.is_a(token, kw::FALSE) || self.is_a(token, kw::TRUE));
        self.listener.handle_literal_bool(&mut self.tokens, token);
        token
    }

    /// ```text
    /// nullLiteral:
    ///   'null'
    /// ;
    /// ```
    pub fn parse_literal_null(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.is_a(token, kw::NULL));
        self.listener.handle_literal_null(&mut self.tokens, token);
        token
    }

    pub fn parse_send(
        &mut self,
        mut token: TokenId,
        context: &'static IdentifierContext,
        mut constant_pattern_context: ConstantPatternContext,
    ) -> TokenId {
        // Least-costly recovery of `Map<...>{ ... }`, `Set<...>{ ... }` and
        // `List<...>[ ... ]`.
        let mut potential_type_arg = None;
        let mut after_token = NO_TOKEN;
        let next = self.next(token);
        if self.tokens.kind(next) == IDENTIFIER_TOKEN {
            let identifier = next;
            let type_arg = compute_type_param_or_arg(&mut self.tokens, identifier, false, false);
            after_token = self.next_after_skip(&type_arg, identifier);
            let is_no_type_arg = type_arg == noTypeParamOrArg;
            potential_type_arg = Some(type_arg);
            if self.is_a(after_token, TokenType::OPEN_CURLY_BRACKET) {
                let value = self.tokens.lexeme_string(identifier);
                if value == "Map" || value == "Set" {
                    // Recover by ignoring the `Map`/`Set` and parse as a literal map/set.
                    let message = (diag::literalWithClass.with_arguments)(
                        &self.tokens,
                        &value.to_lowercase(),
                        identifier,
                    );
                    self.report_recoverable_error(identifier, message);
                    return self.parse_primary(identifier, context, ConstantPatternContext::none);
                }
            } else if (!is_no_type_arg && self.is_a(after_token, TokenType::OPEN_SQUARE_BRACKET))
                || self.is_a(after_token, TokenType::INDEX)
            {
                let value = self.tokens.lexeme_string(identifier);
                if value == "List" {
                    // Recover by ignoring the `List` and parse as a literal list.
                    let message = (diag::literalWithClass.with_arguments)(
                        &self.tokens,
                        &value.to_lowercase(),
                        identifier,
                    );
                    self.report_recoverable_error(identifier, message);
                    return self.parse_primary(identifier, context, ConstantPatternContext::none);
                }
            }
        }

        token = self.ensure_identifier(token, context);
        let begin_token = token;
        // Type arguments may have been computed in a previous step but the
        // identifier may have been rewritten since then.
        let potential_type_arg = match potential_type_arg {
            Some(type_arg) => type_arg,
            None => compute_type_param_or_arg(&mut self.tokens, token, false, false),
        };
        if after_token == NO_TOKEN {
            after_token = self.next_after_skip(&potential_type_arg, token);
        }
        let type_arg =
            if self.is_a(after_token, TokenType::OPEN_PAREN) && !potential_type_arg.recovered() {
                potential_type_arg
            } else {
                noTypeParamOrArg
            };
        if type_arg != noTypeParamOrArg {
            token = type_arg.parse_arguments(token, self);
        }
        if constant_pattern_context == ConstantPatternContext::explicit
            && !(self.is_a(self.next(token), TokenType::PERIOD)
                || self.is_a(self.next(token), TokenType::OPEN_PAREN)
                || self.is_a(self.next(token), TokenType::LT))
        {
            self.report_recoverable_error(token, diag::invalidConstantPatternConstPrefix);
            constant_pattern_context = ConstantPatternContext::none;
        }
        let _ = constant_pattern_context;
        if type_arg == noTypeParamOrArg && !self.is_a(self.next(token), TokenType::OPEN_PAREN) {
            let next_14 = self.tokens.next(token);
            self.listener.handle_send_without_arguments(
                &mut self.tokens,
                begin_token,
                token,
                next_14,
            );
            return token;
        }
        if type_arg == noTypeParamOrArg {
            token = self.parse_arguments_opt(token, false);
            self.listener.handle_invocation_without_type_arguments(
                &mut self.tokens,
                begin_token,
                token,
            );
            return token;
        }
        token = self.parse_arguments_opt(token, false);
        self.listener
            .handle_send(&mut self.tokens, begin_token, token);
        token
    }

    pub fn skip_arguments_opt(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        self.listener.handle_no_arguments(&mut self.tokens, next);
        if self.is_a(next, TokenType::OPEN_PAREN) {
            self.tokens.end_group(next)
        } else {
            token
        }
    }

    pub fn parse_arguments_opt_metadata(
        &mut self,
        token: TokenId,
        has_type_arguments: bool,
    ) -> TokenId {
        let next = self.next(token);
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            self.listener.handle_no_arguments(&mut self.tokens, next);
            token
        } else if self.tokens.char_end(token) == self.tokens.char_offset(next) {
            self.parse_arguments(token)
        } else {
            if has_type_arguments {
                self.report_recoverable_error(next, diag::metadataSpaceBeforeParenthesis);
                return self.parse_arguments(token);
            }
            let start_paren = next;
            let end_paren = self.tokens.end_group(start_paren);
            let after_paren = self.next(end_paren);
            let value = self.sv(after_paren);
            if value == Some("class") || value == Some("enum") {
                // The `(` is not the start of a function type.
                self.report_recoverable_error(next, diag::metadataSpaceBeforeParenthesis);
                return self.parse_arguments(token);
            }
            self.listener.handle_no_arguments(&mut self.tokens, next);
            token
        }
    }

    pub fn parse_arguments_opt(&mut self, token: TokenId, _for_pattern: bool) -> TokenId {
        if self.kind != ParserKind::Parser {
            // `ClassMemberParser.parseArgumentsOpt`.
            return self.skip_arguments_opt(token);
        }
        let next = self.next(token);
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            self.listener.handle_no_arguments(&mut self.tokens, next);
            token
        } else {
            self.parse_arguments(token)
        }
    }

    /// ```text
    /// arguments:
    ///   '(' (argumentList ','?)? ')'
    /// ;
    /// ```
    pub fn parse_arguments(&mut self, token: TokenId) -> TokenId {
        let next = self.next(token);
        self.parse_arguments_rest(next)
    }

    pub fn parse_arguments_rest(&mut self, mut token: TokenId) -> TokenId {
        let begin = token;
        debug_assert!(self.is_a(begin, TokenType::OPEN_PAREN));
        self.listener.begin_arguments(&mut self.tokens, begin);
        let mut argument_count = 0;
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_PAREN) {
                token = next;
                break;
            }
            let mut colon = NO_TOKEN;
            if self.is_a(self.next(next), TokenType::COLON) || /* recovery */ self.is_a(next, TokenType::COLON)
            {
                token = self.ensure_identifier(token, IdentifierContext::namedArgumentReference);
                token = self.next(token);
                colon = token;
            }
            let mut expression_handled = false;
            let begin_expression_token = token;
            if self.allowed_to_shortcut_parse_expression() {
                let next1 = self.next(token);
                if self.is_a(next1, TokenType::IDENTIFIER) {
                    let next2 = self.next(next1);
                    if self.is_a(next2, TokenType::COMMA)
                        || self.is_a(next2, TokenType::CLOSE_PAREN)
                    {
                        self.listener.handle_identifier(
                            &mut self.tokens,
                            next1,
                            IdentifierContext::expression,
                        );
                        self.listener.handle_send_without_arguments(
                            &mut self.tokens,
                            next1,
                            next1,
                            next2,
                        );
                        token = next1;
                        expression_handled = true;
                    } else if self.is_a(next2, TokenType::PERIOD) {
                        let next3 = self.next(next2);
                        if self.is_a(next3, TokenType::IDENTIFIER) {
                            let next4 = self.next(next3);
                            if self.is_a(next4, TokenType::COMMA)
                                || self.is_a(next4, TokenType::CLOSE_PAREN)
                            {
                                self.listener.handle_identifier(
                                    &mut self.tokens,
                                    next1,
                                    IdentifierContext::expression,
                                );
                                self.listener.handle_send_without_arguments(
                                    &mut self.tokens,
                                    next1,
                                    next1,
                                    next2,
                                );
                                self.listener.handle_identifier(
                                    &mut self.tokens,
                                    next3,
                                    IdentifierContext::expressionContinuation,
                                );
                                self.listener.handle_send_without_arguments(
                                    &mut self.tokens,
                                    next3,
                                    next3,
                                    next4,
                                );
                                self.listener.handle_dot_access(
                                    &mut self.tokens,
                                    next2,
                                    next3,
                                    false,
                                );
                                token = next3;
                                expression_handled = true;
                            }
                        }
                    }
                } else if self.is_a(next1, TokenType::STRING) {
                    let next2 = self.next(next1);
                    if self.is_a(next2, TokenType::COMMA)
                        || self.is_a(next2, TokenType::CLOSE_PAREN)
                    {
                        self.listener.begin_literal_string(&mut self.tokens, next1);
                        self.listener.end_literal_string(&mut self.tokens, 0, next1);
                        token = next1;
                        expression_handled = true;
                    }
                }
            }
            if !expression_handled {
                token = self.parse_expression(token);
            }
            next = self.next(token);
            if colon != NO_TOKEN {
                self.listener.handle_named_argument(&mut self.tokens, colon);
            } else {
                let next_13 = self.tokens.next(begin_expression_token);
                self.listener
                    .handle_positional_argument(&mut self.tokens, next_13);
            }
            argument_count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                if self.is_a(next, TokenType::CLOSE_PAREN) {
                    token = next;
                    break;
                }
                // Recovery
                if looks_like_expression_start(&self.tokens, next) {
                    // If this looks like the start of an expression,
                    // then report an error, insert the comma, and continue parsing.
                    let offset = self.tokens.offset(next);
                    let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                    next = self.rewrite_and_recover(
                        token,
                        (diag::expectedButGot.with_arguments)(","),
                        comma,
                    );
                } else {
                    token = self.ensure_close_paren(token, begin);
                    break;
                }
            }
            token = next;
        }
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        self.may_parse_function_expressions = old;
        self.listener
            .end_arguments(&mut self.tokens, argument_count, begin, token);
        token
    }

    /// ```text
    /// typeTest::
    ///   'is' '!'? type
    /// ;
    /// ```
    pub fn parse_is_operator_rest(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let operator = token;
        debug_assert!(self.is_a(operator, kw::IS));
        let mut not = NO_TOKEN;
        if self.is_a(self.next(token), TokenType::BANG) {
            token = self.next(token);
            not = token;
        }
        self.listener
            .begin_is_operator_type(&mut self.tokens, operator);
        let type_info = self.compute_type_after_is_or_as(token);
        token = type_info.ensure_type_not_void(token, self);
        self.listener
            .end_is_operator_type(&mut self.tokens, operator);
        self.listener
            .handle_is_operator(&mut self.tokens, operator, not);
        self.skip_chained_as_is_operators(token)
    }

    pub fn compute_type_after_is_or_as(&mut self, token: TokenId) -> TypeInfo {
        let mut type_info = compute_type(&mut self.tokens, token, true, false, false);
        if type_info.is_nullable() {
            let skip_token = type_info.skip_type(&mut self.tokens, token);
            let next = self.next(skip_token);
            if self.is_a(next, TokenType::CLOSE_PAREN)
                || self.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                || self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET)
                || self.is_a(next, TokenType::QUESTION)
                || self.is_a(next, TokenType::QUESTION_QUESTION)
                || self.is_a(next, TokenType::COMMA)
                || self.is_a(next, TokenType::SEMICOLON)
                || self.is_a(next, TokenType::COLON)
                || self.is_a(next, kw::IS)
                || self.is_a(next, kw::AS)
                || self.is_a(next, TokenType::PERIOD_PERIOD)
                || self.is_a(next, TokenType::BAR_BAR)
                || self.is_a(next, TokenType::AMPERSAND_AMPERSAND)
                || self.is_a(next, TokenType::EOF)
            {
                return type_info;
            }
            if self.is_a(next, TokenType::OPEN_CURLY_BRACKET) || self.is_a(next, kw::WHEN) {
                // `?` could be a conditional or part of the type.
                let is_conditional = self.can_parse_as_conditional(skip_token);
                if !is_conditional {
                    return type_info;
                }
            }
            type_info = type_info.as_non_nullable();
        }
        type_info
    }

    /// ```text
    /// typeCast:
    ///   'as' type
    /// ;
    /// ```
    pub fn parse_as_operator_rest(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let operator = token;
        debug_assert!(self.is_a(operator, kw::AS));
        self.listener
            .begin_as_operator_type(&mut self.tokens, operator);
        let type_info = self.compute_type_after_is_or_as(token);
        token = type_info.ensure_type_not_void(token, self);
        self.listener
            .end_as_operator_type(&mut self.tokens, operator);
        self.listener.handle_as_operator(&mut self.tokens, operator);
        self.skip_chained_as_is_operators(token)
    }

    pub fn skip_chained_as_is_operators(&mut self, mut token: TokenId) -> TokenId {
        loop {
            let mut next = self.next(token);
            let value = self.sv(next);
            if value != Some("is") && value != Some("as") {
                return token;
            }
            // The is- and as-operators cannot be chained.
            // TODO(danrubel): Consider a better error message.
            self.report_recoverable_error_with_token(next, diag::unexpectedToken);
            if self.is_a(self.next(next), TokenType::BANG) {
                next = self.next(next);
            }
            let type_info = self.compute_type_after_is_or_as(next);
            token = type_info.skip_type(&mut self.tokens, next);
        }
    }

    /// Returns true if [token] could be the start of a function declaration
    /// without a return type.
    pub fn looks_like_local_function(&mut self, mut token: TokenId) -> bool {
        if self.tokens.is_identifier(token) {
            if self.is_a(self.next(token), TokenType::LT) {
                let type_param = compute_type_param_or_arg(&mut self.tokens, token, false, false);
                if type_param == noTypeParamOrArg {
                    return false;
                }
                token = type_param.skip(&mut self.tokens, token);
            }
            token = self.next(token);
            if self.is_a(token, TokenType::OPEN_PAREN) {
                token = self.next(self.tokens.end_group(token));
                return self.is_a(token, TokenType::OPEN_CURLY_BRACKET)
                    || self.is_a(token, TokenType::FUNCTION)
                    || self.is_a(token, kw::ASYNC)
                    || self.is_a(token, kw::SYNC);
            } else if self.is_a(token, TokenType::FUNCTION) {
                return true;
            }
        }
        false
    }

    pub fn looks_like_function_body(&self, token: TokenId) -> bool {
        self.is_a(token, TokenType::OPEN_CURLY_BRACKET)
            || self.is_a(token, TokenType::FUNCTION)
            || self.is_a(token, kw::ASYNC)
            || self.is_a(token, kw::SYNC)
    }

    pub fn parse_expression_statement_or_const_declaration(&mut self, start: TokenId) -> TokenId {
        let const_token = self.next(start);
        debug_assert!(self.is_a(const_token, kw::CONST));
        if !is_modifier(&self.tokens, self.next(const_token)) {
            let type_info = compute_type(&mut self.tokens, const_token, false, false, false);
            if type_info == noType {
                let mut next = self.next(const_token);
                if !self.tokens.is_identifier(next) {
                    return self.parse_expression_statement(start);
                }
                next = self.next(next);
                if !(self.is_a(next, TokenType::EQ)
                    // Recovery
                    || self.tokens.is_keyword_or_identifier(next)
                    || self.is_a(next, TokenType::SEMICOLON)
                    || self.is_a(next, TokenType::COMMA)
                    || self.is_a(next, TokenType::OPEN_CURLY_BRACKET))
                {
                    return self.parse_expression_statement(start);
                }
            }
            return self.parse_expression_statement_or_declaration_after_modifiers(
                const_token,
                start,
                NO_TOKEN,
                const_token,
                Some(type_info),
                None,
            );
        }
        self.parse_expression_statement_or_declaration(start, None)
    }

    pub fn parse_expression_statement_or_declaration(
        &mut self,
        start: TokenId,
        for_parts_context: Option<&mut ForPartsContext>,
    ) -> TokenId {
        let mut token = start;
        let mut next = self.next(token);
        if self.is_a(next, TokenType::AT) {
            token = self.parse_metadata_star(token);
            next = self.next(token);
        }

        let mut late_token = NO_TOKEN;
        let mut var_final_or_const = NO_TOKEN;

        if is_modifier(&self.tokens, next) {
            if self.is_a(next, kw::AUGMENT) && self.is_a(self.next(next), kw::SUPER) {
                // Special case: `augment super` expression.
                return self.parse_expression_statement(start);
            } else if self.is_a(next, kw::VAR)
                || self.is_a(next, kw::FINAL)
                || self.is_a(next, kw::CONST)
            {
                token = self.next(token);
                var_final_or_const = token;
                next = self.next(token);
            } else if self.is_a(next, kw::LATE) {
                token = next;
                late_token = token;
                next = self.next(token);
                if is_modifier(&self.tokens, next)
                    && (self.is_a(next, kw::VAR) || self.is_a(next, kw::FINAL))
                {
                    token = next;
                    var_final_or_const = token;
                    next = self.next(token);
                }
            }

            if is_modifier(&self.tokens, next) {
                // Recovery
                let mut context = ModifierContext::new();
                context.late_token = late_token;
                context.set_var_final_or_const(&self.tokens, var_final_or_const);

                token = context.parse_variable_declaration_modifiers(self, token);

                late_token = context.late_token;
                var_final_or_const = context.var_final_or_const();
            }
        }

        self.parse_expression_statement_or_declaration_after_modifiers(
            token,
            start,
            late_token,
            var_final_or_const,
            None,
            for_parts_context,
        )
    }

    /// See [parseExpressionStatementOrDeclaration]
    ///
    /// If `forPartsContext` is non-null and the token following `beforeType`
    /// does not start a variable declaration, then return `start` instead of
    /// parsing an expression statement.
    pub fn parse_expression_statement_or_declaration_after_modifiers(
        &mut self,
        before_type: TokenId,
        start: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        type_info: Option<TypeInfo>,
        for_parts_context: Option<&mut ForPartsContext>,
    ) -> TokenId {
        // Check for variable pattern declaration.
        if self.is_patterns_feature_enabled
            && var_final_or_const != NO_TOKEN
            && (self.is_a(var_final_or_const, kw::VAR) || self.is_a(var_final_or_const, kw::FINAL))
        {
            let after_outer_pattern = self.skip_outer_pattern(before_type);
            if after_outer_pattern != NO_TOKEN
                && (self.is_a(self.next(after_outer_pattern), TokenType::EQ)
                    || (for_parts_context.is_some()
                        && self.is_a(self.next(after_outer_pattern), kw::IN)))
            {
                if late_token != NO_TOKEN {
                    self.report_recoverable_error(late_token, diag::latePatternVariableDeclaration);
                }
                if !self.is_a(self.next(start), TokenType::AT) {
                    let next_12 = self.tokens.next(start);
                    self.listener.begin_metadata_star(&mut self.tokens, next_12);
                    self.listener.end_metadata_star(&mut self.tokens, 0);
                }
                if let Some(for_parts_context) = for_parts_context {
                    for_parts_context.pattern_keyword = var_final_or_const;
                    return self.parse_pattern(before_type, PatternContext::declaration, 1);
                } else {
                    return self.parse_pattern_variable_declaration_statement(
                        before_type,
                        start,
                        var_final_or_const,
                    );
                }
            }
        }

        let mut type_info = match type_info {
            Some(type_info) => type_info,
            None => compute_type(&mut self.tokens, before_type, false, false, false),
        };

        let mut token = type_info.skip_type(&mut self.tokens, before_type);
        let mut next = self.next(token);

        if for_parts_context.is_some() {
            if late_token != NO_TOKEN {
                self.report_recoverable_error_with_token(late_token, diag::extraneousModifier);
            }
        } else {
            if self.looks_like_local_function(next) {
                // Parse a local function declaration.
                if var_final_or_const != NO_TOKEN {
                    self.report_recoverable_error_with_token(
                        var_final_or_const,
                        diag::extraneousModifier,
                    );
                } else if late_token != NO_TOKEN {
                    self.report_recoverable_error_with_token(late_token, diag::extraneousModifier);
                }
                if !self.is_a(self.next(start), TokenType::AT) {
                    let next_11 = self.tokens.next(start);
                    self.listener.begin_metadata_star(&mut self.tokens, next_11);
                    self.listener.end_metadata_star(&mut self.tokens, 0);
                }
                let before_formals =
                    compute_type_param_or_arg(&mut self.tokens, next, false, false)
                        .parse_variables(next, self);
                let next_10 = self.tokens.next(start);
                self.listener
                    .begin_local_function_declaration(&mut self.tokens, next_10);
                token = type_info.parse_type(before_type, self);
                let begin = self.next(start);
                return self.parse_named_function_rest(token, begin, before_formals, false);
            }
        }

        if before_type == start && type_info.is_nullable() && type_info.could_be_expression() {
            debug_assert!(self.is_a(token, TokenType::QUESTION));
            if !looks_like_name(&self.tokens, next) {
                // Recovery: insert synthetic identifier.
                let message = (diag::expectedIdentifier.with_arguments)(&self.tokens, next);
                self.report_recoverable_error(next, message);
                next = self.rewriter().insert_synthetic_identifier(next);
            }
            let after_identifier = self.next(next);
            //
            // found <typeref> `?` <identifier>
            // with no annotations or modifiers preceding it
            //
            if self.is_a(after_identifier, TokenType::EQ) {
                //
                // found <typeref> `?` <identifier> `=`
                // with no annotations or modifiers preceding it
                //
                let original_listener =
                    std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
                let original_rewriter = self
                    .cached_rewriter
                    .replace(AnyRewriter::Undoable(UndoableTokenStreamRewriter::default()));
                let after_expression = self.parse_expression_without_cascade(after_identifier);
                let after_expression = self.next(after_expression);
                if let Some(AnyRewriter::Undoable(mut undoable)) = self.cached_rewriter.take() {
                    undoable.undo(&mut self.tokens);
                }
                self.listener = original_listener;
                self.cached_rewriter = original_rewriter;

                if self.is_a(after_expression, TokenType::COLON) {
                    // Looks like part of a conditional expression.
                    // Drop the type information and reset the last consumed token.
                    type_info = noType;
                    token = start;
                    next = self.next(token);
                }
            } else if !self.tokens.is_keyword(after_identifier)
                && !(self.is_a(after_identifier, TokenType::SEMICOLON)
                    || self.is_a(after_identifier, TokenType::COMMA)
                    || self.is_a(after_identifier, TokenType::CLOSE_PAREN)
                    || self.is_a(after_identifier, TokenType::EOF))
            {
                // Looks like part of a conditional expression.
                // Drop the type information and reset the last consumed token.
                type_info = noType;
                token = start;
                next = self.next(token);
            }
        }

        if token == start {
            // If no annotation, modifier, or type, and this is not a local function
            // then this must be an expression statement.
            if for_parts_context.is_some() {
                return start;
            } else {
                return self.parse_expression_statement(start);
            }
        }

        if self.tokens.type_(next).is_built_in()
            && before_type == start
            && type_info.could_be_expression()
        {
            // Detect expressions such as identifier `as` identifier
            // and treat those as expressions.
            if self.is_a(next, kw::AS) || self.is_a(next, kw::IS) {
                let kind = self.tokens.kind(self.next(next));
                if EQ_TOKEN != kind && SEMICOLON_TOKEN != kind && COMMA_TOKEN != kind {
                    if for_parts_context.is_some() {
                        if !self.is_a(self.next(next), kw::IN) {
                            return start;
                        }
                    } else {
                        return self.parse_expression_statement(start);
                    }
                }
            }
        }

        if self.tokens.is_identifier(next) {
            // Only report these errors if there is an identifier. If there is not an
            // identifier, then allow ensureIdentifier to report an error
            // and don't report errors here.
            if var_final_or_const == NO_TOKEN {
                if type_info == noType {
                    self.report_recoverable_error(next, diag::missingConstFinalVarOrType);
                }
            } else if self.is_a(var_final_or_const, kw::VAR) {
                if type_info != noType {
                    self.report_recoverable_error(var_final_or_const, diag::typeAfterVar);
                }
            }
        }

        if !self.is_a(self.next(start), TokenType::AT) {
            let next_9 = self.tokens.next(start);
            self.listener.begin_metadata_star(&mut self.tokens, next_9);
            self.listener.end_metadata_star(&mut self.tokens, 0);
        }
        if self.is_a(self.next(before_type), TokenType::LT) {
            // Recovery: `Foo<int> x` type args without type.
            let message =
                (diag::expectedIdentifier.with_arguments)(&self.tokens, self.next(before_type));
            self.insert_synthetic_identifier(
                before_type,
                IdentifierContext::localVariableDeclaration,
                Some(message),
                NO_TOKEN,
            );
            type_info = compute_type(&mut self.tokens, before_type, true, false, false);
        }
        token = type_info.parse_type(before_type, self);
        next = self.next(token);
        self.listener.begin_variables_declaration(
            &mut self.tokens,
            next,
            late_token,
            var_final_or_const,
        );
        if for_parts_context.is_none() {
            token = self.parse_variables_declaration_rest(token, true);
        }
        token
    }

    pub fn parse_variables_declaration_rest(
        &mut self,
        mut token: TokenId,
        end_with_semicolon: bool,
    ) -> TokenId {
        let mut count = 1;
        token = self.parse_optionally_initialized_identifier(token);
        while self.is_a(self.next(token), TokenType::COMMA) {
            let next = self.next(token);
            token = self.parse_optionally_initialized_identifier(next);
            count += 1;
        }
        if end_with_semicolon {
            let semicolon = self.ensure_semicolon(token);
            self.listener
                .end_variables_declaration(&mut self.tokens, count, semicolon);
            semicolon
        } else {
            self.listener
                .end_variables_declaration(&mut self.tokens, count, NO_TOKEN);
            token
        }
    }

    pub fn parse_optionally_initialized_identifier(&mut self, token: TokenId) -> TokenId {
        let name_token = self.ensure_identifier(token, IdentifierContext::localVariableDeclaration);
        self.listener
            .begin_initialized_identifier(&mut self.tokens, name_token);
        let token = self.parse_variable_initializer_opt(name_token);
        self.listener
            .end_initialized_identifier(&mut self.tokens, name_token);
        token
    }

    /// ```text
    /// ifStatement:
    ///   'if' '(' expression ')' statement ('else' statement)?
    /// ;
    /// ```
    pub fn parse_if_statement(&mut self, mut token: TokenId) -> TokenId {
        let if_token = self.next(token);
        debug_assert!(self.is_a(if_token, kw::IF));
        self.listener.begin_if_statement(&mut self.tokens, if_token);
        let allow_case = self.is_patterns_feature_enabled;
        token = self.ensure_parenthesized_condition(if_token, allow_case);
        let then_begin_token = self.next(token);
        self.listener
            .begin_then_statement(&mut self.tokens, then_begin_token);
        token = self.parse_statement(token);
        self.listener
            .end_then_statement(&mut self.tokens, then_begin_token, token);
        let mut else_token = NO_TOKEN;
        if self.is_a(self.next(token), kw::ELSE) {
            else_token = self.next(token);
            self.listener
                .begin_else_statement(&mut self.tokens, else_token);
            token = self.parse_statement(else_token);
            self.listener
                .end_else_statement(&mut self.tokens, else_token, token);
        }
        self.listener
            .end_if_statement(&mut self.tokens, if_token, else_token, token);
        token
    }

    /// ```text
    /// forStatement:
    ///   'await'? 'for' '(' forLoopParts ')' statement
    /// ;
    /// ```
    pub fn parse_for_statement(&mut self, mut token: TokenId, await_token: TokenId) -> TokenId {
        token = self.next(token);
        let for_token = token;
        debug_assert!(await_token == NO_TOKEN || self.is_a(await_token, kw::AWAIT));
        debug_assert!(self.is_a(token, kw::FOR));
        self.listener
            .begin_for_statement(&mut self.tokens, for_token);

        let mut for_parts_context = ForPartsContext::new();
        token = self.parse_for_loop_parts_start(await_token, for_token, &mut for_parts_context);
        let pattern_keyword = for_parts_context.pattern_keyword;
        if pattern_keyword != NO_TOKEN {
            if self.is_a(self.next(token), TokenType::EQ) {
                // Process `for ( pattern = expression ; ... ; ... )`
                let equals = self.next(token);
                token = self.parse_expression(equals);
                self.listener
                    .handle_for_initializer_pattern_variable_assignment(
                        &mut self.tokens,
                        pattern_keyword,
                        equals,
                    );
                return self.parse_for_rest(await_token, token, for_token);
            } else {
                // Process `for ( pattern in expression )`
                debug_assert!(self.is_a(self.next(token), kw::IN));
                return self.parse_for_in_rest(
                    token,
                    await_token,
                    for_token,
                    pattern_keyword,
                    NO_TOKEN,
                );
            }
        }
        let identifier = self.next(token);
        token = self.parse_for_loop_parts_mid(token, await_token, for_token);
        if self.is_a(self.next(token), kw::IN) || self.is_a(self.next(token), TokenType::COLON) {
            // Process `for ( ... in ... )`
            self.parse_for_in_rest(token, await_token, for_token, NO_TOKEN, identifier)
        } else {
            // Process `for ( ... ; ... ; ... )`
            self.parse_for_rest(await_token, token, for_token)
        }
    }

    /// Parse the start of a for loop control structure
    /// from the open parenthesis up to but not including the identifier.
    pub fn parse_for_loop_parts_start(
        &mut self,
        await_token: TokenId,
        for_token: TokenId,
        for_parts_context: &mut ForPartsContext,
    ) -> TokenId {
        let mut left_parenthesis = self.next(for_token);
        if !self.is_a(left_parenthesis, TokenType::OPEN_PAREN) {
            self.report_recoverable_error(
                left_parenthesis,
                (diag::expectedButGot.with_arguments)("("),
            );

            let offset = self.tokens.offset(left_parenthesis);
            let begin = self
                .tokens
                .synthetic_begin_token(TokenType::OPEN_PAREN, offset, NO_TOKEN);
            let open_paren = self.rewriter().insert_token(for_token, begin);

            let mut token;
            if await_token != NO_TOKEN {
                token = self.rewriter().insert_synthetic_identifier(open_paren);
                token = self.rewriter().insert_synthetic_keyword(token, Keyword::IN);
                token = self.rewriter().insert_synthetic_identifier(token);
            } else {
                token = self
                    .rewriter()
                    .insert_synthetic_token(open_paren, TokenType::SEMICOLON);
                token = self
                    .rewriter()
                    .insert_synthetic_token(token, TokenType::SEMICOLON);
            }

            let close = self.tokens.synthetic_token(TokenType::CLOSE_PAREN, offset);
            token = self.rewriter().insert_token(token, close);
            self.tokens.set_end_group(open_paren, token);

            token = self.rewriter().insert_synthetic_identifier(token);
            self.rewriter()
                .insert_synthetic_token(token, TokenType::SEMICOLON);

            left_parenthesis = open_paren;
        }

        // Pass `true` so that the [parseExpressionStatementOrDeclaration] only
        // parses the metadata, modifiers, and type of a local variable
        // declaration if it exists. This enables capturing [beforeIdentifier]
        // for later error reporting.
        self.parse_expression_statement_or_declaration(left_parenthesis, Some(for_parts_context))
    }

    /// Parse the remainder of the local variable declaration
    /// or an expression if no local variable declaration was found.
    pub fn parse_for_loop_parts_mid(
        &mut self,
        mut token: TokenId,
        await_token: TokenId,
        for_token: TokenId,
    ) -> TokenId {
        if token != self.next(for_token) {
            token = self.parse_variables_declaration_rest(token, false);
            let next = self.next(token);
            let is_in = self.is_a(next, kw::IN) || self.is_a(next, TokenType::COLON);
            self.listener
                .handle_for_initializer_local_variable_declaration(&mut self.tokens, token, is_in);
        } else if self.is_a(self.next(token), TokenType::SEMICOLON) {
            let next_8 = self.tokens.next(token);
            self.listener
                .handle_for_initializer_empty_statement(&mut self.tokens, next_8);
        } else {
            token = self.parse_expression(token);
            let next = self.next(token);
            let for_in = self.is_a(next, kw::IN)
                || self.is_a(next, TokenType::COLON)
                || (await_token != NO_TOKEN && self.is_a(next, TokenType::CLOSE_PAREN));
            self.listener.handle_for_initializer_expression_statement(
                &mut self.tokens,
                token,
                for_in,
            );
        }
        let next = self.next(token);
        if self.is_a(next, TokenType::SEMICOLON) {
            if await_token != NO_TOKEN {
                self.report_recoverable_error(await_token, diag::invalidAwaitFor);
            }
        } else if !self.is_a(next, kw::IN) {
            // Recovery
            if self.is_a(next, TokenType::COLON) {
                self.report_recoverable_error(next, diag::colonInPlaceOfIn);
            } else if await_token != NO_TOKEN {
                self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("in"));
                let offset = self.tokens.offset(next);
                let in_token = self.tokens.synthetic_keyword_token(Keyword::IN, offset);
                self.tokens.set_next(in_token, next);
                self.tokens.set_next(token, in_token);
            }
        }
        token
    }

    /// This method parses the portion of the for loop
    /// that follows the `for` keyword, starting with the open paren.
    pub fn parse_for_rest(
        &mut self,
        await_token: TokenId,
        mut token: TokenId,
        for_token: TokenId,
    ) -> TokenId {
        token = self.parse_for_loop_parts_rest(token, for_token, await_token);
        let next_7 = self.tokens.next(token);
        self.listener
            .begin_for_statement_body(&mut self.tokens, next_7);
        let saved_loop_state = self.loop_state;
        self.loop_state = LoopState::InsideLoop;
        token = self.parse_statement(token);
        self.loop_state = saved_loop_state;
        self.listener
            .end_for_statement_body(&mut self.tokens, token);
        self.listener.end_for_statement(&mut self.tokens, token);
        token
    }

    pub fn parse_for_loop_parts_rest(
        &mut self,
        mut token: TokenId,
        for_token: TokenId,
        _await_token: TokenId,
    ) -> TokenId {
        let left_parenthesis = self.next(for_token);
        debug_assert!(self.is_a(for_token, kw::FOR));
        debug_assert!(self.is_a(left_parenthesis, TokenType::OPEN_PAREN));

        let left_separator = self.ensure_semicolon(token);
        if self.is_a(self.next(left_separator), TokenType::SEMICOLON) {
            token = self.parse_empty_statement(left_separator);
        } else {
            token = self.parse_expression_statement(left_separator);
        }
        let right_separator = token;
        let mut expression_count = 0;
        loop {
            let next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_PAREN) {
                token = next;
                break;
            }
            token = self.parse_expression(token);
            token = self.next(token);
            expression_count += 1;
            if !self.is_a(token, TokenType::COMMA) {
                break;
            }
        }
        let end_group = self.tokens.end_group(left_parenthesis);
        if token != end_group {
            self.report_recoverable_error_with_token(token, diag::unexpectedToken);
            token = end_group;
        }
        self.listener.handle_for_loop_parts(
            &mut self.tokens,
            for_token,
            left_parenthesis,
            left_separator,
            right_separator,
            expression_count,
        );
        token
    }

    /// This method parses the portion of the for-in statement
    /// that follows the `for` keyword, starting with the open paren.
    pub fn parse_for_in_rest(
        &mut self,
        mut token: TokenId,
        await_token: TokenId,
        for_token: TokenId,
        pattern_keyword: TokenId,
        identifier: TokenId,
    ) -> TokenId {
        token = self.parse_for_in_loop_parts_rest(
            token,
            await_token,
            for_token,
            pattern_keyword,
            identifier,
        );
        let next_6 = self.tokens.next(token);
        self.listener.begin_for_in_body(&mut self.tokens, next_6);
        let saved_loop_state = self.loop_state;
        self.loop_state = LoopState::InsideLoop;
        token = self.parse_statement(token);
        self.loop_state = saved_loop_state;
        self.listener.end_for_in_body(&mut self.tokens, token);
        self.listener.end_for_in(&mut self.tokens, token);
        token
    }

    pub fn parse_for_in_loop_parts_rest(
        &mut self,
        mut token: TokenId,
        await_token: TokenId,
        for_token: TokenId,
        pattern_keyword: TokenId,
        identifier: TokenId,
    ) -> TokenId {
        let in_keyword = self.next(token);
        debug_assert!(self.is_a(for_token, kw::FOR));
        debug_assert!(self.is_a(self.next(for_token), TokenType::OPEN_PAREN));
        debug_assert!(self.is_a(in_keyword, kw::IN) || self.is_a(in_keyword, TokenType::COLON));

        if await_token != NO_TOKEN && !self.in_async() {
            self.report_recoverable_error(await_token, diag::awaitForNotAsync);
        }

        if identifier != NO_TOKEN {
            if !self.tokens.is_identifier(identifier) {
                self.report_recoverable_error_with_token(identifier, diag::expectedIdentifier);
            } else if identifier != token {
                let next = self.next(identifier);
                if self.is_a(next, TokenType::EQ) {
                    self.report_recoverable_error(next, diag::initializedVariableInForEach);
                } else {
                    self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                }
            }
        }

        let next_5 = self.tokens.next(in_keyword);
        self.listener
            .begin_for_in_expression(&mut self.tokens, next_5);
        token = self.parse_expression(in_keyword);
        let open_paren = self.next(for_token);
        token = self.ensure_close_paren(token, open_paren);
        self.listener.end_for_in_expression(&mut self.tokens, token);
        self.listener.handle_for_in_loop_parts(
            &mut self.tokens,
            await_token,
            for_token,
            open_paren,
            pattern_keyword,
            in_keyword,
        );
        token
    }

    /// ```text
    /// whileStatement:
    ///   'while' '(' expression ')' statement
    /// ;
    /// ```
    pub fn parse_while_statement(&mut self, mut token: TokenId) -> TokenId {
        let while_token = self.next(token);
        debug_assert!(self.is_a(while_token, kw::WHILE));
        self.listener
            .begin_while_statement(&mut self.tokens, while_token);
        token = self.ensure_parenthesized_condition(while_token, false);
        let next_4 = self.tokens.next(token);
        self.listener
            .begin_while_statement_body(&mut self.tokens, next_4);
        let saved_loop_state = self.loop_state;
        self.loop_state = LoopState::InsideLoop;
        token = self.parse_statement(token);
        self.loop_state = saved_loop_state;
        self.listener
            .end_while_statement_body(&mut self.tokens, token);
        self.listener
            .end_while_statement(&mut self.tokens, while_token, token);
        token
    }

    /// ```text
    /// doStatement:
    ///   'do' statement 'while' '(' expression ')' ';'
    /// ;
    /// ```
    pub fn parse_do_while_statement(&mut self, mut token: TokenId) -> TokenId {
        let do_token = self.next(token);
        debug_assert!(self.is_a(do_token, kw::DO));
        self.listener
            .begin_do_while_statement(&mut self.tokens, do_token);
        let next_3 = self.tokens.next(do_token);
        self.listener
            .begin_do_while_statement_body(&mut self.tokens, next_3);
        let saved_loop_state = self.loop_state;
        self.loop_state = LoopState::InsideLoop;
        token = self.parse_statement(do_token);
        self.loop_state = saved_loop_state;
        self.listener
            .end_do_while_statement_body(&mut self.tokens, token);
        let mut while_token = self.next(token);
        if !self.is_a(while_token, kw::WHILE) {
            self.report_recoverable_error(
                while_token,
                (diag::expectedButGot.with_arguments)("while"),
            );
            while_token = self
                .rewriter()
                .insert_synthetic_keyword(token, Keyword::WHILE);
        }
        token = self.ensure_parenthesized_condition(while_token, false);
        token = self.ensure_semicolon(token);
        self.listener
            .end_do_while_statement(&mut self.tokens, do_token, while_token, token);
        token
    }

    /// ```text
    /// block:
    ///   '{' statement* '}'
    /// ;
    /// ```
    pub fn parse_block(&mut self, mut token: TokenId, block_kind: BlockKind) -> TokenId {
        token = self.ensure_block(token, Some(block_kind));
        let begin = token;
        self.listener
            .begin_block(&mut self.tokens, begin, block_kind);
        let mut statement_count = 0;
        let mut start_token = self.next(token);
        while self.not_eof_or_type(TokenType::CLOSE_CURLY_BRACKET, start_token) {
            token = self.parse_statement(token);
            if self.next(token) == start_token {
                // No progress was made, so report an error and skip the token.
                token = self.next(token);
                let message = (diag::unexpectedToken.with_arguments)(&self.tokens, token);
                self.report_recoverable_error(token, message);
            }
            statement_count += 1;
            start_token = self.next(token);
        }
        token = self.next(token);
        debug_assert!(
            self.tokens.is_eof(token) || self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
        );
        self.listener
            .end_block(&mut self.tokens, statement_count, begin, token, block_kind);
        token
    }

    pub fn parse_invalid_block(&mut self, mut token: TokenId) -> TokenId {
        if self.kind != ParserKind::Parser {
            // `ClassMemberParser.parseInvalidBlock`.
            return self.skip_block(token);
        }
        let begin = self.next(token);
        debug_assert!(self.is_a(begin, TokenType::OPEN_CURLY_BRACKET));
        let original_listener =
            std::mem::replace(&mut self.listener, Box::new(NullListener::new()));
        let mut forwarding = ForwardingListener::new(Some(original_listener));
        forwarding.forward_errors = false;
        self.listener = Box::new(forwarding);
        token = self.parse_block(token, BlockKind::invalid);
        let original_listener = self
            .listener_as::<ForwardingListener>()
            .listener
            .take()
            .unwrap();
        self.listener = original_listener;
        self.listener
            .handle_invalid_top_level_block(&mut self.tokens, begin);
        token
    }

    /// Determine if the following tokens look like an expression and not a local
    /// variable or local function declaration.
    pub fn looks_like_expression_after_await_or_yield(
        &self,
        mut token: TokenId,
        context: AwaitOrYieldContext,
    ) -> bool {
        // TODO(srawlins): Consider parsing the potential expression once doing so
        //  does not modify the token stream. For now, use simple look ahead and
        //  ensure no false positives.

        token = self.next(token);
        if self.tokens.is_identifier(token) {
            token = self.next(token);
            if self.is_a(token, TokenType::OPEN_PAREN) {
                token = self.next(self.tokens.end_group(token));
                if self.is_a(token, TokenType::SEMICOLON)
                    || self.is_a(token, TokenType::PERIOD)
                    || self.is_a(token, TokenType::COMMA)
                    || self.is_a(token, TokenType::PERIOD_PERIOD)
                    || self.is_a(token, TokenType::QUESTION)
                    || self.is_a(token, TokenType::QUESTION_PERIOD)
                    || self.is_a(token, TokenType::CLOSE_PAREN)
                {
                    // E.g. `await foo();`
                    return true;
                } else if self.tokens.type_(token).is_binary_operator {
                    // E.g. `await foo() + 1`
                    return true;
                }
            } else if self.is_a(token, TokenType::PERIOD)
                || self.is_a(token, TokenType::CLOSE_PAREN)
                || self.is_a(token, TokenType::CLOSE_SQUARE_BRACKET)
            {
                // E.g. `await foo.bar;`
                return true;
            } else if self.is_a(token, TokenType::COMMA)
                && context == AwaitOrYieldContext::UnaryExpression
            {
                // E.g. `bar(await foo, 42);`
                return true;
            } else if self.tokens.type_(token).is_binary_operator {
                // E.g. `await foo + 1`
                return true;
            } else if self.is_a(token, TokenType::SEMICOLON)
                && context == AwaitOrYieldContext::UnaryExpression
            {
                // E.g. `int x = await foo;`
                return true;
            }
        } else if self
            .tokens
            .keyword(token)
            .is_some_and(|k| k.base.index == Keyword::NULL.base.index)
        {
            return true;
        }
        // TODO(srawlins): Consider whether other patterns should be considered.
        false
    }

    /// Determine if the following tokens look like an 'await' expression
    /// and not a local variable or local function declaration.
    pub fn looks_like_await_expression(
        &self,
        token: TokenId,
        context: AwaitOrYieldContext,
    ) -> bool {
        let token = self.next(token);
        debug_assert!(self.is_a(token, kw::AWAIT));
        self.looks_like_expression_after_await_or_yield(token, context)
    }

    /// Determine if the following tokens look like a 'yield' expression and not a
    /// local variable or local function declaration.
    pub fn looks_like_yield_statement(&self, token: TokenId, context: AwaitOrYieldContext) -> bool {
        let token = self.next(token);
        debug_assert!(self.is_a(token, kw::YIELD));
        self.looks_like_expression_after_await_or_yield(token, context)
    }

    /// ```text
    /// awaitExpression:
    ///   'await' unaryExpression
    /// ;
    /// ```
    pub fn parse_await_expression(&mut self, mut token: TokenId, allow_cascades: bool) -> TokenId {
        let await_token = self.next(token);
        debug_assert!(self.is_a(await_token, kw::AWAIT));
        self.listener
            .begin_await_expression(&mut self.tokens, await_token);
        token = self.parse_precedence_expression(
            await_token,
            POSTFIX_PRECEDENCE,
            allow_cascades,
            ConstantPatternContext::none,
        );
        if self.in_async() {
            self.listener
                .end_await_expression(&mut self.tokens, await_token, token);
        } else {
            self.report_recoverable_error(await_token, diag::awaitNotAsync);
            self.listener.end_invalid_await_expression(
                &mut self.tokens,
                await_token,
                token,
                &diag::awaitNotAsync,
            );
        }
        token
    }

    /// ```text
    /// throwExpression:
    ///   'throw' expression
    /// ;
    /// ```
    pub fn parse_throw_expression(&mut self, mut token: TokenId, allow_cascades: bool) -> TokenId {
        let throw_token = self.next(token);
        debug_assert!(self.is_a(throw_token, kw::THROW));
        if self.is_a(self.next(throw_token), TokenType::SEMICOLON) {
            // TODO(danrubel): Find a better way to intercept the parseExpression
            // recovery to generate this error message rather than explicitly
            // checking the next token as we are doing here.
            let next = self.next(throw_token);
            self.report_recoverable_error(next, diag::missingExpressionInThrow);
            let offset = self.tokens.char_offset(next);
            let index = self.tokens.add_string("\"\"".encode_utf16().collect());
            let string = self.tokens.synthetic_string_token(
                TokenType::STRING,
                crate::scanner::token::Lexeme::Owned(index),
                offset,
                Some(0),
            );
            self.rewriter().insert_token(throw_token, string);
        }
        token = if allow_cascades {
            self.parse_expression(throw_token)
        } else {
            self.parse_expression_without_cascade(throw_token)
        };
        self.listener
            .handle_throw_expression(&mut self.tokens, throw_token, token);
        token
    }

    /// ```text
    /// rethrowStatement:
    ///   'rethrow' ';'
    /// ;
    /// ```
    pub fn parse_rethrow_statement(&mut self, token: TokenId) -> TokenId {
        let throw_token = self.next(token);
        debug_assert!(self.is_a(throw_token, kw::RETHROW));
        self.listener
            .begin_rethrow_statement(&mut self.tokens, throw_token);
        let token = self.ensure_semicolon(throw_token);
        self.listener
            .end_rethrow_statement(&mut self.tokens, throw_token, token);
        token
    }

    /// ```text
    /// tryStatement:
    ///   'try' block (onPart+ finallyPart? | finallyPart)
    /// ;
    /// ```
    pub fn parse_try_statement(&mut self, token: TokenId) -> TokenId {
        let try_keyword = self.next(token);
        debug_assert!(self.is_a(try_keyword, kw::TRY));
        self.listener
            .begin_try_statement(&mut self.tokens, try_keyword);
        let mut last_consumed = self.parse_block(try_keyword, BlockKind::tryStatement);
        let mut token = self.next(last_consumed);
        let mut catch_count = 0;

        let mut value = self.sv(token);
        while value == Some("catch") || value == Some("on") {
            let mut did_begin_catch_clause = false;
            let mut on_keyword = NO_TOKEN;
            if value == Some("on") {
                // 'on' type catchPart?
                on_keyword = token;
                let type_info = compute_type(&mut self.tokens, token, true, false, false);
                self.listener.begin_catch_clause(&mut self.tokens, token);
                did_begin_catch_clause = true;
                last_consumed = type_info.ensure_type_not_void(token, self);
                token = self.next(last_consumed);
                value = self.sv(token);
            }
            let mut catch_keyword = NO_TOKEN;
            let mut comma = NO_TOKEN;
            if value == Some("catch") {
                if !did_begin_catch_clause {
                    self.listener.begin_catch_clause(&mut self.tokens, token);
                    did_begin_catch_clause = true;
                }
                catch_keyword = token;

                let mut open_parens = self.next(catch_keyword);
                if !self.is_a(open_parens, TokenType::OPEN_PAREN) {
                    self.report_recoverable_error(open_parens, diag::catchSyntax);
                    open_parens = self.rewriter().insert_parens(catch_keyword, true);
                }

                let mut exception_name = self.next(open_parens);
                if self.tokens.kind(exception_name) != IDENTIFIER_TOKEN {
                    exception_name =
                        IdentifierContext::catchParameter.ensure_identifier(open_parens, self);
                }

                if self.is_a(self.next(exception_name), TokenType::CLOSE_PAREN) {
                    // OK: `catch (identifier)`.
                } else {
                    comma = self.next(exception_name);
                    if !self.is_a(comma, TokenType::COMMA) {
                        // Recovery
                        if !self.tokens.is_synthetic(exception_name) {
                            self.report_recoverable_error(comma, diag::catchSyntax);
                        }

                        // TODO(danrubel): Consider inserting `on` clause if
                        // exceptionName is preceded by type and followed by a comma.
                        // Then this
                        //   } catch (E e, t) {
                        // will recover to
                        //   } on E catch (e, t) {
                        // with a detailed explanation for the user in the error message.

                        let end_group = self.tokens.end_group(open_parens);
                        if self.tokens.is_synthetic(end_group) {
                            // The scanner did not place the synthetic ')' correctly.
                            self.rewriter().move_synthetic(exception_name, end_group);
                            comma = NO_TOKEN;
                        } else {
                            comma = self
                                .rewriter()
                                .insert_synthetic_token(exception_name, TokenType::COMMA);
                        }
                    }
                    if comma != NO_TOKEN {
                        let mut trace_name = self.next(comma);
                        if self.tokens.kind(trace_name) != IDENTIFIER_TOKEN {
                            trace_name =
                                IdentifierContext::catchParameter.ensure_identifier(comma, self);
                        }
                        if !self.is_a(self.next(trace_name), TokenType::CLOSE_PAREN) {
                            // Recovery
                            if !self.tokens.is_synthetic(trace_name) {
                                let next = self.next(trace_name);
                                self.report_recoverable_error(
                                    next,
                                    diag::catchSyntaxExtraParameters,
                                );
                            }
                            let end_group = self.tokens.end_group(open_parens);
                            if self.tokens.is_synthetic(end_group) {
                                // The scanner did not place the synthetic ')' correctly.
                                self.rewriter().move_synthetic(trace_name, end_group);
                            }
                        }
                    }
                }
                last_consumed = self.parse_formal_parameters(catch_keyword, MemberKind::Catch);
                token = self.next(last_consumed);
            }
            self.listener.end_catch_clause(&mut self.tokens, token);
            last_consumed = self.parse_block(last_consumed, BlockKind::catchClause);
            token = self.next(last_consumed);
            catch_count += 1;
            self.listener
                .handle_catch_block(&mut self.tokens, on_keyword, catch_keyword, comma);
            value = self.sv(token); // while condition
        }

        let mut finally_keyword = NO_TOKEN;
        if self.is_a(token, kw::FINALLY) {
            finally_keyword = token;
            last_consumed = self.parse_block(token, BlockKind::finallyClause);
            self.listener
                .handle_finally_block(&mut self.tokens, finally_keyword);
        } else {
            if catch_count == 0 {
                self.report_recoverable_error(try_keyword, diag::onlyTry);
            }
        }
        self.listener.end_try_statement(
            &mut self.tokens,
            catch_count,
            try_keyword,
            finally_keyword,
            last_consumed,
        );
        last_consumed
    }

    /// ```text
    /// switchStatement:
    ///   'switch' parenthesizedExpression switchBlock
    /// ;
    /// ```
    pub fn parse_switch_statement(&mut self, mut token: TokenId) -> TokenId {
        let switch_keyword = self.next(token);
        debug_assert!(self.is_a(switch_keyword, kw::SWITCH));
        self.listener
            .begin_switch_statement(&mut self.tokens, switch_keyword);
        token = self.ensure_parenthesized_condition(switch_keyword, false);
        let saved_loop_state = self.loop_state;
        if self.loop_state == LoopState::OutsideLoop {
            self.loop_state = LoopState::InsideSwitch;
        }
        token = self.parse_switch_block(token);
        self.loop_state = saved_loop_state;
        self.listener
            .end_switch_statement(&mut self.tokens, switch_keyword, token);
        token
    }

    /// ```text
    /// switchBlock:
    ///   '{' switchCase* defaultCase? '}'
    /// ;
    /// ```
    pub fn parse_switch_block(&mut self, mut token: TokenId) -> TokenId {
        token = self.ensure_block(token, Some(BlockKind::switchStatement));
        let begin_switch = token;
        self.listener
            .begin_switch_block(&mut self.tokens, begin_switch);
        let mut case_count = 0;
        let mut has_default = false;
        while self.not_eof_or_type(TokenType::CLOSE_CURLY_BRACKET, self.next(token)) {
            let begin_case = self.next(token);
            let mut expression_count = 0;
            let mut label_count = 0;
            let mut default_keyword = NO_TOKEN;
            let mut colon_after_default = NO_TOKEN;
            let mut peek = self.peek_past_labels(begin_case);
            loop {
                // Loop until we find something that can't be part of a switch case.
                let value = self.sv(peek);
                if value == Some("default") {
                    while self.next(token) != peek {
                        token = self.parse_label(token);
                        label_count += 1;
                    }
                    if has_default {
                        let next = self.next(token);
                        self.report_recoverable_error(next, diag::switchHasMultipleDefaults);
                    }
                    has_default = true;
                    default_keyword = self.next(token);
                    token = self.ensure_colon(default_keyword);
                    colon_after_default = token;
                    peek = self.next(token);
                    break;
                } else if value == Some("case") {
                    while self.next(token) != peek {
                        token = self.parse_label(token);
                        label_count += 1;
                    }
                    let case_keyword = self.next(token);
                    if has_default {
                        self.report_recoverable_error(
                            case_keyword,
                            diag::switchHasCaseAfterDefault,
                        );
                    }
                    self.listener
                        .begin_case_expression(&mut self.tokens, case_keyword);
                    if self.is_patterns_feature_enabled {
                        token = self.parse_pattern(case_keyword, PatternContext::matching, 1);
                    } else {
                        token = self.parse_expression(case_keyword);
                    }
                    let next = self.next(token);
                    let mut when = NO_TOKEN;
                    if self.is_a(next, kw::WHEN) {
                        token = next;
                        when = token;
                        self.listener
                            .begin_switch_case_when_clause(&mut self.tokens, when);
                        token = self.parse_expression(token);
                        self.listener
                            .end_switch_case_when_clause(&mut self.tokens, token);
                    } else {
                        self.listener
                            .handle_switch_case_no_when_clause(&mut self.tokens, token);
                    }
                    token = self.ensure_colon(token);
                    self.listener
                        .end_case_expression(&mut self.tokens, case_keyword, when, token);
                    expression_count += 1;
                    peek = self.peek_past_labels(self.next(token));
                } else if expression_count > 0 {
                    break;
                } else {
                    // Recovery
                    self.report_recoverable_error(
                        peek,
                        (diag::expectedToken.with_arguments)("case"),
                    );
                    let end_group = self.tokens.end_group(begin_switch);
                    while self.next(token) != end_group {
                        token = self.next(token);
                    }
                    peek = self.peek_past_labels(self.next(token));
                    break;
                }
            }
            token = self.parse_statements_in_switch_case(
                token,
                peek,
                begin_case,
                label_count,
                expression_count,
                default_keyword,
                colon_after_default,
            );
            case_count += 1;
        }
        token = self.next(token);
        self.listener
            .end_switch_block(&mut self.tokens, case_count, begin_switch, token);
        debug_assert!(
            self.tokens.is_eof(token) || self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
        );
        token
    }

    /// Peek past the labels in a switch case.
    pub fn peek_past_labels(&self, mut token: TokenId) -> TokenId {
        while self.tokens.is_identifier(token) && self.is_a(self.next(token), TokenType::COLON) {
            token = self.next(self.next(token));
        }
        token
    }

    /// Parse statements after a switch `case:` or `default:`.
    pub fn parse_statements_in_switch_case(
        &mut self,
        mut token: TokenId,
        mut peek: TokenId,
        begin: TokenId,
        label_count: i32,
        expression_count: i32,
        default_keyword: TokenId,
        colon_after_default: TokenId,
    ) -> TokenId {
        self.listener
            .begin_switch_case(&mut self.tokens, label_count, expression_count, begin);
        // Finally zero or more statements.
        let mut statement_count = 0;
        while self.tokens.kind(self.next(token)) != EOF_TOKEN {
            let value = self.sv(peek);
            if value == Some("case")
                || value == Some("default")
                || (value == Some("}") && self.next(token) == peek)
            {
                // A label just before "}" will be handled as a statement error.
                break;
            } else {
                let start_token = self.next(token);
                token = self.parse_statement(token);
                let next = self.next(token);
                if next == start_token {
                    let message = (diag::unexpectedToken.with_arguments)(&self.tokens, next);
                    self.report_recoverable_error(next, message);
                    token = next;
                }
                statement_count += 1;
            }
            peek = self.peek_past_labels(self.next(token));
        }
        self.listener.end_switch_case(
            &mut self.tokens,
            label_count,
            expression_count,
            default_keyword,
            colon_after_default,
            statement_count,
            begin,
            token,
        );
        token
    }

    /// ```text
    /// breakStatement:
    ///   'break' identifier? ';'
    /// ;
    /// ```
    pub fn parse_break_statement(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let break_keyword = token;
        debug_assert!(self.is_a(break_keyword, kw::BREAK));
        let mut has_target = false;
        if self.tokens.is_identifier(self.next(token)) {
            token = self.ensure_identifier(token, IdentifierContext::labelReference);
            has_target = true;
        } else if !self.is_break_allowed() {
            self.report_recoverable_error(break_keyword, diag::breakOutsideOfLoop);
        }
        token = self.ensure_semicolon(token);
        self.listener
            .handle_break_statement(&mut self.tokens, has_target, break_keyword, token);
        token
    }

    /// ```text
    /// assertion:
    ///   'assert' '(' expression (',' expression)? ','? ')'
    /// ;
    /// ```
    pub fn parse_assert(&mut self, mut token: TokenId, kind: Assert) -> TokenId {
        token = self.next(token);
        debug_assert!(self.is_a(token, kw::ASSERT));
        self.listener.begin_assert(&mut self.tokens, token, kind);
        let assert_keyword = token;
        let mut left_parenthesis = self.next(token);
        if !self.is_a(left_parenthesis, TokenType::OPEN_PAREN) {
            // Recovery
            self.report_recoverable_error(
                left_parenthesis,
                (diag::expectedButGot.with_arguments)("("),
            );
            left_parenthesis = self.rewriter().insert_parens(token, true);
        }
        token = left_parenthesis;
        let mut comma_token = NO_TOKEN;
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;

        token = self.parse_expression(token);
        if self.is_a(self.next(token), TokenType::COMMA) {
            token = self.next(token);
            if !self.is_a(self.next(token), TokenType::CLOSE_PAREN) {
                comma_token = token;
                token = self.parse_expression(token);
                if self.is_a(self.next(token), TokenType::COMMA) {
                    // Trailing comma is ignored.
                    token = self.next(token);
                }
            }
        }

        let end_group = self.tokens.end_group(left_parenthesis);
        if self.next(token) == end_group {
            token = end_group;
        } else {
            // Recovery
            if self.tokens.is_synthetic(end_group) {
                // The scanner did not place the synthetic ')' correctly, so move it.
                token = self.rewriter().move_synthetic(token, end_group);
            } else {
                let next = self.next(token);
                self.report_recoverable_error_with_token(next, diag::unexpectedToken);
                token = end_group;
            }
        }

        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        self.may_parse_function_expressions = old;
        if kind == Assert::Expression {
            self.report_recoverable_error(assert_keyword, diag::assertAsExpression);
        } else if kind == Assert::Statement {
            self.ensure_semicolon(token);
        }
        self.listener.end_assert(
            &mut self.tokens,
            assert_keyword,
            kind,
            left_parenthesis,
            comma_token,
            token,
        );
        token
    }

    /// ```text
    /// assertStatement:
    ///   assertion ';'
    /// ;
    /// ```
    pub fn parse_assert_statement(&mut self, token: TokenId) -> TokenId {
        debug_assert!(self.is_a(self.next(token), kw::ASSERT));
        let token = self.parse_assert(token, Assert::Statement);
        self.next(token)
    }

    /// ```text
    /// continueStatement:
    ///   'continue' identifier? ';'
    /// ;
    /// ```
    pub fn parse_continue_statement(&mut self, mut token: TokenId) -> TokenId {
        token = self.next(token);
        let continue_keyword = token;
        debug_assert!(self.is_a(continue_keyword, kw::CONTINUE));
        let mut has_target = false;
        if self.tokens.is_identifier(self.next(token)) {
            token = self.ensure_identifier(token, IdentifierContext::labelReference);
            has_target = true;
            if !self.is_continue_with_label_allowed() {
                self.report_recoverable_error(continue_keyword, diag::continueOutsideOfLoop);
            }
        } else if !self.is_continue_allowed() {
            let message = if self.loop_state == LoopState::InsideSwitch {
                diag::continueWithoutLabelInCase
            } else {
                diag::continueOutsideOfLoop
            };
            self.report_recoverable_error(continue_keyword, message);
        }
        token = self.ensure_semicolon(token);
        self.listener.handle_continue_statement(
            &mut self.tokens,
            has_target,
            continue_keyword,
            token,
        );
        token
    }

    /// ```text
    /// emptyStatement:
    ///   ';'
    /// ;
    /// ```
    pub fn parse_empty_statement(&mut self, token: TokenId) -> TokenId {
        let token = self.next(token);
        debug_assert!(self.is_a(token, TokenType::SEMICOLON));
        self.listener
            .handle_empty_statement(&mut self.tokens, token);
        token
    }

    /// Given a token ([beforeToken]) in a token stream, return the next token
    /// before [token] in the stream.
    pub fn previous_token(&self, mut before_token: TokenId, token: TokenId) -> TokenId {
        let mut next = self.next(before_token);
        while next != token && next != before_token {
            before_token = next;
            next = self.next(before_token);
        }
        before_token
    }

    /// Recover from finding an operator declaration missing the `operator`
    /// keyword. The metadata for the member, if any, has already been parsed
    /// (and events have already been generated).
    pub fn parse_invalid_operator_declaration(
        &mut self,
        before_start: TokenId,
        abstract_token: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        before_type: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
    ) -> TokenId {
        let mut type_info = compute_type(&mut self.tokens, before_start, false, true, false);
        let mut before_name = type_info.skip_type(&mut self.tokens, before_type);
        let mut next = self.next(before_name);

        if self.is_a(next, kw::OPERATOR) {
            next = self.next(next);
        } else {
            // The 'operator' keyword is missing, but we may or may not have a type
            // before the token that is the actual operator.
            let mut operator = next;
            if !self.tokens.is_operator(next) && self.tokens.is_operator(self.next(next)) {
                before_name = next;
                operator = self.next(next);
            }
            self.report_recoverable_error(operator, diag::missingOperatorKeyword);
            self.rewriter()
                .insert_synthetic_keyword(before_name, Keyword::OPERATOR);

            // Having inserted the keyword the type now might be parsable.
            type_info = compute_type(&mut self.tokens, before_start, true, true, false);
            before_name = type_info.skip_type(&mut self.tokens, before_type);
            next = self.next(before_name);

            // The 'next' token can be the just-inserted 'operator' keyword.
            // If it is, change it to the actual operator.
            if !self.tokens.is_operator(next)
                && self.tokens.is_operator(self.next(next))
                && self.sv(next) == Some("operator")
            {
                next = self.next(next);
            }
        }

        debug_assert!(
            (self.tokens.is_operator(next) && self.tokens.end_group(next) == NO_TOKEN)
                || self.is_a(next, TokenType::EQ_EQ_EQ)
                || self.is_a(next, TokenType::BANG_EQ_EQ)
        );

        let name = self.next(before_name);
        let token = self.parse_method(
            before_start,
            abstract_token,
            augment_token,
            external_token,
            static_token,
            covariant_token,
            late_token,
            var_final_or_const,
            before_type,
            type_info,
            NO_TOKEN,
            NO_TOKEN,
            name,
            kind,
            enclosing_declaration_name,
            false,
        );
        self.listener.end_member(&mut self.tokens);
        token
    }

    /// Recover from finding an invalid class member. The metadata for the member,
    /// if any, has already been parsed (and events have already been generated).
    /// The member was expected to start with the token after [token].
    pub fn recover_from_invalid_member(
        &mut self,
        mut token: TokenId,
        before_start: TokenId,
        abstract_token: TokenId,
        augment_token: TokenId,
        external_token: TokenId,
        static_token: TokenId,
        covariant_token: TokenId,
        late_token: TokenId,
        var_final_or_const: TokenId,
        before_type: TokenId,
        type_info: TypeInfo,
        get_or_set: TokenId,
        new_token: TokenId,
        kind: DeclarationKind,
        enclosing_declaration_name: Option<&str>,
    ) -> TokenId {
        let next = self.next(token);
        let value = self.sv(next);
        if value == Some("class") {
            return self.report_and_skip_class_in_class(next);
        } else if value == Some("enum") {
            return self.report_and_skip_enum_in_class(next);
        } else if value == Some("typedef") {
            return self.report_and_skip_typedef_in_class(next);
        } else if self.tokens.is_operator(next) && self.tokens.end_group(next) == NO_TOKEN {
            return self.parse_invalid_operator_declaration(
                before_start,
                abstract_token,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                before_type,
                kind,
                enclosing_declaration_name,
            );
        }

        if get_or_set != NO_TOKEN || value == Some("(") || value == Some("=>") || value == Some("{")
        {
            let name = self.next(token);
            token = self.parse_method(
                before_start,
                abstract_token,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                before_type,
                type_info,
                get_or_set,
                new_token,
                name,
                kind,
                enclosing_declaration_name,
                false,
            );
        } else if token == before_start {
            // TODO(danrubel): Provide a more specific error message for extra ';'.
            self.report_recoverable_error_with_token(next, diag::expectedClassMember);
            self.listener.handle_invalid_member(&mut self.tokens, next);
            if value != Some("}") {
                // Ensure we make progress.
                token = next;
            }
        } else {
            let name = self.next(token);
            token = self.parse_fields(
                before_start,
                abstract_token,
                augment_token,
                external_token,
                static_token,
                covariant_token,
                late_token,
                var_final_or_const,
                before_type,
                type_info,
                name,
                kind,
                enclosing_declaration_name,
                false,
            );
        }

        self.listener.end_member(&mut self.tokens);
        token
    }

    /// Report that the nesting depth of the code being parsed is too large for
    /// the parser to safely handle. Return the next `}` or EOF.
    pub fn recover_from_stack_overflow(&mut self, mut token: TokenId) -> TokenId {
        let next = self.next(token);
        self.report_recoverable_error(next, diag::stackOverflow);
        let mut next = self
            .rewriter()
            .insert_synthetic_token(token, TokenType::SEMICOLON);
        self.listener.handle_empty_statement(&mut self.tokens, next);

        while self.not_eof_or_type(TokenType::CLOSE_CURLY_BRACKET, next) {
            token = next;
            next = self.next(token);
        }
        token
    }

    pub fn parse_invalid_top_level_declaration(&mut self, token: TokenId) -> TokenId {
        let mut next = self.next(token);
        let template = if self.is_a(next, TokenType::SEMICOLON) {
            diag::unexpectedToken
        } else {
            diag::expectedDeclaration
        };
        self.report_recoverable_error_with_token(next, template);
        if self.is_a(next, TokenType::OPEN_CURLY_BRACKET) {
            next = self.parse_invalid_block(token);
        }
        self.listener
            .handle_invalid_top_level_declaration(&mut self.tokens, next);
        next
    }

    pub fn report_and_skip_class_in_class(&mut self, mut token: TokenId) -> TokenId {
        debug_assert!(self.is_a(token, kw::CLASS));
        self.report_recoverable_error(token, diag::classInClass);
        self.listener.handle_invalid_member(&mut self.tokens, token);
        let mut next = self.next(token);
        // If the declaration appears to be a valid class declaration
        // then skip the entire declaration so that we only generate the one
        // error (above) rather than a plethora of unhelpful errors.
        if self.tokens.is_identifier(next) {
            token = next;
            next = self.next(token);
            // TODO(danrubel): consider parsing (skipping) the class header
            // with a recovery listener so that no events are generated
            if self.is_a(next, TokenType::OPEN_CURLY_BRACKET)
                && self.tokens.end_group(next) != NO_TOKEN
            {
                token = self.tokens.end_group(next);
            }
        }
        self.listener.end_member(&mut self.tokens);
        token
    }

    pub fn report_and_skip_enum_in_class(&mut self, mut token: TokenId) -> TokenId {
        debug_assert!(self.is_a(token, kw::ENUM));
        self.report_recoverable_error(token, diag::enumInClass);
        self.listener.handle_invalid_member(&mut self.tokens, token);
        let mut next = self.next(token);
        // If the declaration appears to be a valid enum declaration
        // then skip the entire declaration so that we only generate the one
        // error (above) rather than a plethora of unhelpful errors.
        if self.tokens.is_identifier(next) {
            token = next;
            next = self.next(token);
            if self.is_a(next, TokenType::OPEN_CURLY_BRACKET)
                && self.tokens.end_group(next) != NO_TOKEN
            {
                token = self.tokens.end_group(next);
            }
        }
        self.listener.end_member(&mut self.tokens);
        token
    }

    pub fn report_and_skip_typedef_in_class(&mut self, token: TokenId) -> TokenId {
        debug_assert!(self.is_a(token, kw::TYPEDEF));
        self.report_recoverable_error(token, diag::typedefInClass);
        self.listener.handle_invalid_member(&mut self.tokens, token);
        // TODO(brianwilkerson): If the declaration appears to be a valid typedef
        // then skip the entire declaration so that we generate a single error
        // (above) rather than many unhelpful errors.
        self.listener.end_member(&mut self.tokens);
        token
    }

    /// Returns the documentation comment before [token], if any.
    pub fn find_dart_doc(&self, token: TokenId) -> TokenId {
        let mut comments = self.tokens.preceding_comments(token);
        let mut dartdoc = NO_TOKEN;
        let mut is_multiline = false;
        while comments != NO_TOKEN {
            let lexeme = self.tokens.lexeme_string(comments);
            if lexeme.starts_with("///") {
                if !is_multiline {
                    dartdoc = comments;
                    is_multiline = true;
                }
            } else if lexeme.starts_with("/**") {
                dartdoc = comments;
                is_multiline = false;
            }
            comments = self.next(comments);
        }
        dartdoc
    }

    /// Parses the pattern starting at [token]. Returns the last consumed
    /// token. (`precedence` is upstream's named parameter, default 1.)
    pub fn parse_pattern(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
        precedence: i32,
    ) -> TokenId {
        debug_assert!(precedence >= 1);
        debug_assert!(precedence <= SELECTOR_PRECEDENCE);
        self.listener.begin_pattern(&mut self.tokens, token);
        let start = self.next(token);
        token = self.parse_primary_pattern(token, pattern_context);
        loop {
            let next = self.next(token);
            let token_level = self.compute_precedence(next, true);
            if token_level < precedence {
                self.listener.end_pattern(&mut self.tokens, token);
                return token;
            }
            match self.tokens.lexeme_string(next).as_str() {
                // TODO(paulberry): add more operators as they are supported by
                // the grammar
                "as" => {
                    if !self.is_last_pattern_allowed_inside_unary_pattern {
                        self.report_recoverable_error_with_end(
                            start,
                            token,
                            diag::invalidInsideUnaryPattern,
                        );
                    }
                    token = next;
                    let operator = token;
                    self.listener
                        .begin_as_operator_type(&mut self.tokens, token);
                    let type_info = self.compute_type_after_is_or_as(token);
                    token = type_info.ensure_type_not_void(token, self);
                    self.listener
                        .end_as_operator_type(&mut self.tokens, operator);
                    self.listener
                        .handle_cast_pattern(&mut self.tokens, operator);
                }
                "!" => {
                    if !self.is_last_pattern_allowed_inside_unary_pattern {
                        self.report_recoverable_error_with_end(
                            start,
                            token,
                            diag::invalidInsideUnaryPattern,
                        );
                    }
                    self.listener
                        .handle_null_assert_pattern(&mut self.tokens, next);
                    token = next;
                }
                "?" => {
                    if !self.is_last_pattern_allowed_inside_unary_pattern {
                        self.report_recoverable_error_with_end(
                            start,
                            token,
                            diag::invalidInsideUnaryPattern,
                        );
                    }
                    self.listener
                        .handle_null_check_pattern(&mut self.tokens, next);
                    token = next;
                }
                "&&" | "||" => {
                    self.listener.begin_binary_pattern(&mut self.tokens, next);
                    // Left associative, so we recurse at the next higher precedence
                    // level.
                    token = self.parse_pattern(next, pattern_context, token_level + 1);
                    self.listener.end_binary_pattern(&mut self.tokens, next);
                }
                _ => {
                    // Some other operator that doesn't belong in a pattern
                    self.listener.end_pattern(&mut self.tokens, token);
                    return token;
                }
            }
            // None of the pattern types handled by the switch above are valid
            // inside a unary pattern.
            self.is_last_pattern_allowed_inside_unary_pattern = false;
        }
    }

    /// Parses a primary pattern starting at [token]. Returns the last consumed
    /// token. (Upstream's assertions that re-skip the pattern are not ported:
    /// they are disabled in the oracle, and skipping can allocate tokens.)
    pub fn parse_primary_pattern(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
    ) -> TokenId {
        let type_arg = compute_type_param_or_arg(&mut self.tokens, token, true, false);
        let mut next = self.next_after_skip(&type_arg, token);
        match self.tokens.lexeme_string(next).as_str() {
            "[]" | "[" => {
                // listPattern
                token = type_arg.parse_arguments(token, self);
                token = self.parse_list_pattern_suffix(token, pattern_context);
                // A list pattern is a primary pattern so it's allowed inside unary
                // patterns.
                self.is_last_pattern_allowed_inside_unary_pattern = true;
                return token;
            }
            "{" => {
                // mapPattern
                token = type_arg.parse_arguments(token, self);
                token = self.parse_map_pattern_suffix(token, pattern_context);
                // A map pattern is a primary pattern so it's allowed inside unary
                // patterns.
                self.is_last_pattern_allowed_inside_unary_pattern = true;
                return token;
            }
            _ => {}
        }
        // Whatever was after the optional type arguments didn't parse as a pattern
        // that can start with type arguments, so back up and reparse assuming that
        // there are no type arguments.
        next = self.next(token);
        match self.tokens.lexeme_string(next).as_str() {
            "var" | "final" => {
                // variablePattern ::= ( 'var' | 'final' | 'final'? type )? identifier
                // A variable pattern is a primary pattern so it's allowed inside unary
                // patterns.
                self.is_last_pattern_allowed_inside_unary_pattern = true;
                return self.parse_variable_pattern(token, pattern_context, noType);
            }
            "(" => {
                // "(" could start a record type (which has to be followed by an
                // identifier though), e.g. `(int, int) foo`.
                let after_end_group = self.next(self.tokens.end_group(next));
                if self.tokens.is_identifier(after_end_group)
                    || (self.is_a(after_end_group, TokenType::QUESTION)
                        && self.tokens.is_identifier(self.next(after_end_group)))
                {
                    let type_info = compute_variable_pattern_type(&mut self.tokens, token, true);
                    if let TypeInfo::Complex(info) = &type_info {
                        let is_record = {
                            let info = info.borrow();
                            info.is_record_type && !info.recovered
                        };
                        if is_record {
                            // A variable pattern is a primary pattern so it's allowed
                            // inside unary patterns.
                            self.is_last_pattern_allowed_inside_unary_pattern = true;
                            return self.parse_variable_pattern(token, pattern_context, type_info);
                        }
                    }
                }
                // parenthesizedPattern  ::= '(' pattern ')'
                // recordPattern         ::= '(' patterns? ')'
                // patterns              ::= patternField ( ',' patternField )* ','?
                // patternField          ::= ( identifier? ':' )? pattern
                let next_next = self.next(next);
                if self.is_a(next_next, TokenType::CLOSE_PAREN) {
                    self.listener
                        .handle_record_pattern(&mut self.tokens, next, 0);
                    token = next_next;
                } else {
                    token =
                        self.parse_parenthesized_pattern_or_record_pattern(token, pattern_context);
                }
                // A record or parenthesized pattern is a primary pattern so it's
                // allowed inside unary patterns.
                self.is_last_pattern_allowed_inside_unary_pattern = true;
                return token;
            }
            "const" => {
                // constantPattern ::= booleanLiteral
                //                   | nullLiteral
                //                   | numericLiteral
                //                   | stringLiteral
                //                   | identifier
                //                   | qualifiedName
                //                   | constObjectExpression
                //                   | 'const' typeArguments? '[' elements? ']'
                //                   | 'const' typeArguments? '{' elements? '}'
                //                   | 'const' '(' expression ')'
                let const_ = next;
                self.listener
                    .begin_constant_pattern(&mut self.tokens, const_);
                token = self.parse_precedence_expression(
                    const_,
                    EQUALITY_PRECEDENCE,
                    false,
                    ConstantPatternContext::explicit,
                );
                self.listener.end_constant_pattern(&mut self.tokens, const_);
                // A constant pattern is a primary pattern so it's allowed inside unary
                // patterns.
                self.is_last_pattern_allowed_inside_unary_pattern = true;
                return token;
            }
            _ => {}
        }
        let type_ = self.tokens.type_(next);
        if type_.is_relational_operator() || type_.is_equality_operator() {
            // relationalPattern ::= relationalOperator bitwiseOrExpression
            let operator = next;
            token = self.parse_precedence_expression(
                next,
                BITWISE_OR_PRECEDENCE,
                false,
                ConstantPatternContext::none,
            );
            self.listener
                .handle_relational_pattern(&mut self.tokens, operator);
            // A relational pattern is a unary pattern so it's not allowed inside
            // another unary pattern.
            self.is_last_pattern_allowed_inside_unary_pattern = false;
            return token;
        }
        let type_info = compute_variable_pattern_type(&mut self.tokens, token, false);
        if type_info != noType {
            // A variable pattern is a primary pattern so it's allowed inside unary
            // patterns.
            self.is_last_pattern_allowed_inside_unary_pattern = true;
            return self.parse_variable_pattern(token, pattern_context, type_info);
        }
        // objectPattern ::= typeName typeArguments? '(' patternFields? ')'
        // TODO(paulberry): Make sure OTHER_IDENTIFIER is handled
        // TODO(paulberry): Technically `dynamic` is valid for
        // `typeIdentifier`--file an issue
        if self.tokens.is_identifier(next) {
            let before_first_identifier = token;
            token = next;
            let first_identifier = token;
            next = self.next(token);
            let mut dot = NO_TOKEN;
            let mut second_identifier = NO_TOKEN;
            if self.is_a(next, TokenType::PERIOD) {
                token = next;
                dot = token;
                next = self.next(token);
                if self.tokens.is_identifier(next) {
                    token = next;
                    second_identifier = token;
                } else {
                    second_identifier =
                        IdentifierContext::expressionContinuation.ensure_identifier(token, self);
                }
            }
            let potential_type_arg =
                compute_type_param_or_arg(&mut self.tokens, token, false, false);
            let after_token = self.next_after_skip(&potential_type_arg, token);
            if self.is_a(after_token, TokenType::OPEN_PAREN) && !potential_type_arg.recovered() {
                let type_arg = potential_type_arg;
                token = type_arg.parse_arguments(token, self);
                token = self.parse_object_pattern_rest(token, pattern_context);
                self.listener.handle_object_pattern(
                    &mut self.tokens,
                    first_identifier,
                    dot,
                    second_identifier,
                );
                // An object pattern is a primary pattern so it's allowed inside unary
                // patterns.
                self.is_last_pattern_allowed_inside_unary_pattern = true;
                return token;
            } else if dot == NO_TOKEN {
                // It's a single identifier.  If it's a wildcard pattern or we're in an
                // irrefutable context, parse it as a variable pattern.
                let name = self.tokens.lexeme_string(first_identifier);
                if !pattern_context.is_refutable() || name == "_" {
                    // It's a wildcard pattern with no preceding type, so parse it as a
                    // variable pattern.
                    self.is_last_pattern_allowed_inside_unary_pattern = true;
                    return self.parse_variable_pattern(
                        before_first_identifier,
                        pattern_context,
                        type_info,
                    );
                } else if illegalPatternIdentifiers.contains(&name.as_str()) {
                    let message = (diag::illegalPatternIdentifierName.with_arguments)(
                        &self.tokens,
                        first_identifier,
                    );
                    self.report_recoverable_error(first_identifier, message);
                }
            }
            // It's not an object pattern so parse it as an expression.
            token = before_first_identifier;
        }
        self.listener
            .begin_constant_pattern(&mut self.tokens, NO_TOKEN);
        token = self.parse_precedence_expression(
            token,
            EQUALITY_PRECEDENCE,
            false,
            ConstantPatternContext::implicit,
        );
        self.listener
            .end_constant_pattern(&mut self.tokens, NO_TOKEN);
        // A constant pattern is a primary pattern so it's allowed inside unary
        // patterns.
        self.is_last_pattern_allowed_inside_unary_pattern = true;
        token
    }

    /// Parses a variable pattern starting at [token]. Returns the last consumed
    /// token. (`typeInfo` is upstream's named parameter, default `noType`.)
    pub fn parse_variable_pattern(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
        mut type_info: TypeInfo,
    ) -> TokenId {
        let mut is_bare_identifier = false;
        let mut keyword = NO_TOKEN;
        if type_info != noType {
            token = type_info.parse_type(token, self);
        } else {
            let next = self.next(token);
            if self.is_a(next, kw::VAR) || self.is_a(next, kw::FINAL) {
                token = next;
                keyword = token;
                let next_is_paren = self.is_a(self.next(token), TokenType::OPEN_PAREN);
                // For the sake of recovery, we allow a nonsensical parenthesized type
                // after `var` or `final` when the type is itself a record type.
                type_info = compute_variable_pattern_type(&mut self.tokens, token, next_is_paren);
                token = type_info.parse_type(token, self);
            } else {
                is_bare_identifier = true;
            }
        }
        let next = self.next(token);
        if self.tokens.is_identifier(next) {
            token = next;
        } else {
            // Recovery
            token = self.insert_synthetic_identifier(
                token,
                IdentifierContext::localVariableDeclaration,
                None,
                NO_TOKEN,
            );
        }
        let variable_name = self.tokens.lexeme_string(token);
        match pattern_context {
            PatternContext::declaration => {
                if keyword != NO_TOKEN {
                    self.report_recoverable_error(
                        keyword,
                        diag::variablePatternKeywordInDeclarationContext,
                    );
                }
            }
            PatternContext::matching => {
                if type_info != noType && keyword != NO_TOKEN && self.is_a(keyword, kw::VAR) {
                    self.report_recoverable_error(keyword, diag::typeAfterVar);
                }
            }
            PatternContext::assignment => {
                if !is_bare_identifier {
                    let name = if variable_name.is_empty() {
                        "(unnamed)"
                    } else {
                        variable_name.as_str()
                    };
                    self.report_recoverable_error(
                        token,
                        (diag::patternAssignmentDeclaresVariable.with_arguments)(name),
                    );
                }
            }
        }
        let in_assignment_pattern = pattern_context == PatternContext::assignment;
        if variable_name == "_" {
            if is_bare_identifier {
                self.listener.handle_no_type(&mut self.tokens, token);
            }
            self.listener
                .handle_wildcard_pattern(&mut self.tokens, keyword, token);
        } else if in_assignment_pattern && is_bare_identifier {
            if illegalPatternIdentifiers.contains(&variable_name.as_str()) {
                let message = (diag::illegalPatternAssignmentVariableName.with_arguments)(
                    &self.tokens,
                    token,
                );
                self.report_recoverable_error(token, message);
            }
            self.listener
                .handle_assigned_variable_pattern(&mut self.tokens, token);
        } else {
            if illegalPatternIdentifiers.contains(&variable_name.as_str()) {
                let message =
                    (diag::illegalPatternVariableName.with_arguments)(&self.tokens, token);
                self.report_recoverable_error(token, message);
            }
            if is_bare_identifier {
                self.listener.handle_no_type(&mut self.tokens, token);
            }
            self.listener.handle_declared_variable_pattern(
                &mut self.tokens,
                keyword,
                token,
                in_assignment_pattern,
            );
        }
        token
    }

    /// ```text
    /// listPattern ::= typeArguments? '[' patterns? ']'
    /// ```
    pub fn parse_list_pattern_suffix(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
    ) -> TokenId {
        let before_token = token;
        token = self.next(token);
        let begin_token = token;
        debug_assert!(
            self.is_a(token, TokenType::OPEN_SQUARE_BRACKET) || self.is_a(token, TokenType::INDEX)
        );
        let mut count = 0;
        if self.is_a(token, TokenType::INDEX) {
            let rewritten = self.rewrite_square_brackets(before_token);
            token = self.next(rewritten);
            let next_2 = self.tokens.next(token);
            self.listener
                .handle_list_pattern(&mut self.tokens, 0, token, next_2);
            return self.next(token);
        }
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET) {
                token = next;
                break;
            }
            if self.is_a(next, TokenType::PERIOD_PERIOD_PERIOD) {
                let dots = next;
                token = next;
                next = self.next(token);
                let has_sub_pattern = looks_like_pattern_start(&self.tokens, next);
                if has_sub_pattern {
                    token = self.parse_pattern(token, pattern_context, 1);
                }
                self.listener
                    .handle_rest_pattern(&mut self.tokens, dots, has_sub_pattern);
            } else {
                token = self.parse_pattern(token, pattern_context, 1);
                if next == self.next(token) {
                    // Recovery: Avoid looping endlessly.
                    token = self.next(token);
                }
            }
            next = self.next(token);
            count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                if self.is_a(next, TokenType::CLOSE_SQUARE_BRACKET) {
                    token = next;
                    break;
                }

                // Recovery
                if !looks_like_literal_entry(&self.tokens, next) {
                    let end_group = self.tokens.end_group(begin_token);
                    if self.tokens.is_synthetic(end_group) {
                        token = self.rewriter().move_synthetic(token, end_group);
                    } else {
                        self.report_recoverable_error(
                            next,
                            (diag::expectedButGot.with_arguments)("]"),
                        );
                        // Scanner ensures a closing ']'
                        token = end_group;
                    }
                    break;
                }
                // This looks like the start of an expression.
                // Report an error, insert the comma, and continue parsing.
                let offset = self.tokens.offset(next);
                let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                next = self.rewrite_and_recover(
                    token,
                    (diag::expectedButGot.with_arguments)(","),
                    comma,
                );
            }
            token = next;
        }
        self.listener
            .handle_list_pattern(&mut self.tokens, count, begin_token, token);
        self.may_parse_function_expressions = old;
        token
    }

    /// ```text
    /// mapPattern        ::= typeArguments? '{' mapPatternEntries? '}'
    /// mapPatternEntries ::= mapPatternEntry ( ',' mapPatternEntry )* ','?
    /// mapPatternEntry   ::= expression ':' pattern | '...'
    /// ```
    pub fn parse_map_pattern_suffix(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
    ) -> TokenId {
        token = self.next(token);
        let left_brace = token;
        debug_assert!(self.is_a(left_brace, TokenType::OPEN_CURLY_BRACKET));
        let mut next = self.next(token);
        if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
            self.listener
                .handle_map_pattern(&mut self.tokens, 0, left_brace, next);
            return next;
        }
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        let mut count = 0;
        loop {
            if self.is_a(next, TokenType::PERIOD_PERIOD_PERIOD) {
                let dots = next;
                token = next;
                next = self.next(token);
                let has_sub_pattern = looks_like_pattern_start(&self.tokens, next);
                if has_sub_pattern {
                    token = self.parse_pattern(token, pattern_context, 1);
                }
                self.listener
                    .handle_rest_pattern(&mut self.tokens, dots, has_sub_pattern);
            } else {
                token = self.parse_expression(token);
                let mut colon = self.next(token);
                if !self.is_a(colon, TokenType::COLON) {
                    // Recover from a missing colon by inserting one.
                    let offset = self.tokens.char_offset(next);
                    let synthetic = self.tokens.synthetic_token(TokenType::COLON, offset);
                    colon = self.rewrite_and_recover(
                        token,
                        (diag::expectedButGot.with_arguments)(":"),
                        synthetic,
                    );
                }
                token = self.parse_pattern(colon, pattern_context, 1);
                if next == self.next(token) {
                    // Recovery: Avoid looping endlessly.
                    token = self.next(token);
                }
                let next_1 = self.tokens.next(token);
                self.listener
                    .handle_map_pattern_entry(&mut self.tokens, colon, next_1);
            }
            count += 1;
            next = self.next(token);
            let mut comma = NO_TOKEN;
            if self.is_a(next, TokenType::COMMA) {
                token = next;
                comma = token;
                next = self.next(token);
            }
            if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
                break;
            }
            if comma == NO_TOKEN {
                // Recovery
                if looks_like_literal_entry(&self.tokens, next) {
                    // If this looks like the start of an expression,
                    // then report an error, insert the comma, and continue parsing.
                    let offset = self.tokens.offset(next);
                    let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                    token = self.rewrite_and_recover(
                        token,
                        (diag::expectedButGot.with_arguments)(","),
                        comma,
                    );
                } else {
                    self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)("}"));
                    // Scanner guarantees a closing curly bracket
                    next = self.tokens.end_group(left_brace);
                    break;
                }
            }
        }
        self.may_parse_function_expressions = old;
        self.listener
            .handle_map_pattern(&mut self.tokens, count, left_brace, next);
        next
    }

    /// Parses either a parenthesized pattern or a record pattern.
    pub fn parse_parenthesized_pattern_or_record_pattern(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
    ) -> TokenId {
        let begin = self.next(token);
        debug_assert!(self.is_a(begin, TokenType::OPEN_PAREN));
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;

        token = begin;
        let mut count = 0;
        let mut was_record = false;
        let mut was_valid_record = false;
        loop {
            let mut next = self.next(token);
            if (count > 0 || was_record) && self.is_a(next, TokenType::CLOSE_PAREN) {
                break;
            }
            let mut colon = NO_TOKEN;
            if self.is_a(next, TokenType::COLON) {
                was_record = true;
                was_valid_record = true;
                self.listener.handle_no_name(&mut self.tokens, token);
                token = next;
                colon = token;
            } else if !self.is_a(next, TokenType::OPEN_PAREN)
                && self.is_a(self.next(next), TokenType::COLON)
            {
                was_record = true;
                token = self.ensure_identifier(token, IdentifierContext::namedRecordFieldReference);
                token = self.next(token);
                colon = token;
                was_valid_record = true;
            }
            token = self.parse_pattern(token, pattern_context, 1);
            next = self.next(token);
            if was_record || colon != NO_TOKEN {
                self.listener.handle_pattern_field(&mut self.tokens, colon);
            }
            count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                break;
            } else {
                if !was_record && colon == NO_TOKEN {
                    self.listener.handle_pattern_field(&mut self.tokens, colon);
                }
                was_record = true;
                was_valid_record = true;
            }
            token = next;
        }
        token = self.ensure_close_paren(token, begin);
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        debug_assert!(was_record || count <= 1);

        if was_record {
            if count == 1 && !was_valid_record {
                self.report_recoverable_error(
                    token,
                    diag::recordLiteralOnePositionalFieldNoTrailingComma,
                );
            }
            self.listener
                .handle_record_pattern(&mut self.tokens, begin, count);
        } else {
            self.listener
                .handle_parenthesized_pattern(&mut self.tokens, begin);
        }

        self.may_parse_function_expressions = old;
        token
    }

    /// Parses the rest of an object pattern, where [token] is the token before
    /// the `(`.
    pub fn parse_object_pattern_rest(
        &mut self,
        mut token: TokenId,
        pattern_context: PatternContext,
    ) -> TokenId {
        token = self.next(token);
        let begin = token;
        debug_assert!(self.is_a(begin, TokenType::OPEN_PAREN));
        let mut argument_count = 0;
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        loop {
            let mut next = self.next(token);
            if self.is_a(next, TokenType::CLOSE_PAREN) {
                token = next;
                break;
            }
            let mut colon = NO_TOKEN;
            if self.is_a(next, TokenType::COLON) {
                self.listener.handle_no_name(&mut self.tokens, token);
                token = next;
                colon = token;
            } else if self.is_a(self.next(next), TokenType::COLON) {
                token = self.ensure_identifier(token, IdentifierContext::namedArgumentReference);
                token = self.next(token);
                colon = token;
            }
            token = self.parse_pattern(token, pattern_context, 1);
            next = self.next(token);
            self.listener.handle_pattern_field(&mut self.tokens, colon);
            argument_count += 1;
            if !self.is_a(next, TokenType::COMMA) {
                if self.is_a(next, TokenType::CLOSE_PAREN) {
                    token = next;
                    break;
                }
                // Recovery
                if looks_like_expression_start(&self.tokens, next) {
                    // If this looks like the start of an expression,
                    // then report an error, insert the comma, and continue parsing.
                    let offset = self.tokens.offset(next);
                    let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                    next = self.rewrite_and_recover(
                        token,
                        (diag::expectedButGot.with_arguments)(","),
                        comma,
                    );
                } else {
                    token = self.ensure_close_paren(token, begin);
                    break;
                }
            }
            token = next;
        }
        debug_assert!(self.is_a(token, TokenType::CLOSE_PAREN));
        self.may_parse_function_expressions = old;
        self.listener
            .handle_object_pattern_fields(&mut self.tokens, argument_count, begin, token);
        token
    }

    /// Returns `true` if the given [token] should be treated like the start of
    /// a pattern assignment (`outerPattern '=' expression`).
    pub fn looks_like_outer_pattern_equals(&mut self, token: TokenId) -> bool {
        let after_outer_pattern = self.skip_outer_pattern(token);
        if after_outer_pattern == NO_TOKEN {
            return false;
        }
        self.is_a(self.next(after_outer_pattern), TokenType::EQ)
    }

    /// Tries to advance beyond an "outer pattern" starting from [token]. If the
    /// next construct after [token] is not an outer pattern, returns `null`.
    pub fn skip_outer_pattern(&mut self, mut token: TokenId) -> TokenId {
        let mut next = self.next(token);
        if self.tokens.is_identifier(next) {
            token = next;
            next = self.next(token);
            if !self.is_a(next, TokenType::PERIOD) {
                return self.skip_object_pattern_rest(token);
            }
            token = next;
            next = self.next(token);
            if self.tokens.is_identifier(next) {
                return self.skip_object_pattern_rest(next);
            } else {
                // `.` not followed by identifier; not a pattern.
                return NO_TOKEN;
            }
        }
        let type_param_or_arg = compute_type_param_or_arg(&mut self.tokens, token, false, false);
        token = type_param_or_arg.skip(&mut self.tokens, token);
        next = self.next(token);
        if self.is_a(next, TokenType::INDEX) {
            // Empty list pattern
            return next;
        }
        if self.is_a(next, TokenType::OPEN_SQUARE_BRACKET)
            || self.is_a(next, TokenType::OPEN_CURLY_BRACKET)
        {
            // List or map pattern
            return self.tokens.end_group(next);
        }
        if type_param_or_arg == noTypeParamOrArg && self.is_a(next, TokenType::OPEN_PAREN) {
            // Record or parenthesized pattern
            return self.tokens.end_group(next);
        }
        // Not an outer pattern
        NO_TOKEN
    }

    /// Tries to advance through an object pattern, where [token] is the last
    /// token of the object pattern's type name. If the tokens following [token]
    /// don't look like the rest of an object pattern, returns `null`.
    pub fn skip_object_pattern_rest(&mut self, mut token: TokenId) -> TokenId {
        let type_param_or_arg = compute_type_param_or_arg(&mut self.tokens, token, false, false);
        token = type_param_or_arg.skip(&mut self.tokens, token);
        let next = self.next(token);
        if next == NO_TOKEN {
            return NO_TOKEN;
        }
        if !self.is_a(next, TokenType::OPEN_PAREN) {
            return NO_TOKEN;
        }
        self.tokens.end_group(next)
    }

    /// Parses a pattern variable declaration statement.
    pub fn parse_pattern_variable_declaration_statement(
        &mut self,
        keyword: TokenId,
        _start: TokenId,
        _var_or_final: TokenId,
    ) -> TokenId {
        let mut token = self.parse_pattern(keyword, PatternContext::declaration, 1);
        let equals = self.next(token);
        debug_assert!(self.is_a(equals, TokenType::EQ));
        token = self.parse_expression(equals);
        let semicolon = self.ensure_semicolon(token);
        self.listener.handle_pattern_variable_declaration_statement(
            &mut self.tokens,
            keyword,
            equals,
            semicolon,
        );
        semicolon
    }

    /// Parses a pattern assignment.
    pub fn parse_pattern_assignment(&mut self, token: TokenId) -> TokenId {
        self.parse_pattern_assignment_impl(token, true)
    }

    /// `_parsePatternAssignment`.
    fn parse_pattern_assignment_impl(
        &mut self,
        mut token: TokenId,
        allow_cascades: bool,
    ) -> TokenId {
        token = self.parse_pattern(token, PatternContext::assignment, 1);
        let equals = self.next(token);
        debug_assert!(self.is_a(equals, TokenType::EQ));
        token = if allow_cascades {
            self.parse_expression(equals)
        } else {
            self.parse_expression_without_cascade(equals)
        };
        self.listener
            .handle_pattern_assignment(&mut self.tokens, equals);
        token
    }

    /// ```text
    /// switchExpression ::= 'switch' '(' expression ')' '{'
    ///     switchExpressionCase ( ',' switchExpressionCase )* ','? '}'
    /// switchExpressionCase ::= guardedPattern '=>' expression
    /// ```
    pub fn parse_switch_expression(&mut self, mut token: TokenId) -> TokenId {
        let switch_keyword = self.next(token);
        debug_assert!(self.is_a(switch_keyword, kw::SWITCH));
        let old = self.may_parse_function_expressions;
        self.may_parse_function_expressions = true;
        self.listener
            .begin_switch_expression(&mut self.tokens, switch_keyword);
        token = self.ensure_parenthesized_condition(switch_keyword, false);
        token = self.ensure_block(token, Some(BlockKind::switchExpression));
        let begin_switch = token;
        self.listener
            .begin_switch_expression_block(&mut self.tokens, begin_switch);
        let mut next = self.next(token);
        let mut case_count = 0;
        if !self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
            self.may_parse_function_expressions = false;
            loop {
                self.listener.begin_switch_expression_case(&mut self.tokens);
                next = self.next(token);
                let begin_token = next;
                if self.is_a(next, kw::DEFAULT) {
                    self.report_recoverable_error(next, diag::defaultInSwitchExpression);
                    self.listener.handle_no_type(&mut self.tokens, next);
                    self.listener
                        .handle_wildcard_pattern(&mut self.tokens, NO_TOKEN, next);
                    token = next;
                } else {
                    if self.is_a(next, kw::CASE) {
                        let message = (diag::unexpectedToken.with_arguments)(&self.tokens, next);
                        self.report_recoverable_error(next, message);
                        token = next;
                    }
                    token = self.parse_pattern(token, PatternContext::matching, 1);
                }
                self.listener
                    .handle_switch_expression_case_pattern(&mut self.tokens, token);
                let mut when = NO_TOKEN;
                next = self.next(token);
                if self.is_a(next, kw::WHEN) {
                    token = next;
                    when = token;
                    token = self.parse_expression(token);
                }
                let arrow;
                // Note: upstream checks the `next` computed before the guard.
                if self.is_a(next, TokenType::COLON) {
                    // Recovery: `:` instead of `=>`.
                    arrow = next;
                    self.report_recoverable_error(
                        arrow,
                        (diag::expectedButGot.with_arguments)("=>"),
                    );
                } else {
                    arrow = self.ensure_function_arrow(token);
                }
                token = arrow;
                self.may_parse_function_expressions = true;
                token = self.parse_expression(token);
                self.may_parse_function_expressions = false;
                self.listener.end_switch_expression_case(
                    &mut self.tokens,
                    begin_token,
                    when,
                    arrow,
                    token,
                );
                case_count += 1;
                next = self.next(token);
                let mut comma = NO_TOKEN;
                if self.is_a(next, TokenType::COMMA) {
                    token = next;
                    comma = token;
                    next = self.next(token);
                } else if self.is_a(next, TokenType::SEMICOLON) {
                    // Recovery: `;` instead of `,`.
                    self.report_recoverable_error(next, (diag::expectedButGot.with_arguments)(","));
                    token = next;
                    comma = token;
                    next = self.next(token);
                }
                if self.is_a(next, TokenType::CLOSE_CURLY_BRACKET) {
                    break;
                }
                if comma == NO_TOKEN {
                    // Recovery
                    if looks_like_pattern_start(&self.tokens, next) {
                        // If this looks like the start of a pattern, then report an error,
                        // insert the comma, and continue parsing.
                        let offset = self.tokens.offset(next);
                        let comma = self.tokens.synthetic_token(TokenType::COMMA, offset);
                        token = self.rewrite_and_recover(
                            token,
                            (diag::expectedButGot.with_arguments)(","),
                            comma,
                        );
                    } else {
                        let closing_bracket = self.tokens.end_group(begin_switch);
                        let comma = self.find_next_comma_or_semicolon(next, closing_bracket);
                        if comma == NO_TOKEN {
                            self.report_recoverable_error(
                                next,
                                (diag::expectedButGot.with_arguments)("}"),
                            );
                            next = closing_bracket;
                            break;
                        } else {
                            // Recovery: skip to the next comma or semicolon.
                            self.report_recoverable_error(
                                next,
                                (diag::expectedButGot.with_arguments)(","),
                            );
                            token = comma;
                            next = self.next(token);
                        }
                    }
                }
            }
        }
        self.listener
            .end_switch_expression_block(&mut self.tokens, case_count, begin_switch, next);
        self.may_parse_function_expressions = old;
        token = next;
        debug_assert!(
            self.tokens.is_eof(token) || self.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
        );
        self.listener
            .end_switch_expression(&mut self.tokens, switch_keyword, token);
        token
    }

    /// Finds the next comma or semicolon from [token], skipping groups, and
    /// stops at [limit].
    pub fn find_next_comma_or_semicolon(&self, mut token: TokenId, limit: TokenId) -> TokenId {
        loop {
            if self.tokens.is_eof(token) || token == limit {
                return NO_TOKEN;
            }
            if self.is_a(token, TokenType::COMMA) || self.is_a(token, TokenType::SEMICOLON) {
                return token;
            }
            let end_group = self.tokens.end_group(token);
            token = if end_group != NO_TOKEN {
                end_group
            } else {
                self.next(token)
            };
        }
    }
}

impl Parser {
    pub(crate) fn swap_recover_at_precedence_level(&mut self, value: bool) -> bool {
        std::mem::replace(&mut self.recover_at_precedence_level, value)
    }

    pub(crate) fn swap_currently_recovering(&mut self, value: bool) -> bool {
        std::mem::replace(&mut self.currently_recovering, value)
    }
}

impl Parser {
    /// `info.skip(token).next!`, which upstream writes inline.
    fn next_after_skip(&mut self, info: &TypeParamOrArgInfo, token: TokenId) -> TokenId {
        let skipped = info.skip(&mut self.tokens, token);
        self.next(skipped)
    }
}
