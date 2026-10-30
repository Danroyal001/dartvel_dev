// Port of lib/src/scanner/token.dart.
//
// Upstream tokens are objects in a doubly linked list. Here they live in a
// `TokenStore`, an arena addressed by 32-bit `TokenId`s, and each Dart token
// getter is a `TokenStore` method that takes the token's id. The token
// classes become a `TokenRuntimeType` tag on each token, named after the Dart
// runtime type, so code that dispatched on a class dispatches on the tag.
//
// `TokenType` and `Keyword` constants keep upstream's names, indexes and
// fields; their rows were printed from the upstream constants at the pinned
// commit, so they cannot have been retyped wrongly.
#![allow(non_upper_case_globals)]

use std::rc::Rc;

use super::string_canonicalizer::{decode_string, utf16_length_of_utf8_allow_malformed};
use super::token_constants::*;

pub const NO_PRECEDENCE: i32 = 0;
pub const ASSIGNMENT_PRECEDENCE: i32 = 1;
pub const CASCADE_PRECEDENCE: i32 = 2;
pub const CONDITIONAL_PRECEDENCE: i32 = 3;
pub const IF_NULL_PRECEDENCE: i32 = 4;
pub const LOGICAL_OR_PRECEDENCE: i32 = 5;
pub const LOGICAL_AND_PRECEDENCE: i32 = 6;
pub const EQUALITY_PRECEDENCE: i32 = 7;
pub const RELATIONAL_PRECEDENCE: i32 = 8;
pub const BITWISE_OR_PRECEDENCE: i32 = 9;
pub const BITWISE_XOR_PRECEDENCE: i32 = 10;
pub const BITWISE_AND_PRECEDENCE: i32 = 11;
pub const SHIFT_PRECEDENCE: i32 = 12;
pub const ADDITIVE_PRECEDENCE: i32 = 13;
pub const MULTIPLICATIVE_PRECEDENCE: i32 = 14;
pub const PREFIX_PRECEDENCE: i32 = 15;
pub const POSTFIX_PRECEDENCE: i32 = 16;
pub const SELECTOR_PRECEDENCE: i32 = 17;

// ---------------------------------------------------------------------------
// KeywordStyle, Keyword

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[allow(non_camel_case_types)]
pub enum KeywordStyle {
    reserved,
    builtIn,
    pseudo,
}

impl KeywordStyle {
    pub fn name(self) -> &'static str {
        match self {
            KeywordStyle::reserved => "reserved",
            KeywordStyle::builtIn => "builtIn",
            KeywordStyle::pseudo => "pseudo",
        }
    }
}

/// `class Keyword extends TokenType`: the `TokenType` part is [Keyword::base].
#[derive(Debug)]
pub struct Keyword {
    pub base: TokenType,
    pub keyword_style: KeywordStyle,
}

impl Keyword {
    pub const ABSTRACT: &'static Keyword = &Keyword::new(
        82,
        "abstract",
        "ABSTRACT",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const AS: &'static Keyword = &Keyword::new(
        83,
        "as",
        "AS",
        KeywordStyle::builtIn,
        false,
        false,
        RELATIONAL_PRECEDENCE,
    );
    pub const ASSERT: &'static Keyword = &Keyword::new(
        84,
        "assert",
        "ASSERT",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const ASYNC: &'static Keyword = &Keyword::new(
        85,
        "async",
        "ASYNC",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const AUGMENT: &'static Keyword = &Keyword::new(
        86,
        "augment",
        "AUGMENT",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const AWAIT: &'static Keyword = &Keyword::new(
        87,
        "await",
        "AWAIT",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const BASE: &'static Keyword = &Keyword::new(
        88,
        "base",
        "BASE",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const BREAK: &'static Keyword = &Keyword::new(
        89,
        "break",
        "BREAK",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const CASE: &'static Keyword = &Keyword::new(
        90,
        "case",
        "CASE",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const CATCH: &'static Keyword = &Keyword::new(
        91,
        "catch",
        "CATCH",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const CLASS: &'static Keyword = &Keyword::new(
        92,
        "class",
        "CLASS",
        KeywordStyle::reserved,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const CONST: &'static Keyword = &Keyword::new(
        93,
        "const",
        "CONST",
        KeywordStyle::reserved,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const CONTINUE: &'static Keyword = &Keyword::new(
        94,
        "continue",
        "CONTINUE",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const COVARIANT: &'static Keyword = &Keyword::new(
        95,
        "covariant",
        "COVARIANT",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const DEFAULT: &'static Keyword = &Keyword::new(
        96,
        "default",
        "DEFAULT",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const DEFERRED: &'static Keyword = &Keyword::new(
        97,
        "deferred",
        "DEFERRED",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const DO: &'static Keyword = &Keyword::new(
        98,
        "do",
        "DO",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const DYNAMIC: &'static Keyword = &Keyword::new(
        99,
        "dynamic",
        "DYNAMIC",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const ELSE: &'static Keyword = &Keyword::new(
        100,
        "else",
        "ELSE",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const ENUM: &'static Keyword = &Keyword::new(
        101,
        "enum",
        "ENUM",
        KeywordStyle::reserved,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const EXPORT: &'static Keyword = &Keyword::new(
        102,
        "export",
        "EXPORT",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const EXTENDS: &'static Keyword = &Keyword::new(
        103,
        "extends",
        "EXTENDS",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const EXTENSION: &'static Keyword = &Keyword::new(
        104,
        "extension",
        "EXTENSION",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const EXTERNAL: &'static Keyword = &Keyword::new(
        105,
        "external",
        "EXTERNAL",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const FACTORY: &'static Keyword = &Keyword::new(
        106,
        "factory",
        "FACTORY",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const FALSE: &'static Keyword = &Keyword::new(
        107,
        "false",
        "FALSE",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const FINAL: &'static Keyword = &Keyword::new(
        108,
        "final",
        "FINAL",
        KeywordStyle::reserved,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const FINALLY: &'static Keyword = &Keyword::new(
        109,
        "finally",
        "FINALLY",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const FOR: &'static Keyword = &Keyword::new(
        110,
        "for",
        "FOR",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const FUNCTION: &'static Keyword = &Keyword::new(
        111,
        "Function",
        "FUNCTION",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const GET: &'static Keyword = &Keyword::new(
        112,
        "get",
        "GET",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const HIDE: &'static Keyword = &Keyword::new(
        113,
        "hide",
        "HIDE",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const IF: &'static Keyword = &Keyword::new(
        114,
        "if",
        "IF",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const IMPLEMENTS: &'static Keyword = &Keyword::new(
        115,
        "implements",
        "IMPLEMENTS",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const IMPORT: &'static Keyword = &Keyword::new(
        116,
        "import",
        "IMPORT",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const IN: &'static Keyword = &Keyword::new(
        117,
        "in",
        "IN",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const INOUT: &'static Keyword = &Keyword::new(
        118,
        "inout",
        "INOUT",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const INTERFACE: &'static Keyword = &Keyword::new(
        119,
        "interface",
        "INTERFACE",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const IS: &'static Keyword = &Keyword::new(
        120,
        "is",
        "IS",
        KeywordStyle::reserved,
        false,
        false,
        RELATIONAL_PRECEDENCE,
    );
    pub const LATE: &'static Keyword = &Keyword::new(
        121,
        "late",
        "LATE",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const LIBRARY: &'static Keyword = &Keyword::new(
        122,
        "library",
        "LIBRARY",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const MIXIN: &'static Keyword = &Keyword::new(
        123,
        "mixin",
        "MIXIN",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const NATIVE: &'static Keyword = &Keyword::new(
        124,
        "native",
        "NATIVE",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const NEW: &'static Keyword = &Keyword::new(
        125,
        "new",
        "NEW",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const NULL: &'static Keyword = &Keyword::new(
        126,
        "null",
        "NULL",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const OF: &'static Keyword = &Keyword::new(
        127,
        "of",
        "OF",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const ON: &'static Keyword = &Keyword::new(
        128,
        "on",
        "ON",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const OPERATOR: &'static Keyword = &Keyword::new(
        129,
        "operator",
        "OPERATOR",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const OUT: &'static Keyword = &Keyword::new(
        130,
        "out",
        "OUT",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const PART: &'static Keyword = &Keyword::new(
        131,
        "part",
        "PART",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const PATCH: &'static Keyword = &Keyword::new(
        132,
        "patch",
        "PATCH",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const REQUIRED: &'static Keyword = &Keyword::new(
        133,
        "required",
        "REQUIRED",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const RETHROW: &'static Keyword = &Keyword::new(
        134,
        "rethrow",
        "RETHROW",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const RETURN: &'static Keyword = &Keyword::new(
        135,
        "return",
        "RETURN",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const SEALED: &'static Keyword = &Keyword::new(
        136,
        "sealed",
        "SEALED",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const SET: &'static Keyword = &Keyword::new(
        137,
        "set",
        "SET",
        KeywordStyle::builtIn,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const SHOW: &'static Keyword = &Keyword::new(
        138,
        "show",
        "SHOW",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const SOURCE: &'static Keyword = &Keyword::new(
        139,
        "source",
        "SOURCE",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const STATIC: &'static Keyword = &Keyword::new(
        140,
        "static",
        "STATIC",
        KeywordStyle::builtIn,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const SUPER: &'static Keyword = &Keyword::new(
        141,
        "super",
        "SUPER",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const SWITCH: &'static Keyword = &Keyword::new(
        142,
        "switch",
        "SWITCH",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const SYNC: &'static Keyword = &Keyword::new(
        143,
        "sync",
        "SYNC",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const THIS: &'static Keyword = &Keyword::new(
        144,
        "this",
        "THIS",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const THROW: &'static Keyword = &Keyword::new(
        145,
        "throw",
        "THROW",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const TRUE: &'static Keyword = &Keyword::new(
        146,
        "true",
        "TRUE",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const TRY: &'static Keyword = &Keyword::new(
        147,
        "try",
        "TRY",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const TYPEDEF: &'static Keyword = &Keyword::new(
        148,
        "typedef",
        "TYPEDEF",
        KeywordStyle::builtIn,
        false,
        true,
        NO_PRECEDENCE,
    );
    pub const VAR: &'static Keyword = &Keyword::new(
        149,
        "var",
        "VAR",
        KeywordStyle::reserved,
        true,
        false,
        NO_PRECEDENCE,
    );
    pub const VOID: &'static Keyword = &Keyword::new(
        150,
        "void",
        "VOID",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const WHEN: &'static Keyword = &Keyword::new(
        151,
        "when",
        "WHEN",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const WHILE: &'static Keyword = &Keyword::new(
        152,
        "while",
        "WHILE",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const WITH: &'static Keyword = &Keyword::new(
        153,
        "with",
        "WITH",
        KeywordStyle::reserved,
        false,
        false,
        NO_PRECEDENCE,
    );
    pub const YIELD: &'static Keyword = &Keyword::new(
        154,
        "yield",
        "YIELD",
        KeywordStyle::pseudo,
        false,
        false,
        NO_PRECEDENCE,
    );

    pub const values: [&'static Keyword; 73] = [
        Keyword::ABSTRACT,
        Keyword::AS,
        Keyword::ASSERT,
        Keyword::ASYNC,
        Keyword::AUGMENT,
        Keyword::AWAIT,
        Keyword::BASE,
        Keyword::BREAK,
        Keyword::CASE,
        Keyword::CATCH,
        Keyword::CLASS,
        Keyword::CONST,
        Keyword::CONTINUE,
        Keyword::COVARIANT,
        Keyword::DEFAULT,
        Keyword::DEFERRED,
        Keyword::DO,
        Keyword::DYNAMIC,
        Keyword::ELSE,
        Keyword::ENUM,
        Keyword::EXPORT,
        Keyword::EXTENDS,
        Keyword::EXTENSION,
        Keyword::EXTERNAL,
        Keyword::FACTORY,
        Keyword::FALSE,
        Keyword::FINAL,
        Keyword::FINALLY,
        Keyword::FOR,
        Keyword::FUNCTION,
        Keyword::GET,
        Keyword::HIDE,
        Keyword::IF,
        Keyword::IMPLEMENTS,
        Keyword::IMPORT,
        Keyword::IN,
        Keyword::INOUT,
        Keyword::INTERFACE,
        Keyword::IS,
        Keyword::LATE,
        Keyword::LIBRARY,
        Keyword::MIXIN,
        Keyword::NATIVE,
        Keyword::NEW,
        Keyword::NULL,
        Keyword::OF,
        Keyword::ON,
        Keyword::OPERATOR,
        Keyword::OUT,
        Keyword::PART,
        Keyword::PATCH,
        Keyword::REQUIRED,
        Keyword::RETHROW,
        Keyword::RETURN,
        Keyword::SEALED,
        Keyword::SET,
        Keyword::SHOW,
        Keyword::SOURCE,
        Keyword::STATIC,
        Keyword::SUPER,
        Keyword::SWITCH,
        Keyword::SYNC,
        Keyword::THIS,
        Keyword::THROW,
        Keyword::TRUE,
        Keyword::TRY,
        Keyword::TYPEDEF,
        Keyword::VAR,
        Keyword::VOID,
        Keyword::WHEN,
        Keyword::WHILE,
        Keyword::WITH,
        Keyword::YIELD,
    ];

    #[allow(clippy::too_many_arguments)]
    pub const fn new(
        index: i32,
        lexeme: &'static str,
        name: &'static str,
        keyword_style: KeywordStyle,
        is_modifier: bool,
        is_top_level_keyword: bool,
        precedence: i32,
    ) -> Keyword {
        Keyword {
            base: TokenType::new(
                index,
                lexeme,
                name,
                precedence,
                KEYWORD_TOKEN,
                TokenTypeFlags {
                    binary_operator_of_compound_assignment: None,
                    is_binary_operator: false,
                    is_modifier,
                    is_operator: false,
                    is_top_level_keyword,
                    is_user_definable_operator: false,
                    string_value_should_be_null: false,
                },
            ),
            keyword_style,
        }
    }

    /// `Keyword.keywords[lexeme]`.
    pub fn keywords(lexeme: &str) -> Option<&'static Keyword> {
        Keyword::values
            .iter()
            .copied()
            .find(|k| k.base.lexeme == lexeme)
    }

    pub fn lexeme(&self) -> &'static str {
        self.base.lexeme
    }

    pub fn is_built_in(&self) -> bool {
        self.keyword_style == KeywordStyle::builtIn
    }

    pub fn is_pseudo(&self) -> bool {
        self.keyword_style == KeywordStyle::pseudo
    }

    pub fn is_built_in_or_pseudo(&self) -> bool {
        self.is_built_in() || self.is_pseudo()
    }

    pub fn is_reserved_word(&self) -> bool {
        self.keyword_style == KeywordStyle::reserved
    }

    /// `name` is overridden to `lexeme.toUpperCase()`.
    pub fn name(&self) -> String {
        self.base.lexeme.to_uppercase()
    }

    /// The keyword whose `TokenType` is [type_], if it is one.
    pub fn of_type(type_: &TokenType) -> Option<&'static Keyword> {
        if type_.kind != KEYWORD_TOKEN {
            return None;
        }
        let i = (type_.index - Keyword::values[0].base.index) as usize;
        let keyword = Keyword::values[i];
        debug_assert!(keyword.base.index == type_.index);
        Some(keyword)
    }
}

