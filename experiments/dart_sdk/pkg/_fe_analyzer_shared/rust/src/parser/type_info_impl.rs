// Port of lib/src/parser/type_info_impl.dart.
//
// The `TypeInfo` and `TypeParamOrArgInfo` classes here are the variants of
// the enums in type_info.rs; their members are the `impl` blocks below,
// dispatching on the variant. `ComplexTypeInfo` and
// `ComplexTypeParamOrArgInfo` are structs whose `compute...` methods consume
// the value being built and return the resulting info, which is `this`
// upstream. `Link`s of tokens are vectors in prepend order (head last).

use std::cell::RefCell;
use std::rc::Rc;

use crate::messages::diagnostic as diag;
use crate::parser::forwarding_listener::ForwardingListener;
use crate::parser::identifier_context::IdentifierContext;
use crate::parser::member_kind::MemberKind;
use crate::parser::parser_impl::Parser;
use crate::parser::type_info::{
    TypeInfo, TypeParamOrArgInfo, compute_type, compute_type_param_or_arg, is_possible_record_type,
    is_valid_non_record_type_reference, noType, noTypeParamOrArg, voidType,
};
use crate::parser::util::{
    kw, skip_metadata, split_gt_eq, split_gt_from_gt_gt_eq, split_gt_from_gt_gt_gt,
    split_gt_from_gt_gt_gt_eq, split_gt_gt, synthetic_gt,
};
use crate::scanner::token::{NO_TOKEN, TokenId, TokenStore, TokenType};
use crate::scanner::token_constants::IDENTIFIER_TOKEN;

/// See documentation on the [simpleType] const.
pub const simpleType: TypeInfo = TypeInfo::SimpleType;

/// See documentation on the [simpleNullableType] const.
pub const simpleNullableType: TypeInfo = TypeInfo::SimpleNullableType;

/// See documentation on the [prefixedType] const.
pub const prefixedType: TypeInfo = TypeInfo::PrefixedType;

/// See documentation on the [simpleTypeWith1Argument] const.
pub const simpleTypeWith1Argument: TypeInfo =
    TypeInfo::SimpleTypeWith1Argument(TypeParamOrArgInfo::SimpleTypeArgument1);

/// See documentation on the [simpleTypeWith1ArgumentGtEq] const.
pub const simpleTypeWith1ArgumentGtEq: TypeInfo =
    TypeInfo::SimpleTypeWith1Argument(TypeParamOrArgInfo::SimpleTypeArgument1GtEq);

/// See documentation on the [simpleTypeWith1ArgumentGtGt] const.
pub const simpleTypeWith1ArgumentGtGt: TypeInfo =
    TypeInfo::SimpleTypeWith1Argument(TypeParamOrArgInfo::SimpleTypeArgument1GtGt);

/// See documentation on the [simpleNullableTypeWith1Argument] const.
pub const simpleNullableTypeWith1Argument: TypeInfo = TypeInfo::SimpleNullableTypeWith1Argument;

/// See documentation on the [simpleTypeArgument1] const.
pub const simpleTypeArgument1: TypeParamOrArgInfo = TypeParamOrArgInfo::SimpleTypeArgument1;

/// See documentation on the [simpleTypeArgument1GtEq] const.
pub const simpleTypeArgument1GtEq: TypeParamOrArgInfo = TypeParamOrArgInfo::SimpleTypeArgument1GtEq;

/// See documentation on the [simpleTypeArgument1GtGt] const.
pub const simpleTypeArgument1GtGt: TypeParamOrArgInfo = TypeParamOrArgInfo::SimpleTypeArgument1GtGt;

impl TypeInfo {
    pub fn complex(info: ComplexTypeInfo) -> TypeInfo {
        TypeInfo::Complex(Rc::new(RefCell::new(info)))
    }

    /// Return type info representing the receiver without the trailing `?`
    /// or the receiver if the receiver does not represent a nullable type.
    pub fn as_non_nullable(&self) -> TypeInfo {
        match self {
            TypeInfo::SimpleNullableTypeWith1Argument => simpleTypeWith1Argument,
            TypeInfo::SimpleNullableType => simpleType,
            TypeInfo::Complex(info) => {
                let info_ref = info.borrow();
                if info_ref.before_question_mark == NO_TOKEN {
                    self.clone()
                } else {
                    TypeInfo::complex(ComplexTypeInfo {
                        start: info_ref.start,
                        type_arguments: info_ref.type_arguments.clone(),
                        before_question_mark: NO_TOKEN,
                        end: info_ref.before_question_mark,
                        type_variable_starters: info_ref.type_variable_starters.clone(),
                        gft_has_return_type: info_ref.gft_has_return_type,
                        is_record_type: info_ref.is_record_type,
                        gft_return_type_has_record_type: info_ref.gft_return_type_has_record_type,
                        recovered: info_ref.recovered,
                    })
                }
            }
            _ => self.clone(),
        }
    }

    /// Return true if the tokens comprising the type represented by the
    /// receiver could be interpreted as a valid standalone expression.
    pub fn could_be_expression(&self) -> bool {
        match self {
            TypeInfo::PrefixedType | TypeInfo::SimpleType | TypeInfo::SimpleNullableType => true,
            TypeInfo::Complex(info) => {
                let info = info.borrow();
                info.type_arguments == noTypeParamOrArg && info.type_variable_starters.is_empty()
            }
            _ => false,
        }
    }

    /// Return true if the receiver represents a nullable type.
    pub fn is_nullable(&self) -> bool {
        match self {
            TypeInfo::SimpleNullableTypeWith1Argument | TypeInfo::SimpleNullableType => true,
            TypeInfo::Complex(info) => info.borrow().before_question_mark != NO_TOKEN,
            _ => false,
        }
    }

    /// Returns true if the type represents a function type.
    pub fn is_function_type(&self) -> bool {
        match self {
            TypeInfo::Complex(info) => info.borrow().gft_has_return_type.is_some(),
            _ => false,
        }
    }

    /// Return true if the receiver has type arguments.
    pub fn has_type_arguments(&self) -> bool {
        match self {
            TypeInfo::SimpleNullableTypeWith1Argument | TypeInfo::SimpleTypeWith1Argument(_) => {
                true
            }
            TypeInfo::Complex(info) => info.borrow().type_arguments != noTypeParamOrArg,
            _ => false,
        }
    }

    /// Returns true if the type was recovered.
    pub fn recovered(&self) -> bool {
        match self {
            TypeInfo::Complex(info) => info.borrow().recovered,
            _ => false,
        }
    }

