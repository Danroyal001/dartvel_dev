// Port of lib/src/parser/token_stream_rewriter.dart.
//
// The rewriters keep no reference to the tokens: every operation takes the
// `TokenStore` they live in. `Rewriter` binds one to a store, so that the
// parser can write `parser.rewriter().insert_token(...)` as upstream writes
// `parser.rewriter.insertToken(...)`.

use crate::scanner::token::{Keyword, NO_TOKEN, TokenId, TokenRuntimeType, TokenStore, TokenType};

/// Provides the capability of inserting tokens into a token stream. This
/// implementation does this by rewriting the previous token to point to the
/// inserted token.
pub trait TokenStreamRewriter {
    // TODO(brianwilkerson): Consider adding the ability to replace tokens.

    /// Remove the tokens after [before] up to and not including [after].
    fn drop_range(&mut self, s: &mut TokenStore, before: TokenId, after: TokenId) {
        self.set_next(s, before, after);
    }

    /// Insert a synthetic open and close parenthesis and return the new synthetic
    /// open parenthesis. If [includeIdentifier] is true, then a synthetic
    /// identifier is included between the open and close parenthesis.
    fn insert_parens(
        &mut self,
        s: &mut TokenStore,
        token: TokenId,
        include_identifier: bool,
    ) -> TokenId {
        if !(!s.is_eof(token) || s.offset(token) < 0) {
            panic!("Internal Error: Rewriting at eof.");
        }
        let mut next = s.next(token);
        let offset = s.char_offset(next);
        let left_paren = s.synthetic_begin_token(TokenType::OPEN_PAREN, offset, NO_TOKEN);
        next = left_paren;
        if include_identifier {
            let identifier = synthetic_identifier(s, "", offset);
            next = self.set_next(s, next, identifier);
        }
        let close = s.synthetic_token(TokenType::CLOSE_PAREN, offset);
        next = self.set_next(s, next, close);
        self.set_end_group(s, left_paren, next);
        let token_next = s.next(token);
        self.set_next(s, next, token_next);
        self.set_next(s, token, left_paren);
        left_paren
    }

    /// Insert a synthetic `{` and `}` after [previousToken], returning both.
    fn insert_block(&mut self, s: &mut TokenStore, previous_token: TokenId) -> (TokenId, TokenId) {
        let following_token = s.next(previous_token);
        let offset = s.char_offset(following_token);
        let left_bracket = s.synthetic_begin_token(TokenType::OPEN_CURLY_BRACKET, offset, NO_TOKEN);
        let right_bracket = s.synthetic_token(TokenType::CLOSE_CURLY_BRACKET, offset);
        self.insert_token(s, previous_token, left_bracket);
        self.insert_token(s, left_bracket, right_bracket);
        self.set_end_group(s, left_bracket, right_bracket);
        (left_bracket, right_bracket)
    }

    /// Insert [newToken] after [token] and return [newToken].
    fn insert_token(&mut self, s: &mut TokenStore, token: TokenId, new_token: TokenId) -> TokenId {
        if !(!s.is_eof(token) || s.offset(token) < 0) {
            panic!("Internal Error: Rewriting at eof.");
        }
        let next = s.next(token);
        self.set_next(s, new_token, next);
        self.set_next(s, token, new_token);
        new_token
    }

    /// Move [endGroup] (a synthetic `)`, `]`, or `}` token) and associated
    /// error token after [token] in the token stream and return [endGroup].
    fn move_synthetic(
        &mut self,
        s: &mut TokenStore,
        token: TokenId,
        end_group: TokenId,
    ) -> TokenId {
        if !(!s.is_eof(token) || s.offset(token) < 0) {
            panic!("Internal Error: Rewriting at eof.");
        }
        debug_assert!(s.before_synthetic(end_group) != NO_TOKEN);
        if token == end_group {
            return end_group;
        }
        let mut error_token = NO_TOKEN;
        if s.runtime_type(s.next(end_group)) == TokenRuntimeType::UnmatchedToken {
            error_token = s.next(end_group);
        }

        // Remove endGroup from its current location
        let before = s.before_synthetic(end_group);
        let after = s.next(if error_token != NO_TOKEN {
            error_token
        } else {
            end_group
        });
        self.set_next(s, before, after);

        // Insert endGroup into its new location
        let next = s.next(token);
        self.set_next(s, token, end_group);
        self.set_next(
            s,
            if error_token != NO_TOKEN {
                error_token
            } else {
                end_group
            },
            next,
        );
        let offset = s.offset(next);
        self.set_offset(s, end_group, offset);
        if error_token != NO_TOKEN {
            self.set_offset(s, error_token, offset);
        }

        end_group
    }