// ---------------------------------------------------------------------------
// TokenClass

#[derive(Debug)]
pub struct TokenClass {
    pub name: &'static str,
    pub precedence: i32,
}

impl TokenClass {
    pub const NO_CLASS: TokenClass = TokenClass::new("NO_CLASS", NO_PRECEDENCE);
    pub const ADDITIVE_OPERATOR: TokenClass =
        TokenClass::new("ADDITIVE_OPERATOR", ADDITIVE_PRECEDENCE);
    pub const ASSIGNMENT_OPERATOR: TokenClass =
        TokenClass::new("ASSIGNMENT_OPERATOR", ASSIGNMENT_PRECEDENCE);
    pub const BITWISE_AND_OPERATOR: TokenClass =
        TokenClass::new("BITWISE_AND_OPERATOR", BITWISE_AND_PRECEDENCE);
    pub const BITWISE_OR_OPERATOR: TokenClass =
        TokenClass::new("BITWISE_OR_OPERATOR", BITWISE_OR_PRECEDENCE);
    pub const BITWISE_XOR_OPERATOR: TokenClass =
        TokenClass::new("BITWISE_XOR_OPERATOR", BITWISE_XOR_PRECEDENCE);
    pub const CASCADE_OPERATOR: TokenClass =
        TokenClass::new("CASCADE_OPERATOR", CASCADE_PRECEDENCE);
    pub const CONDITIONAL_OPERATOR: TokenClass =
        TokenClass::new("CONDITIONAL_OPERATOR", CONDITIONAL_PRECEDENCE);
    pub const EQUALITY_OPERATOR: TokenClass =
        TokenClass::new("EQUALITY_OPERATOR", EQUALITY_PRECEDENCE);
    pub const IF_NULL_OPERATOR: TokenClass =
        TokenClass::new("IF_NULL_OPERATOR", IF_NULL_PRECEDENCE);
    pub const LOGICAL_AND_OPERATOR: TokenClass =
        TokenClass::new("LOGICAL_AND_OPERATOR", LOGICAL_AND_PRECEDENCE);
    pub const LOGICAL_OR_OPERATOR: TokenClass =
        TokenClass::new("LOGICAL_OR_OPERATOR", LOGICAL_OR_PRECEDENCE);
    pub const MULTIPLICATIVE_OPERATOR: TokenClass =
        TokenClass::new("MULTIPLICATIVE_OPERATOR", MULTIPLICATIVE_PRECEDENCE);
    pub const RELATIONAL_OPERATOR: TokenClass =
        TokenClass::new("RELATIONAL_OPERATOR", RELATIONAL_PRECEDENCE);
    pub const SHIFT_OPERATOR: TokenClass = TokenClass::new("SHIFT_OPERATOR", SHIFT_PRECEDENCE);
    pub const UNARY_POSTFIX_OPERATOR: TokenClass =
        TokenClass::new("UNARY_POSTFIX_OPERATOR", POSTFIX_PRECEDENCE);
    pub const UNARY_PREFIX_OPERATOR: TokenClass =
        TokenClass::new("UNARY_PREFIX_OPERATOR", PREFIX_PRECEDENCE);

    pub const fn new(name: &'static str, precedence: i32) -> TokenClass {
        TokenClass { name, precedence }
    }
}

// ---------------------------------------------------------------------------
// TokenType

/// The named optional parameters of upstream's `TokenType` constructor.
#[derive(Debug)]
pub struct TokenTypeFlags {
    pub binary_operator_of_compound_assignment: Option<&'static TokenType>,
    pub is_binary_operator: bool,
    pub is_modifier: bool,
    pub is_operator: bool,
    pub is_top_level_keyword: bool,
    pub is_user_definable_operator: bool,
    pub string_value_should_be_null: bool,
}

#[derive(Debug)]
pub struct TokenType {
    pub index: i32,
    pub binary_operator_of_compound_assignment: Option<&'static TokenType>,
    pub kind: i32,
    pub is_modifier: bool,
    pub is_operator: bool,
    pub is_binary_operator: bool,
    pub is_top_level_keyword: bool,
    pub is_user_definable_operator: bool,
    pub lexeme: &'static str,
    pub name: &'static str,
    pub precedence: i32,
    pub string_value: Option<&'static str>,
}

/// Upstream compares token types by identity, and every type has its own
/// index, so comparing indexes is the same test.
impl PartialEq for TokenType {
    fn eq(&self, other: &TokenType) -> bool {
        self.index == other.index
    }
}

impl Eq for TokenType {}

