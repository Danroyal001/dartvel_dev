// Port of lib/src/parser/literal_entry_info.dart.
//
// `LiteralEntryInfo` and its subclasses in literal_entry_info_impl.dart are
// one enum; the subclasses' overrides are the match arms there.

use crate::parser::identifier_context::looks_like_expression_start;
use crate::parser::util::kw;
use crate::scanner::token::{TokenId, TokenStore, TokenType};

/// [LiteralEntryInfo] represents steps for processing an entry
/// in a literal list, map, or set. These steps will handle parsing
/// both control flow and spreadable operators, and indicate
/// when the client should parse the literal entry.
#[derive(Clone, Debug, PartialEq)]
pub enum LiteralEntryInfo {
    /// `simpleEntry`: an entry with no control flow or spread.
    SimpleEntry,
    IfCondition,
    SpreadOperator,
    NullAwareEntry,
    ForCondition {
        in_style: bool,
    },
    ForSpread,
    ForInSpread,
    ForEntry,
    ForInEntry,
    ForComplete,
    ForInComplete,
    IfSpread,
    IfEntry,
    IfComplete,
    IfElse,
    ElseSpread,
    ElseEntry,
    IfElseComplete,
    Nested {
        nested_step: Option<Box<LiteralEntryInfo>>,
        last_step: Box<LiteralEntryInfo>,
    },
}

/// [simpleEntry] is the first step for processing a simple literal entry.
pub const simpleEntry: LiteralEntryInfo = LiteralEntryInfo::SimpleEntry;

impl LiteralEntryInfo {
    /// `true` if an entry should be parsed by the caller
    /// or `false` if this object's [parse] method should be called.
    pub fn has_entry(&self) -> bool {
        use LiteralEntryInfo::*;
        match self {
            SimpleEntry | NullAwareEntry | ForEntry | ForInEntry | IfEntry | ElseEntry => true,
            Nested { nested_step, .. } => nested_step.as_ref().unwrap().has_entry(),
            _ => false,
        }
    }

    /// Used for recovery, this indicates
    /// +1 for an `if` condition and -1 for `else`.
    pub fn if_condition_delta(&self) -> i32 {
        match self {
            LiteralEntryInfo::IfCondition => 1,
            LiteralEntryInfo::IfElse => -1,
            _ => 0,
        }
    }
}

/// Compute the [LiteralEntryInfo] for the literal list, map, or set entry.
pub fn compute_literal_entry(t: &TokenStore, token: TokenId) -> LiteralEntryInfo {
    let next = t.next(token);
    if t.is_a(next, kw::IF) {
        LiteralEntryInfo::IfCondition
    } else if t.is_a(next, kw::FOR) || (t.is_a(next, kw::AWAIT) && t.is_a(t.next(next), kw::FOR)) {
        LiteralEntryInfo::ForCondition { in_style: false }
    } else if t.is_a(next, TokenType::PERIOD_PERIOD_PERIOD)
        || t.is_a(next, TokenType::PERIOD_PERIOD_PERIOD_QUESTION)
    {
        LiteralEntryInfo::SpreadOperator
    } else if t.is_a(next, TokenType::QUESTION) {
        LiteralEntryInfo::NullAwareEntry
    } else {
        simpleEntry
    }
}

/// Return `true` if the given [token] should be treated like the start of
/// a literal entry in a list, set, or map for the purposes of recovery.
pub fn looks_like_literal_entry(t: &TokenStore, token: TokenId) -> bool {
    looks_like_expression_start(t, token)
        || t.is_a(token, TokenType::PERIOD_PERIOD_PERIOD)
        || t.is_a(token, TokenType::PERIOD_PERIOD_PERIOD_QUESTION)
        || t.is_a(token, kw::IF)
        || t.is_a(token, kw::FOR)
        || (t.is_a(token, kw::AWAIT) && t.is_a(t.next(token), kw::FOR))
}