    /// Replace the single token immediately following the [previousToken] with
    /// the chain of tokens starting at the [replacementToken]. Return the
    /// [replacementToken].
    fn replace_token_following(
        &mut self,
        s: &mut TokenStore,
        previous_token: TokenId,
        replacement_token: TokenId,
    ) -> TokenId {
        let replaced_token = s.next(previous_token);
        self.set_next(s, previous_token, replacement_token);
        let comments = s.preceding_comments(replaced_token);
        self.set_preceding_comments(s, replacement_token, comments);
        let last = self.last_token_in_chain(s, replacement_token);
        let next = s.next(replaced_token);
        self.set_next(s, last, next);

        replacement_token
    }

    /// Given the [firstToken] in a chain of tokens to be inserted, return the
    /// last token in the chain.
    ///
    /// As a side-effect, this method also ensures that the tokens in the chain
    /// have their `previous` pointers set correctly.
    fn last_token_in_chain(&mut self, s: &mut TokenStore, first_token: TokenId) -> TokenId {
        let mut previous = NO_TOKEN;
        let mut current = first_token;
        while s.next(current) != NO_TOKEN && s.type_(s.next(current)) != TokenType::EOF {
            if previous != NO_TOKEN {
                self.set_previous(s, current, previous);
            }
            previous = current;
            current = s.next(current);
        }
        if previous != NO_TOKEN {
            self.set_previous(s, current, previous);
        }
        current
    }

    /// Insert a new simple synthetic token of [newTokenType] after
    /// [previousToken] instead of the token actually coming after it and
    /// return the new token.
    /// The old token is not removed from the token stream, but the token
    /// after [previousToken] will be the new token.
    fn replace_next_token_with_synthetic_token(
        &mut self,
        s: &mut TokenStore,
        previous_token: TokenId,
        new_token_type: &TokenType,
    ) -> TokenId {
        debug_assert!(
            new_token_type.kind != crate::scanner::token_constants::KEYWORD_TOKEN,
            "use an unwritten variation of insertSyntheticKeyword instead"
        );

        // TODO(jensj): Possibly this should use replaceTokenFollowing instead.

        let replaced = s.next(previous_token);
        let replacement = s.replacement_token(new_token_type, replaced);
        self.insert_token(s, previous_token, replacement);
        let after = s.next(s.next(replacement));
        self.set_next(s, replacement, after);

        replacement
    }

    /// Insert a new simple synthetic token of [newTokenType] after
    /// [previousToken] instead of the [count] tokens actually coming after it
    /// and return the new token.
    fn replace_next_tokens_with_synthetic_token(
        &mut self,
        s: &mut TokenStore,
        previous_token: TokenId,
        mut count: i32,
        new_token_type: &TokenType,
    ) -> TokenId {
        debug_assert!(
            new_token_type.kind != crate::scanner::token_constants::KEYWORD_TOKEN,
            "use an unwritten variation of insertSyntheticKeyword instead"
        );

        let replaced = s.next(previous_token);
        let replacement = s.replacement_token(new_token_type, replaced);
        self.insert_token(s, previous_token, replacement);
        let mut end = s.next(replacement);
        while count > 0 {
            count -= 1;
            end = s.next(end);
        }
        self.set_next(s, replacement, end);

        replacement
    }

    /// Insert a synthetic identifier after [token] and return the new identifier.
    fn insert_synthetic_identifier(
        &mut self,
        s: &mut TokenStore,
        token: TokenId,
        value: &str,
    ) -> TokenId {
        let offset = s.char_offset(s.next(token));
        let identifier = synthetic_identifier(s, value, offset);
        self.insert_token(s, token, identifier)
    }

    /// Insert a new synthetic [keyword] after [token] and return the new token.
    fn insert_synthetic_keyword(
        &mut self,
        s: &mut TokenStore,
        token: TokenId,
        keyword: &Keyword,
    ) -> TokenId {
        let offset = s.char_offset(s.next(token));
        let new_token = s.synthetic_keyword_token(keyword, offset);
        self.insert_token(s, token, new_token)
    }

    /// Insert a new simple synthetic token of [newTokenType] after [token]
    /// and return the new token.
    fn insert_synthetic_token(
        &mut self,
        s: &mut TokenStore,
        token: TokenId,
        new_token_type: &TokenType,
    ) -> TokenId {
        debug_assert!(
            new_token_type.kind != crate::scanner::token_constants::KEYWORD_TOKEN,
            "use insertSyntheticKeyword instead"
        );
        let offset = s.char_offset(s.next(token));
        let new_token = s.synthetic_token(new_token_type, offset);
        self.insert_token(s, token, new_token)
    }

