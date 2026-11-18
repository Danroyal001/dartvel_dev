// Port of lib/src/parser/util.dart.
//
// Functions that take a `Token` take the `TokenStore` it lives in first.
// `kw` is not upstream's: it names each `Keyword`'s `TokenType`, so that
// `token.isA(Keyword.CLASS)` reads `tokens.is_a(token, kw::CLASS)`.

use crate::messages::codes::noLength;
use crate::scanner::token::{NO_TOKEN, TokenId, TokenStore, TokenType};

/// The `TokenType` of each keyword (`Keyword extends TokenType`).
pub mod kw {
    use crate::scanner::token::{Keyword, TokenType};

    pub const ABSTRACT: &TokenType = &Keyword::ABSTRACT.base;
    pub const AS: &TokenType = &Keyword::AS.base;
    pub const ASSERT: &TokenType = &Keyword::ASSERT.base;
    pub const ASYNC: &TokenType = &Keyword::ASYNC.base;
    pub const AUGMENT: &TokenType = &Keyword::AUGMENT.base;
    pub const AWAIT: &TokenType = &Keyword::AWAIT.base;
    pub const BASE: &TokenType = &Keyword::BASE.base;
    pub const BREAK: &TokenType = &Keyword::BREAK.base;
    pub const CASE: &TokenType = &Keyword::CASE.base;
    pub const CATCH: &TokenType = &Keyword::CATCH.base;
    pub const CLASS: &TokenType = &Keyword::CLASS.base;
    pub const CONST: &TokenType = &Keyword::CONST.base;
    pub const CONTINUE: &TokenType = &Keyword::CONTINUE.base;
    pub const COVARIANT: &TokenType = &Keyword::COVARIANT.base;
    pub const DEFAULT: &TokenType = &Keyword::DEFAULT.base;
    pub const DEFERRED: &TokenType = &Keyword::DEFERRED.base;
    pub const DO: &TokenType = &Keyword::DO.base;
    pub const DYNAMIC: &TokenType = &Keyword::DYNAMIC.base;
    pub const ELSE: &TokenType = &Keyword::ELSE.base;
    pub const ENUM: &TokenType = &Keyword::ENUM.base;
    pub const EXPORT: &TokenType = &Keyword::EXPORT.base;
    pub const EXTENDS: &TokenType = &Keyword::EXTENDS.base;
    pub const EXTENSION: &TokenType = &Keyword::EXTENSION.base;
    pub const EXTERNAL: &TokenType = &Keyword::EXTERNAL.base;
    pub const FACTORY: &TokenType = &Keyword::FACTORY.base;
    pub const FALSE: &TokenType = &Keyword::FALSE.base;
    pub const FINAL: &TokenType = &Keyword::FINAL.base;
    pub const FINALLY: &TokenType = &Keyword::FINALLY.base;
    pub const FOR: &TokenType = &Keyword::FOR.base;
    pub const FUNCTION: &TokenType = &Keyword::FUNCTION.base;
    pub const GET: &TokenType = &Keyword::GET.base;
    pub const HIDE: &TokenType = &Keyword::HIDE.base;
    pub const IF: &TokenType = &Keyword::IF.base;
    pub const IMPLEMENTS: &TokenType = &Keyword::IMPLEMENTS.base;
    pub const IMPORT: &TokenType = &Keyword::IMPORT.base;
    pub const IN: &TokenType = &Keyword::IN.base;
    pub const INOUT: &TokenType = &Keyword::INOUT.base;
    pub const INTERFACE: &TokenType = &Keyword::INTERFACE.base;
    pub const IS: &TokenType = &Keyword::IS.base;
    pub const LATE: &TokenType = &Keyword::LATE.base;
    pub const LIBRARY: &TokenType = &Keyword::LIBRARY.base;
    pub const MIXIN: &TokenType = &Keyword::MIXIN.base;
    pub const NATIVE: &TokenType = &Keyword::NATIVE.base;
    pub const NEW: &TokenType = &Keyword::NEW.base;
    pub const NULL: &TokenType = &Keyword::NULL.base;
    pub const OF: &TokenType = &Keyword::OF.base;
    pub const ON: &TokenType = &Keyword::ON.base;
    pub const OPERATOR: &TokenType = &Keyword::OPERATOR.base;
    pub const OUT: &TokenType = &Keyword::OUT.base;
    pub const PART: &TokenType = &Keyword::PART.base;
    pub const PATCH: &TokenType = &Keyword::PATCH.base;
    pub const REQUIRED: &TokenType = &Keyword::REQUIRED.base;
    pub const RETHROW: &TokenType = &Keyword::RETHROW.base;
    pub const RETURN: &TokenType = &Keyword::RETURN.base;
    pub const SEALED: &TokenType = &Keyword::SEALED.base;
    pub const SET: &TokenType = &Keyword::SET.base;
    pub const SHOW: &TokenType = &Keyword::SHOW.base;
    pub const SOURCE: &TokenType = &Keyword::SOURCE.base;
    pub const STATIC: &TokenType = &Keyword::STATIC.base;
    pub const SUPER: &TokenType = &Keyword::SUPER.base;
    pub const SWITCH: &TokenType = &Keyword::SWITCH.base;
    pub const SYNC: &TokenType = &Keyword::SYNC.base;
    pub const THIS: &TokenType = &Keyword::THIS.base;
    pub const THROW: &TokenType = &Keyword::THROW.base;
    pub const TRUE: &TokenType = &Keyword::TRUE.base;
    pub const TRY: &TokenType = &Keyword::TRY.base;
    pub const TYPEDEF: &TokenType = &Keyword::TYPEDEF.base;
    pub const VAR: &TokenType = &Keyword::VAR.base;
    pub const VOID: &TokenType = &Keyword::VOID.base;
    pub const WHEN: &TokenType = &Keyword::WHEN.base;
    pub const WHILE: &TokenType = &Keyword::WHILE.base;
    pub const WITH: &TokenType = &Keyword::WITH.base;
    pub const YIELD: &TokenType = &Keyword::YIELD.base;
}