    /// Call this function when the token after [token] must be a type (not void).
    /// This function will call the appropriate event methods on the [Parser]'s
    /// listener to handle the type, inserting a synthetic type reference if
    /// necessary. This may modify the token stream when parsing `>>` or `>>>`
    /// or `>>>=` in valid code or during recovery.
    pub fn ensure_type_not_void(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            TypeInfo::NoType => {
                let next = parser.tokens.next(token);
                parser.report_recoverable_error_with_token(next, diag::expectedType);
                parser.rewriter().insert_synthetic_identifier(token);
                simpleType.parse_type(token, parser)
            }
            TypeInfo::VoidType => {
                // Report an error, then parse `void` as if it were a type name.
                let next = parser.tokens.next(token);
                parser.report_recoverable_error(next, diag::invalidVoid);
                simpleType.parse_type_not_void(token, parser)
            }
            _ => self.parse_type(token, parser),
        }
    }

    /// Call this function when the token after [token] must be a type or void.
    pub fn ensure_type_or_void(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            TypeInfo::NoType => self.ensure_type_not_void(token, parser),
            _ => self.parse_type(token, parser),
        }
    }

    /// Call this function to parse an optional type (not void) after [token].
    pub fn parse_type_not_void(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            TypeInfo::VoidType => self.ensure_type_not_void(token, parser),
            _ => self.parse_type(token, parser),
        }
    }

    /// Call this function to parse an optional type or void after [token].
    pub fn parse_type(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            TypeInfo::NoType => {
                parser.listener.handle_no_type(&parser.tokens, token);
                token
            }
            TypeInfo::PrefixedType => {
                let t = &parser.tokens;
                let start = t.next(token);
                debug_assert!(t.is_keyword_or_identifier(start));
                parser.listener.handle_identifier(
                    &parser.tokens,
                    start,
                    IdentifierContext::prefixedTypeReference,
                );

                let period = parser.tokens.next(start);
                debug_assert!(parser.tokens.is_a(period, TokenType::PERIOD));

                let token = parser.tokens.next(period);
                debug_assert!(parser.tokens.is_keyword_or_identifier(token));
                parser.listener.handle_identifier(
                    &parser.tokens,
                    token,
                    IdentifierContext::typeReferenceContinuation,
                );
                parser.listener.handle_qualified(&parser.tokens, period);

                let next = parser.tokens.next(token);
                parser
                    .listener
                    .handle_no_type_arguments(&parser.tokens, next);
                parser.listener.handle_type(&parser.tokens, start, NO_TOKEN);
                token
            }
            TypeInfo::SimpleNullableTypeWith1Argument | TypeInfo::SimpleTypeWith1Argument(_) => {
                let type_arg = match self {
                    TypeInfo::SimpleTypeWith1Argument(type_arg) => type_arg.clone(),
                    _ => simpleTypeArgument1,
                };
                let start = parser.tokens.next(token);
                debug_assert!(parser.tokens.is_keyword_or_identifier(start));
                parser.listener.handle_identifier(
                    &parser.tokens,
                    start,
                    IdentifierContext::typeReference,
                );
                let token = type_arg.parse_arguments(start, parser);
                // parseTypeRest
                if let TypeInfo::SimpleNullableTypeWith1Argument = self {
                    let token = parser.tokens.next(token);
                    debug_assert!(parser.tokens.is_a(token, TokenType::QUESTION));
                    parser.listener.handle_type(&parser.tokens, start, token);
                    token
                } else {
                    parser.listener.handle_type(&parser.tokens, start, NO_TOKEN);
                    token
                }
            }
            TypeInfo::SimpleNullableType | TypeInfo::SimpleType => {
                let token = parser.tokens.next(token);
                debug_assert!(is_valid_non_record_type_reference(&parser.tokens, token));
                parser.listener.handle_identifier(
                    &parser.tokens,
                    token,
                    IdentifierContext::typeReference,
                );
                let token = noTypeParamOrArg.parse_arguments(token, parser);
                // parseTypeRest
                if let TypeInfo::SimpleNullableType = self {
                    let start = token;
                    let token = parser.tokens.next(start);
                    debug_assert!(parser.tokens.is_a(token, TokenType::QUESTION));
                    parser.listener.handle_type(&parser.tokens, start, token);
                    token
                } else {
                    parser.listener.handle_type(&parser.tokens, token, NO_TOKEN);
                    token
                }
            }
            TypeInfo::VoidType => {
                let void_keyword = parser.tokens.next(token);
                let mut token = void_keyword;
                let mut has_type_arguments = false;

                // Recovery: Skip past, but issue problem, if followed by type arguments.
                if parser.tokens.is_a(parser.tokens.next(token), TokenType::LT) {
                    let type_param =
                        compute_type_param_or_arg(&mut parser.tokens, token, false, false);
                    if type_param != noTypeParamOrArg {
                        has_type_arguments = true;
                        let next = parser.tokens.next(token);
                        parser.report_recoverable_error(next, diag::voidWithTypeArguments);
                        token = type_param.parse_arguments(token, parser);
                    }
                }

                if has_type_arguments {
                    parser
                        .listener
                        .handle_void_keyword_with_type_arguments(&parser.tokens, void_keyword);
                } else {
                    // Normal case.
                    parser
                        .listener
                        .handle_void_keyword(&parser.tokens, void_keyword);
                }
                token
            }
            TypeInfo::Complex(info) => ComplexTypeInfo::parse_type(info, token, parser),
        }
    }

    /// Call this function with the [token] before the type to obtain
    /// the last token in the type. If there is no type, then this method
    /// will return [token]. This does not modify the token stream.
    pub fn skip_type(&self, t: &mut TokenStore, token: TokenId) -> TokenId {
        match self {
            TypeInfo::NoType => token,
            TypeInfo::PrefixedType => t.next(t.next(t.next(token))),
            TypeInfo::SimpleTypeWith1Argument(type_arg) => {
                let token = t.next(token);
                debug_assert!(t.is_keyword_or_identifier(token));
                type_arg.skip(t, token)
            }
            TypeInfo::SimpleNullableTypeWith1Argument => {
                let token = t.next(token);
                let token = {
                    let skipped = simpleTypeArgument1.skip(t, token);
                    t.next(skipped)
                };
                debug_assert!(t.is_a(token, TokenType::QUESTION));
                token
            }
            TypeInfo::SimpleNullableType => t.next(t.next(token)),
            TypeInfo::SimpleType => t.next(token),
            TypeInfo::VoidType => {
                let mut token = t.next(token);
                // Recovery: Skip past if followed by type arguments.
                if t.is_a(t.next(token), TokenType::LT) {
                    let type_param = compute_type_param_or_arg(t, token, false, false);
                    if type_param != noTypeParamOrArg {
                        token = type_param.skip(t, token);
                    }
                }
                token
            }
            TypeInfo::Complex(info) => info.borrow().end,
        }
    }
}

pub fn looks_like_name(t: &TokenStore, token: TokenId) -> bool {
    t.kind(token) == IDENTIFIER_TOKEN
        || t.is_a(token, kw::THIS)
        || t.is_a(token, kw::SUPER)
        || (t.is_identifier(token)
            &&
            // Although `typedef` is a legal identifier,
            // type `typedef` identifier is not legal and in this situation
            // `typedef` is probably a separate declaration.
            (!t.is_a(token, kw::TYPEDEF) || !t.is_identifier(t.next(token))))
}