impl TokenType {
    pub const EOF: &'static TokenType = &TokenType::new(
        0,
        "",
        "EOF",
        NO_PRECEDENCE,
        EOF_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const DOUBLE: &'static TokenType = &TokenType::new(
        1,
        "double",
        "DOUBLE",
        NO_PRECEDENCE,
        DOUBLE_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const DOUBLE_WITH_SEPARATORS: &'static TokenType = &TokenType::new(
        2,
        "double",
        "DOUBLE_WITH_SEPARATORS",
        NO_PRECEDENCE,
        DOUBLE_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const HEXADECIMAL: &'static TokenType = &TokenType::new(
        3,
        "hexadecimal",
        "HEXADECIMAL",
        NO_PRECEDENCE,
        HEXADECIMAL_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const HEXADECIMAL_WITH_SEPARATORS: &'static TokenType = &TokenType::new(
        4,
        "hexadecimal",
        "HEXADECIMAL_WITH_SEPARATORS",
        NO_PRECEDENCE,
        HEXADECIMAL_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const IDENTIFIER: &'static TokenType = &TokenType::new(
        5,
        "identifier",
        "IDENTIFIER",
        NO_PRECEDENCE,
        IDENTIFIER_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const INT: &'static TokenType = &TokenType::new(
        6,
        "int",
        "INT",
        NO_PRECEDENCE,
        INT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const INT_WITH_SEPARATORS: &'static TokenType = &TokenType::new(
        7,
        "int",
        "INT_WITH_SEPARATORS",
        NO_PRECEDENCE,
        INT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const MULTI_LINE_COMMENT: &'static TokenType = &TokenType::new(
        8,
        "comment",
        "MULTI_LINE_COMMENT",
        NO_PRECEDENCE,
        COMMENT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const SCRIPT_TAG: &'static TokenType = &TokenType::new(
        9,
        "script",
        "SCRIPT_TAG",
        NO_PRECEDENCE,
        SCRIPT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const SINGLE_LINE_COMMENT: &'static TokenType = &TokenType::new(
        10,
        "comment",
        "SINGLE_LINE_COMMENT",
        NO_PRECEDENCE,
        COMMENT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const STRING: &'static TokenType = &TokenType::new(
        11,
        "string",
        "STRING",
        NO_PRECEDENCE,
        STRING_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const AMPERSAND: &'static TokenType = &TokenType::new(
        12,
        "&",
        "AMPERSAND",
        BITWISE_AND_PRECEDENCE,
        AMPERSAND_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const AMPERSAND_AMPERSAND: &'static TokenType = &TokenType::new(
        13,
        "&&",
        "AMPERSAND_AMPERSAND",
        LOGICAL_AND_PRECEDENCE,
        AMPERSAND_AMPERSAND_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const AMPERSAND_AMPERSAND_EQ: &'static TokenType = &TokenType::new(
        14,
        "&&=",
        "AMPERSAND_AMPERSAND_EQ",
        ASSIGNMENT_PRECEDENCE,
        AMPERSAND_AMPERSAND_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::AMPERSAND_AMPERSAND),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const AMPERSAND_EQ: &'static TokenType = &TokenType::new(
        15,
        "&=",
        "AMPERSAND_EQ",
        ASSIGNMENT_PRECEDENCE,
        AMPERSAND_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::AMPERSAND),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const AT: &'static TokenType = &TokenType::new(
        16,
        "@",
        "AT",
        NO_PRECEDENCE,
        AT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BANG: &'static TokenType = &TokenType::new(
        17,
        "!",
        "BANG",
        PREFIX_PRECEDENCE,
        BANG_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BANG_EQ: &'static TokenType = &TokenType::new(
        18,
        "!=",
        "BANG_EQ",
        EQUALITY_PRECEDENCE,
        BANG_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BANG_EQ_EQ: &'static TokenType = &TokenType::new(
        19,
        "!==",
        "BANG_EQ_EQ",
        EQUALITY_PRECEDENCE,
        BANG_EQ_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BAR: &'static TokenType = &TokenType::new(
        20,
        "|",
        "BAR",
        BITWISE_OR_PRECEDENCE,
        BAR_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const BAR_BAR: &'static TokenType = &TokenType::new(
        21,
        "||",
        "BAR_BAR",
        LOGICAL_OR_PRECEDENCE,
        BAR_BAR_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BAR_BAR_EQ: &'static TokenType = &TokenType::new(
        22,
        "||=",
        "BAR_BAR_EQ",
        ASSIGNMENT_PRECEDENCE,
        BAR_BAR_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::BAR_BAR),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BAR_EQ: &'static TokenType = &TokenType::new(
        23,
        "|=",
        "BAR_EQ",
        ASSIGNMENT_PRECEDENCE,
        BAR_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::BAR),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const COLON: &'static TokenType = &TokenType::new(
        24,
        ":",
        "COLON",
        NO_PRECEDENCE,
        COLON_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const COMMA: &'static TokenType = &TokenType::new(
        25,
        ",",
        "COMMA",
        NO_PRECEDENCE,
        COMMA_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const CARET: &'static TokenType = &TokenType::new(
        26,
        "^",
        "CARET",
        BITWISE_XOR_PRECEDENCE,
        CARET_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const CARET_EQ: &'static TokenType = &TokenType::new(
        27,
        "^=",
        "CARET_EQ",
        ASSIGNMENT_PRECEDENCE,
        CARET_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::CARET),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const CLOSE_CURLY_BRACKET: &'static TokenType = &TokenType::new(
        28,
        "}",
        "CLOSE_CURLY_BRACKET",
        NO_PRECEDENCE,
        CLOSE_CURLY_BRACKET_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const CLOSE_PAREN: &'static TokenType = &TokenType::new(
        29,
        ")",
        "CLOSE_PAREN",
        NO_PRECEDENCE,
        CLOSE_PAREN_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const CLOSE_SQUARE_BRACKET: &'static TokenType = &TokenType::new(
        30,
        "]",
        "CLOSE_SQUARE_BRACKET",
        NO_PRECEDENCE,
        CLOSE_SQUARE_BRACKET_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const EQ: &'static TokenType = &TokenType::new(
        31,
        "=",
        "EQ",
        ASSIGNMENT_PRECEDENCE,
        EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const EQ_EQ: &'static TokenType = &TokenType::new(
        32,
        "==",
        "EQ_EQ",
        EQUALITY_PRECEDENCE,
        EQ_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const EQ_EQ_EQ: &'static TokenType = &TokenType::new(
        33,
        "===",
        "EQ_EQ_EQ",
        EQUALITY_PRECEDENCE,
        EQ_EQ_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const FUNCTION: &'static TokenType = &TokenType::new(
        34,
        "=>",
        "FUNCTION",
        NO_PRECEDENCE,
        FUNCTION_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const GT: &'static TokenType = &TokenType::new(
        35,
        ">",
        "GT",
        RELATIONAL_PRECEDENCE,
        GT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const GT_EQ: &'static TokenType = &TokenType::new(
        36,
        ">=",
        "GT_EQ",
        RELATIONAL_PRECEDENCE,
        GT_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const GT_GT: &'static TokenType = &TokenType::new(
        37,
        ">>",
        "GT_GT",
        SHIFT_PRECEDENCE,
        GT_GT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const GT_GT_EQ: &'static TokenType = &TokenType::new(
        38,
        ">>=",
        "GT_GT_EQ",
        ASSIGNMENT_PRECEDENCE,
        GT_GT_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::GT_GT),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const GT_GT_GT: &'static TokenType = &TokenType::new(
        39,
        ">>>",
        "GT_GT_GT",
        SHIFT_PRECEDENCE,
        GT_GT_GT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const GT_GT_GT_EQ: &'static TokenType = &TokenType::new(
        40,
        ">>>=",
        "GT_GT_GT_EQ",
        ASSIGNMENT_PRECEDENCE,
        GT_GT_GT_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::GT_GT_GT),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const HASH: &'static TokenType = &TokenType::new(
        41,
        "#",
        "HASH",
        NO_PRECEDENCE,
        HASH_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const INDEX: &'static TokenType = &TokenType::new(
        42,
        "[]",
        "INDEX",
        SELECTOR_PRECEDENCE,
        INDEX_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const INDEX_EQ: &'static TokenType = &TokenType::new(
        43,
        "[]=",
        "INDEX_EQ",
        NO_PRECEDENCE,
        INDEX_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const LT: &'static TokenType = &TokenType::new(
        44,
        "<",
        "LT",
        RELATIONAL_PRECEDENCE,
        LT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const LT_EQ: &'static TokenType = &TokenType::new(
        45,
        "<=",
        "LT_EQ",
        RELATIONAL_PRECEDENCE,
        LT_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const LT_LT: &'static TokenType = &TokenType::new(
        46,
        "<<",
        "LT_LT",
        SHIFT_PRECEDENCE,
        LT_LT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const LT_LT_EQ: &'static TokenType = &TokenType::new(
        47,
        "<<=",
        "LT_LT_EQ",
        ASSIGNMENT_PRECEDENCE,
        LT_LT_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::LT_LT),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const MINUS: &'static TokenType = &TokenType::new(
        48,
        "-",
        "MINUS",
        ADDITIVE_PRECEDENCE,
        MINUS_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const MINUS_EQ: &'static TokenType = &TokenType::new(
        49,
        "-=",
        "MINUS_EQ",
        ASSIGNMENT_PRECEDENCE,
        MINUS_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::MINUS),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const MINUS_MINUS: &'static TokenType = &TokenType::new(
        50,
        "--",
        "MINUS_MINUS",
        POSTFIX_PRECEDENCE,
        MINUS_MINUS_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const OPEN_CURLY_BRACKET: &'static TokenType = &TokenType::new(
        51,
        "{",
        "OPEN_CURLY_BRACKET",
        NO_PRECEDENCE,
        OPEN_CURLY_BRACKET_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const OPEN_PAREN: &'static TokenType = &TokenType::new(
        52,
        "(",
        "OPEN_PAREN",
        SELECTOR_PRECEDENCE,
        OPEN_PAREN_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const OPEN_SQUARE_BRACKET: &'static TokenType = &TokenType::new(
        53,
        "[",
        "OPEN_SQUARE_BRACKET",
        SELECTOR_PRECEDENCE,
        OPEN_SQUARE_BRACKET_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PERCENT: &'static TokenType = &TokenType::new(
        54,
        "%",
        "PERCENT",
        MULTIPLICATIVE_PRECEDENCE,
        PERCENT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const PERCENT_EQ: &'static TokenType = &TokenType::new(
        55,
        "%=",
        "PERCENT_EQ",
        ASSIGNMENT_PRECEDENCE,
        PERCENT_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::PERCENT),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PERIOD: &'static TokenType = &TokenType::new(
        56,
        ".",
        "PERIOD",
        SELECTOR_PRECEDENCE,
        PERIOD_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PERIOD_PERIOD: &'static TokenType = &TokenType::new(
        57,
        "..",
        "PERIOD_PERIOD",
        CASCADE_PRECEDENCE,
        PERIOD_PERIOD_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PLUS: &'static TokenType = &TokenType::new(
        58,
        "+",
        "PLUS",
        ADDITIVE_PRECEDENCE,
        PLUS_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const PLUS_EQ: &'static TokenType = &TokenType::new(
        59,
        "+=",
        "PLUS_EQ",
        ASSIGNMENT_PRECEDENCE,
        PLUS_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::PLUS),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PLUS_PLUS: &'static TokenType = &TokenType::new(
        60,
        "++",
        "PLUS_PLUS",
        POSTFIX_PRECEDENCE,
        PLUS_PLUS_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const QUESTION: &'static TokenType = &TokenType::new(
        61,
        "?",
        "QUESTION",
        CONDITIONAL_PRECEDENCE,
        QUESTION_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const QUESTION_PERIOD: &'static TokenType = &TokenType::new(
        62,
        "?.",
        "QUESTION_PERIOD",
        SELECTOR_PRECEDENCE,
        QUESTION_PERIOD_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const QUESTION_QUESTION: &'static TokenType = &TokenType::new(
        63,
        "??",
        "QUESTION_QUESTION",
        IF_NULL_PRECEDENCE,
        QUESTION_QUESTION_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const QUESTION_QUESTION_EQ: &'static TokenType = &TokenType::new(
        64,
        "??=",
        "QUESTION_QUESTION_EQ",
        ASSIGNMENT_PRECEDENCE,
        QUESTION_QUESTION_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::QUESTION_QUESTION),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const SEMICOLON: &'static TokenType = &TokenType::new(
        65,
        ";",
        "SEMICOLON",
        NO_PRECEDENCE,
        SEMICOLON_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const SLASH: &'static TokenType = &TokenType::new(
        66,
        "/",
        "SLASH",
        MULTIPLICATIVE_PRECEDENCE,
        SLASH_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const SLASH_EQ: &'static TokenType = &TokenType::new(
        67,
        "/=",
        "SLASH_EQ",
        ASSIGNMENT_PRECEDENCE,
        SLASH_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::SLASH),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const STAR: &'static TokenType = &TokenType::new(
        68,
        "*",
        "STAR",
        MULTIPLICATIVE_PRECEDENCE,
        STAR_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const STAR_EQ: &'static TokenType = &TokenType::new(
        69,
        "*=",
        "STAR_EQ",
        ASSIGNMENT_PRECEDENCE,
        STAR_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::STAR),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const STRING_INTERPOLATION_EXPRESSION: &'static TokenType = &TokenType::new(
        70,
        "${",
        "STRING_INTERPOLATION_EXPRESSION",
        NO_PRECEDENCE,
        STRING_INTERPOLATION_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const STRING_INTERPOLATION_IDENTIFIER: &'static TokenType = &TokenType::new(
        71,
        "$",
        "STRING_INTERPOLATION_IDENTIFIER",
        NO_PRECEDENCE,
        STRING_INTERPOLATION_IDENTIFIER_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const TILDE: &'static TokenType = &TokenType::new(
        72,
        "~",
        "TILDE",
        PREFIX_PRECEDENCE,
        TILDE_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const TILDE_SLASH: &'static TokenType = &TokenType::new(
        73,
        "~/",
        "TILDE_SLASH",
        MULTIPLICATIVE_PRECEDENCE,
        TILDE_SLASH_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: true,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: true,
            string_value_should_be_null: false,
        },
    );
    pub const TILDE_SLASH_EQ: &'static TokenType = &TokenType::new(
        74,
        "~/=",
        "TILDE_SLASH_EQ",
        ASSIGNMENT_PRECEDENCE,
        TILDE_SLASH_EQ_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: Some(TokenType::TILDE_SLASH),
            is_binary_operator: false,
            is_modifier: false,
            is_operator: true,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BACKPING: &'static TokenType = &TokenType::new(
        75,
        "`",
        "BACKPING",
        NO_PRECEDENCE,
        BACKPING_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BACKSLASH: &'static TokenType = &TokenType::new(
        76,
        "\\",
        "BACKSLASH",
        NO_PRECEDENCE,
        BACKSLASH_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PERIOD_PERIOD_PERIOD: &'static TokenType = &TokenType::new(
        77,
        "...",
        "PERIOD_PERIOD_PERIOD",
        NO_PRECEDENCE,
        PERIOD_PERIOD_PERIOD_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const PERIOD_PERIOD_PERIOD_QUESTION: &'static TokenType = &TokenType::new(
        78,
        "...?",
        "PERIOD_PERIOD_PERIOD_QUESTION",
        NO_PRECEDENCE,
        PERIOD_PERIOD_PERIOD_QUESTION_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const QUESTION_PERIOD_PERIOD: &'static TokenType = &TokenType::new(
        79,
        "?..",
        "QUESTION_PERIOD_PERIOD",
        CASCADE_PRECEDENCE,
        QUESTION_PERIOD_PERIOD_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const BAD_INPUT: &'static TokenType = &TokenType::new(
        80,
        "malformed input",
        "BAD_INPUT",
        NO_PRECEDENCE,
        BAD_INPUT_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const RECOVERY: &'static TokenType = &TokenType::new(
        81,
        "recovery",
        "RECOVERY",
        NO_PRECEDENCE,
        RECOVERY_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: true,
        },
    );
    pub const UNUSED: &'static TokenType = &TokenType::new(
        255,
        "",
        "UNUSED",
        NO_PRECEDENCE,
        EOF_TOKEN,
        TokenTypeFlags {
            binary_operator_of_compound_assignment: None,
            is_binary_operator: false,
            is_modifier: false,
            is_operator: false,
            is_top_level_keyword: false,
            is_user_definable_operator: false,
            string_value_should_be_null: false,
        },
    );
    pub const AS: &'static TokenType = &Keyword::AS.base;
    pub const IS: &'static TokenType = &Keyword::IS.base;

    pub const all: [&'static TokenType; 73] = [
        TokenType::EOF,
        TokenType::DOUBLE,
        TokenType::DOUBLE_WITH_SEPARATORS,
        TokenType::HEXADECIMAL,
        TokenType::HEXADECIMAL_WITH_SEPARATORS,
        TokenType::IDENTIFIER,
        TokenType::INT,
        TokenType::INT_WITH_SEPARATORS,
        TokenType::MULTI_LINE_COMMENT,
        TokenType::SCRIPT_TAG,
        TokenType::SINGLE_LINE_COMMENT,
        TokenType::STRING,
        TokenType::AMPERSAND,
        TokenType::AMPERSAND_AMPERSAND,
        TokenType::AMPERSAND_EQ,
        TokenType::AT,
        TokenType::BANG,
        TokenType::BANG_EQ,
        TokenType::BAR,
        TokenType::BAR_BAR,
        TokenType::BAR_EQ,
        TokenType::COLON,
        TokenType::COMMA,
        TokenType::CARET,
        TokenType::CARET_EQ,
        TokenType::CLOSE_CURLY_BRACKET,
        TokenType::CLOSE_PAREN,
        TokenType::CLOSE_SQUARE_BRACKET,
        TokenType::EQ,
        TokenType::EQ_EQ,
        TokenType::FUNCTION,
        TokenType::GT,
        TokenType::GT_EQ,
        TokenType::GT_GT,
        TokenType::GT_GT_EQ,
        TokenType::HASH,
        TokenType::INDEX,
        TokenType::INDEX_EQ,
        TokenType::LT,
        TokenType::LT_EQ,
        TokenType::LT_LT,
        TokenType::LT_LT_EQ,
        TokenType::MINUS,
        TokenType::MINUS_EQ,
        TokenType::MINUS_MINUS,
        TokenType::OPEN_CURLY_BRACKET,
        TokenType::OPEN_PAREN,
        TokenType::OPEN_SQUARE_BRACKET,
        TokenType::PERCENT,
        TokenType::PERCENT_EQ,
        TokenType::PERIOD,
        TokenType::PERIOD_PERIOD,
        TokenType::PLUS,
        TokenType::PLUS_EQ,
        TokenType::PLUS_PLUS,
        TokenType::QUESTION,
        TokenType::QUESTION_PERIOD,
        TokenType::QUESTION_QUESTION,
        TokenType::QUESTION_QUESTION_EQ,
        TokenType::SEMICOLON,
        TokenType::SLASH,
        TokenType::SLASH_EQ,
        TokenType::STAR,
        TokenType::STAR_EQ,
        TokenType::STRING_INTERPOLATION_EXPRESSION,
        TokenType::STRING_INTERPOLATION_IDENTIFIER,
        TokenType::TILDE,
        TokenType::TILDE_SLASH,
        TokenType::TILDE_SLASH_EQ,
        TokenType::BACKPING,
        TokenType::BACKSLASH,
        TokenType::PERIOD_PERIOD_PERIOD,
        TokenType::PERIOD_PERIOD_PERIOD_QUESTION,
    ];

    pub const fn new(
        index: i32,
        lexeme: &'static str,
        name: &'static str,
        precedence: i32,
        kind: i32,
        flags: TokenTypeFlags,
    ) -> TokenType {
        TokenType {
            index,
            binary_operator_of_compound_assignment: flags.binary_operator_of_compound_assignment,
            kind,
            is_modifier: flags.is_modifier,
            is_operator: flags.is_operator,
            is_binary_operator: flags.is_binary_operator,
            is_top_level_keyword: flags.is_top_level_keyword,
            is_user_definable_operator: flags.is_user_definable_operator,
            lexeme,
            name,
            precedence,
            string_value: if flags.string_value_should_be_null {
                None
            } else {
                Some(lexeme)
            },
        }
    }

    pub fn is_additive_operator(&self) -> bool {
        self.precedence == ADDITIVE_PRECEDENCE
    }

    pub fn is_assignment_operator(&self) -> bool {
        self.precedence == ASSIGNMENT_PRECEDENCE
    }

    pub fn is_associative_operator(&self) -> bool {
        self == TokenType::AMPERSAND
            || self == TokenType::AMPERSAND_AMPERSAND
            || self == TokenType::BAR
            || self == TokenType::BAR_BAR
            || self == TokenType::CARET
            || self == TokenType::PLUS
            || self == TokenType::STAR
    }

    pub fn is_built_in(&self) -> bool {
        Keyword::of_type(self).is_some_and(|k| k.is_built_in())
    }

    pub fn is_reserved_word(&self) -> bool {
        Keyword::of_type(self).is_some_and(|k| k.is_reserved_word())
    }

    pub fn is_equality_operator(&self) -> bool {
        self == TokenType::BANG_EQ || self == TokenType::EQ_EQ
    }

    pub fn is_increment_operator(&self) -> bool {
        self == TokenType::PLUS_PLUS || self == TokenType::MINUS_MINUS
    }

    pub fn is_keyword(&self) -> bool {
        self.kind == KEYWORD_TOKEN
    }

    pub fn is_pseudo(&self) -> bool {
        Keyword::of_type(self).is_some_and(|k| k.is_pseudo())
    }

    pub fn is_multiplicative_operator(&self) -> bool {
        self.precedence == MULTIPLICATIVE_PRECEDENCE
    }

    pub fn is_relational_operator(&self) -> bool {
        self == TokenType::LT
            || self == TokenType::LT_EQ
            || self == TokenType::GT
            || self == TokenType::GT_EQ
    }

    pub fn is_shift_operator(&self) -> bool {
        self.precedence == SHIFT_PRECEDENCE
    }

    pub fn is_unary_postfix_operator(&self) -> bool {
        self.precedence == POSTFIX_PRECEDENCE
    }

    pub fn is_unary_prefix_operator(&self) -> bool {
        self.precedence == PREFIX_PRECEDENCE
            || self == TokenType::MINUS
            || self == TokenType::PLUS_PLUS
            || self == TokenType::MINUS_MINUS
    }

    pub fn is_selector_operator(&self) -> bool {
        self.precedence == SELECTOR_PRECEDENCE
    }

    /// `TokenTypeIsAExtension.isA`.
    #[inline(always)]
    pub fn is_a(&self, value: &TokenType) -> bool {
        self.index == value.index
    }
}