/// Returns true if [token] is the symbol or keyword [value].
pub fn optional(tokens: &TokenStore, value: &str, token: TokenId) -> bool {
    tokens.string_value(token) == Some(value)
}

/// Returns the token before the close brace, bracket, or parenthesis
/// associated with [left]. For '<', it may return `null`.
pub fn before_close_brace_token_for(tokens: &TokenStore, left: TokenId) -> TokenId {
    let end_token = tokens.end_group(left);
    if end_token == NO_TOKEN {
        return NO_TOKEN;
    }
    let mut token = left;
    let mut next = tokens.next(token);
    while next != end_token && next != tokens.next(next) {
        token = next;
        next = tokens.next(token);
    }
    token
}

/// Return [token] or a token before [token] which is either
/// not synthetic or synthetic with non-zero length.
pub fn find_previous_non_zero_length_token(tokens: &TokenStore, mut token: TokenId) -> TokenId {
    while tokens.is_synthetic(token) && tokens.length(token) == 0 {
        let previous = tokens.before_synthetic(token);
        if previous == token {
            panic!("Bad state: token == token.beforeSynthetic");
        }
        if previous == NO_TOKEN {
            break;
        }
        token = previous;
    }
    token
}

/// Return [token] or a token after [token] which is either
/// not synthetic or synthetic with non-zero length.
/// This may return EOF if there are no more non-synthetic tokens in the stream.
pub fn find_non_zero_length_token(tokens: &TokenStore, mut token: TokenId) -> TokenId {
    while tokens.is_synthetic(token) && tokens.length(token) == 0 && !tokens.is_eof(token) {
        token = tokens.next(token);
    }
    token
}

pub fn is_digit(c: i32) -> bool {
    c >= 0x30 && c <= 0x39
}