/// When missing a comma, determine if the given token looks like it should
/// be part of a collection of type parameters or arguments.
pub fn looks_like_name_or_end_of_block(t: &TokenStore, token: TokenId) -> bool {
    // End-of-file isn't a name, but this is called in a situation where
    // if there had been a name it would have used the type-info it had
    // collected --- this being eof probably mean the user is currently
    // typing and will probably write a name in a moment.
    // The same logic applies to "}" which ends for instance a class. Again,
    // the user is likely typing and will soon write a name.
    looks_like_name(t, token) || t.is_eof(token) || t.is_a(token, TokenType::CLOSE_CURLY_BRACKET)
}

/// When missing a comma, determine if the given token looks like it should
/// be part of a collection of type parameters or arguments.
pub fn looks_like_type_param_or_arg(t: &TokenStore, in_declaration: bool, token: TokenId) -> bool {
    if in_declaration && t.kind(token) == IDENTIFIER_TOKEN {
        let next = t.next(token);
        if t.kind(next) == IDENTIFIER_TOKEN || t.is_a(next, TokenType::COMMA) || is_closer(t, next)
        {
            return true;
        }
    }
    false
}

/// Instances of [ComplexTypeInfo] are returned by [computeType] to represent
/// type references that cannot be represented by the constants above.
#[derive(Debug, Clone)]
pub struct ComplexTypeInfo {
    /// The first token in the type reference.
    pub start: TokenId,

    /// Type arguments were seen during analysis.
    pub type_arguments: TypeParamOrArgInfo,

    /// The token before the trailing question mark or null if either
    /// 1) there is no trailing question mark, or
    /// 2) the trailing question mark is not part of the type reference.
    pub before_question_mark: TokenId,

    /// The last token in the type reference.
    pub end: TokenId,

    /// The `Function` tokens before the start of type variables of function
    /// types as seen during analysis (prepend order: the head is last).
    pub type_variable_starters: Vec<TokenId>,

    /// If the receiver represents a generalized function type then this
    /// indicates whether it has a return type, otherwise this is `null`.
    pub gft_has_return_type: Option<bool>,

    /// If the type is a record type.
    pub is_record_type: bool,

    /// If the type is a function type with a record type as return type.
    pub gft_return_type_has_record_type: bool,

    pub recovered: bool,
}

impl ComplexTypeInfo {
    pub fn new(
        t: &TokenStore,
        before_start: TokenId,
        type_arguments: TypeParamOrArgInfo,
    ) -> ComplexTypeInfo {
        let recovered = type_arguments.recovered();
        ComplexTypeInfo {
            start: t.next(before_start),
            type_arguments,
            before_question_mark: NO_TOKEN,
            end: NO_TOKEN,
            type_variable_starters: Vec::new(),
            gft_has_return_type: None,
            is_record_type: false,
            gft_return_type_has_record_type: false,
            recovered,
        }
    }

    fn into_type_info(self) -> TypeInfo {
        TypeInfo::complex(self)
    }

    fn parse_type(
        this: &Rc<RefCell<ComplexTypeInfo>>,
        mut token: TokenId,
        parser: &mut Parser,
    ) -> TokenId {
        let mut info = this.borrow().clone();
        debug_assert!(parser.tokens.next(token) == info.start);

        if parser.tokens.is_a(info.start, TokenType::PERIOD) {
            // Recovery: Insert missing identifier without sending events
            info.start = parser.insert_synthetic_identifier(
                token,
                IdentifierContext::prefixedTypeReference,
                None,
                NO_TOKEN,
            );
            this.borrow_mut().start = info.start;
        }

        let mut type_variable_end_groups: Vec<TokenId> = Vec::new();
        for &head in info.type_variable_starters.iter().rev() {
            parser
                .listener
                .begin_function_type(&parser.tokens, info.start);
            let type_params = compute_type_param_or_arg(&mut parser.tokens, head, true, false);
            type_variable_end_groups.push(type_params.parse_variables(head, parser));
        }

        if info.gft_has_return_type == Some(false) {
            // A function type without return type.
            // Push the non-existing return type first. The loop below will
            // generate the full type.
            noType.parse_type(token, parser);
        } else if info.is_record_type {
            token =
                parser.parse_record_type(info.start, token, info.before_question_mark != NO_TOKEN);
        } else if info.gft_return_type_has_record_type {
            token = parser.parse_record_type(info.start, token, true);
        } else {
            let type_ref_or_prefix = parser.tokens.next(token);
            if parser.tokens.is_a(type_ref_or_prefix, kw::VOID) {
                token = voidType.parse_type(token, parser);
            } else {
                if !parser.tokens.is_a(type_ref_or_prefix, TokenType::PERIOD)
                    && !parser
                        .tokens
                        .is_a(parser.tokens.next(type_ref_or_prefix), TokenType::PERIOD)
                {
                    token = parser.ensure_identifier(token, IdentifierContext::typeReference);
                } else {
                    token =
                        parser.ensure_identifier(token, IdentifierContext::prefixedTypeReference);
                    token = parser
                        .parse_qualified_rest(token, IdentifierContext::typeReferenceContinuation);
                    let end = this.borrow().end;
                    if parser.tokens.is_synthetic(token)
                        && end == parser.tokens.next(type_ref_or_prefix)
                    {
                        // Recovery: Update `end` if a synthetic identifier was inserted.
                        this.borrow_mut().end = token;
                    }
                }
                token = info.type_arguments.parse_arguments(token, parser);

                // Only consume the `?` if it is part of the complex type
                let mut question_mark = parser.tokens.next(token);
                if parser.tokens.is_a(question_mark, TokenType::QUESTION)
                    && (!type_variable_end_groups.is_empty()
                        || info.before_question_mark != NO_TOKEN)
                {
                    token = question_mark;
                } else {
                    question_mark = NO_TOKEN;
                }

                parser
                    .listener
                    .handle_type(&parser.tokens, type_ref_or_prefix, question_mark);
            }
        }

        let mut end_group_index = type_variable_end_groups.len() as i32 - 1;
        for _ in info.type_variable_starters.iter().rev() {
            token = parser.tokens.next(token);
            debug_assert!(parser.tokens.is_a(token, kw::FUNCTION));
            let function_token = token;
            if parser.tokens.is_a(parser.tokens.next(token), TokenType::LT) {
                // Skip type parameters, they were parsed above.
                token = type_variable_end_groups[end_group_index as usize];
                debug_assert!(parser.tokens.is_a(token, TokenType::GT));
            }
            token = parser
                .parse_formal_parameters_required_opt(token, MemberKind::GeneralizedFunctionType);

            // Only consume the `?` if it is part of the complex type
            let mut question_mark = parser.tokens.next(token);
            if parser.tokens.is_a(question_mark, TokenType::QUESTION)
                && (end_group_index > 0 || info.before_question_mark != NO_TOKEN)
            {
                token = question_mark;
            } else {
                question_mark = NO_TOKEN;
            }
            end_group_index -= 1;
            parser
                .listener
                .end_function_type(&parser.tokens, function_token, question_mark);
        }

        // There are two situations in which the [token] != [end]:
        // Valid code:    identifier `<` identifier `<` identifier `>>`
        //    where `>>` is replaced by two tokens.
        // Invalid code:  identifier `<` identifier identifier `>`
        //    where a synthetic `>` is inserted between the identifiers.
        debug_assert!(token == this.borrow().end || parser.tokens.is_a(token, TokenType::GT));

        // During recovery, [token] may be a synthetic that was inserted in the
        // middle of the type reference.
        this.borrow_mut().end = token;
        token
    }