impl std::fmt::Display for TokenType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.name)
    }
}

pub static tokenTypesByIndex: [&TokenType; 256] = [
    &TokenType::EOF,
    &TokenType::DOUBLE,
    &TokenType::DOUBLE_WITH_SEPARATORS,
    &TokenType::HEXADECIMAL,
    &TokenType::HEXADECIMAL_WITH_SEPARATORS,
    &TokenType::IDENTIFIER,
    &TokenType::INT,
    &TokenType::INT_WITH_SEPARATORS,
    &TokenType::MULTI_LINE_COMMENT,
    &TokenType::SCRIPT_TAG,
    &TokenType::SINGLE_LINE_COMMENT,
    &TokenType::STRING,
    &TokenType::AMPERSAND,
    &TokenType::AMPERSAND_AMPERSAND,
    &TokenType::AMPERSAND_AMPERSAND_EQ,
    &TokenType::AMPERSAND_EQ,
    &TokenType::AT,
    &TokenType::BANG,
    &TokenType::BANG_EQ,
    &TokenType::BANG_EQ_EQ,
    &TokenType::BAR,
    &TokenType::BAR_BAR,
    &TokenType::BAR_BAR_EQ,
    &TokenType::BAR_EQ,
    &TokenType::COLON,
    &TokenType::COMMA,
    &TokenType::CARET,
    &TokenType::CARET_EQ,
    &TokenType::CLOSE_CURLY_BRACKET,
    &TokenType::CLOSE_PAREN,
    &TokenType::CLOSE_SQUARE_BRACKET,
    &TokenType::EQ,
    &TokenType::EQ_EQ,
    &TokenType::EQ_EQ_EQ,
    &TokenType::FUNCTION,
    &TokenType::GT,
    &TokenType::GT_EQ,
    &TokenType::GT_GT,
    &TokenType::GT_GT_EQ,
    &TokenType::GT_GT_GT,
    &TokenType::GT_GT_GT_EQ,
    &TokenType::HASH,
    &TokenType::INDEX,
    &TokenType::INDEX_EQ,
    &TokenType::LT,
    &TokenType::LT_EQ,
    &TokenType::LT_LT,
    &TokenType::LT_LT_EQ,
    &TokenType::MINUS,
    &TokenType::MINUS_EQ,
    &TokenType::MINUS_MINUS,
    &TokenType::OPEN_CURLY_BRACKET,
    &TokenType::OPEN_PAREN,
    &TokenType::OPEN_SQUARE_BRACKET,
    &TokenType::PERCENT,
    &TokenType::PERCENT_EQ,
    &TokenType::PERIOD,
    &TokenType::PERIOD_PERIOD,
    &TokenType::PLUS,
    &TokenType::PLUS_EQ,
    &TokenType::PLUS_PLUS,
    &TokenType::QUESTION,
    &TokenType::QUESTION_PERIOD,
    &TokenType::QUESTION_QUESTION,
    &TokenType::QUESTION_QUESTION_EQ,
    &TokenType::SEMICOLON,
    &TokenType::SLASH,
    &TokenType::SLASH_EQ,
    &TokenType::STAR,
    &TokenType::STAR_EQ,
    &TokenType::STRING_INTERPOLATION_EXPRESSION,
    &TokenType::STRING_INTERPOLATION_IDENTIFIER,
    &TokenType::TILDE,
    &TokenType::TILDE_SLASH,
    &TokenType::TILDE_SLASH_EQ,
    &TokenType::BACKPING,
    &TokenType::BACKSLASH,
    &TokenType::PERIOD_PERIOD_PERIOD,
    &TokenType::PERIOD_PERIOD_PERIOD_QUESTION,
    &TokenType::QUESTION_PERIOD_PERIOD,
    &TokenType::BAD_INPUT,
    &TokenType::RECOVERY,
    &Keyword::ABSTRACT.base,
    &Keyword::AS.base,
    &Keyword::ASSERT.base,
    &Keyword::ASYNC.base,
    &Keyword::AUGMENT.base,
    &Keyword::AWAIT.base,
    &Keyword::BASE.base,
    &Keyword::BREAK.base,
    &Keyword::CASE.base,
    &Keyword::CATCH.base,
    &Keyword::CLASS.base,
    &Keyword::CONST.base,
    &Keyword::CONTINUE.base,
    &Keyword::COVARIANT.base,
    &Keyword::DEFAULT.base,
    &Keyword::DEFERRED.base,
    &Keyword::DO.base,
    &Keyword::DYNAMIC.base,
    &Keyword::ELSE.base,
    &Keyword::ENUM.base,
    &Keyword::EXPORT.base,
    &Keyword::EXTENDS.base,
    &Keyword::EXTENSION.base,
    &Keyword::EXTERNAL.base,
    &Keyword::FACTORY.base,
    &Keyword::FALSE.base,
    &Keyword::FINAL.base,
    &Keyword::FINALLY.base,
    &Keyword::FOR.base,
    &Keyword::FUNCTION.base,
    &Keyword::GET.base,
    &Keyword::HIDE.base,
    &Keyword::IF.base,
    &Keyword::IMPLEMENTS.base,
    &Keyword::IMPORT.base,
    &Keyword::IN.base,
    &Keyword::INOUT.base,
    &Keyword::INTERFACE.base,
    &Keyword::IS.base,
    &Keyword::LATE.base,
    &Keyword::LIBRARY.base,
    &Keyword::MIXIN.base,
    &Keyword::NATIVE.base,
    &Keyword::NEW.base,
    &Keyword::NULL.base,
    &Keyword::OF.base,
    &Keyword::ON.base,
    &Keyword::OPERATOR.base,
    &Keyword::OUT.base,
    &Keyword::PART.base,
    &Keyword::PATCH.base,
    &Keyword::REQUIRED.base,
    &Keyword::RETHROW.base,
    &Keyword::RETURN.base,
    &Keyword::SEALED.base,
    &Keyword::SET.base,
    &Keyword::SHOW.base,
    &Keyword::SOURCE.base,
    &Keyword::STATIC.base,
    &Keyword::SUPER.base,
    &Keyword::SWITCH.base,
    &Keyword::SYNC.base,
    &Keyword::THIS.base,
    &Keyword::THROW.base,
    &Keyword::TRUE.base,
    &Keyword::TRY.base,
    &Keyword::TYPEDEF.base,
    &Keyword::VAR.base,
    &Keyword::VOID.base,
    &Keyword::WHEN.base,
    &Keyword::WHILE.base,
    &Keyword::WITH.base,
    &Keyword::YIELD.base,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
    &TokenType::UNUSED,
];