pub fn is_letter(c: i32) -> bool {
    c >= 0x41 && c <= 0x5A || c >= 0x61 && c <= 0x7A
}

pub fn is_letter_or_digit(c: i32) -> bool {
    is_letter(c) || is_digit(c)
}

pub fn is_whitespace(c: i32) -> bool {
    c == 0x20 || c == 0xA || c == 0xD || c == 0x9
}

pub fn is_any_of(tokens: &TokenStore, token: TokenId, values: &[&TokenType]) -> bool {
    let type_ = tokens.type_(token);
    for token_value in values {
        if *token_value == type_ {
            return true;
        }
    }
    false
}

/// A null-aware alternative to `token.length`.  If [token] is `null`, returns
/// [noLength].
pub fn length_for_token(tokens: &TokenStore, token: TokenId) -> i32 {
    if token == NO_TOKEN {
        noLength
    } else {
        tokens.length(token)
    }
}

/// Returns the length of the span from [begin] to [end] (inclusive). If both
/// tokens are null, return [noLength]. If one of the tokens are null, return
/// the length of the other token.
pub fn length_of_span(tokens: &TokenStore, begin: TokenId, end: TokenId) -> i32 {
    if begin == NO_TOKEN {
        return length_for_token(tokens, end);
    }
    if end == NO_TOKEN {
        return length_for_token(tokens, begin);
    }
    tokens.offset(end) + tokens.length(end) - tokens.offset(begin)
}

pub fn skip_metadata(tokens: &TokenStore, mut token: TokenId) -> TokenId {
    token = tokens.next(token);
    debug_assert!(tokens.is_a(token, TokenType::AT));
    let mut next = tokens.next(token);
    // Corresponds to 'ensureIdentifier' in [parseMetadata].
    if tokens.is_identifier(next) {
        token = next;
        next = tokens.next(token);
        // Corresponds to 'parseQualifiedRestOpt' in [parseMetadata].
        if tokens.is_a(next, TokenType::PERIOD) {
            token = next;
            next = tokens.next(token);
            if tokens.is_identifier(next) {
                token = next;
                next = tokens.next(token);
            }
        }
        // Corresponds to 'computeTypeParamOrArg' in [parseMetadata].
        if tokens.is_a(next, TokenType::LT) && !tokens.is_synthetic(tokens.end_group(next)) {
            token = tokens.end_group(next);
            next = tokens.next(token);
        }
        // The extra .identifier after arguments in [parseMetadata].
        if tokens.is_a(next, TokenType::PERIOD) {
            token = next;
            next = tokens.next(token);
            if tokens.is_identifier(next) {
                token = next;
                next = tokens.next(token);
            }
        }
        // Corresponds to 'parseArgumentsOpt' in [parseMetadata].
        if tokens.is_a(next, TokenType::OPEN_PAREN) && !tokens.is_synthetic(tokens.end_group(next))
        {
            token = tokens.end_group(next);
        }
    }
    token
}

/// `new SimpleToken(first, token.charOffset, token.precedingComments)`
/// followed by simple tokens of [rest] at the following offsets, the last of
/// which gets `next = token.next` without setting its previous: the shape
/// every `splitGt...` below returns.
fn split(
    tokens: &mut TokenStore,
    token: TokenId,
    first: &TokenType,
    rest: &[&TokenType],
) -> TokenId {
    let offset = tokens.char_offset(token);
    let comments = tokens.preceding_comments(token);
    let head = tokens.simple_token(first, offset, comments);
    let mut last = head;
    for (i, type_) in rest.iter().enumerate() {
        let t = tokens.simple_token(type_, offset + 1 + i as i32, NO_TOKEN);
        tokens.set_next(last, t);
        last = t;
    }
    // Set next rather than calling Token.setNext
    // so that the previous token is not set.
    let next = tokens.next(token);
    tokens.set_next_field(last, next);
    head
}

/// Split `>=` into two separate tokens.
/// Call [Token.setNext] to add the token to the stream.
pub fn split_gt_eq(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    debug_assert!(tokens.is_a(token, TokenType::GT_EQ));
    split(tokens, token, TokenType::GT, &[TokenType::EQ])
}