    /// Given `Function` non-identifier, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_no_type_gft(
        mut self,
        t: &mut TokenStore,
        before_start: TokenId,
        required: bool,
    ) -> TypeInfo {
        debug_assert!(t.is_a(self.start, kw::FUNCTION));
        debug_assert!(t.next(before_start) == self.start);

        self.compute_rest(t, before_start, required);
        if self.gft_has_return_type.is_none() {
            return if required { simpleType } else { noType };
        }
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    /// Given a builtin, return the receiver so that parseType will report
    /// an error for the builtin used as a type.
    pub fn compute_record_type(mut self, t: &mut TokenStore, required: bool) -> TypeInfo {
        debug_assert!(is_possible_record_type(t, self.start));
        let mut token = self.start;
        let end_group = t.end_group(token);

        // Verify stuff between parenthesis.
        self.check_if_record_type_parenthesis_are_recovered(t, token, end_group);

        token = end_group;
        if !required {
            let mut next = t.next(token);
            if t.is_a(next, TokenType::QUESTION) {
                next = t.next(next);
            }
            let mut get_or_set = false;
            if t.is_keyword(next)
                && (t.is_a(next, kw::GET) || t.is_a(next, kw::SET))
                && t.is_identifier(t.next(next))
            {
                get_or_set = true;
                next = t.next(next);
            }
            if t.is_identifier(next) {
                let after_identifier = t.next(next);
                // TODO(jensj): Are there any other instances where it's a valid
                // (optional) record type?
                if !(t.is_a(after_identifier, TokenType::SEMICOLON)
                    || t.is_a(after_identifier, TokenType::EQ)
                    || t.is_a(after_identifier, TokenType::LT)
                    || t.is_a(after_identifier, TokenType::OPEN_PAREN)
                    || t.is_a(after_identifier, TokenType::COMMA)
                    || t.is_a(after_identifier, TokenType::CLOSE_PAREN)
                    || t.is_a(after_identifier, kw::IN)
                    || t.is_a(after_identifier, TokenType::CLOSE_CURLY_BRACKET)
                    || t.is_a(after_identifier, TokenType::COLON)
                    || t.is_a(after_identifier, TokenType::CLOSE_SQUARE_BRACKET)
                    || t.is_a(after_identifier, TokenType::EOF))
                {
                    if get_or_set
                        && (t.is_a(after_identifier, TokenType::FUNCTION)
                            || t.is_a(after_identifier, TokenType::OPEN_CURLY_BRACKET)
                            || t.is_a(after_identifier, kw::ASYNC)
                            || t.is_a(after_identifier, kw::SYNC)
                            || t.is_a(after_identifier, TokenType::EOF))
                    {
                        // With a getter/setter in the mix we can accept more stuff.
                    } else if t.is_a(next, kw::OPERATOR)
                        && t.is_user_definable_operator(after_identifier)
                    {
                        // E.g.
                        // `(int, int) operator [](int foo) {}`
                    } else {
                        // This could for instance be `(int x, int y) async {`.
                        return noType;
                    }
                }
            } else if (t.is_a(next, kw::THIS) || t.is_a(next, kw::SUPER))
                && t.is_a(t.next(next), TokenType::PERIOD)
            {
                // E.g.
                // * C(({int n, String s}) this.x);
                // * C((int, int) super.x);
            } else {
                // Is it e.g. `List<(int, int)>`?
                // But don't confuse e.g. `(() => print("hello")) >> 42;` for that.
                if self.recovered
                    || !(t.is_a(next, TokenType::COMMA)
                        || t.is_a(next, TokenType::GT)
                        || t.is_a(next, TokenType::GT_GT)
                        || t.is_a(next, TokenType::GT_GT_EQ)
                        || t.is_a(next, TokenType::GT_GT_GT)
                        || t.is_a(next, TokenType::GT_GT_GT_EQ)
                        || t.is_a(next, TokenType::EOF))
                {
                    return noType;
                }
            }
        }
        debug_assert!(t.is_a(token, TokenType::CLOSE_PAREN));
        self.before_question_mark = NO_TOKEN;
        self.end = token;
        token = t.next(token);

        if t.is_a(token, TokenType::QUESTION) {
            self.before_question_mark = self.end;
            self.end = token;
        }
        self.is_record_type = true;
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    fn check_if_record_type_parenthesis_are_recovered(
        &mut self,
        t: &mut TokenStore,
        mut token: TokenId,
        end_group: TokenId,
    ) {
        let mut parameter_count = 0;
        let mut has_named_fields = false;
        let mut has_comma = false;
        loop {
            let mut next = t.next(token);
            if t.is_a(next, TokenType::CLOSE_PAREN) {
                token = next;
                break;
            } else if has_named_fields
                && t.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                && t.is_a(t.next(next), TokenType::CLOSE_PAREN)
            {
                token = t.next(next);
                break;
            }
            parameter_count += 1;
            let value = t.string_value(next);
            if !has_named_fields && value == Some("{") {
                has_named_fields = true;
                token = t.next(token);
            }
            if t.is_a(t.next(token), TokenType::AT) {
                token = skip_metadata(t, token);
            }
            let type_ = compute_type(t, token, true, false, false);
            if type_.recovered() {
                self.recovered = true;
                return;
            }
            token = type_.skip_type(t, token);
            if t.is_identifier(t.next(token)) {
                token = t.next(token);
            } else if has_named_fields {
                self.recovered = true;
                return;
            }
            next = t.next(token);
            if !t.is_a(next, TokenType::COMMA) {
                let next = t.next(token);
                if t.is_a(next, TokenType::CLOSE_PAREN) {
                    token = next;
                } else if t.is_a(next, TokenType::CLOSE_CURLY_BRACKET)
                    && t.is_a(t.next(next), TokenType::CLOSE_PAREN)
                {
                    token = t.next(next);
                } else {
                    // Recovery.
                    self.recovered = true;
                    return;
                }
                break;
            } else {
                has_comma = true;
            }
            token = next;
        }
        if !self.recovered
            && ((parameter_count == 1 && !has_named_fields && !has_comma) || token != end_group)
        {
            self.recovered = true;
        }
    }

    /// Given void `Function` non-identifier, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_void_gft(mut self, t: &mut TokenStore, required: bool) -> TypeInfo {
        debug_assert!(t.is_a(self.start, kw::VOID));
        debug_assert!(t.is_a(t.next(self.start), kw::FUNCTION));

        let start = self.start;
        self.compute_rest(t, start, required);
        if self.gft_has_return_type.is_none() {
            return voidType;
        }
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    /// Given identifier `Function` non-identifier, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_identifier_gft(mut self, t: &mut TokenStore, required: bool) -> TypeInfo {
        debug_assert!(is_valid_non_record_type_reference(t, self.start));
        debug_assert!(t.is_a(t.next(self.start), kw::FUNCTION));

        let start = self.start;
        self.compute_rest(t, start, required);
        if self.gft_has_return_type.is_none() {
            return simpleType;
        }
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    /// Given a record type followed by `Function`, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_record_type_gft(mut self, t: &mut TokenStore, required: bool) -> TypeInfo {
        debug_assert!(is_possible_record_type(t, self.start));
        debug_assert!(t.is_a(t.next(t.end_group(self.start)), kw::FUNCTION));

        // TODO(jensj): Check the record type stuff to set recovered properly.
        let end_group = t.end_group(self.start);
        self.compute_rest(t, end_group, required);
        if self.gft_has_return_type.is_none() {
            return self.compute_record_type(t, required);
        }
        debug_assert!(self.end != NO_TOKEN);
        self.gft_return_type_has_record_type = true;
        self.into_type_info()
    }

    /// Given identifier `?` `Function` non-identifier, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_identifier_question_gft(
        mut self,
        t: &mut TokenStore,
        required: bool,
    ) -> TypeInfo {
        debug_assert!(is_valid_non_record_type_reference(t, self.start));
        debug_assert!(t.is_a(t.next(self.start), TokenType::QUESTION));
        debug_assert!(t.is_a(t.next(t.next(self.start)), kw::FUNCTION));

        let start = self.start;
        self.compute_rest(t, start, required);
        if self.gft_has_return_type.is_none() {
            return simpleNullableType;
        }
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    /// Given a record type followed by `?` `Function`, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_record_type_question_gft(
        mut self,
        t: &mut TokenStore,
        required: bool,
    ) -> TypeInfo {
        debug_assert!(is_possible_record_type(t, self.start));
        debug_assert!(t.is_a(t.next(t.end_group(self.start)), TokenType::QUESTION));

        // TODO(jensj): Check the record type stuff to set recovered properly.
        let end_group = t.end_group(self.start);
        self.compute_rest(t, end_group, required);
        if self.gft_has_return_type.is_none() {
            return self.compute_record_type(t, required);
        }
        debug_assert!(self.end != NO_TOKEN);
        self.gft_return_type_has_record_type = true;
        self.into_type_info()
    }

    /// Given a builtin, return the receiver so that parseType will report
    /// an error for the builtin used as a type.
    pub fn compute_builtin_or_var_as_type(
        mut self,
        t: &mut TokenStore,
        required: bool,
    ) -> ComplexTypeInfo {
        debug_assert!(t.type_(self.start).is_built_in() || t.is_a(self.start, kw::VAR));

        self.end = self.type_arguments.skip(t, self.start);
        let end = self.end;
        self.compute_rest(t, end, required);
        debug_assert!(self.end != NO_TOKEN);
        self
    }

    /// Given identifier `<` ... `>`, compute the type
    /// and return the receiver or one of the [TypeInfo] constants.
    pub fn compute_simple_with_type_arguments(
        mut self,
        t: &mut TokenStore,
        required: bool,
    ) -> TypeInfo {
        debug_assert!(is_valid_non_record_type_reference(t, self.start));
        debug_assert!(t.is_a(t.next(self.start), TokenType::LT));
        debug_assert!(self.type_arguments != noTypeParamOrArg);

        self.end = self.type_arguments.skip(t, self.start);
        let end = self.end;
        self.compute_rest(t, end, required);

        if !required
            && !looks_like_name_or_end_of_block(t, t.next(self.end))
            && self.gft_has_return_type.is_none()
        {
            return noType;
        }
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    /// Given identifier `.` identifier (or `.` identifier or identifier `.`
    /// for recovery), compute the type and return the receiver or one of the
    /// [TypeInfo] constants.
    pub fn compute_prefixed_type(mut self, t: &mut TokenStore, required: bool) -> TypeInfo {
        let mut token = self.start;
        if !t.is_a(token, TokenType::PERIOD) {
            debug_assert!(t.is_keyword_or_identifier(token));
            token = t.next(token);
        }
        debug_assert!(t.is_a(token, TokenType::PERIOD));
        if t.is_keyword_or_identifier(t.next(token)) {
            token = t.next(token);
        }

        self.end = self.type_arguments.skip(t, token);
        let end = self.end;
        self.compute_rest(t, end, required);
        if !required && !looks_like_name(t, t.next(self.end)) && self.gft_has_return_type.is_none()
        {
            return noType;
        }
        debug_assert!(self.end != NO_TOKEN);
        self.into_type_info()
    }

    pub fn compute_rest(&mut self, t: &mut TokenStore, mut token: TokenId, required: bool) {
        if t.is_a(t.next(token), TokenType::QUESTION) {
            self.before_question_mark = token;
            token = t.next(token);
            self.end = token;
        }
        token = t.next(token);
        while t.is_a(token, kw::FUNCTION) {
            let type_variable_start = token;
            // TODO(danrubel): Consider caching TypeParamOrArgInfo
            token = compute_type_param_or_arg(t, token, true, false).skip(t, token);
            token = t.next(token);
            if !t.is_a(token, TokenType::OPEN_PAREN) {
                break; // Not a function type.
            }
            if t.end_group(token) == NO_TOKEN {
                break; // Not a function type.
            }
            token = t.end_group(token);
            if !required {
                let mut next = t.next(token);
                if t.is_a(next, TokenType::QUESTION) {
                    next = t.next(next);
                }
                if !(t.is_identifier(next) || t.is_a(next, kw::THIS) || t.is_a(next, kw::SUPER)) {
                    break; // `Function` used as the name in a function declaration.
                }
            }
            debug_assert!(t.is_a(token, TokenType::CLOSE_PAREN));
            if self.gft_has_return_type.is_none() {
                self.gft_has_return_type = Some(type_variable_start != self.start);
            }
            self.type_variable_starters.push(type_variable_start);

            self.before_question_mark = NO_TOKEN;
            self.end = token;
            token = t.next(token);

            if t.is_a(token, TokenType::QUESTION) {
                self.before_question_mark = self.end;
                self.end = token;
                token = t.next(token);
            }
        }
    }
}