// ---------------------------------------------------------------------------
// Tokens
//
// Upstream: `abstract class Token`, `SimpleToken`, `BeginToken`,
// `KeywordToken`, `StringToken`, `CommentToken`, `DocumentationCommentToken`,
// `LanguageVersionToken`, `SyntheticBeginToken`, `SyntheticKeywordToken`,
// `SyntheticStringToken`, `SyntheticToken`, `ReplacementToken`, plus the
// subclasses in token_impl.dart and error_token.dart.

/// A token: an index into a [TokenStore].
pub type TokenId = u32;

/// `null` for a token reference.
pub const NO_TOKEN: TokenId = u32::MAX;

/// The Dart runtime type of a token. Every getter whose behaviour a class
/// overrides dispatches on this.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum TokenRuntimeType {
    SimpleToken,
    BeginToken,
    KeywordToken,
    StringToken,
    CommentToken,
    DocumentationCommentToken,
    LanguageVersionToken,
    SyntheticBeginToken,
    SyntheticKeywordToken,
    SyntheticStringToken,
    SyntheticToken,
    ReplacementToken,
    // token_impl.dart
    StringTokenImpl,
    CommentTokenImpl,
    LanguageVersionTokenImpl,
    DartDocToken,
    // error_token.dart
    EncodingErrorToken,
    NonAsciiIdentifierToken,
    NonAsciiWhitespaceToken,
    AsciiControlCharacterToken,
    UnsupportedOperator,
    UnterminatedString,
    UnterminatedToken,
    UnmatchedToken,
}