    /// Sets the next token of [setOn] to [nextToken] and returns [nextToken].
    fn set_next(&mut self, s: &mut TokenStore, set_on: TokenId, next_token: TokenId) -> TokenId;

    fn set_end_group(&mut self, s: &mut TokenStore, set_on: TokenId, end_group: TokenId);

    fn set_offset(&mut self, s: &mut TokenStore, set_on: TokenId, offset: i32);

    fn set_preceding_comments(&mut self, s: &mut TokenStore, set_on: TokenId, comment: TokenId);

    fn set_previous(&mut self, s: &mut TokenStore, set_on: TokenId, previous: TokenId);
}

/// `new SyntheticStringToken(TokenType.IDENTIFIER, value, offset, 0)`.
fn synthetic_identifier(s: &mut TokenStore, value: &str, offset: i32) -> TokenId {
    let index = s.add_string(value.encode_utf16().collect());
    let lexeme = crate::scanner::token::Lexeme::Owned(index);
    s.synthetic_string_token(TokenType::IDENTIFIER, lexeme, offset, Some(0))
}

/// Provides the capability of inserting tokens into a token stream by rewriting
/// the previous token to point to the inserted token.
#[derive(Default, Debug)]
pub struct TokenStreamRewriterImpl;

impl TokenStreamRewriter for TokenStreamRewriterImpl {
    fn set_next(&mut self, s: &mut TokenStore, set_on: TokenId, next_token: TokenId) -> TokenId {
        s.set_next(set_on, next_token)
    }

    fn set_end_group(&mut self, s: &mut TokenStore, set_on: TokenId, end_group: TokenId) {
        s.set_end_group(set_on, end_group);
    }

    fn set_offset(&mut self, s: &mut TokenStore, set_on: TokenId, offset: i32) {
        s.set_offset(set_on, offset);
    }

    fn set_preceding_comments(&mut self, s: &mut TokenStore, set_on: TokenId, comment: TokenId) {
        s.set_preceding_comments(set_on, comment);
    }

    fn set_previous(&mut self, s: &mut TokenStore, set_on: TokenId, previous: TokenId) {
        s.set_previous_field(set_on, previous);
    }
}

/// One change an [UndoableTokenStreamRewriter] made, with what it replaced
/// (upstream's `TokenStreamChange` subclasses).
#[derive(Debug)]
pub enum TokenStreamChange {
    Next {
        set_on: TokenId,
        set_on_next: TokenId,
        next_token: TokenId,
        next_token_previous: TokenId,
        next_token_before_synthetic: TokenId,
    },
    EndGroup {
        set_on: TokenId,
        end_group: TokenId,
    },
    Offset {
        set_on: TokenId,
        offset: i32,
    },
    PrecedingComments {
        set_on: TokenId,
        comment: TokenId,
    },
    Previous {
        set_on: TokenId,
        previous: TokenId,
    },
}

impl TokenStreamChange {
    pub fn undo(&self, s: &mut TokenStore) {
        match *self {
            TokenStreamChange::Next {
                set_on,
                set_on_next,
                next_token,
                next_token_previous,
                next_token_before_synthetic,
            } => {
                s.set_before_synthetic(next_token, next_token_before_synthetic);
                s.set_previous_field(next_token, next_token_previous);
                s.set_next_field(set_on, set_on_next);
            }
            TokenStreamChange::EndGroup { set_on, end_group } => s.set_end_group(set_on, end_group),
            TokenStreamChange::Offset { set_on, offset } => s.set_offset(set_on, offset),
            TokenStreamChange::PrecedingComments { set_on, comment } => {
                s.data_mut(set_on).preceding_comments = comment;
            }
            TokenStreamChange::Previous { set_on, previous } => {
                s.set_previous_field(set_on, previous)
            }
        }
    }
}

/// Provides the capability of adding tokens that lead into a token stream
/// without modifying the original token stream and not setting the any token's
/// `previous` field.
#[derive(Default, Debug)]
pub struct UndoableTokenStreamRewriter {
    changes: Vec<TokenStreamChange>,
}

impl UndoableTokenStreamRewriter {
    pub fn undo(&mut self, s: &mut TokenStore) {
        for change in self.changes.iter().rev() {
            change.undo(s);
        }
        self.changes.clear();
    }
}