impl TypeParamOrArgInfo {
    /// Return `true` if this represents a single simple type argument.
    pub fn is_simple_type_argument(&self) -> bool {
        matches!(
            self,
            TypeParamOrArgInfo::SimpleTypeArgument1
                | TypeParamOrArgInfo::SimpleTypeArgument1GtEq
                | TypeParamOrArgInfo::SimpleTypeArgument1GtGt
        )
    }

    /// Return the number of type arguments
    pub fn type_argument_count(&self) -> i32 {
        match self {
            TypeParamOrArgInfo::NoTypeParamOrArg => 0,
            TypeParamOrArgInfo::Complex(info) => info.type_argument_count,
            _ => 1,
        }
    }

    /// Returns true if the type was recovered.
    pub fn recovered(&self) -> bool {
        match self {
            TypeParamOrArgInfo::Complex(info) => info.recovered,
            _ => false,
        }
    }

    /// Return the simple type associated with this simple type argument
    /// or throw an exception if this is not a simple type argument.
    pub fn type_info(&self) -> TypeInfo {
        match self {
            TypeParamOrArgInfo::SimpleTypeArgument1 => simpleTypeWith1Argument,
            TypeParamOrArgInfo::SimpleTypeArgument1GtEq => simpleTypeWith1ArgumentGtEq,
            TypeParamOrArgInfo::SimpleTypeArgument1GtGt => simpleTypeWith1ArgumentGtGt,
            _ => panic!("Internal error: {self:?} is not a SimpleTypeArgument."),
        }
    }

