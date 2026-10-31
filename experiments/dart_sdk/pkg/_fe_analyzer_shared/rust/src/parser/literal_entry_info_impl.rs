// Port of lib/src/parser/literal_entry_info_impl.dart.
//
// `parse` and `computeNext` of each `LiteralEntryInfo` subclass, as arms of
// a match on the variant. `computeNext` consumes the step, as upstream's
// steps are not reused once the next one is computed.

use crate::parser::literal_entry_info::LiteralEntryInfo;
use crate::parser::literal_entry_info::LiteralEntryInfo::*;
use crate::parser::parser_impl::{ForPartsContext, Parser};
use crate::parser::util::kw;
use crate::scanner::token::{NO_TOKEN, TokenId, TokenStore, TokenType};

/// The first step when processing a `for` control flow collection entry.
pub const ifCondition: LiteralEntryInfo = IfCondition;

/// The first step when processing a spread entry.
pub const spreadOperator: LiteralEntryInfo = SpreadOperator;

/// The first step when processing a null-aware entry.
pub const nullAwareEntry: LiteralEntryInfo = NullAwareEntry;

fn nested(nested_step: LiteralEntryInfo, last_step: LiteralEntryInfo) -> LiteralEntryInfo {
    Nested {
        nested_step: Some(Box::new(nested_step)),
        last_step: Box::new(last_step),
    }
}

fn is_for(t: &TokenStore, next: TokenId) -> bool {
    t.is_a(next, kw::FOR) || (t.is_a(next, kw::AWAIT) && t.is_a(t.next(next), kw::FOR))
}

fn is_spread(t: &TokenStore, next: TokenId) -> bool {
    t.is_a(next, TokenType::PERIOD_PERIOD_PERIOD)
        || t.is_a(next, TokenType::PERIOD_PERIOD_PERIOD_QUESTION)
}

impl LiteralEntryInfo {
    /// Parse the control flow and spread collection aspects of this entry.
    pub fn parse(&mut self, mut token: TokenId, parser: &mut Parser) -> TokenId {
        match self {
            ForCondition { in_style } => {
                let mut next = parser.tokens.next(token);
                let mut await_token = NO_TOKEN;
                if parser.tokens.is_a(next, kw::AWAIT) {
                    await_token = next;
                    token = next;
                    next = parser.tokens.next(token);
                }
                let for_token = next;
                debug_assert!(parser.tokens.is_a(for_token, kw::FOR));
                parser
                    .listener
                    .begin_for_control_flow(&mut parser.tokens, await_token, for_token);

                let mut for_parts_context = ForPartsContext::new();
                token = parser.parse_for_loop_parts_start(
                    await_token,
                    for_token,
                    &mut for_parts_context,
                );
                let pattern_keyword = for_parts_context.pattern_keyword;
                if pattern_keyword != NO_TOKEN {
                    if parser.tokens.is_a(parser.tokens.next(token), TokenType::EQ) {
                        // Process `for ( pattern = expression ; ... ; ... )`
                        let equals = parser.tokens.next(token);
                        token = parser.parse_expression(equals);
                        parser
                            .listener
                            .handle_for_initializer_pattern_variable_assignment(
                                &mut parser.tokens,
                                pattern_keyword,
                                equals,
                            );
                        *in_style = false;
                        return parser.parse_for_loop_parts_rest(token, for_token, await_token);
                    } else {
                        // Process `for ( pattern in expression )`
                        debug_assert!(parser.tokens.is_a(parser.tokens.next(token), kw::IN));
                        *in_style = true;
                        return parser.parse_for_in_loop_parts_rest(
                            token,
                            await_token,
                            for_token,
                            pattern_keyword,
                            NO_TOKEN,
                        );
                    }
                }

                let identifier = parser.tokens.next(token);
                token = parser.parse_for_loop_parts_mid(token, await_token, for_token);
                let next = parser.tokens.next(token);
                if parser.tokens.is_a(next, kw::IN) || parser.tokens.is_a(next, TokenType::COLON) {
                    // Process `for ( ... in ... )`
                    *in_style = true;
                    token = parser.parse_for_in_loop_parts_rest(
                        token,
                        await_token,
                        for_token,
                        NO_TOKEN,
                        identifier,
                    );
                } else {
                    // Process `for ( ... ; ... ; ... )`
                    *in_style = false;
                    token = parser.parse_for_loop_parts_rest(token, for_token, await_token);
                }
                token
            }
            ForComplete => {
                parser
                    .listener
                    .end_for_control_flow(&mut parser.tokens, token);
                token
            }
            ForInComplete => {
                parser
                    .listener
                    .end_for_in_control_flow(&mut parser.tokens, token);
                token
            }
            IfCondition => {
                let if_token = parser.tokens.next(token);
                debug_assert!(parser.tokens.is_a(if_token, kw::IF));
                parser
                    .listener
                    .begin_if_control_flow(&mut parser.tokens, if_token);
                let allow_case = parser.is_patterns_feature_enabled;
                let result = parser.ensure_parenthesized_condition(if_token, allow_case);
                parser
                    .listener
                    .handle_then_control_flow(&mut parser.tokens, result);
                result
            }
            IfComplete => {
                if !parser.tokens.is_a(parser.tokens.next(token), kw::ELSE) {
                    parser
                        .listener
                        .end_if_control_flow(&mut parser.tokens, token);
                }
                token
            }
            IfElse => {
                let else_token = parser.tokens.next(token);
                debug_assert!(parser.tokens.is_a(else_token, kw::ELSE));
                parser
                    .listener
                    .handle_else_control_flow(&mut parser.tokens, else_token);
                else_token
            }
            IfElseComplete => {
                parser
                    .listener
                    .end_if_else_control_flow(&mut parser.tokens, token);
                token
            }
            SpreadOperator | ForSpread | ForInSpread | IfSpread | ElseSpread => {
                let operator = parser.tokens.next(token);
                debug_assert!(is_spread(&parser.tokens, operator));

                token = parser.parse_expression(operator);
                parser
                    .listener
                    .handle_spread_expression(&mut parser.tokens, operator);
                token
            }
            Nested { nested_step, .. } => nested_step.as_mut().unwrap().parse(token, parser),
            _ => {
                if self.has_entry() {
                    panic!("Internal Error: should not call parse");
                } else {
                    panic!("Internal Error: {self:?} should implement parse");
                }
            }
        }
    }