/// Split `>>` into two separate tokens.
/// Call [Token.setNext] to add the token to the stream.
pub fn split_gt_gt(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    debug_assert!(tokens.is_a(token, TokenType::GT_GT));
    split(tokens, token, TokenType::GT, &[TokenType::GT])
}

/// Split `>>=` into three separate tokens.
/// Call [Token.setNext] to add the token to the stream.
pub fn split_gt_gt_eq(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    debug_assert!(tokens.is_a(token, TokenType::GT_GT_EQ));
    split(
        tokens,
        token,
        TokenType::GT,
        &[TokenType::GT, TokenType::EQ],
    )
}

/// Split `>>=` into two separate tokens... `>` followed by `>=`.
/// Call [Token.setNext] to add the token to the stream.
pub fn split_gt_from_gt_gt_eq(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    debug_assert!(tokens.is_a(token, TokenType::GT_GT_EQ));
    split(tokens, token, TokenType::GT, &[TokenType::GT_EQ])
}

/// Split `>>>` into two separate tokens... `>` followed by `>>`.
/// Call [Token.setNext] to add the token to the stream.
pub fn split_gt_from_gt_gt_gt(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    debug_assert!(tokens.is_a(token, TokenType::GT_GT_GT));
    split(tokens, token, TokenType::GT, &[TokenType::GT_GT])
}

/// Split `>>>=` into two separate tokens... `>` followed by `>>=`.
/// Call [Token.setNext] to add the token to the stream.
pub fn split_gt_from_gt_gt_gt_eq(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    debug_assert!(tokens.is_a(token, TokenType::GT_GT_GT_EQ));
    split(tokens, token, TokenType::GT, &[TokenType::GT_GT_EQ])
}

/// Strips separator characters (underscore) from [source].
///
/// No validation is performed on [source]; it could be a valid int, a valid
/// double, or invalid. (Upstream reuses a buffer; that is not observable.)
pub fn strip_separators(source: &str) -> String {
    source.chars().filter(|&c| c != '_').collect()
}

/// Return a synthetic `>` followed by [next].
/// Call [Token.setNext] to add the token to the stream.
pub fn synthetic_gt(tokens: &mut TokenStore, next: TokenId) -> TokenId {
    let offset = tokens.char_offset(next);
    let gt = tokens.synthetic_token(TokenType::GT, offset);
    // Set next rather than calling Token.setNext
    // so that the previous token is not set.
    tokens.set_next_field(gt, next);
    gt
}

/// Returns the boolean value from a 'true' or 'false' [token].
pub fn bool_from_token(tokens: &TokenStore, token: TokenId) -> bool {
    let value = tokens.is_a(token, kw::TRUE);
    debug_assert!(value || tokens.is_a(token, kw::FALSE));
    value
}

/// Returns the integer value from an integer literal token, or `None` if
/// the token text could not be parsed as an integer value (Dart's
/// `int.tryParse`, which also takes hexadecimal with a `0x` prefix).
pub fn int_from_token(tokens: &TokenStore, token: TokenId, has_separators: bool) -> Option<i64> {
    let mut text = tokens.lexeme_string(token);
    if has_separators {
        text = strip_separators(&text);
    }
    let lower = text.to_ascii_lowercase();
    if let Some(hex) = lower.strip_prefix("0x") {
        // Dart reads a hexadecimal literal up to 64 bits as a two's
        // complement value.
        return u64::from_str_radix(hex, 16).ok().map(|v| v as i64);
    }
    text.parse::<i64>().ok()
}

/// Returns the double value from an double literal token.
pub fn double_from_token(tokens: &TokenStore, token: TokenId, has_separators: bool) -> f64 {
    let mut text = tokens.lexeme_string(token);
    if has_separators {
        text = strip_separators(&text);
    }
    text.parse::<f64>().unwrap()
}
