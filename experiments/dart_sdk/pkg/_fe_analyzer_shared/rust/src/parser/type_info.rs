// Port of lib/src/parser/type_info.dart.
//
// `TypeInfo` and `TypeParamOrArgInfo` are enums over upstream's
// implementations (type_info_impl.dart). The constant implementations are
// unit variants; the computed ones hold their state behind an `Rc`, and two
// infos are equal when upstream's would be identical. Computing a type can
// split a `>>`-like token, which allocates, so it takes the store mutably.

use std::cell::RefCell;
use std::rc::Rc;

use crate::parser::identifier_context::is_ok_next_value_in_formal_parameter;
use crate::parser::type_info_impl::{ComplexTypeInfo, ComplexTypeParamOrArgInfo, looks_like_name};
use crate::parser::util::{is_any_of, kw};
use crate::scanner::token::{TokenId, TokenStore, TokenType};
use crate::scanner::token_constants::{IDENTIFIER_TOKEN, KEYWORD_TOKEN};

/// [TypeInfo] provides information collected by [computeType]
/// about a particular type reference.
#[derive(Clone, Debug)]
pub enum TypeInfo {
    /// `noType`
    NoType,
    /// `prefixedType`
    PrefixedType,
    /// `simpleNullableTypeWith1Argument`
    SimpleNullableTypeWith1Argument,
    /// `simpleTypeWith1Argument`, `simpleTypeWith1ArgumentGtEq` and
    /// `simpleTypeWith1ArgumentGtGt`: the argument is the matching
    /// `simpleTypeArgument1...`.
    SimpleTypeWith1Argument(TypeParamOrArgInfo),
    /// `simpleNullableType`
    SimpleNullableType,
    /// `simpleType`
    SimpleType,
    /// `voidType`
    VoidType,
    Complex(Rc<RefCell<ComplexTypeInfo>>),
}

impl PartialEq for TypeInfo {
    fn eq(&self, other: &TypeInfo) -> bool {
        use TypeInfo::*;
        match (self, other) {
            (NoType, NoType)
            | (PrefixedType, PrefixedType)
            | (SimpleNullableTypeWith1Argument, SimpleNullableTypeWith1Argument)
            | (SimpleNullableType, SimpleNullableType)
            | (SimpleType, SimpleType)
            | (VoidType, VoidType) => true,
            (SimpleTypeWith1Argument(a), SimpleTypeWith1Argument(b)) => a == b,
            (Complex(a), Complex(b)) => Rc::ptr_eq(a, b),
            _ => false,
        }
    }
}

/// [TypeParamOrArgInfo] provides information collected by
/// [computeTypeParamOrArg] about a particular group of type arguments
/// or type parameters.
#[derive(Clone, Debug)]
pub enum TypeParamOrArgInfo {
    /// `noTypeParamOrArg`
    NoTypeParamOrArg,
    /// `simpleTypeArgument1`
    SimpleTypeArgument1,
    /// `simpleTypeArgument1GtEq`
    SimpleTypeArgument1GtEq,
    /// `simpleTypeArgument1GtGt`
    SimpleTypeArgument1GtGt,
    Complex(Rc<ComplexTypeParamOrArgInfo>),
}

impl PartialEq for TypeParamOrArgInfo {
    fn eq(&self, other: &TypeParamOrArgInfo) -> bool {
        use TypeParamOrArgInfo::*;
        match (self, other) {
            (NoTypeParamOrArg, NoTypeParamOrArg)
            | (SimpleTypeArgument1, SimpleTypeArgument1)
            | (SimpleTypeArgument1GtEq, SimpleTypeArgument1GtEq)
            | (SimpleTypeArgument1GtGt, SimpleTypeArgument1GtGt) => true,
            (Complex(a), Complex(b)) => Rc::ptr_eq(a, b),
            _ => false,
        }
    }
}

/// [noType] is a specialized [TypeInfo] returned by [computeType] when
/// there is no type information in the source.
pub const noType: TypeInfo = TypeInfo::NoType;

/// [noTypeParamOrArg] is a specialized [TypeParamOrArgInfo] returned by
/// [computeTypeParamOrArg] when no type parameters or arguments are found.
pub const noTypeParamOrArg: TypeParamOrArgInfo = TypeParamOrArgInfo::NoTypeParamOrArg;

/// [voidType] is a specialized [TypeInfo] returned by [computeType] when
/// `void` is found.
pub const voidType: TypeInfo = TypeInfo::VoidType;

pub fn is_generalized_function_type(t: &TokenStore, token: TokenId) -> bool {
    t.is_a(token, kw::FUNCTION)
        && (t.is_a(t.next(token), TokenType::LT) || t.is_a(t.next(token), TokenType::OPEN_PAREN))
}