    /// Call this function to parse optional type arguments after [token].
    /// This function will call the appropriate event methods on the [Parser]'s
    /// listener to handle the arguments. This may modify the token stream
    /// when parsing `>>` in valid code or during recovery.
    pub fn parse_arguments(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            TypeParamOrArgInfo::NoTypeParamOrArg => {
                let next = parser.tokens.next(token);
                parser
                    .listener
                    .handle_no_type_arguments(&parser.tokens, next);
                token
            }
            TypeParamOrArgInfo::Complex(info) => info.parse_arguments(token, parser),
            _ => {
                let begin_group = parser.tokens.next(token);
                debug_assert!(parser.tokens.is_a(begin_group, TokenType::LT));
                let before_end = parser.tokens.next(begin_group);
                let end_group = self.parse_end_group(&mut parser.tokens, begin_group, before_end);
                parser
                    .listener
                    .begin_type_arguments(&parser.tokens, begin_group);
                simpleType.parse_type(begin_group, parser);
                parser
                    .listener
                    .end_type_arguments(&parser.tokens, 1, begin_group, end_group);
                end_group
            }
        }
    }

    /// Call this function to parse optional type parameters
    /// (also known as type variables) after [token].
    pub fn parse_variables(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            TypeParamOrArgInfo::NoTypeParamOrArg => {
                let next = parser.tokens.next(token);
                parser
                    .listener
                    .handle_no_type_variables(&parser.tokens, next);
                token
            }
            TypeParamOrArgInfo::Complex(info) => info.parse_variables(token, parser),
            _ => {
                let begin_group = parser.tokens.next(token);
                debug_assert!(parser.tokens.is_a(begin_group, TokenType::LT));
                let token = parser.tokens.next(begin_group);
                let end_group = self.parse_end_group(&mut parser.tokens, begin_group, token);
                let t = &parser.tokens;
                let listener = &mut parser.listener;
                listener.begin_type_variables(t, begin_group);
                listener.begin_metadata_star(t, token);
                listener.end_metadata_star(t, 0);
                listener.handle_identifier(t, token, IdentifierContext::typeVariableDeclaration);
                listener.begin_type_variable(t, token);
                listener.handle_type_variables_defined(t, token, 1);
                listener.handle_no_type(t, token);
                listener.end_type_variable(t, end_group, 0, NO_TOKEN, NO_TOKEN);
                listener.end_type_variables(t, begin_group, end_group);
                end_group
            }
        }
    }

    /// Call this function with the [token] before the type var to obtain
    /// the last token in the type var. If there is no type var, then this method
    /// will return [token]. This does not modify the token stream.
    pub fn skip(&self, t: &mut TokenStore, token: TokenId) -> TokenId {
        match self {
            TypeParamOrArgInfo::NoTypeParamOrArg => token,
            TypeParamOrArgInfo::Complex(info) => {
                debug_assert!(info.skip_end != NO_TOKEN);
                info.skip_end
            }
            _ => {
                let token = t.next(token);
                debug_assert!(t.is_a(token, TokenType::LT));
                let token = t.next(token);
                debug_assert!(t.is_keyword_or_identifier(token));
                self.skip_end_group(t, token)
            }
        }
    }

    fn skip_end_group(&self, t: &mut TokenStore, token: TokenId) -> TokenId {
        let token = t.next(token);
        match self {
            TypeParamOrArgInfo::SimpleTypeArgument1GtEq => {
                debug_assert!(t.is_a(token, TokenType::GT_EQ));
                split_gt_eq(t, token)
            }
            TypeParamOrArgInfo::SimpleTypeArgument1GtGt => {
                debug_assert!(t.is_a(token, TokenType::GT_GT));
                split_gt_gt(t, token)
            }
            _ => {
                debug_assert!(t.is_a(token, TokenType::GT));
                token
            }
        }
    }

    fn parse_end_group(
        &self,
        t: &mut TokenStore,
        _begin_group: TokenId,
        before_end_group: TokenId,
    ) -> TokenId {
        match self {
            TypeParamOrArgInfo::SimpleTypeArgument1GtEq
            | TypeParamOrArgInfo::SimpleTypeArgument1GtGt => {
                let mut end_group = t.next(before_end_group);
                if !t.is_a(end_group, TokenType::GT) {
                    end_group = if let TypeParamOrArgInfo::SimpleTypeArgument1GtEq = self {
                        split_gt_eq(t, end_group)
                    } else {
                        split_gt_gt(t, end_group)
                    };
                    let second = t.next(end_group);
                    let after = t.next(second);
                    t.set_next(second, after);
                }
                t.set_next(before_end_group, end_group);
                end_group
            }
            _ => {
                let token = t.next(before_end_group);
                debug_assert!(t.is_a(token, TokenType::GT));
                token
            }
        }
    }
}

#[derive(Debug)]
pub struct ComplexTypeParamOrArgInfo {
    /// The first token in the type var.
    pub start: TokenId,

    /// If [inDeclaration] is `true`, then this will more aggressively recover
    /// given unbalanced `<` `>` and invalid parameters or arguments.
    pub in_declaration: bool,

    // Only support variance parsing if it makes sense.
    // Allows parsing of variance for certain structures.
    // See https://github.com/dart-lang/language/issues/524
    pub allows_variance: bool,

    pub type_argument_count: i32,

    /// The last token in the group (typically `>`).
    /// If a `>>` has not yet been split, then this field will be
    /// `>` for the purpose of skipping the type arguments.
    pub skip_end: TokenId,

    pub recovered: bool,
}

impl ComplexTypeParamOrArgInfo {
    pub fn new(
        t: &TokenStore,
        token: TokenId,
        in_declaration: bool,
        allows_variance: bool,
    ) -> ComplexTypeParamOrArgInfo {
        debug_assert!(t.is_a(t.next(token), TokenType::LT));
        ComplexTypeParamOrArgInfo {
            start: t.next(token),
            in_declaration,
            allows_variance,
            type_argument_count: 0,
            skip_end: NO_TOKEN,
            recovered: false,
        }
    }