impl TokenRuntimeType {
    pub fn name(self) -> &'static str {
        use TokenRuntimeType::*;
        match self {
            SimpleToken => "SimpleToken",
            BeginToken => "BeginToken",
            KeywordToken => "KeywordToken",
            StringToken => "StringToken",
            CommentToken => "CommentToken",
            DocumentationCommentToken => "DocumentationCommentToken",
            LanguageVersionToken => "LanguageVersionToken",
            SyntheticBeginToken => "SyntheticBeginToken",
            SyntheticKeywordToken => "SyntheticKeywordToken",
            SyntheticStringToken => "SyntheticStringToken",
            SyntheticToken => "SyntheticToken",
            ReplacementToken => "ReplacementToken",
            StringTokenImpl => "StringTokenImpl",
            CommentTokenImpl => "CommentTokenImpl",
            LanguageVersionTokenImpl => "LanguageVersionTokenImpl",
            DartDocToken => "DartDocToken",
            EncodingErrorToken => "EncodingErrorToken",
            NonAsciiIdentifierToken => "NonAsciiIdentifierToken",
            NonAsciiWhitespaceToken => "NonAsciiWhitespaceToken",
            AsciiControlCharacterToken => "AsciiControlCharacterToken",
            UnsupportedOperator => "UnsupportedOperator",
            UnterminatedString => "UnterminatedString",
            UnterminatedToken => "UnterminatedToken",
            UnmatchedToken => "UnmatchedToken",
        }
    }

    /// `token is ErrorToken`.
    pub fn is_error_token(self) -> bool {
        self as u8 >= TokenRuntimeType::EncodingErrorToken as u8
    }

    /// `token is CommentToken`.
    pub fn is_comment_token(self) -> bool {
        use TokenRuntimeType::*;
        matches!(
            self,
            CommentToken
                | DocumentationCommentToken
                | LanguageVersionToken
                | CommentTokenImpl
                | LanguageVersionTokenImpl
                | DartDocToken
        )
    }

    /// `token is BeginToken`.
    pub fn is_begin_token(self) -> bool {
        matches!(
            self,
            TokenRuntimeType::BeginToken | TokenRuntimeType::SyntheticBeginToken
        )
    }

    /// `token is LanguageVersionToken`.
    pub fn is_language_version_token(self) -> bool {
        matches!(
            self,
            TokenRuntimeType::LanguageVersionToken | TokenRuntimeType::LanguageVersionTokenImpl
        )
    }

    /// `token is StringToken` (which includes comments).
    pub fn has_own_lexeme(self) -> bool {
        use TokenRuntimeType::*;
        matches!(
            self,
            StringToken
                | CommentToken
                | DocumentationCommentToken
                | LanguageVersionToken
                | SyntheticStringToken
                | StringTokenImpl
                | CommentTokenImpl
                | LanguageVersionTokenImpl
                | DartDocToken
        )
    }
}

/// Where a token's own lexeme comes from. Upstream stores a `String`, or a
/// `_LazySubstring` of the source that becomes one on first use; here the
/// substring stays a range, which is that same laziness without the cache.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lexeme {
    /// The token's type's lexeme (`SimpleToken.lexeme => type.lexeme`).
    Fixed,
    /// UTF-16 code units `start..end` of the [SourceText::Utf16] source.
    Utf16 { start: u32, end: u32 },
    /// Bytes `start..end` of the [SourceText::Utf8] source, decoded as
    /// `decodeString(bytes, start, end, asciiOnly)` decodes them.
    Utf8 {
        start: u32,
        end: u32,
        ascii_only: bool,
    },
    /// A string the scanner built: an index into [TokenStore::strings].
    Owned(u32),
}

/// The text a scanner read, shared by the scanner and the tokens it made.
#[derive(Clone, Debug)]
pub enum SourceText {
    Utf8(Rc<[u8]>),
    Utf16(Rc<[u16]>),
}

impl Default for SourceText {
    fn default() -> Self {
        SourceText::Utf8(Rc::from(&[][..]))
    }
}

/// One token's fields. Which of the generic ones a token uses depends on its
/// runtime type:
///
/// * `end_token`: `BeginToken.endToken`.
/// * `extras` (in [TokenStore::extras], when `has_extras`): the fields
///   few tokens use, which keeps a token at 28 bytes:
///   * `preceding_comments`: `Token.precedingComments`.
///   * `parent`: `CommentToken.parent`.
///   * `before_synthetic`: the synthetic classes' `beforeSynthetic`.
///   * `a`: `SyntheticStringToken._length` (-1 for null);
///   `LanguageVersionToken` (an index into [TokenStore::versions]); `ErrorToken.character`;
///   `UnterminatedString.endOffset` and `UnterminatedToken.endOffset`;
///   `UnsupportedOperator.token` and `UnmatchedToken.begin` (a `TokenId`).
/// * `b`: `UnterminatedToken.assertionMessage`
///   (a `ScannerMessage` index); `UnterminatedString.start` (an index into
///   [TokenStore::strings]).
#[derive(Clone, Debug)]
pub struct TokenData {
    pub type_index: u8,
    pub runtime_type: TokenRuntimeType,
    /// Whether [TokenStore::extras] holds fields of this token.
    pub has_extras: bool,
    pub offset: i32,
    pub next: TokenId,
    pub previous: TokenId,
    pub end_token: TokenId,
    /// The [Lexeme], packed (see [TokenData::lexeme]).
    lexeme: [u32; 2],
}

impl TokenData {
    /// The lexeme: the first word holds a start or an index, the second
    /// the kind in its top two bits, then for UTF-8 whether it is ASCII
    /// only, then the length.
    #[inline(always)]
    pub fn lexeme(&self) -> Lexeme {
        let [first, second] = self.lexeme;
        match second >> 30 {
            0 => Lexeme::Fixed,
            1 => Lexeme::Utf16 {
                start: first,
                end: first + (second & 0x3fff_ffff),
            },
            2 => Lexeme::Utf8 {
                start: first,
                end: first + (second & 0x1fff_ffff),
                ascii_only: second & 0x2000_0000 != 0,
            },
            _ => Lexeme::Owned(first),
        }
    }

    /// Sets the lexeme.
    pub fn set_lexeme(&mut self, lexeme: Lexeme) {
        self.lexeme = TokenData::pack(lexeme);
    }

    #[inline(always)]
    fn pack(lexeme: Lexeme) -> [u32; 2] {
        match lexeme {
            Lexeme::Fixed => [0, 0],
            Lexeme::Utf16 { start, end } => {
                debug_assert!(end - start < 0x4000_0000);
                [start, 1 << 30 | (end - start)]
            }
            Lexeme::Utf8 {
                start,
                end,
                ascii_only,
            } => {
                debug_assert!(end - start < 0x2000_0000);
                [start, 2 << 30 | (ascii_only as u32) << 29 | (end - start)]
            }
            Lexeme::Owned(index) => [index, 3 << 30],
        }
    }
}

/// The fields of a token that few tokens use (see [TokenData]).
#[derive(Clone, Copy, Debug)]
pub struct TokenExtras {
    pub preceding_comments: TokenId,
    pub parent: TokenId,
    pub before_synthetic: TokenId,
    pub a: i32,
    pub b: i32,
}

impl Default for TokenExtras {
    fn default() -> Self {
        TokenExtras {
            preceding_comments: NO_TOKEN,
            parent: NO_TOKEN,
            before_synthetic: NO_TOKEN,
            a: 0,
            b: 0,
        }
    }
}

/// Hashes a [TokenId] as itself: the ids are distinct small integers.
#[derive(Default)]
pub struct TokenIdHasher(u64);

impl std::hash::Hasher for TokenIdHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = self.0.rotate_left(8) ^ b as u64;
        }
    }

    fn write_u32(&mut self, value: u32) {
        self.0 = (value as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15);
    }
}

/// The arena every token of one scan lives in.
#[derive(Default, Debug)]
pub struct TokenStore {
    pub tokens: Vec<TokenData>,
    pub strings: Vec<Box<[u16]>>,
    /// `LanguageVersionToken.major` and `.minor`, which are Dart `int`s.
    pub versions: Vec<(i64, i64)>,
    pub source: SourceText,
    /// The fields few tokens use, of the tokens that use them.
    pub extras: std::collections::HashMap<TokenId, TokenExtras, std::hash::BuildHasherDefault<TokenIdHasher>>,
}

impl TokenStore {
    pub fn new(source: SourceText, capacity_hint: usize) -> TokenStore {
        TokenStore {
            tokens: Vec::with_capacity(capacity_hint),
            strings: Vec::new(),
            versions: Vec::new(),
            source,
            extras: Default::default(),
        }
    }

    #[inline(always)]
    pub fn data(&self, token: TokenId) -> &TokenData {
        &self.tokens[token as usize]
    }

    #[inline(always)]
    pub fn data_mut(&mut self, token: TokenId) -> &mut TokenData {
        &mut self.tokens[token as usize]
    }

    /// The fields few tokens use (defaults where the token has none).
    #[inline(always)]
    pub fn extras(&self, token: TokenId) -> TokenExtras {
        if !self.tokens[token as usize].has_extras {
            return TokenExtras::default();
        }
        self.extras[&token]
    }

    /// The fields few tokens use, to set them.
    pub fn extras_mut(&mut self, token: TokenId) -> &mut TokenExtras {
        self.tokens[token as usize].has_extras = true;
        self.extras.entry(token).or_default()
    }