    /// Returns the next step when parsing an entry or `null` if none.
    pub fn compute_next(self, t: &TokenStore, token: TokenId) -> Option<LiteralEntryInfo> {
        match self {
            ForCondition { in_style } => {
                let next = t.next(token);
                let complete = if in_style { ForInComplete } else { ForComplete };
                Some(if is_for(t, next) {
                    nested(ForCondition { in_style: false }, complete)
                } else if t.is_a(next, kw::IF) {
                    nested(ifCondition, complete)
                } else if is_spread(t, next) {
                    if in_style { ForInSpread } else { ForSpread }
                } else if t.is_a(next, TokenType::QUESTION) {
                    nested(nullAwareEntry, complete)
                } else if in_style {
                    ForInEntry
                } else {
                    ForEntry
                })
            }
            ForSpread | ForEntry => Some(ForComplete),
            ForInSpread | ForInEntry => Some(ForInComplete),
            IfCondition => {
                let next = t.next(token);
                Some(if is_for(t, next) {
                    nested(ForCondition { in_style: false }, IfComplete)
                } else if t.is_a(next, kw::IF) {
                    nested(ifCondition, IfComplete)
                } else if is_spread(t, next) {
                    IfSpread
                } else if t.is_a(next, TokenType::QUESTION) {
                    nested(nullAwareEntry, IfComplete)
                } else {
                    IfEntry
                })
            }
            IfSpread | IfEntry => Some(IfComplete),
            IfComplete => {
                if t.is_a(t.next(token), kw::ELSE) {
                    Some(IfElse)
                } else {
                    None
                }
            }
            IfElse => {
                debug_assert!(t.is_a(token, kw::ELSE));
                let next = t.next(token);
                Some(if is_for(t, next) {
                    nested(ForCondition { in_style: false }, IfElseComplete)
                } else if t.is_a(next, kw::IF) {
                    nested(ifCondition, IfElseComplete)
                } else if is_spread(t, next) {
                    ElseSpread
                } else if t.is_a(next, TokenType::QUESTION) {
                    nested(nullAwareEntry, IfElseComplete)
                } else {
                    ElseEntry
                })
            }
            ElseSpread | ElseEntry => Some(IfElseComplete),
            Nested {
                nested_step,
                last_step,
            } => {
                let nested_step = nested_step.unwrap().compute_next(t, token);
                match nested_step {
                    Some(step) => Some(Nested {
                        nested_step: Some(Box::new(step)),
                        last_step,
                    }),
                    None => Some(*last_step),
                }
            }
            _ => None,
        }
    }
}