impl TokenStreamRewriter for UndoableTokenStreamRewriter {
    fn set_end_group(&mut self, s: &mut TokenStore, set_on: TokenId, end_group: TokenId) {
        self.changes.push(TokenStreamChange::EndGroup {
            set_on,
            end_group: s.end_group(set_on),
        });
        s.set_end_group(set_on, end_group);
    }

    fn set_next(&mut self, s: &mut TokenStore, set_on: TokenId, next_token: TokenId) -> TokenId {
        self.changes.push(TokenStreamChange::Next {
            set_on,
            set_on_next: s.next(set_on),
            next_token,
            next_token_previous: s.previous(next_token),
            next_token_before_synthetic: s.before_synthetic(next_token),
        });
        s.set_next_field(set_on, next_token);
        s.set_previous_field(next_token, set_on);
        s.set_before_synthetic(next_token, set_on);
        next_token
    }

    fn set_offset(&mut self, s: &mut TokenStore, set_on: TokenId, offset: i32) {
        self.changes.push(TokenStreamChange::Offset {
            set_on,
            offset: s.offset(set_on),
        });
        s.set_offset(set_on, offset);
    }

    fn set_preceding_comments(&mut self, s: &mut TokenStore, set_on: TokenId, comment: TokenId) {
        self.changes.push(TokenStreamChange::PrecedingComments {
            set_on,
            comment: s.preceding_comments(set_on),
        });
        s.set_preceding_comments(set_on, comment);
    }

    fn set_previous(&mut self, s: &mut TokenStore, set_on: TokenId, previous: TokenId) {
        self.changes.push(TokenStreamChange::Previous {
            set_on,
            previous: s.previous(set_on),
        });
        s.set_previous_field(set_on, previous);
    }
}

/// A rewriter bound to the store it rewrites, with upstream's method names.
pub struct Rewriter<'a, R: TokenStreamRewriter> {
    pub rewriter: &'a mut R,
    pub tokens: &'a mut TokenStore,
}

impl<R: TokenStreamRewriter> Rewriter<'_, R> {
    pub fn drop_range(&mut self, before: TokenId, after: TokenId) {
        self.rewriter.drop_range(self.tokens, before, after)
    }

    pub fn insert_parens(&mut self, token: TokenId, include_identifier: bool) -> TokenId {
        self.rewriter
            .insert_parens(self.tokens, token, include_identifier)
    }

    pub fn insert_block(&mut self, previous_token: TokenId) -> (TokenId, TokenId) {
        self.rewriter.insert_block(self.tokens, previous_token)
    }

    pub fn insert_token(&mut self, token: TokenId, new_token: TokenId) -> TokenId {
        self.rewriter.insert_token(self.tokens, token, new_token)
    }

    pub fn move_synthetic(&mut self, token: TokenId, end_group: TokenId) -> TokenId {
        self.rewriter.move_synthetic(self.tokens, token, end_group)
    }

    pub fn replace_token_following(
        &mut self,
        previous_token: TokenId,
        replacement_token: TokenId,
    ) -> TokenId {
        self.rewriter
            .replace_token_following(self.tokens, previous_token, replacement_token)
    }

    pub fn replace_next_token_with_synthetic_token(
        &mut self,
        previous_token: TokenId,
        new_token_type: &TokenType,
    ) -> TokenId {
        self.rewriter.replace_next_token_with_synthetic_token(
            self.tokens,
            previous_token,
            new_token_type,
        )
    }

    pub fn replace_next_tokens_with_synthetic_token(
        &mut self,
        previous_token: TokenId,
        count: i32,
        new_token_type: &TokenType,
    ) -> TokenId {
        self.rewriter.replace_next_tokens_with_synthetic_token(
            self.tokens,
            previous_token,
            count,
            new_token_type,
        )
    }

    pub fn insert_synthetic_identifier(&mut self, token: TokenId) -> TokenId {
        self.rewriter
            .insert_synthetic_identifier(self.tokens, token, "")
    }

    pub fn insert_synthetic_identifier_with_value(
        &mut self,
        token: TokenId,
        value: &str,
    ) -> TokenId {
        self.rewriter
            .insert_synthetic_identifier(self.tokens, token, value)
    }

    pub fn insert_synthetic_keyword(&mut self, token: TokenId, keyword: &Keyword) -> TokenId {
        self.rewriter
            .insert_synthetic_keyword(self.tokens, token, keyword)
    }

    pub fn insert_synthetic_token(
        &mut self,
        token: TokenId,
        new_token_type: &TokenType,
    ) -> TokenId {
        self.rewriter
            .insert_synthetic_token(self.tokens, token, new_token_type)
    }
}