    /// Allocates a token. `SimpleToken`'s constructor also points every
    /// comment in `preceding_comments` at the new token (`_setCommentParent`).
    #[inline]
    pub fn push(
        &mut self,
        runtime_type: TokenRuntimeType,
        type_: &TokenType,
        offset: i32,
        preceding_comments: TokenId,
        lexeme: Lexeme,
    ) -> TokenId {
        debug_assert!(offset >= -1);
        let id = self.tokens.len() as TokenId;
        self.tokens.push(TokenData {
            type_index: type_.index as u8,
            runtime_type,
            has_extras: false,
            offset,
            next: NO_TOKEN,
            previous: NO_TOKEN,
            end_token: NO_TOKEN,
            lexeme: TokenData::pack(lexeme),
        });
        if preceding_comments != NO_TOKEN {
            self.extras_mut(id).preceding_comments = preceding_comments;
            self.set_comment_parent(preceding_comments, id);
        }
        id
    }

    #[inline]
    fn set_comment_parent(&mut self, mut comment: TokenId, parent: TokenId) {
        while comment != NO_TOKEN {
            self.extras_mut(comment).parent = parent;
            comment = self.tokens[comment as usize].next;
        }
    }

    pub fn add_string(&mut self, value: Vec<u16>) -> u32 {
        self.strings.push(value.into_boxed_slice());
        (self.strings.len() - 1) as u32
    }

    // -- Constructors -------------------------------------------------------

    /// `new Token(type, offset, precedingComment)`, i.e. `SimpleToken`.
    #[inline]
    pub fn simple_token(
        &mut self,
        type_: &TokenType,
        offset: i32,
        preceding_comment: TokenId,
    ) -> TokenId {
        self.push(
            TokenRuntimeType::SimpleToken,
            type_,
            offset,
            preceding_comment,
            Lexeme::Fixed,
        )
    }

    /// `new Token.eof(offset, precedingComments)`: its own previous and next.
    pub fn eof(&mut self, offset: i32, preceding_comments: TokenId) -> TokenId {
        let eof = self.simple_token(TokenType::EOF, offset, preceding_comments);
        let data = self.data_mut(eof);
        data.previous = eof;
        data.next = eof;
        eof
    }

    /// `new BeginToken(type, offset, precedingComment)`.
    #[inline]
    pub fn begin_token(
        &mut self,
        type_: &TokenType,
        offset: i32,
        preceding_comment: TokenId,
    ) -> TokenId {
        debug_assert!(
            type_ == TokenType::LT
                || type_ == TokenType::OPEN_CURLY_BRACKET
                || type_ == TokenType::OPEN_PAREN
                || type_ == TokenType::OPEN_SQUARE_BRACKET
                || type_ == TokenType::STRING_INTERPOLATION_EXPRESSION
        );
        self.push(
            TokenRuntimeType::BeginToken,
            type_,
            offset,
            preceding_comment,
            Lexeme::Fixed,
        )
    }

    /// `new KeywordToken(keyword, offset, precedingComment)`.
    #[inline]
    pub fn keyword_token(
        &mut self,
        keyword: &Keyword,
        offset: i32,
        preceding_comment: TokenId,
    ) -> TokenId {
        self.push(
            TokenRuntimeType::KeywordToken,
            &keyword.base,
            offset,
            preceding_comment,
            Lexeme::Fixed,
        )
    }

    /// `new SyntheticToken(type, offset)`.
    pub fn synthetic_token(&mut self, type_: &TokenType, offset: i32) -> TokenId {
        self.push(
            TokenRuntimeType::SyntheticToken,
            type_,
            offset,
            NO_TOKEN,
            Lexeme::Fixed,
        )
    }

    /// `new SyntheticStringToken(type, value, offset, length)`.
    pub fn synthetic_string_token(
        &mut self,
        type_: &TokenType,
        value: Lexeme,
        offset: i32,
        length: Option<i32>,
    ) -> TokenId {
        let id = self.push(
            TokenRuntimeType::SyntheticStringToken,
            type_,
            offset,
            NO_TOKEN,
            value,
        );
        self.extras_mut(id).a = length.unwrap_or(-1);
        id
    }

    // -- Getters ------------------------------------------------------------