    /// Parse the tokens and return the receiver or [noTypeParamOrArg] if there
    /// are no type parameters or arguments. This does not modify the token
    /// stream.
    pub fn compute(mut self, t: &mut TokenStore) -> TypeParamOrArgInfo {
        let mut token;
        let mut next = self.start;
        let in_declaration = self.in_declaration;
        loop {
            let mut type_info = compute_type(t, next, true, in_declaration, false);
            self.recovered |= type_info.recovered();
            if type_info == noType {
                while type_info == noType && t.is_a(t.next(next), TokenType::AT) {
                    next = skip_metadata(t, next);
                    type_info = compute_type(t, next, true, in_declaration, false);
                }
                if type_info == noType {
                    if next == self.start
                        && !in_declaration
                        && !is_closer(t, t.next(next))
                        && !t.is_a(t.next(next), TokenType::COMMA)
                    {
                        return noTypeParamOrArg;
                    }
                    if !t.is_a(t.next(next), TokenType::COMMA) {
                        token = next;
                        next = t.next(token);
                        break;
                    }
                }
                debug_assert!(type_info != noType || t.is_a(t.next(next), TokenType::COMMA));
                // Fall through to process type (if any) and consume `,`
            }
            self.type_argument_count += 1;
            token = type_info.skip_type(t, next);
            next = t.next(token);
            if t.is_a(next, kw::EXTENDS) {
                token = compute_type(t, next, true, in_declaration, false).skip_type(t, next);
                next = t.next(token);
            }
            if !t.is_a(next, TokenType::COMMA) {
                self.skip_end = split_closer(t, next);
                if self.skip_end != NO_TOKEN {
                    return TypeParamOrArgInfo::Complex(Rc::new(self));
                }
                if !in_declaration {
                    return noTypeParamOrArg;
                }

                // Recovery
                if !looks_like_type_param_or_arg(t, in_declaration, next) {
                    break;
                }
                // Looks like missing comma. Continue looping.
                next = token;
            }
        }

        // Recovery
        self.skip_end = split_closer(t, next);
        if self.skip_end == NO_TOKEN {
            self.recovered = true;
            if t.is_a(next, TokenType::OPEN_PAREN) {
                token = t.end_group(next);
                next = t.next(token);
            }
            self.skip_end = split_closer(t, next);
            if self.skip_end == NO_TOKEN {
                let after = t.next(next);
                self.skip_end = split_closer(t, after);
            }
            if self.skip_end == NO_TOKEN {
                self.skip_end = synthetic_gt(t, next);
            }
        }
        TypeParamOrArgInfo::Complex(Rc::new(self))
    }

    pub fn parse_arguments(&self, mut token: TokenId, parser: &mut Parser) -> TokenId {
        debug_assert!(parser.tokens.next(token) == self.start);
        let mut next = self.start;
        parser
            .listener
            .begin_type_arguments(&parser.tokens, self.start);
        let mut count = 0;
        loop {
            let mut type_info =
                compute_type(&mut parser.tokens, next, true, self.in_declaration, false);
            if type_info == noType {
                // Recovery
                while type_info == noType
                    && parser.tokens.is_a(parser.tokens.next(next), TokenType::AT)
                {
                    let at_token = parser.tokens.next(next);
                    next = skip_metadata(&parser.tokens, next);
                    parser.report_recoverable_error_with_end(
                        at_token,
                        next,
                        diag::annotationOnTypeArgument,
                    );
                    type_info =
                        compute_type(&mut parser.tokens, next, true, self.in_declaration, false);
                }
                // Fall through to process type (if any) and consume `,`
            }
            token = type_info.ensure_type_or_void(next, parser);
            next = parser.tokens.next(token);
            count += 1;
            if !parser.tokens.is_a(next, TokenType::COMMA) {
                if parse_closer(&mut parser.tokens, token) {
                    break;
                }

                // Recovery
                if !looks_like_type_param_or_arg(&parser.tokens, self.in_declaration, next) {
                    token = self.parse_unexpected_end(token, true, parser);
                    break;
                }
                // Missing comma. Report error, insert comma, and continue looping.
                next = self.parse_missing_comma(token, parser);
            }
        }
        let end_group = parser.tokens.next(token);
        parser
            .listener
            .end_type_arguments(&parser.tokens, count, self.start, end_group);
        end_group
    }

    pub fn parse_variables(&self, mut token: TokenId, parser: &mut Parser) -> TokenId {
        debug_assert!(parser.tokens.next(token) == self.start);
        let mut next = self.start;
        parser
            .listener
            .begin_type_variables(&parser.tokens, self.start);
        let mut count: i32 = 0;

        // Prepend order: the head of each upstream `Link` is the last element.
        let mut type_starts: Vec<TokenId> = Vec::new();
        let mut super_type_infos: Vec<Option<TypeInfo>> = Vec::new();
        let mut variances: Vec<TokenId> = Vec::new();

        loop {
            token = parser.parse_metadata_star(next);

            let t = &parser.tokens;
            let mut variance = t.next(next);
            let mut identifier = t.next(variance);
            if self.allows_variance
                && is_variance(t, variance)
                && identifier != NO_TOKEN
                && t.is_keyword_or_identifier(identifier)
            {
                variances.push(variance);

                // Recovery for multiple variance modifiers
                while identifier != NO_TOKEN
                    && is_variance(&parser.tokens, identifier)
                    && parser.tokens.next(identifier) != NO_TOKEN
                    && parser
                        .tokens
                        .is_keyword_or_identifier(parser.tokens.next(identifier))
                {
                    // Report an error and skip actual identifier
                    parser.report_recoverable_error(identifier, diag::multipleVarianceModifiers);
                    variance = parser.tokens.next(variance);
                    identifier = parser.tokens.next(identifier);
                }

                token = variance;
            } else {
                variances.push(NO_TOKEN);
            }

            next = parser.ensure_identifier(token, IdentifierContext::typeVariableDeclaration);
            token = next;
            parser.listener.begin_type_variable(&parser.tokens, token);
            type_starts.push(token);

            next = parser.tokens.next(token);
            if parser.tokens.is_a(next, kw::EXTENDS) {
                let type_info =
                    compute_type(&mut parser.tokens, next, true, self.in_declaration, false);
                token = type_info.skip_type(&mut parser.tokens, next);
                next = parser.tokens.next(token);
                super_type_infos.push(Some(type_info));
            } else {
                super_type_infos.push(None);
            }

            count += 1;
            if !parser.tokens.is_a(next, TokenType::COMMA) {
                if is_closer(&parser.tokens, token) {
                    break;
                }

                // Recovery
                if !looks_like_type_param_or_arg(&parser.tokens, self.in_declaration, next) {
                    break;
                }
                // Missing comma. Report error, insert comma, and continue looping.
                next = self.parse_missing_comma(token, parser);
            }
        }

        debug_assert!(count > 0);
        parser
            .listener
            .handle_type_variables_defined(&parser.tokens, token, count);

        let mut token3 = NO_TOKEN;
        while let Some(mut token2) = type_starts.pop() {
            let type_info = super_type_infos.pop().unwrap();
            let variance = variances.pop().unwrap();

            let mut extends_or_super = NO_TOKEN;
            let mut next2 = parser.tokens.next(token2);
            if let Some(type_info) = type_info {
                debug_assert!(parser.tokens.is_a(next2, kw::EXTENDS));
                extends_or_super = next2;
                token2 = type_info.ensure_type_not_void(next2, parser);
                next2 = parser.tokens.next(token2);
            } else {
                debug_assert!(!parser.tokens.is_a(next2, kw::EXTENDS));
                parser.listener.handle_no_type(&parser.tokens, token2);
            }
            // Type variables are "completed" in reverse order, so capture the last
            // consumed token from the first "completed" type variable.
            if token3 == NO_TOKEN {
                token3 = token2;
            }
            count -= 1;
            parser.listener.end_type_variable(
                &parser.tokens,
                next2,
                count,
                extends_or_super,
                variance,
            );
        }

        if !parse_closer(&mut parser.tokens, token3) {
            token3 = self.parse_unexpected_end(token3, false, parser);
        }
        let end_group = parser.tokens.next(token3);
        parser
            .listener
            .end_type_variables(&parser.tokens, self.start, end_group);
        end_group
    }