pub fn is_possible_record_type(t: &TokenStore, token: TokenId) -> bool {
    use crate::scanner::token::NO_TOKEN;
    t.is_a(token, TokenType::OPEN_PAREN)
        && t.end_group(token) != NO_TOKEN
        && !t.is_synthetic(t.end_group(token))
}

/// Returns `true` if the given [token] is either an identifier or a keyword
/// that is valid as the start of a type reference (not including record
/// types).
pub fn is_valid_non_record_type_reference(t: &TokenStore, token: TokenId) -> bool {
    let type_ = t.type_(token);
    let kind = type_.kind;
    if IDENTIFIER_TOKEN == kind {
        return true;
    }
    if KEYWORD_TOKEN == kind {
        return type_.is_pseudo()
            || (type_.is_built_in() && t.is_a(t.next(token), TokenType::PERIOD))
            || type_.is_a(kw::DYNAMIC)
            || type_.is_a(kw::FUNCTION)
            || type_.is_a(kw::VOID);
    }
    false
}

/// Called by the parser to obtain information about a possible type reference
/// that follows [token]. This does not modify the token stream.
///
/// If [inDeclaration] is `true`, then this will more aggressively recover
/// given unbalanced `<` `>` and invalid parameters or arguments.
pub fn compute_type(
    t: &mut TokenStore,
    token: TokenId,
    required: bool,
    in_declaration: bool,
    accept_keyword_for_simple_type: bool,
) -> TypeInfo {
    let mut next = t.next(token);
    if !is_valid_non_record_type_reference(t, next) && !is_possible_record_type(t, next) {
        // As next is not a valid type reference, this is all recovery.
        if t.type_(next).is_built_in() {
            let type_param_or_arg = compute_type_param_or_arg(t, next, in_declaration, false);
            if type_param_or_arg != noTypeParamOrArg {
                // Recovery: built-in `<` ... `>`
                let after = type_param_or_arg.skip(t, next);
                if required || looks_like_name(t, t.next(after)) {
                    let mut info = ComplexTypeInfo::new(t, token, type_param_or_arg)
                        .compute_builtin_or_var_as_type(t, required);
                    info.recovered = true;
                    return TypeInfo::complex(info);
                }
            } else if required || is_generalized_function_type(t, t.next(next)) {
                let value = t.string_value(next);
                if value != Some("get")
                    && value != Some("set")
                    && value != Some("factory")
                    && value != Some("operator")
                    && !(value == Some("typedef") && t.is_identifier(t.next(next)))
                {
                    let mut info = ComplexTypeInfo::new(t, token, type_param_or_arg)
                        .compute_builtin_or_var_as_type(t, required);
                    info.recovered = true;
                    return TypeInfo::complex(info);
                }
            }
        } else if required {
            // Recovery
            if t.is_a(next, TokenType::PERIOD) {
                // Looks like prefixed type missing the prefix
                let type_args = compute_type_param_or_arg(t, next, in_declaration, false);
                let result =
                    ComplexTypeInfo::new(t, token, type_args).compute_prefixed_type(t, required);
                if let TypeInfo::Complex(info) = &result {
                    info.borrow_mut().recovered = true;
                }
                return result;
            } else if t.is_a(next, kw::VAR)
                && is_any_of(
                    t,
                    t.next(next),
                    &[TokenType::LT, TokenType::COMMA, TokenType::GT],
                )
            {
                let type_args = compute_type_param_or_arg(t, next, in_declaration, false);
                let mut info = ComplexTypeInfo::new(t, token, type_args)
                    .compute_builtin_or_var_as_type(t, required);
                info.recovered = true;
                return TypeInfo::complex(info);
            }
        }
        return noType;
    }

    if t.is_a(next, kw::VOID) {
        next = t.next(next);
        if is_generalized_function_type(t, next) {
            // `void` `Function` ...
            return ComplexTypeInfo::new(t, token, noTypeParamOrArg).compute_void_gft(t, required);
        }
        // `void`
        return voidType;
    }

    if is_generalized_function_type(t, next) {
        // `Function` ...
        return ComplexTypeInfo::new(t, token, noTypeParamOrArg)
            .compute_no_type_gft(t, token, required);
    }

    if is_possible_record_type(t, next) {
        // ([...])
        let after = t.next(t.end_group(next));
        if is_generalized_function_type(t, after) {
            // ([...]) `Function`
            return ComplexTypeInfo::new(t, token, noTypeParamOrArg)
                .compute_record_type_gft(t, required);
        }
        if t.is_a(after, TokenType::QUESTION) && is_generalized_function_type(t, t.next(after)) {
            // ([...]) `?` `Function`
            return ComplexTypeInfo::new(t, token, noTypeParamOrArg)
                .compute_record_type_question_gft(t, required);
        }
        return ComplexTypeInfo::new(t, token, noTypeParamOrArg).compute_record_type(t, required);
    }

    // We've seen an identifier.

    let mut type_param_or_arg = compute_type_param_or_arg(t, next, in_declaration, false);
    if type_param_or_arg != noTypeParamOrArg {
        if type_param_or_arg.is_simple_type_argument() {
            // We've seen identifier `<` identifier `>`
            next = {
                let skipped = type_param_or_arg.skip(t, next);
                t.next(skipped)
            };
            if t.is_a(next, TokenType::QUESTION) {
                next = t.next(next);
                if !is_generalized_function_type(t, next) {
                    if (required || looks_like_name(t, next))
                        && type_param_or_arg == TypeParamOrArgInfo::SimpleTypeArgument1
                    {
                        // identifier `<` identifier `>` `?` identifier
                        return TypeInfo::SimpleNullableTypeWith1Argument;
                    }
                    // identifier `<` identifier `>` `?` non-identifier
                    return noType;
                }
            } else if !is_generalized_function_type(t, next) {
                if required || looks_like_name(t, next) {
                    // identifier `<` identifier `>` identifier
                    return type_param_or_arg.type_info();
                }
                // identifier `<` identifier `>` non-identifier
                return noType;
            }
        }
        // TODO(danrubel): Consider adding a const for
        // identifier `<` identifier `,` identifier `>`
        // if that proves to be a common case.

        // identifier `<` ... `>`
        return ComplexTypeInfo::new(t, token, type_param_or_arg)
            .compute_simple_with_type_arguments(t, required);
    }

    debug_assert!(type_param_or_arg == noTypeParamOrArg);
    next = t.next(next);
    if t.is_a(next, TokenType::PERIOD) {
        next = t.next(next);
        if is_valid_non_record_type_reference(t, next) {
            // We've seen identifier `.` identifier
            type_param_or_arg = compute_type_param_or_arg(t, next, in_declaration, false);
            next = t.next(next);
            if type_param_or_arg == noTypeParamOrArg {
                if t.is_a(next, TokenType::QUESTION) {
                    next = t.next(next);
                    if !is_generalized_function_type(t, next) {
                        if required || looks_like_name(t, next) {
                            // identifier `.` identifier `?` identifier
                            // TODO(danrubel): consider adding PrefixedNullableType
                            // Fall through to build complex type
                        } else {
                            // identifier `.` identifier `?` non-identifier
                            return noType;
                        }
                    }
                } else if !is_generalized_function_type(t, next) {
                    if required || looks_like_name(t, next) {
                        // identifier `.` identifier identifier
                        return TypeInfo::PrefixedType;
                    } else {
                        // identifier `.` identifier non-identifier
                        return noType;
                    }
                }
            }
            // identifier `.` identifier
            return ComplexTypeInfo::new(t, token, type_param_or_arg)
                .compute_prefixed_type(t, required);
        }
        // identifier `.` non-identifier
        if required {
            let after_period = t.next(t.next(token));
            type_param_or_arg = compute_type_param_or_arg(t, after_period, in_declaration, false);
            return ComplexTypeInfo::new(t, token, type_param_or_arg)
                .compute_prefixed_type(t, required);
        }
        return noType;
    }

    debug_assert!(type_param_or_arg == noTypeParamOrArg);
    if is_generalized_function_type(t, next) {
        // identifier `Function`
        return ComplexTypeInfo::new(t, token, noTypeParamOrArg)
            .compute_identifier_gft(t, required);
    }

    if t.is_a(next, TokenType::QUESTION) {
        next = t.next(next);
        if is_generalized_function_type(t, next) {
            // identifier `?` Function `(`
            return ComplexTypeInfo::new(t, token, noTypeParamOrArg)
                .compute_identifier_question_gft(t, required);
        } else if required || looks_like_name(t, next) {
            // identifier `?`
            return TypeInfo::SimpleNullableType;
        }
    } else if required
        || looks_like_name(t, next)
        || (accept_keyword_for_simple_type
            && t.is_keyword_or_identifier(next)
            && is_ok_next_value_in_formal_parameter(t, t.next(next)))
    {
        // identifier identifier
        return TypeInfo::SimpleType;
    }
    noType
}

