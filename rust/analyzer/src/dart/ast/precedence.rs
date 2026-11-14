// Port of lib/dart/ast/precedence.dart.

use fe_analyzer_shared::scanner::token::*;

/// `class PatternPrecedence`: compared by its index.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct PatternPrecedence(i32);

#[allow(non_upper_case_globals)]
impl PatternPrecedence {
    pub const logicalOr: PatternPrecedence = PatternPrecedence(1);
    pub const logicalAnd: PatternPrecedence = PatternPrecedence(2);
    pub const relational: PatternPrecedence = PatternPrecedence(3);
    pub const postfix: PatternPrecedence = PatternPrecedence(4);
    pub const primary: PatternPrecedence = PatternPrecedence(5);
}

/// `class Precedence`: compared by its index, the token precedence.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct Precedence(i32);

#[allow(non_upper_case_globals)]
impl Precedence {
    pub const none: Precedence = Precedence(NO_PRECEDENCE);
    pub const assignment: Precedence = Precedence(ASSIGNMENT_PRECEDENCE);
    pub const cascade: Precedence = Precedence(CASCADE_PRECEDENCE);
    pub const conditional: Precedence = Precedence(CONDITIONAL_PRECEDENCE);
    pub const ifNull: Precedence = Precedence(IF_NULL_PRECEDENCE);
    pub const logicalOr: Precedence = Precedence(LOGICAL_OR_PRECEDENCE);
    pub const logicalAnd: Precedence = Precedence(LOGICAL_AND_PRECEDENCE);
    pub const equality: Precedence = Precedence(EQUALITY_PRECEDENCE);
    pub const relational: Precedence = Precedence(RELATIONAL_PRECEDENCE);
    pub const bitwiseOr: Precedence = Precedence(BITWISE_OR_PRECEDENCE);
    pub const bitwiseXor: Precedence = Precedence(BITWISE_XOR_PRECEDENCE);
    pub const bitwiseAnd: Precedence = Precedence(BITWISE_AND_PRECEDENCE);
    pub const shift: Precedence = Precedence(SHIFT_PRECEDENCE);
    pub const additive: Precedence = Precedence(ADDITIVE_PRECEDENCE);
    pub const multiplicative: Precedence = Precedence(MULTIPLICATIVE_PRECEDENCE);
    pub const prefix: Precedence = Precedence(PREFIX_PRECEDENCE);
    pub const postfix: Precedence = Precedence(POSTFIX_PRECEDENCE);
    pub const primary: Precedence = Precedence(SELECTOR_PRECEDENCE);

    /// `Precedence.forTokenType(type)`.
    pub fn for_token_type(type_: &TokenType) -> Precedence {
        Precedence(type_.precedence)
    }
}