    fn parse_missing_comma(&self, token: TokenId, parser: &mut Parser) -> TokenId {
        let next = parser.tokens.next(token);
        parser.report_recoverable_error(next, (diag::expectedButGot.with_arguments)(","));
        let offset = parser.tokens.char_offset(next);
        let comma = parser.tokens.synthetic_token(TokenType::COMMA, offset);
        parser.rewriter().insert_token(token, comma)
    }

    fn parse_unexpected_end(
        &self,
        mut token: TokenId,
        is_arguments: bool,
        parser: &mut Parser,
    ) -> TokenId {
        let mut next = parser.tokens.next(token);
        let mut error_reported = parser.tokens.is_synthetic(token)
            || (parser.tokens.is_synthetic(next) && !parser.tokens.is_eof(next));

        let mut type_follows_extends = false;
        if parser.tokens.is_a(next, kw::EXTENDS) {
            if !error_reported {
                parser.report_recoverable_error(
                    token,
                    (diag::expectedAfterButGot.with_arguments)(">"),
                );
                error_reported = true;
            }
            token = next;
            next = parser.tokens.next(token);
            type_follows_extends = is_valid_non_record_type_reference(&parser.tokens, next);

            if parse_closer(&mut parser.tokens, token) {
                return token;
            }
        }

        if type_follows_extends
            || parser.tokens.is_a(next, kw::DYNAMIC)
            || parser.tokens.is_a(next, kw::VOID)
            || parser.tokens.is_a(next, kw::FUNCTION)
        {
            let invalid_type = compute_type(&mut parser.tokens, token, true, false, false);
            if invalid_type != noType {
                if !error_reported {
                    parser.report_recoverable_error(
                        token,
                        (diag::expectedAfterButGot.with_arguments)(">"),
                    );
                    error_reported = true;
                }

                // Parse the type so that the token stream is properly modified,
                // but ensure that parser events are ignored by replacing the listener.
                let original_listener = std::mem::replace(
                    &mut parser.listener,
                    Box::new(ForwardingListener::new(None)),
                );
                token = invalid_type.parse_type(token, parser);
                next = parser.tokens.next(token);
                parser.listener = original_listener;

                if parse_closer(&mut parser.tokens, token) {
                    return token;
                }
            }
        }

        let invalid_type_var =
            compute_type_param_or_arg(&mut parser.tokens, token, self.in_declaration, false);
        if invalid_type_var != noTypeParamOrArg {
            if !error_reported {
                parser.report_recoverable_error(
                    token,
                    (diag::expectedAfterButGot.with_arguments)(">"),
                );
                error_reported = true;
            }

            // Parse the type so that the token stream is properly modified,
            // but ensure that parser events are ignored by replacing the listener.
            let original_listener = std::mem::replace(
                &mut parser.listener,
                Box::new(ForwardingListener::new(None)),
            );
            token = if is_arguments {
                invalid_type_var.parse_arguments(token, parser)
            } else {
                invalid_type_var.parse_variables(token, parser)
            };
            next = parser.tokens.next(token);
            parser.listener = original_listener;

            if parse_closer(&mut parser.tokens, token) {
                return token;
            }
        }

        if parser.tokens.is_a(next, TokenType::OPEN_PAREN)
            && parser.tokens.end_group(next) != NO_TOKEN
        {
            if !error_reported {
                // Only report an error if one has not already been reported.
                parser.report_recoverable_error(
                    token,
                    (diag::expectedAfterButGot.with_arguments)(">"),
                );
                error_reported = true;
            }
            token = parser.tokens.end_group(next);
            next = parser.tokens.next(token);

            if parse_closer(&mut parser.tokens, token) {
                return token;
            }
        }

        if !error_reported {
            // Only report an error if one has not already been reported.
            parser.report_recoverable_error(token, (diag::expectedAfterButGot.with_arguments)(">"));
        }

        if parse_closer(&mut parser.tokens, next) {
            return next;
        }
        let t = &mut parser.tokens;
        let end_group = t.end_group(self.start);
        if end_group != NO_TOKEN {
            while t.next(token) != end_group
                && !t.is_eof(token)
                && t.char_offset(token) <= t.char_offset(end_group)
            {
                token = t.next(token);
            }
        } else {
            let end_group = synthetic_gt(t, next);
            t.set_next(end_group, next);
            t.set_next(token, end_group);
        }
        token
    }
}

pub fn is_variance(t: &TokenStore, token: TokenId) -> bool {
    t.is_a(token, kw::IN) || t.is_a(token, kw::INOUT) || t.is_a(token, kw::OUT)
}

/// Return `true` if [token] is one of `>`, `>>`, `>=`, `>>>`, `>>=`, or `>>>=`.
pub fn is_closer(t: &TokenStore, token: TokenId) -> bool {
    t.is_a(token, TokenType::GT)
        || t.is_a(token, TokenType::GT_GT)
        || t.is_a(token, TokenType::GT_EQ)
        || t.is_a(token, TokenType::GT_GT_GT)
        || t.is_a(token, TokenType::GT_GT_EQ)
        || t.is_a(token, TokenType::GT_GT_GT_EQ)
}

/// If [beforeCloser].next is one of `>`, `>>`, `>=`, `>>>`, `>>=`, or `>>>=`,
/// then update the token stream and return `true`.
pub fn parse_closer(t: &mut TokenStore, before_closer: TokenId) -> bool {
    let unsplit = t.next(before_closer);
    let split = split_closer(t, unsplit);
    if split == unsplit {
        return true;
    } else if split == NO_TOKEN {
        return false;
    }
    let second = t.next(split);
    let after = t.next(unsplit);
    t.set_next(second, after);
    t.set_next(before_closer, split);
    true
}

/// If [closer] is `>` then return it.
/// If [closer] is one of `>>`, `>=`, `>>>`, `>>=`, or `>>>=` then split
/// the token and return the leading `>` without updating the token stream.
/// If [closer] is none of the above, then return null;
pub fn split_closer(t: &mut TokenStore, closer: TokenId) -> TokenId {
    if t.is_a(closer, TokenType::GT) {
        closer
    } else if t.is_a(closer, TokenType::GT_GT) {
        split_gt_gt(t, closer)
    } else if t.is_a(closer, TokenType::GT_EQ) {
        split_gt_eq(t, closer)
    } else if t.is_a(closer, TokenType::GT_GT_GT) {
        split_gt_from_gt_gt_gt(t, closer)
    } else if t.is_a(closer, TokenType::GT_GT_EQ) {
        split_gt_from_gt_gt_eq(t, closer)
    } else if t.is_a(closer, TokenType::GT_GT_GT_EQ) {
        split_gt_from_gt_gt_gt_eq(t, closer)
    } else {
        NO_TOKEN
    }
}