/// Called by the parser to obtain information about a possible type reference
/// that follows [token] in a variable pattern.
pub fn compute_variable_pattern_type(
    t: &mut TokenStore,
    token: TokenId,
    required: bool,
) -> TypeInfo {
    let type_info = compute_type(t, token, required, false, false);
    let after_type = type_info.skip_type(t, token);
    if after_type != token {
        let next = t.next(after_type);
        if t.is_identifier(next) && (t.is_a(next, kw::AS) || t.is_a(next, kw::WHEN)) {
            // We've seen `TYPE as` or `TYPE when`.  `as` is a built-in identifier
            // and `when` is a pseudo-keyword, so this *could* be a variable
            // pattern.  Or it could be that TYPE should have been parsed as a
            // pattern.  We've decided to resolve the ambiguity by assuming that
            // TYPE was the pattern, and interpret the `when` or `as` as introducing
            // a guard or a cast pattern, respectively (see discussion at
            // https://github.com/dart-lang/sdk/issues/52199).
            return noType;
        }
    }
    type_info
}

/// Called by the parser to obtain information about a possible group of type
/// parameters or type arguments that follow [token].
pub fn compute_type_param_or_arg(
    t: &mut TokenStore,
    token: TokenId,
    in_declaration: bool,
    allows_variance: bool,
) -> TypeParamOrArgInfo {
    let begin_group = t.next(token);
    if !t.is_a(begin_group, TokenType::LT) {
        return noTypeParamOrArg;
    }
    compute_type_param_or_arg_impl(t, token, begin_group, in_declaration, allows_variance)
}