    #[inline(always)]
    pub fn type_(&self, token: TokenId) -> &'static TokenType {
        tokenTypesByIndex[self.data(token).type_index as usize]
    }

    #[inline(always)]
    pub fn type_index(&self, token: TokenId) -> i32 {
        self.data(token).type_index as i32
    }

    #[inline(always)]
    pub fn runtime_type(&self, token: TokenId) -> TokenRuntimeType {
        self.data(token).runtime_type
    }

    /// `TokenIsAExtension.isA`.
    #[inline(always)]
    pub fn is_a(&self, token: TokenId, value: &TokenType) -> bool {
        value.index == self.type_index(token)
    }

    #[inline(always)]
    pub fn offset(&self, token: TokenId) -> i32 {
        self.data(token).offset
    }

    pub fn set_offset(&mut self, token: TokenId, value: i32) {
        debug_assert!(value >= -1);
        self.data_mut(token).offset = value;
    }

    #[inline(always)]
    pub fn char_offset(&self, token: TokenId) -> i32 {
        self.offset(token)
    }

    #[inline(always)]
    pub fn next(&self, token: TokenId) -> TokenId {
        self.data(token).next
    }

    #[inline(always)]
    pub fn previous(&self, token: TokenId) -> TokenId {
        self.data(token).previous
    }

    #[inline(always)]
    pub fn set_next_field(&mut self, token: TokenId, next: TokenId) {
        self.data_mut(token).next = next;
    }

    #[inline(always)]
    pub fn set_previous_field(&mut self, token: TokenId, previous: TokenId) {
        self.data_mut(token).previous = previous;
    }

    /// `Token.setNext`.
    pub fn set_next(&mut self, token: TokenId, next: TokenId) -> TokenId {
        self.set_next_field(token, next);
        self.set_previous_field(next, token);
        self.set_before_synthetic(next, token);
        next
    }

    /// `Token.setNextWithoutSettingPrevious`.
    pub fn set_next_without_setting_previous(&mut self, token: TokenId, next: TokenId) -> TokenId {
        self.set_next_field(token, next);
        next
    }

    #[inline(always)]
    pub fn preceding_comments(&self, token: TokenId) -> TokenId {
        self.extras(token).preceding_comments
    }

    pub fn set_preceding_comments(&mut self, token: TokenId, comment: TokenId) {
        self.extras_mut(token).preceding_comments = comment;
        self.set_comment_parent(comment, token);
    }

    /// `CommentToken.parent`.
    pub fn parent(&self, comment: TokenId) -> TokenId {
        self.extras(comment).parent
    }

    /// `Token.endGroup`: `BeginToken.endToken`, null for other tokens.
    #[inline(always)]
    pub fn end_group(&self, token: TokenId) -> TokenId {
        if self.runtime_type(token).is_begin_token() {
            self.data(token).end_token
        } else {
            NO_TOKEN
        }
    }

    /// `BeginToken.endGroup = ...` / `BeginToken.endToken = ...`.
    #[inline(always)]
    pub fn set_end_group(&mut self, begin: TokenId, end: TokenId) {
        debug_assert!(self.runtime_type(begin).is_begin_token());
        self.data_mut(begin).end_token = end;
    }

    /// `Token.beforeSynthetic`: null except on the synthetic classes.
    pub fn before_synthetic(&self, token: TokenId) -> TokenId {
        use TokenRuntimeType::*;
        match self.runtime_type(token) {
            SyntheticBeginToken
            | SyntheticKeywordToken
            | SyntheticStringToken
            | SyntheticToken
            | ReplacementToken => self.extras(token).before_synthetic,
            _ => NO_TOKEN,
        }
    }

    /// `Token.beforeSynthetic = ...`: ignored except on the synthetic classes.
    pub fn set_before_synthetic(&mut self, token: TokenId, previous: TokenId) {
        use TokenRuntimeType::*;
        if matches!(
            self.runtime_type(token),
            SyntheticBeginToken
                | SyntheticKeywordToken
                | SyntheticStringToken
                | SyntheticToken
                | ReplacementToken
        ) {
            self.extras_mut(token).before_synthetic = previous;
        }
    }

    #[inline(always)]
    pub fn kind(&self, token: TokenId) -> i32 {
        self.type_(token).kind
    }

    #[inline(always)]
    pub fn is_eof(&self, token: TokenId) -> bool {
        self.type_index(token) == TokenType::EOF.index
    }

    /// `Token.keyword`: the keyword of a `KeywordToken`.
    pub fn keyword(&self, token: TokenId) -> Option<&'static Keyword> {
        match self.runtime_type(token) {
            TokenRuntimeType::KeywordToken | TokenRuntimeType::SyntheticKeywordToken => {
                Keyword::of_type(self.type_(token))
            }
            _ => None,
        }
    }

    pub fn is_identifier(&self, token: TokenId) -> bool {
        match self.runtime_type(token) {
            TokenRuntimeType::KeywordToken | TokenRuntimeType::SyntheticKeywordToken => {
                let keyword = self.keyword(token).unwrap();
                keyword.is_pseudo() || keyword.is_built_in()
            }
            rt if rt.has_own_lexeme() => self.kind(token) == IDENTIFIER_TOKEN,
            _ => false,
        }
    }

    pub fn is_keyword(&self, token: TokenId) -> bool {
        matches!(
            self.runtime_type(token),
            TokenRuntimeType::KeywordToken | TokenRuntimeType::SyntheticKeywordToken
        )
    }

    pub fn is_keyword_or_identifier(&self, token: TokenId) -> bool {
        self.is_keyword(token) || self.is_identifier(token)
    }

    pub fn is_modifier(&self, token: TokenId) -> bool {
        self.type_(token).is_modifier
    }

    pub fn is_operator(&self, token: TokenId) -> bool {
        self.type_(token).is_operator
    }

    pub fn is_top_level_keyword(&self, token: TokenId) -> bool {
        self.type_(token).is_top_level_keyword
    }

    pub fn is_user_definable_operator(&self, token: TokenId) -> bool {
        self.type_(token).is_user_definable_operator
    }

    /// `Token.stringValue`.
    pub fn string_value(&self, token: TokenId) -> Option<&'static str> {
        self.type_(token).string_value
    }

    /// `Token.length`.
    pub fn length(&self, token: TokenId) -> i32 {
        use TokenRuntimeType::*;
        let data = self.data(token);
        match data.runtime_type {
            SyntheticBeginToken | SyntheticKeywordToken | SyntheticToken | ReplacementToken => 0,
            SyntheticStringToken if self.extras(token).a >= 0 => self.extras(token).a,
            UnterminatedString => self.char_count(token),
            EncodingErrorToken
            | NonAsciiIdentifierToken
            | NonAsciiWhitespaceToken
            | AsciiControlCharacterToken
            | UnsupportedOperator
            | UnterminatedToken
            | UnmatchedToken => 1,
            _ => self.lexeme_length(data.lexeme(), data.type_index),
        }
    }

    /// `Token.charCount`.
    pub fn char_count(&self, token: TokenId) -> i32 {
        let data = self.data(token);
        match data.runtime_type {
            TokenRuntimeType::UnterminatedString | TokenRuntimeType::UnterminatedToken => {
                self.extras(token).a - data.offset
            }
            _ => self.length(token),
        }
    }

    /// `Token.end`.
    pub fn end(&self, token: TokenId) -> i32 {
        self.offset(token) + self.length(token)
    }

    /// `Token.charEnd`.
    pub fn char_end(&self, token: TokenId) -> i32 {
        self.end(token)
    }

    /// `Token.isSynthetic`.
    pub fn is_synthetic(&self, token: TokenId) -> bool {
        use TokenRuntimeType::*;
        match self.runtime_type(token) {
            SyntheticBeginToken | SyntheticStringToken | SyntheticToken | ReplacementToken => true,
            _ => self.length(token) == 0,
        }
    }

    fn lexeme_length(&self, lexeme: Lexeme, type_index: u8) -> i32 {
        match lexeme {
            Lexeme::Fixed => tokenTypesByIndex[type_index as usize]
                .lexeme
                .encode_utf16()
                .count() as i32,
            Lexeme::Utf16 { start, end } => (end - start) as i32,
            Lexeme::Utf8 {
                start,
                end,
                ascii_only,
            } => {
                if ascii_only {
                    (end - start) as i32
                } else {
                    match &self.source {
                        SourceText::Utf8(bytes) => utf16_length_of_utf8_allow_malformed(
                            &bytes[start as usize..end as usize],
                        ) as i32,
                        SourceText::Utf16(_) => unreachable!("UTF-8 lexeme over a UTF-16 source"),
                    }
                }
            }
            Lexeme::Owned(index) => self.strings[index as usize].len() as i32,
        }
    }

    /// `token.lexeme.startsWith(prefix)` for an ASCII [prefix], without
    /// building the lexeme (not upstream). An ASCII byte of UTF-8 is always
    /// the character it encodes, so comparing bytes is comparing characters.
    pub fn lexeme_starts_with(&self, token: TokenId, prefix: &str) -> bool {
        self.lexeme_matches(token, prefix, false)
    }

    /// `token.lexeme == text` for an ASCII [text], without building the
    /// lexeme (not upstream).
    pub fn lexeme_equals(&self, token: TokenId, text: &str) -> bool {
        self.lexeme_matches(token, text, true)
    }

    /// Whether the lexeme starts with, or when [whole] is, the ASCII [text].
    fn lexeme_matches(&self, token: TokenId, text: &str, whole: bool) -> bool {
        debug_assert!(text.is_ascii());
        let prefix = text.as_bytes();
        let fits = |len: usize| if whole { len == prefix.len() } else { len >= prefix.len() };
        let data = self.data(token);
        assert!(
            !data.runtime_type.is_error_token(),
            "ErrorToken has no lexeme"
        );
        match data.lexeme() {
            Lexeme::Fixed => tokenTypesByIndex[data.type_index as usize]
                .lexeme
                .as_bytes()
                .starts_with(prefix),
            Lexeme::Utf16 { start, end } => match &self.source {
                SourceText::Utf16(units) => {
                    let units = &units[start as usize..end as usize];
                    units.len() >= prefix.len()
                        && prefix.iter().zip(units).all(|(&b, &u)| b as u16 == u)
                }
                SourceText::Utf8(_) => unreachable!("UTF-16 lexeme over a UTF-8 source"),
            },
            Lexeme::Utf8 { start, end, .. } => match &self.source {
                SourceText::Utf8(bytes) => bytes[start as usize..end as usize].starts_with(prefix),
                SourceText::Utf16(_) => unreachable!("UTF-8 lexeme over a UTF-16 source"),
            },
            Lexeme::Owned(index) => {
                let units = &self.strings[index as usize];
                units.len() >= prefix.len()
                    && prefix.iter().zip(units.iter()).all(|(&b, &u)| b as u16 == u)
            }
        }
    }

    /// `token.lexeme == text` for an ASCII [text], without building the
    /// lexeme (not upstream).
    pub fn lexeme_equals(&self, token: TokenId, text: &str) -> bool {
        self.length(token) as usize == text.len() && self.lexeme_starts_with(token, text)
    }

    /// `Token.lexeme`, as UTF-16 code units. An `ErrorToken`'s lexeme throws
    /// upstream; here it panics.
    pub fn lexeme(&self, token: TokenId) -> Vec<u16> {
        let data = self.data(token);
        assert!(
            !data.runtime_type.is_error_token(),
            "ErrorToken has no lexeme"
        );
        self.lexeme_text(data.lexeme(), data.type_index)
    }

    /// Appends `token.lexeme` to [out] (not upstream: `sink.write(token.lexeme)`
    /// without building the string first).
    pub fn write_lexeme(&self, token: TokenId, out: &mut Vec<u16>) {
        let data = self.data(token);
        assert!(
            !data.runtime_type.is_error_token(),
            "ErrorToken has no lexeme"
        );
        match data.lexeme() {
            Lexeme::Fixed => out.extend(
                tokenTypesByIndex[data.type_index as usize]
                    .lexeme
                    .encode_utf16(),
            ),
            Lexeme::Utf16 { start, end } => match &self.source {
                SourceText::Utf16(units) => out.extend_from_slice(&units[start as usize..end as usize]),
                SourceText::Utf8(_) => unreachable!("UTF-16 lexeme over a UTF-8 source"),
            },
            Lexeme::Owned(index) => out.extend_from_slice(&self.strings[index as usize]),
            lexeme => out.extend(self.lexeme_text(lexeme, data.type_index)),
        }
    }

    /// `Token.lexeme` as a Rust string (lone surrogates become U+FFFD).
    pub fn lexeme_string(&self, token: TokenId) -> String {
        String::from_utf16_lossy(&self.lexeme(token))
    }

    /// The text a [Lexeme] stands for.
    pub fn lexeme_text(&self, lexeme: Lexeme, type_index: u8) -> Vec<u16> {
        match lexeme {
            Lexeme::Fixed => tokenTypesByIndex[type_index as usize]
                .lexeme
                .encode_utf16()
                .collect(),
            Lexeme::Utf16 { start, end } => match &self.source {
                SourceText::Utf16(units) => units[start as usize..end as usize].to_vec(),
                SourceText::Utf8(_) => unreachable!("UTF-16 lexeme over a UTF-8 source"),
            },
            Lexeme::Utf8 {
                start,
                end,
                ascii_only,
            } => match &self.source {
                SourceText::Utf8(bytes) => {
                    decode_string(bytes, start as usize, end as usize, ascii_only)
                }
                SourceText::Utf16(_) => unreachable!("UTF-8 lexeme over a UTF-16 source"),
            },
            Lexeme::Owned(index) => self.strings[index as usize].to_vec(),
        }
    }

    /// `Token.lexicallyFirst`.
    pub fn lexically_first(&self, tokens: &[TokenId]) -> TokenId {
        let mut result = NO_TOKEN;
        for &t in tokens {
            if result == NO_TOKEN || (t != NO_TOKEN && self.offset(t) < self.offset(result)) {
                result = t;
            }
        }
        result
    }
}

// The synthetic token classes the parser's rewriter creates.
impl TokenStore {
    /// `new SyntheticBeginToken(type, offset, precedingComment)`.
    pub fn synthetic_begin_token(
        &mut self,
        type_: &TokenType,
        offset: i32,
        preceding_comment: TokenId,
    ) -> TokenId {
        self.push(
            TokenRuntimeType::SyntheticBeginToken,
            type_,
            offset,
            preceding_comment,
            Lexeme::Fixed,
        )
    }

    /// `new SyntheticKeywordToken(keyword, offset)`.
    pub fn synthetic_keyword_token(&mut self, keyword: &Keyword, offset: i32) -> TokenId {
        self.push(
            TokenRuntimeType::SyntheticKeywordToken,
            &keyword.base,
            offset,
            NO_TOKEN,
            Lexeme::Fixed,
        )
    }

    /// `new ReplacementToken(type, replacedToken)`: at the replaced token's
    /// offset and with its comments. `replacedToken` is kept in `a`.
    pub fn replacement_token(&mut self, type_: &TokenType, replaced_token: TokenId) -> TokenId {
        let offset = self.offset(replaced_token);
        let id = self.push(
            TokenRuntimeType::ReplacementToken,
            type_,
            offset,
            NO_TOKEN,
            Lexeme::Fixed,
        );
        self.extras_mut(id).a = replaced_token as i32;
        let comments = self.preceding_comments(replaced_token);
        self.set_preceding_comments(id, comments);
        id
    }

    /// `new StringToken(type, value, charOffset)`.
    pub fn string_token(
        &mut self,
        type_: &TokenType,
        value: Vec<u16>,
        char_offset: i32,
    ) -> TokenId {
        let index = self.add_string(value);
        self.push(
            TokenRuntimeType::StringToken,
            type_,
            char_offset,
            NO_TOKEN,
            Lexeme::Owned(index),
        )
    }

    /// `ReplacementToken.replacedToken`.
    pub fn replaced_token(&self, token: TokenId) -> TokenId {
        debug_assert!(self.runtime_type(token) == TokenRuntimeType::ReplacementToken);
        self.extras(token).a as TokenId
    }
}