fn compute_type_param_or_arg_impl(
    t: &mut TokenStore,
    token: TokenId,
    begin_group: TokenId,
    in_declaration: bool,
    allows_variance: bool,
) -> TypeParamOrArgInfo {
    // identifier `<` `void` `>` and `<` `dynamic` `>`
    // are handled by ComplexTypeInfo.
    let next = t.next(begin_group);
    if t.kind(next) == IDENTIFIER_TOKEN || t.type_(next).is_pseudo() {
        let after = t.next(next);
        if t.is_a(after, TokenType::GT) {
            return TypeParamOrArgInfo::SimpleTypeArgument1;
        } else if t.is_a(after, TokenType::GT_GT) {
            return TypeParamOrArgInfo::SimpleTypeArgument1GtGt;
        } else if t.is_a(after, TokenType::GT_EQ) {
            return TypeParamOrArgInfo::SimpleTypeArgument1GtEq;
        }
    } else if t.is_a(next, TokenType::OPEN_PAREN) {
        let mut record_type = false;
        if is_possible_record_type(t, next) {
            let type_ = compute_type(t, begin_group, false, false, false);
            if let TypeInfo::Complex(info) = &type_ {
                let info = info.borrow();
                if (info.is_record_type || info.gft_return_type_has_record_type) && !info.recovered
                {
                    // Looks like a record type.
                    record_type = true;
                }
            }
        }
        if !record_type {
            return noTypeParamOrArg;
        }
    }

    // TODO(danrubel): Consider adding additional const for common situations.
    ComplexTypeParamOrArgInfo::new(t, token, in_declaration, allows_variance).compute(t)
}

/// Called by the parser to obtain information about a possible group of type
/// type arguments that follow [token] and that are followed by '('.
/// Returns the type arguments if [token] matches '<' type (',' type)* '>'
/// followed by '(', and returns [noTypeParamOrArg] otherwise.
pub fn compute_method_type_arguments(t: &mut TokenStore, token: TokenId) -> TypeParamOrArgInfo {
    let type_arg = compute_type_param_or_arg(t, token, false, false);
    let after = type_arg.skip(t, token);
    if may_follow_type_args(t.type_index(t.next(after))) && !type_arg.recovered() {
        type_arg
    } else {
        noTypeParamOrArg
    }
}

/// Identifiers that can't be used as variable names in patterns.
pub const illegalPatternIdentifiers: [&str; 2] = ["when", "as"];

/// Indicates whether a token of the given type, following type arguments,
/// means that they are type arguments of a method or function call.
/// Upstream reads a 256-entry table; this is the comparison the table was
/// built from (upstream's `_mayFollowTypeArgs_helper_for_testing`).
fn may_follow_type_args(token_type_index: i32) -> bool {
    token_type_index == TokenType::OPEN_PAREN.index
        || token_type_index == TokenType::PERIOD.index
        || token_type_index == TokenType::EQ_EQ.index
        || token_type_index == TokenType::BANG_EQ.index
        || token_type_index == TokenType::CLOSE_PAREN.index
        || token_type_index == TokenType::CLOSE_SQUARE_BRACKET.index
        || token_type_index == TokenType::CLOSE_CURLY_BRACKET.index
        || token_type_index == TokenType::SEMICOLON.index
        || token_type_index == TokenType::COLON.index
        || token_type_index == TokenType::COMMA.index
        || token_type_index == TokenType::EOF.index
}
