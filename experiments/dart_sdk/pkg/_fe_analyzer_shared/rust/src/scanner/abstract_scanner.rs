// Port of lib/src/scanner/abstract_scanner.dart.
//
// `abstract class AbstractScanner` becomes `AbstractScanner<S>`, where `S`
// is the subclass part (`StringScanner`, `Utf8BytesScanner`) and implements
// `ScannerSubclass`, the abstract members. Tokens live in the scanner's
// `TokenStore` and the grouping stack's cells in a `LinkStore`; a recovery
// option scanner borrows both from the scanner that created it, because
// upstream's option scanners mutate the `BeginToken`s on the shared grouping
// stack.
#![allow(non_upper_case_globals)]

use super::characters::*;
use super::error_token::{ScannerMessage, build_unexpected_character_token};
use super::internal_utils::is_identifier_char;
use super::keyword_state::KeywordStateHelper;
use super::token::{
    Keyword, NO_TOKEN, SourceText, TokenId, TokenRuntimeType, TokenStore, TokenType,
};
use super::token_constants::*;
use crate::util::link::{Link, LinkStore};

/// `typedef LanguageVersionChanged = void Function(Scanner scanner,
/// LanguageVersionToken languageVersion)`.
///
/// Upstream's callback receives the scanner so that it can set the scanner's
/// `configuration` for the language version it found. Here the callback
/// returns that configuration instead, and the scanner applies it.
pub type LanguageVersionChanged =
    Box<dyn FnMut(&TokenStore, TokenId) -> Option<ScannerConfiguration>>;

/// The abstract members of upstream's `AbstractScanner`, which
/// `StringScanner` and `Utf8BytesScanner` implement.
pub trait ScannerSubclass: Sized {
    /// Advances and returns the next character: a UTF-16 code unit in the
    /// `StringScanner`, a UTF-8 byte in the `Utf8BytesScanner`.
    fn advance(&mut self) -> i32;
    fn current(&self) -> i32;
    fn peek(&self) -> i32;
    fn current_as_unicode(&mut self, next: i32) -> i32;
    fn handle_unicode(&mut self, start_scan_offset: i32);
    fn scan_offset(&self) -> i32;
    fn string_offset(&self) -> i32;
    fn pass_identifier_char_allow_dollar(&mut self) -> i32;
    fn scan_until_line_end(&mut self) -> bool;
    fn skip_spaces(&mut self) -> i32;
    fn at_end_of_file(&self) -> bool;
    fn source(&self) -> SourceText;
    fn number_of_bytes_hint(&self) -> usize;

    #[allow(clippy::too_many_arguments)]
    fn create_substring_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
        allow_lazy: bool,
        token_start: i32,
        comments: TokenId,
    ) -> TokenId;

    fn create_synthetic_substring_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        synthetic_chars: &str,
        token_start: i32,
    ) -> TokenId;

    fn create_comment_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
        token_start: i32,
    ) -> TokenId;

    fn create_dart_doc_token(
        &self,
        store: &mut TokenStore,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
        token_start: i32,
    ) -> TokenId;

    fn create_language_version_token(
        &self,
        store: &mut TokenStore,
        start: i32,
        major: i64,
        minor: i64,
        token_start: i32,
    ) -> TokenId;

    /// The subclass part of `createRecoveryOptionScanner`.
    fn create_recovery_option_scanner(&self) -> Self;
}

pub struct AbstractScanner<S: ScannerSubclass> {
    pub sub: S,

    pub include_comments: bool,
    pub language_version_changed: Option<LanguageVersionChanged>,

    enable_triple_shift: bool,
    enable_augmentations: bool,

    /// The string offset for the next token that will be created.
    pub token_start: i32,

    /// The sentinel token before the first token of the stream.
    pub tokens: TokenId,

    /// The last scanned token.
    pub tail: TokenId,

    /// The last prepended error token.
    pub error_tail: TokenId,

    pub has_errors: bool,

    pub open_brace_with_missing_end_for_possible_recovery: TokenId,

    pub offset_for_curly_bracket_recovery_start: Option<i32>,

    /// Comment tokens not yet attached to a token, or `NO_TOKEN`.
    pub comments: TokenId,

    /// The last scanned comment token, or `NO_TOKEN`.
    pub comments_tail: TokenId,

    pub line_starts: LineStarts,

    /// The stack of open groups, e.g `{ ... ( ..`.
    pub grouping_stack: Link,

    pub in_recovery_option: bool,

    pub recovery_count: i32,

    pub allow_lazy_strings: bool,

    pub store: TokenStore,
    pub links: LinkStore<TokenId>,
}

/// `AbstractScanner.LAZY_ASSIGNMENT_ENABLED`.
pub const LAZY_ASSIGNMENT_ENABLED: bool = false;

/// `ExperimentalFlag.tripleShift.isEnabledByDefault`.
const TRIPLE_SHIFT_ENABLED_BY_DEFAULT: bool = true;

/// `ExperimentalFlag.augmentations.isEnabledByDefault`.
const AUGMENTATIONS_ENABLED_BY_DEFAULT: bool = false;

impl<S: ScannerSubclass> AbstractScanner<S> {
    /// `AbstractScanner(config, includeComments, languageVersionChanged,
    /// numberOfBytesHint: ..., allowLazyStrings: ...)`.
    pub fn new(
        sub: S,
        config: Option<ScannerConfiguration>,
        include_comments: bool,
        language_version_changed: Option<LanguageVersionChanged>,
        allow_lazy_strings: bool,
    ) -> AbstractScanner<S> {
        let number_of_bytes_hint = sub.number_of_bytes_hint();
        // A token every 4 bytes is about what Dart sources have.
        let mut store = TokenStore::new(sub.source(), number_of_bytes_hint / 4 + 16);
        let eof = store.eof(-1, NO_TOKEN);
        let mut scanner = AbstractScanner {
            sub,
            include_comments,
            language_version_changed,
            enable_triple_shift: TRIPLE_SHIFT_ENABLED_BY_DEFAULT,
            enable_augmentations: AUGMENTATIONS_ENABLED_BY_DEFAULT,
            token_start: -1,
            tokens: eof,
            tail: eof,
            error_tail: eof,
            has_errors: false,
            open_brace_with_missing_end_for_possible_recovery: NO_TOKEN,
            offset_for_curly_bracket_recovery_start: None,
            comments: NO_TOKEN,
            comments_tail: NO_TOKEN,
            line_starts: LineStarts::new(number_of_bytes_hint),
            grouping_stack: Link::EMPTY,
            in_recovery_option: false,
            recovery_count: 0,
            allow_lazy_strings,
            store,
            links: LinkStore::new(),
        };
        scanner.set_configuration(config);
        scanner
    }

    /// `createRecoveryOptionScanner()` / `AbstractScanner.recoveryOptionScanner`.
    ///
    /// The option scanner takes this scanner's token and link stores for as
    /// long as it runs; [Self::finish_recovery_option] gives them back.
    fn create_recovery_option_scanner(&mut self) -> AbstractScanner<S> {
        let sub = self.sub.create_recovery_option_scanner();
        let mut store = std::mem::take(&mut self.store);
        let links = std::mem::take(&mut self.links);
        let eof = store.eof(-1, NO_TOKEN);
        AbstractScanner {
            sub,
            include_comments: false,
            language_version_changed: None,
            enable_triple_shift: self.enable_triple_shift,
            // Not copied upstream either: the field initializer applies.
            enable_augmentations: AUGMENTATIONS_ENABLED_BY_DEFAULT,
            token_start: self.token_start,
            tokens: eof,
            tail: eof,
            error_tail: eof,
            has_errors: false,
            open_brace_with_missing_end_for_possible_recovery: NO_TOKEN,
            offset_for_curly_bracket_recovery_start: None,
            comments: NO_TOKEN,
            comments_tail: NO_TOKEN,
            // numberOfBytesHint - fake number, but doesn't really matter.
            line_starts: LineStarts::new(1000),
            grouping_stack: self.grouping_stack,
            in_recovery_option: true,
            recovery_count: 0,
            allow_lazy_strings: true,
            store,
            links,
        }
    }

    fn finish_recovery_option(&mut self, option: AbstractScanner<S>) {
        self.store = option.store;
        self.links = option.links;
    }

    /// `set configuration(ScannerConfiguration? config)`.
    pub fn set_configuration(&mut self, config: Option<ScannerConfiguration>) {
        if let Some(config) = config {
            self.enable_triple_shift = config.enable_triple_shift;
            self.enable_augmentations = config.enable_augmentations;
        }
    }

    /// Returns the first token scanned by this scanner.
    pub fn first_token(&self) -> TokenId {
        self.store.next(self.tokens)
    }

    /// Notifies that a new token starts at current offset.
    #[inline(always)]
    pub fn begin_token(&mut self) {
        self.token_start = self.sub.string_offset();
    }

    #[inline(always)]
    fn advance(&mut self) -> i32 {
        self.sub.advance()
    }

    #[inline(always)]
    fn peek(&self) -> i32 {
        self.sub.peek()
    }

    #[inline(always)]
    fn scan_offset(&self) -> i32 {
        self.sub.scan_offset()
    }

    #[inline(always)]
    fn string_offset(&self) -> i32 {
        self.sub.string_offset()
    }

    /// Appends a substring from the scan offset `start` to the current
    /// scan offset plus `extra_offset`.
    #[inline(always)]
    pub fn append_substring_token(
        &mut self,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        extra_offset: i32,
    ) {
        let token = self.sub.create_substring_token(
            &mut self.store,
            type_,
            start,
            ascii_only,
            extra_offset,
            self.allow_lazy_strings,
            self.token_start,
            self.comments,
        );
        self.append_token(token);
    }

    /// Appends a substring from `start` to the current scan offset plus
    /// `synthetic_chars`, which the token's length does not count.
    pub fn append_synthetic_substring_token(
        &mut self,
        type_: &TokenType,
        start: i32,
        ascii_only: bool,
        synthetic_chars: &str,
    ) {
        let token = self.sub.create_synthetic_substring_token(
            &mut self.store,
            type_,
            start,
            ascii_only,
            synthetic_chars,
            self.token_start,
        );
        self.append_token(token);
    }

    /// Appends an *operator* token from `type_`.
    #[inline(always)]
    pub fn append_precedence_token(&mut self, type_: &TokenType) {
        let token = self
            .store
            .simple_token(type_, self.token_start, self.comments);
        self.append_token(token);
    }

    /// Appends `yes` if the next character is `choice`, else `no`.
    pub fn select(&mut self, choice: i32, yes: &TokenType, no: &TokenType) -> i32 {
        let next = self.advance();
        if next == choice {
            self.append_precedence_token(yes);
            self.advance()
        } else {
            self.append_precedence_token(no);
            next
        }
    }

    /// Appends a keyword token whose kind is determined by `keyword`.
    pub fn append_keyword_token(&mut self, keyword: &'static Keyword) {
        if keyword.base.index == Keyword::THIS.base.index {
            self.discard_open_lt();
        }
        let token = self
            .store
            .keyword_token(keyword, self.token_start, self.comments);
        self.append_token(token);
    }

    fn get_line_of(&self, token: TokenId) -> i32 {
        if self.line_starts.is_empty() {
            return -1;
        }
        let offset = self.store.offset(token);
        let mut low: i32 = 0;
        let mut high: i32 = self.line_starts.length() - 1;
        while low < high {
            let mid = high - ((high - low) >> 1); // Get middle, rounding up.
            let pivot = self.line_starts.get(mid);
            if pivot <= offset {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        low
    }

    fn spaces_at_start_of_logical_line_of(&self, mut token: TokenId) -> i32 {
        let store = &self.store;
        if self.line_starts.is_empty() {
            return -1;
        }
        if store.is_a(token, TokenType::OPEN_CURLY_BRACKET) {
            if store.previous(token) == NO_TOKEN {
                return -1;
            }
            let previous = store.previous(token);
            let mut found_wanted = false;
            if store.is_a(previous, TokenType::CLOSE_PAREN) {
                let close_paren = store.previous(token);
                let mut candidate = store.previous(close_paren);
                while candidate != NO_TOKEN {
                    if store.end_group(candidate) == close_paren {
                        break;
                    }
                    if store.is_eof(candidate) {
                        break;
                    }
                    if store.end_group(candidate) != NO_TOKEN
                        && store.offset(store.end_group(candidate)) > store.offset(close_paren)
                    {
                        break;
                    }
                    candidate = store.previous(candidate);
                }
                if candidate != NO_TOKEN
                    && store.end_group(candidate) == close_paren
                    && store.previous(candidate) != NO_TOKEN
                {
                    token = store.previous(candidate);
                    if store.is_a(token, &Keyword::IF.base)
                        || store.is_a(token, &Keyword::FOR.base)
                        || store.is_a(token, &Keyword::WHILE.base)
                        || store.is_a(token, &Keyword::SWITCH.base)
                        || store.is_a(token, &Keyword::CATCH.base)
                    {
                        found_wanted = true;
                    }
                }
            } else if store.is_a(previous, &Keyword::ELSE.base)
                || store.is_a(previous, &Keyword::TRY.base)
                || store.is_a(previous, &Keyword::FINALLY.base)
            {
                found_wanted = true;
            } else if store.is_a(previous, TokenType::EQ)
                && store.previous(previous) != NO_TOKEN
                && store.is_a(store.previous(previous), TokenType::IDENTIFIER)
            {
                found_wanted = true;
            } else if store.is_a(previous, &Keyword::CONST.base)
                && store.previous(previous) != NO_TOKEN
                && store.is_a(store.previous(previous), TokenType::EQ)
                && store.previous(store.previous(previous)) != NO_TOKEN
                && store.is_a(
                    store.previous(store.previous(previous)),
                    TokenType::IDENTIFIER,
                )
            {
                found_wanted = true;
            }
            if !found_wanted {
                return -1;
            }
        }

        let line_index = self.get_line_of(token);
        if line_index == 0 {
            // On first line.
            let first = store.next(self.tokens);
            return if first != NO_TOKEN {
                store.char_offset(first)
            } else {
                -1
            };
        }
        let line_start_of_token = self.line_starts.get(line_index);
        let mut candidate = store.previous(token);
        while candidate != NO_TOKEN && store.offset(candidate) >= line_start_of_token {
            candidate = store.previous(candidate);
        }
        if candidate != NO_TOKEN {
            return store.offset(store.next(candidate)) - line_start_of_token;
        }
        -1
    }

    pub fn get_offset_for_curly_bracket_recovery_start(&self) -> Option<i32> {
        if self.open_brace_with_missing_end_for_possible_recovery == NO_TOKEN {
            return None;
        }
        let store = &self.store;
        let mut next = store.next(self.open_brace_with_missing_end_for_possible_recovery);
        let mut last_mismatch = NO_TOKEN;
        while next != NO_TOKEN && !store.is_eof(next) {
            if store.is_a(next, TokenType::OPEN_CURLY_BRACKET)
                || store.is_a(next, TokenType::STRING_INTERPOLATION_EXPRESSION)
            {
                let end_group = store.end_group(next);
                assert!(
                    end_group != NO_TOKEN,
                    "Null check operator used on a null value"
                );
                if self.get_line_of(next) != self.get_line_of(end_group) {
                    let indent_of_next = self.spaces_at_start_of_logical_line_of(next);
                    if indent_of_next >= 0
                        && indent_of_next != self.spaces_at_start_of_logical_line_of(end_group)
                    {
                        last_mismatch = next;
                    }
                }
            }
            next = store.next(next);
        }

        if last_mismatch != NO_TOKEN {
            return Some(store.offset(last_mismatch));
        }
        None
    }

    pub fn append_eof_token(&mut self) {
        self.begin_token();
        self.discard_open_lt();
        if !self.links.is_empty(self.grouping_stack)
            && self.store.is_a(
                self.links.head(self.grouping_stack),
                TokenType::OPEN_CURLY_BRACKET,
            )
            && self.links.is_empty(self.links.tail(self.grouping_stack))
        {
            // We have a single unmatched `{`.
            self.open_brace_with_missing_end_for_possible_recovery =
                self.links.head(self.grouping_stack);
        }
        while !self.links.is_empty(self.grouping_stack) {
            let head = self.links.head(self.grouping_stack);
            self.unmatched_begin_group(head);
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
        let eof = self.store.eof(self.token_start, self.comments);
        self.append_token(eof);
    }

    /// Notifies on `$LF` characters in multi-line comments or strings.
    pub fn line_feed_in_multiline(&mut self) {
        let offset = self.string_offset() + 1;
        self.line_starts.add(offset);
    }

    /// Appends a token that begins a new group, represented by `type_`.
    #[inline(always)]
    pub fn append_begin_group(&mut self, type_: &TokenType) {
        let token = self
            .store
            .begin_token(type_, self.token_start, self.comments);
        self.append_token(token);

        // { [ ${ cannot appear inside a type parameters / arguments.
        if type_.kind != LT_TOKEN && type_.kind != OPEN_PAREN_TOKEN {
            self.discard_open_lt();
        }
        self.grouping_stack = self.links.prepend(self.grouping_stack, token);
    }

    /// Appends a token that ends a group: '}', ')' and ']'.
    pub fn append_end_group(&mut self, type_: &TokenType, open_kind: i32) -> i32 {
        debug_assert!(open_kind != LT_TOKEN); // openKind is < for > and >>
        let found_matching_brace = self.discard_begin_group_until(open_kind);
        self.append_end_group_internal(found_matching_brace, type_, open_kind)
    }

    pub fn append_end_group_internal(
        &mut self,
        found_matching_brace: bool,
        type_: &TokenType,
        open_kind: i32,
    ) -> i32 {
        if !found_matching_brace {
            // No begin group. Leave the grouping stack alone and just continue.
            self.append_precedence_token(type_);
            return self.advance();
        }
        self.append_precedence_token(type_);
        let close = self.tail;
        let begin = self.links.head(self.grouping_stack);
        if self.store.kind(begin) != open_kind {
            debug_assert!(
                self.store.kind(begin) == STRING_INTERPOLATION_TOKEN
                    && open_kind == OPEN_CURLY_BRACKET_TOKEN
            );
            // We're ending an interpolated expression.
            self.store.set_end_group(begin, close);
            self.grouping_stack = self.links.tail(self.grouping_stack);
            // Using "start-of-text" to signal that we're back in string
            // scanning mode.
            return C_STX;
        }
        self.store.set_end_group(begin, close);
        self.grouping_stack = self.links.tail(self.grouping_stack);
        self.advance()
    }

    /// Appends a token for '>'.
    pub fn append_gt(&mut self, type_: &TokenType) {
        self.append_precedence_token(type_);
        if self.links.is_empty(self.grouping_stack) {
            return;
        }
        let head = self.links.head(self.grouping_stack);
        if self.store.kind(head) == LT_TOKEN {
            self.store.set_end_group(head, self.tail);
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
    }

    /// Appends a token for '>>'.
    pub fn append_gt_gt(&mut self, type_: &TokenType) {
        self.append_precedence_token(type_);
        if self.links.is_empty(self.grouping_stack) {
            return;
        }
        if self.store.kind(self.links.head(self.grouping_stack)) == LT_TOKEN {
            // Don't assign endGroup: in "T<U<V>>", the '>>' token closes the
            // outer '<', the inner '<' is left without endGroup.
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
        if self.links.is_empty(self.grouping_stack) {
            return;
        }
        let head = self.links.head(self.grouping_stack);
        if self.store.kind(head) == LT_TOKEN {
            self.store.set_end_group(head, self.tail);
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
    }

    /// Appends a token for '>>>'.
    pub fn append_gt_gt_gt(&mut self, type_: &TokenType) {
        self.append_precedence_token(type_);
        if self.links.is_empty(self.grouping_stack) {
            return;
        }

        // Don't assign endGroup: in "T<U<V<X>>>", the '>>>' token closes the
        // outer '<', all the inner '<' are left without endGroups.
        if self.store.kind(self.links.head(self.grouping_stack)) == LT_TOKEN {
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
        if self.links.is_empty(self.grouping_stack) {
            return;
        }
        if self.store.kind(self.links.head(self.grouping_stack)) == LT_TOKEN {
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
        if self.links.is_empty(self.grouping_stack) {
            return;
        }
        let head = self.links.head(self.grouping_stack);
        if self.store.kind(head) == LT_TOKEN {
            self.store.set_end_group(head, self.tail);
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
    }

    pub fn prepend_error_token(&mut self, token: TokenId) {
        self.has_errors = true;
        if self.error_tail == self.tail {
            self.append_token(token);
            self.error_tail = self.tail;
        } else {
            let store = &mut self.store;
            let after = store.next(self.error_tail);
            store.set_next_field(token, after);
            store.set_previous_field(after, token);
            store.set_next_field(self.error_tail, token);
            store.set_previous_field(token, self.error_tail);
            self.error_tail = store.next(self.error_tail);
        }
    }

    /// If a begin group token matches `open_kind`, then discard begin group
    /// tokens up to that match and return `true`, otherwise return `false`.
    pub fn discard_begin_group_until(&mut self, open_kind: i32) -> bool {
        let original_stack = self.grouping_stack;

        let mut first = true;
        loop {
            // Don't report unmatched errors for <; it is also the less-than
            // operator.
            self.discard_open_lt();
            if self.links.is_empty(self.grouping_stack) {
                break; // recover
            }
            let begin = self.links.head(self.grouping_stack);
            let begin_kind = self.store.kind(begin);
            if open_kind == begin_kind
                || (open_kind == OPEN_CURLY_BRACKET_TOKEN
                    && begin_kind == STRING_INTERPOLATION_TOKEN)
            {
                if first {
                    // If the expected opener has been found on the first pass
                    // then no recovery necessary.
                    return true;
                }
                break; // recover
            }
            first = false;
            self.grouping_stack = self.links.tail(self.grouping_stack);
            if self.links.is_empty(self.grouping_stack) {
                break;
            }
        }
        self.recovery_count += 1;

        // If the stack does not have any opener of the given type, then
        // return without discarding anything. This recovers nicely from
        // situations like "{foo());}".
        if self.links.is_empty(self.grouping_stack) {
            self.grouping_stack = original_stack;
            return false;
        }

        // We found a matching group somewhere in the stack, but generally
        // don't know if we should recover by inserting synthetic closers or
        // basically ignore the current token. Try both and see which is
        // better.
        if !self.in_recovery_option {
            let type_: &TokenType = match open_kind {
                OPEN_SQUARE_BRACKET_TOKEN => TokenType::CLOSE_SQUARE_BRACKET,
                OPEN_CURLY_BRACKET_TOKEN => TokenType::CLOSE_CURLY_BRACKET,
                OPEN_PAREN_TOKEN => TokenType::CLOSE_PAREN,
                _ => panic!("Bad state: Unexpected openKind"),
            };

            // Everything the options allocate is unreachable once they are
            // done (they only touch tokens on `original_stack`, and those are
            // reset below), so the stores are cut back to these lengths.
            let token_count = self.store.tokens.len();
            let string_count = self.store.strings.len();
            let link_count = self.links.cell_count();

            // Option #1: Insert synthetic closers.
            let option1_recoveries;
            {
                let mut option1 = self.create_recovery_option_scanner();
                option1.insert_synthetic_closers(original_stack, self.grouping_stack);
                let next = option1.append_end_group_internal(true, type_, open_kind);
                let mut recoveries = option1.recovery_option_tokenizer(next);
                recoveries += option1.links.slow_length(option1.grouping_stack);
                option1_recoveries = recoveries;
                self.finish_recovery_option(option1);
            }

            // Option #2: ignore this token.
            let option2_recoveries;
            {
                let mut option2 = self.create_recovery_option_scanner();
                option2.grouping_stack = original_stack;
                let next = option2.append_end_group_internal(false, type_, open_kind);
                let mut recoveries = option2.recovery_option_tokenizer(next);
                // We add 1 to make this option pay for ignoring this token.
                recoveries += option2.links.slow_length(option2.grouping_stack) + 1;
                option2_recoveries = recoveries;
                self.finish_recovery_option(option2);
            }

            // The recovery-option-scanners might have set endTokens.
            // Remove them.
            let mut link = original_stack;
            while self.links.is_not_empty(link) {
                let head = self.links.head(link);
                self.store.set_end_group(head, NO_TOKEN);
                link = self.links.tail(link);
            }

            self.store.tokens.truncate(token_count);
            self.store.strings.truncate(string_count);
            self.links.truncate(link_count);

            if option2_recoveries < option1_recoveries {
                // Perform option #2 recovery.
                self.grouping_stack = original_stack;
                return false;
            }
            // option #1 is the default, so fall though.
        }

        // Insert synthetic closers and report errors for any unbalanced
        // openers. This recovers nicely from situations like "{[}".
        self.insert_synthetic_closers(original_stack, self.grouping_stack);
        true
    }

    pub fn insert_synthetic_closers(&mut self, mut original_stack: Link, entry_to_use: Link) {
        while original_stack != entry_to_use {
            // Don't report unmatched errors for <; it is also the less-than
            // operator.
            if self.store.kind(self.links.head(entry_to_use)) != LT_TOKEN {
                let head = self.links.head(original_stack);
                self.unmatched_begin_group(head);
            }
            original_stack = self.links.tail(original_stack);
        }
    }

    /// Discards '<' from the grouping stack.
    #[inline(always)]
    pub fn discard_open_lt(&mut self) {
        while !self.links.is_empty(self.grouping_stack)
            && self.store.kind(self.links.head(self.grouping_stack)) == LT_TOKEN
        {
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
    }

    /// Discards '${' from the grouping stack, for an unterminated
    /// interpolation expression.
    pub fn discard_interpolation(&mut self) {
        while !self.links.is_empty(self.grouping_stack) {
            let begin_token = self.links.head(self.grouping_stack);
            self.unmatched_begin_group(begin_token);
            self.grouping_stack = self.links.tail(self.grouping_stack);
            if self.store.kind(begin_token) == STRING_INTERPOLATION_TOKEN {
                break;
            }
        }
    }

    pub fn unmatched_begin_group(&mut self, begin: TokenId) {
        // We want to ensure that unmatched BeginTokens are reported as
        // errors. However, the diet parser assumes that groups are balanced
        // and skips to the end token, so a synthetic closer is inserted.
        let type_ = close_brace_info_for(&self.store, begin);
        let synthetic = self.store.synthetic_token(type_, self.token_start);
        self.store.set_before_synthetic(synthetic, self.tail);
        self.append_token(synthetic);
        self.store.set_end_group(begin, self.tail);
        let error = self.store.unmatched_token(begin);
        self.prepend_error_token(error);
        self.recovery_count += 1;
    }

    /// `Token tokenize()`.
    pub fn tokenize(&mut self) -> TokenId {
        while !self.sub.at_end_of_file() {
            let first = self.advance();

            // Scan the header looking for a language version comment.
            let mut next = self.scan_header_looking_for_language_version(first);

            // Scan the rest of the file.
            while next != C_EOF {
                next = self.big_switch(next);
            }
            debug_assert!(self.sub.at_end_of_file());
            self.append_eof_token();
        }

        // Always pretend that there's a line at the end of the file.
        let offset = self.string_offset() + 1;
        self.line_starts.add(offset);

        self.first_token()
    }

    fn scan_header_looking_for_language_version(&mut self, mut next: i32) -> i32 {
        if next != C_EOF {
            let mut old_tail = self.tail;
            next = self.big_header_switch(next);
            if next != C_EOF && self.store.kind(self.tail) == SCRIPT_TOKEN {
                old_tail = self.tail;
                next = self.big_header_switch(next);
            }
            while next != C_EOF && self.tail == old_tail {
                next = self.big_header_switch(next);
            }
        }
        next
    }

    /// Tokenize a (small) part of the data, up to the first non-directive.
    pub fn tokenize_directives(&mut self) -> TokenId {
        let first = self.advance();
        let mut next = self.scan_header_looking_for_language_version(first);

        let the_first_token = self.store.next(self.tokens);
        if the_first_token != NO_TOKEN {
            if self.store.kind(the_first_token) == SCRIPT_TOKEN {
                let after = self.store.next(the_first_token);
                if !self.is_token_possible_start_of_directive(after) {
                    let remove_last = !(after == NO_TOKEN || self.store.is_eof(after));
                    return self.tokenize_directives_end_helper(remove_last);
                }
            } else if !self.is_token_possible_start_of_directive(the_first_token) {
                return self.tokenize_directives_end_helper(true);
            }
        }

        while next != C_EOF {
            let old_tail = self.tail;
            next = self.big_switch(next);
            if old_tail != self.tail && self.store.is_a(old_tail, TokenType::SEMICOLON) {
                let after = self.store.next(old_tail);
                if !self.is_token_possible_start_of_directive(after) {
                    return self.tokenize_directives_end_helper(true);
                }
            }
        }

        self.tokenize_directives_end_helper(false)
    }

    fn is_token_possible_start_of_directive(&self, token: TokenId) -> bool {
        if token == NO_TOKEN {
            return false;
        }
        matches!(
            self.store.string_value(token),
            Some("@" | "part" | "library" | "import" | "export")
        )
    }

    fn tokenize_directives_end_helper(&mut self, remove_last: bool) -> TokenId {
        if remove_last {
            self.tail = self.store.previous(self.tail);
            self.store.set_next_field(self.tail, NO_TOKEN);
        }
        while !self.links.is_empty(self.grouping_stack) {
            self.grouping_stack = self.links.tail(self.grouping_stack);
        }
        self.append_eof_token();
        let offset = self.string_offset() + 1;
        self.line_starts.add(offset);
        self.first_token()
    }

    pub fn recovery_option_tokenizer(&mut self, mut next: i32) -> i32 {
        let mut iterations = 0;
        while !self.sub.at_end_of_file() {
            while next != C_EOF {
                // TODO(jensj): Look at number of lines, tokens, parenthesis
                // stack, semi-colons etc. to see if we can bail out sooner.
                next = self.big_switch(next);
                iterations += 1;
                if iterations > 100 {
                    return self.recovery_count;
                }
            }
            debug_assert!(self.sub.at_end_of_file());
        }
        self.recovery_count
    }

    pub fn big_header_switch(&mut self, next: i32) -> i32 {
        if next != C_SLASH {
            return self.big_switch(next);
        }
        self.begin_token();
        if C_SLASH != self.peek() {
            return self.tokenize_slash_or_comment(next);
        }
        self.tokenize_language_version_or_single_line_comment(next)
    }

    pub fn big_switch(&mut self, next: i32) -> i32 {
        self.begin_token();

        if next == C_SPACE || next == C_TAB || next == C_CR {
            return self.sub.skip_spaces();
        }

        if next == C_LF {
            let offset = self.string_offset() + 1;
            self.line_starts.add(offset); // +1, the line starts after the $LF.
            return self.sub.skip_spaces();
        }

        let next_lower = next | 0x20;

        if C_a <= next_lower && next_lower <= C_z {
            if C_r == next {
                return self.tokenize_raw_string_keyword_or_identifier(next);
            }
            return self.tokenize_keyword_or_identifier(next, /* allowDollar = */ true);
        }

        if next == C_CLOSE_PAREN {
            return self.append_end_group(TokenType::CLOSE_PAREN, OPEN_PAREN_TOKEN);
        }

        if next == C_OPEN_PAREN {
            self.append_begin_group(TokenType::OPEN_PAREN);
            return self.advance();
        }

        if next == C_SEMICOLON {
            self.append_precedence_token(TokenType::SEMICOLON);
            // Type parameters and arguments cannot contain semicolon.
            self.discard_open_lt();
            return self.advance();
        }

        if next == C_PERIOD {
            return self.tokenize_dots_or_number(next);
        }

        if next == C_COMMA {
            self.append_precedence_token(TokenType::COMMA);
            return self.advance();
        }

        if next == C_EQ {
            return self.tokenize_equals(next);
        }

        if next == C_CLOSE_CURLY_BRACKET {
            if let Some(recovery_start) = self.offset_for_curly_bracket_recovery_start
                && !self.links.is_empty(self.grouping_stack)
                && self.store.is_a(
                    self.links.head(self.grouping_stack),
                    TokenType::OPEN_CURLY_BRACKET,
                )
                && self.store.offset(self.links.head(self.grouping_stack)) == recovery_start
            {
                // This instance of the scanner was instructed to recover
                // this type of curly bracket.
                let head = self.links.head(self.grouping_stack);
                self.unmatched_begin_group(head);
                self.grouping_stack = self.links.tail(self.grouping_stack);
            }
            return self.append_end_group(TokenType::CLOSE_CURLY_BRACKET, OPEN_CURLY_BRACKET_TOKEN);
        }

        if next == C_SLASH {
            return self.tokenize_slash_or_comment(next);
        }

        if next == C_OPEN_CURLY_BRACKET {
            self.append_begin_group(TokenType::OPEN_CURLY_BRACKET);
            return self.advance();
        }

        if next == C_DQ || next == C_SQ {
            let offset = self.scan_offset();
            return self.tokenize_string(next, offset, /* raw = */ false);
        }

        if next == C_UNDERSCORE {
            return self.tokenize_keyword_or_identifier(next, /* allowDollar = */ true);
        }

        if next == C_COLON {
            self.append_precedence_token(TokenType::COLON);
            return self.advance();
        }

        if next == C_LT {
            return self.tokenize_less_than(next);
        }

        if next == C_GT {
            return self.tokenize_greater_than(next);
        }

        if next == C_BANG {
            return self.tokenize_exclamation(next);
        }

        if next == C_OPEN_SQUARE_BRACKET {
            return self.tokenize_open_square_bracket(next);
        }

        if next == C_CLOSE_SQUARE_BRACKET {
            return self
                .append_end_group(TokenType::CLOSE_SQUARE_BRACKET, OPEN_SQUARE_BRACKET_TOKEN);
        }

        if next == C_AT {
            return self.tokenize_at(next);
        }

        if (C_1..=C_9).contains(&next) {
            return self.tokenize_number(next);
        }

        if next == C_AMPERSAND {
            return self.tokenize_ampersand(next);
        }

        if next == C_0 {
            return self.tokenize_hex_or_number(next);
        }

        if next == C_QUESTION {
            return self.tokenize_question(next);
        }

        if next == C_BAR {
            return self.tokenize_bar(next);
        }

        if next == C_PLUS {
            return self.tokenize_plus(next);
        }

        if next == C_DOLLAR {
            return self.tokenize_keyword_or_identifier(next, /* allowDollar = */ true);
        }

        if next == C_MINUS {
            return self.tokenize_minus(next);
        }

        if next == C_STAR {
            return self.tokenize_multiply(next);
        }

        if next == C_CARET {
            return self.tokenize_caret(next);
        }

        if next == C_TILDE {
            return self.tokenize_tilde(next);
        }

        if next == C_PERCENT {
            return self.tokenize_percent(next);
        }

        if next == C_BACKPING {
            self.append_precedence_token(TokenType::BACKPING);
            return self.advance();
        }

        if next == C_BACKSLASH {
            self.append_precedence_token(TokenType::BACKSLASH);
            return self.advance();
        }

        if next == C_HASH {
            return self.tokenize_tag(next);
        }

        if next < 0x1f {
            return self.unexpected(next);
        }

        let next = self.sub.current_as_unicode(next);

        self.unexpected(next)
    }

    #[allow(unused_assignments)]
    pub fn tokenize_tag(&mut self, mut next: i32) -> i32 {
        // # or #!.*[\n\r]
        if self.scan_offset() == 0 && self.peek() == C_BANG {
            let start = self.scan_offset();
            let mut ascii_only = true;
            loop {
                next = self.advance();
                if next > 127 {
                    ascii_only = false;
                }
                if !(next != C_LF && next != C_CR && next != C_EOF) {
                    break;
                }
            }
            if !ascii_only {
                self.sub.handle_unicode(start);
            }
            self.append_substring_token(TokenType::SCRIPT_TAG, start, ascii_only, 0);
            return next;
        }
        self.append_precedence_token(TokenType::HASH);
        self.advance()
    }

    pub fn tokenize_tilde(&mut self, _next: i32) -> i32 {
        // ~ ~/ ~/=
        let next = self.advance();
        if next == C_SLASH {
            self.select(C_EQ, TokenType::TILDE_SLASH_EQ, TokenType::TILDE_SLASH)
        } else {
            self.append_precedence_token(TokenType::TILDE);
            next
        }
    }

    pub fn tokenize_open_square_bracket(&mut self, _next: i32) -> i32 {
        // [ [] []=
        let next = self.advance();
        if next == C_CLOSE_SQUARE_BRACKET {
            return self.select(C_EQ, TokenType::INDEX_EQ, TokenType::INDEX);
        }
        self.append_begin_group(TokenType::OPEN_SQUARE_BRACKET);
        next
    }

    pub fn tokenize_caret(&mut self, _next: i32) -> i32 {
        // ^ ^=
        self.select(C_EQ, TokenType::CARET_EQ, TokenType::CARET)
    }

    pub fn tokenize_question(&mut self, _next: i32) -> i32 {
        // ? ?. ?.. ?? ??=
        let mut next = self.advance();
        if next == C_QUESTION {
            self.select(
                C_EQ,
                TokenType::QUESTION_QUESTION_EQ,
                TokenType::QUESTION_QUESTION,
            )
        } else if next == C_PERIOD {
            next = self.advance();
            if C_PERIOD == next {
                self.append_precedence_token(TokenType::QUESTION_PERIOD_PERIOD);
                return self.advance();
            }
            self.append_precedence_token(TokenType::QUESTION_PERIOD);
            next
        } else {
            self.append_precedence_token(TokenType::QUESTION);
            next
        }
    }

    pub fn tokenize_bar(&mut self, _next: i32) -> i32 {
        // | || |= ||=
        let mut next = self.advance();
        if next == C_BAR {
            next = self.advance();
            if LAZY_ASSIGNMENT_ENABLED && next == C_EQ {
                self.append_precedence_token(TokenType::BAR_BAR_EQ);
                return self.advance();
            }
            self.append_precedence_token(TokenType::BAR_BAR);
            next
        } else if next == C_EQ {
            self.append_precedence_token(TokenType::BAR_EQ);
            self.advance()
        } else {
            self.append_precedence_token(TokenType::BAR);
            next
        }
    }

    pub fn tokenize_ampersand(&mut self, _next: i32) -> i32 {
        // && &= & &&=
        let mut next = self.advance();
        if next == C_AMPERSAND {
            next = self.advance();
            if LAZY_ASSIGNMENT_ENABLED && next == C_EQ {
                self.append_precedence_token(TokenType::AMPERSAND_AMPERSAND_EQ);
                return self.advance();
            }
            self.append_precedence_token(TokenType::AMPERSAND_AMPERSAND);
            next
        } else if next == C_EQ {
            self.append_precedence_token(TokenType::AMPERSAND_EQ);
            self.advance()
        } else {
            self.append_precedence_token(TokenType::AMPERSAND);
            next
        }
    }

    pub fn tokenize_percent(&mut self, _next: i32) -> i32 {
        // % %=
        self.select(C_EQ, TokenType::PERCENT_EQ, TokenType::PERCENT)
    }

    pub fn tokenize_multiply(&mut self, _next: i32) -> i32 {
        // * *=
        self.select(C_EQ, TokenType::STAR_EQ, TokenType::STAR)
    }

    pub fn tokenize_minus(&mut self, _next: i32) -> i32 {
        // - -- -=
        let next = self.advance();
        if next == C_MINUS {
            self.append_precedence_token(TokenType::MINUS_MINUS);
            self.advance()
        } else if next == C_EQ {
            self.append_precedence_token(TokenType::MINUS_EQ);
            self.advance()
        } else {
            self.append_precedence_token(TokenType::MINUS);
            next
        }
    }

    pub fn tokenize_plus(&mut self, _next: i32) -> i32 {
        // + ++ +=
        let next = self.advance();
        if C_PLUS == next {
            self.append_precedence_token(TokenType::PLUS_PLUS);
            self.advance()
        } else if C_EQ == next {
            self.append_precedence_token(TokenType::PLUS_EQ);
            self.advance()
        } else {
            self.append_precedence_token(TokenType::PLUS);
            next
        }
    }

    pub fn tokenize_exclamation(&mut self, _next: i32) -> i32 {
        // ! !=
        // !== is kept for user-friendly error reporting.
        let next = self.advance();
        if next == C_EQ {
            let next = self.advance();
            if next == C_EQ {
                self.append_precedence_token(TokenType::BANG_EQ_EQ);
                let error = self.store.unsupported_operator(self.tail, self.token_start);
                self.prepend_error_token(error);
                return self.advance();
            } else {
                self.append_precedence_token(TokenType::BANG_EQ);
                return next;
            }
        }
        self.append_precedence_token(TokenType::BANG);
        next
    }

    pub fn tokenize_equals(&mut self, _next: i32) -> i32 {
        // = == =>
        // === is kept for user-friendly error reporting.

        // Type parameters and arguments cannot contain any token that
        // starts with '='.
        self.discard_open_lt();

        let next = self.advance();
        if next == C_EQ {
            let next = self.advance();
            if next == C_EQ {
                self.append_precedence_token(TokenType::EQ_EQ_EQ);
                let error = self.store.unsupported_operator(self.tail, self.token_start);
                self.prepend_error_token(error);
                return self.advance();
            } else {
                self.append_precedence_token(TokenType::EQ_EQ);
                return next;
            }
        } else if next == C_GT {
            self.append_precedence_token(TokenType::FUNCTION);
            return self.advance();
        }
        self.append_precedence_token(TokenType::EQ);
        next
    }

    pub fn tokenize_greater_than(&mut self, _next: i32) -> i32 {
        // > >= >> >>= >>> >>>=
        let mut next = self.advance();
        if C_EQ == next {
            // Saw `>=` only.
            self.append_precedence_token(TokenType::GT_EQ);
            self.advance()
        } else if C_GT == next {
            // Saw `>>` so far.
            next = self.advance();
            if C_EQ == next {
                // Saw `>>=` only.
                self.append_precedence_token(TokenType::GT_GT_EQ);
                self.advance()
            } else if self.enable_triple_shift && C_GT == next {
                // Saw `>>>` so far.
                next = self.advance();
                if C_EQ == next {
                    // Saw `>>>=` only.
                    self.append_precedence_token(TokenType::GT_GT_GT_EQ);
                    self.advance()
                } else {
                    // Saw `>>>` only.
                    self.append_gt_gt_gt(TokenType::GT_GT_GT);
                    next
                }
            } else {
                // Saw `>>` only.
                self.append_gt_gt(TokenType::GT_GT);
                next
            }
        } else {
            // Saw `>` only.
            self.append_gt(TokenType::GT);
            next
        }
    }

    pub fn tokenize_less_than(&mut self, _next: i32) -> i32 {
        // < <= << <<=
        let next = self.advance();
        if C_EQ == next {
            self.append_precedence_token(TokenType::LT_EQ);
            self.advance()
        } else if C_LT == next {
            self.select(C_EQ, TokenType::LT_LT_EQ, TokenType::LT_LT)
        } else {
            self.append_begin_group(TokenType::LT);
            next
        }
    }

    fn unexpected_separator_in_number(&mut self, start: i32) {
        let error = self.store.unterminated_token(
            ScannerMessage::UnexpectedSeparatorInNumber,
            start,
            self.string_offset(),
        );
        self.prepend_error_token(error);
    }

    #[allow(unused_assignments)]
    pub fn tokenize_number(&mut self, mut next: i32) -> i32 {
        let start = self.scan_offset();
        let mut has_separators = false;
        let mut previous_was_separator = false;
        loop {
            next = self.advance();
            if C_0 <= next && next <= C_9 {
                previous_was_separator = false;
                continue;
            } else if next == C_UNDERSCORE {
                has_separators = true;
                previous_was_separator = true;
                continue;
            } else if next == C_e || next == C_E {
                if previous_was_separator {
                    // Not allowed.
                    self.unexpected_separator_in_number(start);
                }
                return self.tokenize_fraction_part(next, start, has_separators);
            } else {
                if next == C_PERIOD {
                    if previous_was_separator {
                        // Not allowed.
                        self.unexpected_separator_in_number(start);
                    }
                    let nextnext = self.peek();
                    if C_0 <= nextnext && nextnext <= C_9 {
                        // Use the peeked character.
                        self.advance();
                        return self.tokenize_fraction_part(nextnext, start, has_separators);
                    } else {
                        let token_type = if has_separators {
                            TokenType::INT_WITH_SEPARATORS
                        } else {
                            TokenType::INT
                        };
                        self.append_substring_token(
                            token_type, start, /* asciiOnly = */ true, 0,
                        );
                        return next;
                    }
                }
                if previous_was_separator {
                    // End of the number is a separator; not allowed.
                    self.unexpected_separator_in_number(start);
                }
                let token_type = if has_separators {
                    TokenType::INT_WITH_SEPARATORS
                } else {
                    TokenType::INT
                };
                self.append_substring_token(token_type, start, /* asciiOnly = */ true, 0);
                return next;
            }
        }
    }

    pub fn tokenize_hex_or_number(&mut self, next: i32) -> i32 {
        let x = self.peek();
        if x == C_x || x == C_X {
            return self.tokenize_hex(next);
        }
        self.tokenize_number(next)
    }

    pub fn tokenize_hex(&mut self, _next: i32) -> i32 {
        let start = self.scan_offset();
        self.advance(); // Advance past the $x or $X.
        let mut has_digits = false;
        let mut has_separators = false;
        let mut previous_was_separator = false;
        loop {
            let next = self.advance();
            if (C_0 <= next && next <= C_9)
                || (C_A <= next && next <= C_F)
                || (C_a <= next && next <= C_f)
            {
                has_digits = true;
                previous_was_separator = false;
            } else if next == C_UNDERSCORE {
                if !has_digits {
                    // Not allowed.
                    self.unexpected_separator_in_number(start);
                }
                has_separators = true;
                previous_was_separator = true;
            } else {
                if !has_digits {
                    let error = self.store.unterminated_token(
                        ScannerMessage::ExpectedHexDigit,
                        start,
                        self.string_offset(),
                    );
                    self.prepend_error_token(error);
                    // Recovery
                    self.append_synthetic_substring_token(
                        TokenType::HEXADECIMAL,
                        start,
                        /* asciiOnly = */ true,
                        "0",
                    );
                    return next;
                }
                if previous_was_separator {
                    // End of the number is a separator; not allowed.
                    self.unexpected_separator_in_number(start);
                }
                let token_type = if has_separators {
                    TokenType::HEXADECIMAL_WITH_SEPARATORS
                } else {
                    TokenType::HEXADECIMAL
                };
                self.append_substring_token(token_type, start, /* asciiOnly = */ true, 0);
                return next;
            }
        }
    }

    pub fn tokenize_dots_or_number(&mut self, _next: i32) -> i32 {
        let start = self.scan_offset();
        let mut next = self.advance();
        if C_0 <= next && next <= C_9 {
            self.tokenize_fraction_part(next, start, /* hasSeparators = */ false)
        } else if C_PERIOD == next {
            next = self.advance();
            if next == C_PERIOD {
                next = self.advance();
                if next == C_QUESTION {
                    self.append_precedence_token(TokenType::PERIOD_PERIOD_PERIOD_QUESTION);
                    self.advance()
                } else {
                    self.append_precedence_token(TokenType::PERIOD_PERIOD_PERIOD);
                    next
                }
            } else {
                self.append_precedence_token(TokenType::PERIOD_PERIOD);
                next
            }
        } else {
            self.append_precedence_token(TokenType::PERIOD);
            next
        }
    }

    pub fn tokenize_fraction_part(
        &mut self,
        mut next: i32,
        start: i32,
        mut has_separators: bool,
    ) -> i32 {
        debug_assert!((C_0 <= next && next <= C_9) || (C_e == next || C_E == next));
        let mut done = false;
        let mut previous_was_separator = false;
        'LOOP: while !done {
            if C_0 <= next && next <= C_9 {
                previous_was_separator = false;
            } else if C_UNDERSCORE == next {
                has_separators = true;
                previous_was_separator = true;
            } else if C_e == next || C_E == next {
                if previous_was_separator {
                    // Not allowed.
                    self.unexpected_separator_in_number(start);
                }
                previous_was_separator = false;
                next = self.advance();
                while next == C_UNDERSCORE {
                    self.unexpected_separator_in_number(start);
                    has_separators = true;
                    previous_was_separator = true;
                    next = self.advance();
                }
                if next == C_PLUS || next == C_MINUS {
                    previous_was_separator = false;
                    next = self.advance();
                }
                let mut has_exponent_digits = false;
                loop {
                    if C_0 <= next && next <= C_9 {
                        has_exponent_digits = true;
                        previous_was_separator = false;
                    } else if next == C_UNDERSCORE {
                        if !has_exponent_digits {
                            self.unexpected_separator_in_number(start);
                        }
                        has_separators = true;
                        previous_was_separator = true;
                    } else {
                        if !has_exponent_digits {
                            self.append_synthetic_substring_token(
                                if has_separators {
                                    TokenType::DOUBLE_WITH_SEPARATORS
                                } else {
                                    TokenType::DOUBLE
                                },
                                start,
                                /* asciiOnly = */ true,
                                "0",
                            );
                            let error = self.store.unterminated_token(
                                ScannerMessage::MissingExponent,
                                self.token_start,
                                self.string_offset(),
                            );
                            self.prepend_error_token(error);
                            return next;
                        }
                        break;
                    }
                    next = self.advance();
                }
                if previous_was_separator {
                    // End of the number is a separator; not allowed.
                    self.unexpected_separator_in_number(start);
                }

                done = true;
                continue 'LOOP;
            } else {
                if previous_was_separator {
                    // End of the number is a separator; not allowed.
                    self.unexpected_separator_in_number(start);
                }
                done = true;
                continue 'LOOP;
            }
            next = self.advance();
        }
        let token_type = if has_separators {
            TokenType::DOUBLE_WITH_SEPARATORS
        } else {
            TokenType::DOUBLE
        };
        self.append_substring_token(token_type, start, /* asciiOnly = */ true, 0);
        next
    }

    pub fn tokenize_slash_or_comment(&mut self, _next: i32) -> i32 {
        let start = self.scan_offset();
        let next = self.advance();
        if C_STAR == next {
            self.tokenize_multi_line_comment(next, start)
        } else if C_SLASH == next {
            self.tokenize_single_line_comment(next, start)
        } else if C_EQ == next {
            self.append_precedence_token(TokenType::SLASH_EQ);
            self.advance()
        } else {
            self.append_precedence_token(TokenType::SLASH);
            next
        }
    }

    pub fn tokenize_language_version_or_single_line_comment(&mut self, next: i32) -> i32 {
        debug_assert!(next == C_SLASH);
        let start = self.scan_offset();
        let mut next = self.advance();

        // Dart doc
        debug_assert!(next == C_SLASH);
        if C_SLASH == self.peek() {
            return self.tokenize_single_line_comment(next, start);
        }

        // "@dart"
        next = self.advance();
        while C_SPACE == next {
            next = self.advance();
        }
        if C_AT != next {
            return self.tokenize_single_line_comment_rest(next, start, /* dartdoc = */ false);
        }
        next = self.advance();
        if C_d != next {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }
        next = self.advance();
        if C_a != next {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }
        next = self.advance();
        if C_r != next {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }
        next = self.advance();
        if C_t != next {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }
        next = self.advance();

        // "="
        while C_SPACE == next {
            next = self.advance();
        }
        if C_EQ != next {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }
        next = self.advance();

        // major
        while C_SPACE == next {
            next = self.advance();
        }
        let mut major: i64 = 0;
        let major_start = self.scan_offset();
        while is_digit(next) {
            major = major.wrapping_mul(10).wrapping_add((next - C_0) as i64);
            next = self.advance();
        }
        if self.scan_offset() == major_start {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }

        // minor
        if C_PERIOD != next {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }
        next = self.advance();
        let mut minor: i64 = 0;
        let minor_start = self.scan_offset();
        while is_digit(next) {
            minor = minor.wrapping_mul(10).wrapping_add((next - C_0) as i64);
            next = self.advance();
        }
        if self.scan_offset() == minor_start {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }

        // trailing spaces
        while C_SPACE == next {
            next = self.advance();
        }
        if next != C_LF && next != C_CR && next != C_EOF {
            return self.tokenize_single_line_comment_rest(next, start, false);
        }

        let language_version = self.sub.create_language_version_token(
            &mut self.store,
            start,
            major,
            minor,
            self.token_start,
        );
        if let Some(callback) = self.language_version_changed.as_mut() {
            // TODO(danrubel): make this required and remove the
            // languageVersion field.
            let config = callback(&self.store, language_version);
            self.set_configuration(config);
        }
        if self.include_comments {
            self.append_to_comment_stream(language_version);
        }
        next
    }

    pub fn tokenize_single_line_comment(&mut self, _next: i32, start: i32) -> i32 {
        let next = self.advance();
        let dartdoc = C_SLASH == next;
        self.tokenize_single_line_comment_rest(next, start, dartdoc)
    }

    pub fn tokenize_single_line_comment_rest(
        &mut self,
        next: i32,
        start: i32,
        dartdoc: bool,
    ) -> i32 {
        let mut ascii_only = true;
        if next > 127 {
            ascii_only = false;
        }
        if C_LF == next || C_CR == next || C_EOF == next {
            self.tokenize_single_line_comment_append(ascii_only, start, dartdoc);
            return next;
        }
        ascii_only &= self.sub.scan_until_line_end();
        self.tokenize_single_line_comment_append(ascii_only, start, dartdoc);
        self.sub.current()
    }

    fn tokenize_single_line_comment_append(&mut self, ascii_only: bool, start: i32, dartdoc: bool) {
        if !ascii_only {
            self.sub.handle_unicode(start);
        }
        if dartdoc {
            self.append_dart_doc(start, TokenType::SINGLE_LINE_COMMENT, ascii_only);
        } else {
            self.append_comment(start, TokenType::SINGLE_LINE_COMMENT, ascii_only);
        }
    }

    pub fn tokenize_multi_line_comment(&mut self, _next: i32, start: i32) -> i32 {
        let mut ascii_only_comment = true; // Track if the entire comment is ASCII.
        let mut ascii_only_lines = true; // Track ASCII since the last handleUnicode.
        let mut unicode_start = start;
        let mut nesting = 1;
        let mut next = self.advance();
        let dartdoc = C_STAR == next;
        loop {
            if C_EOF == next {
                if !ascii_only_lines {
                    self.sub.handle_unicode(unicode_start);
                }
                let error = self.store.unterminated_token(
                    ScannerMessage::UnterminatedComment,
                    self.token_start,
                    self.string_offset(),
                );
                self.prepend_error_token(error);
                self.advance_after_error();
                break;
            } else if C_STAR == next {
                next = self.advance();
                if C_SLASH == next {
                    nesting -= 1;
                    if 0 == nesting {
                        if !ascii_only_lines {
                            self.sub.handle_unicode(unicode_start);
                        }
                        next = self.advance();
                        if dartdoc {
                            self.append_dart_doc(
                                start,
                                TokenType::MULTI_LINE_COMMENT,
                                ascii_only_comment,
                            );
                        } else {
                            self.append_comment(
                                start,
                                TokenType::MULTI_LINE_COMMENT,
                                ascii_only_comment,
                            );
                        }
                        break;
                    } else {
                        next = self.advance();
                    }
                }
            } else if C_SLASH == next {
                next = self.advance();
                if C_STAR == next {
                    next = self.advance();
                    nesting += 1;
                }
            } else if next == C_LF {
                if !ascii_only_lines {
                    // Synchronize the string offset in the utf8 scanner.
                    self.sub.handle_unicode(unicode_start);
                    ascii_only_lines = true;
                    unicode_start = self.scan_offset();
                }
                self.line_feed_in_multiline();
                next = self.advance();
            } else {
                if next > 127 {
                    ascii_only_lines = false;
                    ascii_only_comment = false;
                }
                next = self.advance();
            }
        }
        next
    }

    pub fn append_comment(&mut self, start: i32, type_: &TokenType, ascii_only: bool) {
        if !self.include_comments {
            return;
        }
        let new_comment = self.sub.create_comment_token(
            &mut self.store,
            type_,
            start,
            ascii_only,
            0,
            self.token_start,
        );
        self.append_to_comment_stream(new_comment);
    }

    pub fn append_dart_doc(&mut self, start: i32, type_: &TokenType, ascii_only: bool) {
        if !self.include_comments {
            return;
        }
        let new_comment = self.sub.create_dart_doc_token(
            &mut self.store,
            type_,
            start,
            ascii_only,
            0,
            self.token_start,
        );
        self.append_to_comment_stream(new_comment);
    }

    /// Append the given token to the [tail] of the current stream of tokens.
    #[inline(always)]
    pub fn append_token(&mut self, token: TokenId) {
        let store = &mut self.store;
        store.set_next_field(self.tail, token);
        store.set_previous_field(token, self.tail);
        self.tail = token;
        if self.comments != NO_TOKEN && self.comments == store.preceding_comments(token) {
            self.comments = NO_TOKEN;
            self.comments_tail = NO_TOKEN;
        } else {
            // It is the responsibility of the caller to construct the token
            // being appended with preceding comments if any.
            debug_assert!(
                self.comments == NO_TOKEN
                    || store.is_synthetic(token)
                    || store.runtime_type(token).is_error_token()
            );
        }
    }

    fn append_to_comment_stream(&mut self, new_comment: TokenId) {
        if self.comments == NO_TOKEN {
            self.comments = new_comment;
            self.comments_tail = self.comments;
        } else {
            let store = &mut self.store;
            store.set_next_field(self.comments_tail, new_comment);
            store.set_previous_field(new_comment, self.comments_tail);
            self.comments_tail = new_comment;
        }
    }

    pub fn tokenize_raw_string_keyword_or_identifier(&mut self, next: i32) -> i32 {
        // [next] is $r.
        let nextnext = self.peek();
        if nextnext == C_DQ || nextnext == C_SQ {
            let start = self.scan_offset();
            let next = self.advance();
            return self.tokenize_string(next, start, /* raw = */ true);
        }
        self.tokenize_keyword_or_identifier(next, /* allowDollar = */ true)
    }

    pub fn tokenize_keyword_or_identifier(&mut self, mut next: i32, allow_dollar: bool) -> i32 {
        let mut state = KeywordStateHelper::table();
        let start = self.scan_offset();
        // We allow a leading capital character.
        if C_A <= next && next <= C_z {
            state = state.next(next);
            next = self.advance();
        }
        while !state.is_null() && C_a <= next && next <= C_z {
            state = state.next(next);
            next = self.advance();
        }
        if state.is_null() {
            return self.tokenize_identifier(next, start, allow_dollar);
        }
        let Some(keyword) = state.keyword() else {
            return self.tokenize_identifier(next, start, allow_dollar);
        };
        if !self.enable_augmentations && keyword.base.index == Keyword::AUGMENT.base.index {
            return self.tokenize_identifier(next, start, allow_dollar);
        }
        if (C_A <= next && next <= C_Z)
            || (C_0 <= next && next <= C_9)
            || next == C_UNDERSCORE
            || (allow_dollar && next == C_DOLLAR)
        {
            self.tokenize_identifier(next, start, allow_dollar)
        } else {
            self.append_keyword_token(keyword);
            next
        }
    }

    /// `allow_dollar` can exclude '$', which is not allowed as part of a
    /// string interpolation identifier.
    pub fn tokenize_identifier(&mut self, mut next: i32, start: i32, allow_dollar: bool) -> i32 {
        if allow_dollar {
            // Normal case is to allow dollar.
            if is_identifier_char(next, /* allowDollar = */ true) {
                next = self.sub.pass_identifier_char_allow_dollar();
                self.append_substring_token(
                    TokenType::IDENTIFIER,
                    start,
                    /* asciiOnly = */ true,
                    0,
                );
            } else {
                // Identifier ends here.
                if start == self.scan_offset() {
                    return self.unexpected(next);
                } else {
                    self.append_substring_token(
                        TokenType::IDENTIFIER,
                        start,
                        /* asciiOnly = */ true,
                        0,
                    );
                }
            }
        } else {
            loop {
                if is_identifier_char(next, /* allowDollar = */ false) {
                    next = self.advance();
                } else {
                    // Identifier ends here.
                    if start == self.scan_offset() {
                        return self.unexpected(next);
                    } else {
                        self.append_substring_token(
                            TokenType::IDENTIFIER,
                            start,
                            /* asciiOnly = */ true,
                            0,
                        );
                    }
                    break;
                }
            }
        }
        next
    }

    pub fn tokenize_at(&mut self, _next: i32) -> i32 {
        self.append_precedence_token(TokenType::AT);
        self.advance()
    }

    pub fn tokenize_string(&mut self, next: i32, start: i32, raw: bool) -> i32 {
        let quote_char = next;
        let mut next = self.advance();
        if quote_char == next {
            next = self.advance();
            if quote_char == next {
                // Multiline string.
                return self.tokenize_multi_line_string(quote_char, start, raw);
            } else {
                // Empty string.
                self.append_substring_token(
                    TokenType::STRING,
                    start,
                    /* asciiOnly = */ true,
                    0,
                );
                return next;
            }
        }
        if raw {
            self.tokenize_single_line_raw_string(next, quote_char, start)
        } else {
            self.tokenize_single_line_string(next, quote_char, start)
        }
    }

    /// `next` is the first character after the quote, `quote_start` the
    /// scan offset of the quote.
    pub fn tokenize_single_line_string(
        &mut self,
        mut next: i32,
        quote_char: i32,
        quote_start: i32,
    ) -> i32 {
        let mut start = quote_start;
        let mut ascii_only = true;
        while next != quote_char {
            if next == C_BACKSLASH {
                next = self.advance();
            } else if next == C_DOLLAR {
                if !ascii_only {
                    self.sub.handle_unicode(start);
                }
                next = self.tokenize_string_interpolation(start, ascii_only);
                start = self.scan_offset();
                ascii_only = true;
                continue;
            }
            if next <= C_CR && (next == C_LF || next == C_CR || next == C_EOF) {
                if !ascii_only {
                    self.sub.handle_unicode(start);
                }
                self.unterminated_string(quote_char, quote_start, start, ascii_only, false, false);
                return next;
            }
            if next > 127 {
                ascii_only = false;
            }
            next = self.advance();
        }
        if !ascii_only {
            self.sub.handle_unicode(start);
        }
        // Advance past the quote character.
        next = self.advance();
        self.append_substring_token(TokenType::STRING, start, ascii_only, 0);
        next
    }

    pub fn tokenize_string_interpolation(&mut self, start: i32, ascii_only: bool) -> i32 {
        self.append_substring_token(TokenType::STRING, start, ascii_only, 0);
        self.begin_token(); // $ starts here.
        let next = self.advance();
        if next == C_OPEN_CURLY_BRACKET {
            self.tokenize_interpolated_expression(next)
        } else {
            self.tokenize_interpolated_identifier(next)
        }
    }

    pub fn tokenize_interpolated_expression(&mut self, _next: i32) -> i32 {
        self.append_begin_group(TokenType::STRING_INTERPOLATION_EXPRESSION);
        if let Some(recovery_start) = self.offset_for_curly_bracket_recovery_start
            && self.token_start == recovery_start
        {
            // This instance of the scanner was instructed to recover this
            // type of curly bracket.
            self.discard_interpolation();
            return self.advance();
        }
        self.begin_token(); // The expression starts here.
        let mut next = self.advance(); // Move past the curly bracket.
        while next != C_EOF && next != C_STX {
            next = self.big_switch(next);
        }
        if next == C_EOF {
            self.begin_token();
            self.discard_interpolation();
            return next;
        }
        next = self.advance(); // Move past the $STX.
        self.begin_token(); // The string interpolation suffix starts here.
        next
    }

    pub fn tokenize_interpolated_identifier(&mut self, mut next: i32) -> i32 {
        self.append_precedence_token(TokenType::STRING_INTERPOLATION_IDENTIFIER);

        if (C_a <= next && next <= C_z) || (C_A <= next && next <= C_Z) || next == C_UNDERSCORE {
            self.begin_token(); // The identifier starts here.
            next = self.tokenize_keyword_or_identifier(next, /* allowDollar = */ false);
        } else {
            self.begin_token(); // The synthetic identifier starts here.
            let offset = self.scan_offset();
            self.append_synthetic_substring_token(
                TokenType::IDENTIFIER,
                offset,
                /* asciiOnly = */ true,
                "",
            );
            let error = self.store.unterminated_token(
                ScannerMessage::UnexpectedDollarInString,
                self.token_start,
                self.string_offset(),
            );
            self.prepend_error_token(error);
        }
        self.begin_token(); // The string interpolation suffix starts here.
        next
    }

    pub fn tokenize_single_line_raw_string(
        &mut self,
        mut next: i32,
        quote_char: i32,
        quote_start: i32,
    ) -> i32 {
        let mut ascii_only = true;
        while next != C_EOF {
            if next == quote_char {
                if !ascii_only {
                    self.sub.handle_unicode(quote_start);
                }
                next = self.advance();
                self.append_substring_token(TokenType::STRING, quote_start, ascii_only, 0);
                return next;
            } else if next == C_LF || next == C_CR {
                if !ascii_only {
                    self.sub.handle_unicode(quote_start);
                }
                self.unterminated_string(
                    quote_char,
                    quote_start,
                    quote_start,
                    ascii_only,
                    false,
                    true,
                );
                return next;
            } else if next > 127 {
                ascii_only = false;
            }
            next = self.advance();
        }
        if !ascii_only {
            self.sub.handle_unicode(quote_start);
        }
        self.unterminated_string(
            quote_char,
            quote_start,
            quote_start,
            ascii_only,
            false,
            true,
        );
        next
    }

    pub fn tokenize_multi_line_raw_string(&mut self, quote_char: i32, quote_start: i32) -> i32 {
        let mut ascii_only_string = true;
        let mut ascii_only_line = true;
        let mut unicode_start = quote_start;
        let mut next = self.advance(); // Advance past the (last) quote (of three).
        'outer: while next != C_EOF {
            while next != quote_char {
                if next == C_LF {
                    if !ascii_only_line {
                        // Synchronize the string offset in the utf8 scanner.
                        self.sub.handle_unicode(unicode_start);
                        ascii_only_line = true;
                        unicode_start = self.scan_offset();
                    }
                    self.line_feed_in_multiline();
                } else if next > 127 {
                    ascii_only_line = false;
                    ascii_only_string = false;
                }
                next = self.advance();
                if next == C_EOF {
                    break 'outer;
                }
            }
            next = self.advance();
            if next == quote_char {
                next = self.advance();
                if next == quote_char {
                    if !ascii_only_line {
                        self.sub.handle_unicode(unicode_start);
                    }
                    next = self.advance();
                    self.append_substring_token(
                        TokenType::STRING,
                        quote_start,
                        ascii_only_string,
                        0,
                    );
                    return next;
                }
            }
        }
        if !ascii_only_line {
            self.sub.handle_unicode(unicode_start);
        }
        // Upstream passes the line's flag here, not the string's.
        self.unterminated_string(
            quote_char,
            quote_start,
            quote_start,
            ascii_only_line,
            true,
            true,
        );
        next
    }

    pub fn tokenize_multi_line_string(
        &mut self,
        quote_char: i32,
        quote_start: i32,
        raw: bool,
    ) -> i32 {
        if raw {
            return self.tokenize_multi_line_raw_string(quote_char, quote_start);
        }
        let mut start = quote_start;
        let mut ascii_only_string = true;
        let mut ascii_only_line = true;
        let mut unicode_start = start;
        let mut next = self.advance(); // Advance past the (last) quote (of three).
        while next != C_EOF {
            if next == C_DOLLAR {
                if !ascii_only_line {
                    self.sub.handle_unicode(unicode_start);
                }
                next = self.tokenize_string_interpolation(start, ascii_only_string);
                start = self.scan_offset();
                unicode_start = start;
                ascii_only_string = true; // A new string token is created for the rest.
                ascii_only_line = true;
                continue;
            }
            if next == quote_char {
                next = self.advance();
                if next == quote_char {
                    next = self.advance();
                    if next == quote_char {
                        if !ascii_only_line {
                            self.sub.handle_unicode(unicode_start);
                        }
                        next = self.advance();
                        self.append_substring_token(TokenType::STRING, start, ascii_only_string, 0);
                        return next;
                    }
                }
                continue;
            }
            if next == C_BACKSLASH {
                next = self.advance();
                if next == C_EOF {
                    break;
                }
            }
            if next == C_LF {
                if !ascii_only_line {
                    // Synchronize the string offset in the utf8 scanner.
                    self.sub.handle_unicode(unicode_start);
                    ascii_only_line = true;
                    unicode_start = self.scan_offset();
                }
                self.line_feed_in_multiline();
            } else if next > 127 {
                ascii_only_string = false;
                ascii_only_line = false;
            }
            next = self.advance();
        }
        if !ascii_only_line {
            self.sub.handle_unicode(unicode_start);
        }
        self.unterminated_string(
            quote_char,
            quote_start,
            start,
            ascii_only_string,
            true,
            false,
        );
        next
    }

    pub fn unexpected(&mut self, character: i32) -> i32 {
        let error_token =
            build_unexpected_character_token(&mut self.store, character, self.token_start);
        if self.store.runtime_type(error_token) == TokenRuntimeType::NonAsciiIdentifierToken {
            let char_offset;
            let mut code_units: Vec<i32> = Vec::new();
            if self.store.is_a(self.tail, TokenType::IDENTIFIER)
                && self.store.char_end(self.tail) == self.token_start
            {
                char_offset = self.store.char_offset(self.tail);
                code_units.extend(self.store.lexeme(self.tail).iter().map(|&u| u as i32));
                self.tail = self.store.previous(self.tail);
            } else {
                char_offset = self.store.char_offset(error_token);
            }
            code_units.push(self.store.character(error_token).unwrap());
            self.prepend_error_token(error_token);
            let mut next = self.advance_after_error();
            while is_identifier_char(next, /* allowDollar = */ true) {
                code_units.push(next);
                next = self.advance();
            }
            let token = self.store.string_token_impl_from_string(
                TokenType::IDENTIFIER,
                string_from_char_codes(&code_units),
                char_offset,
                self.comments,
            );
            self.append_token(token);
            next
        } else {
            self.prepend_error_token(error_token);
            self.advance_after_error()
        }
    }

    pub fn unterminated_string(
        &mut self,
        quote_char: i32,
        quote_start: i32,
        start: i32,
        ascii_only: bool,
        is_multi_line: bool,
        is_raw: bool,
    ) {
        let quote = char::from_u32(quote_char as u32).unwrap();
        let suffix: String =
            std::iter::repeat_n(quote, if is_multi_line { 3 } else { 1 }).collect();
        let prefix = if is_raw {
            format!("r{suffix}")
        } else {
            suffix.clone()
        };
        self.append_synthetic_substring_token(TokenType::STRING, start, ascii_only, &suffix);
        // Ensure that the error is reported on a visible token.
        let string_offset = self.string_offset();
        let error_start = if self.token_start < string_offset {
            self.token_start
        } else {
            quote_start
        };
        let error = self
            .store
            .unterminated_string(&prefix, error_start, string_offset);
        self.prepend_error_token(error);
    }

    pub fn advance_after_error(&mut self) -> i32 {
        if self.sub.at_end_of_file() {
            return C_EOF;
        }
        self.advance() // Ensure progress.
    }
}

/// `new String.fromCharCodes(codes)`: code points above U+FFFF become
/// surrogate pairs; every other value is one code unit.
pub fn string_from_char_codes(codes: &[i32]) -> Vec<u16> {
    let mut result = Vec::with_capacity(codes.len());
    for &code in codes {
        if code > 0xFFFF {
            let c = code - 0x10000;
            result.push((0xD800 + (c >> 10)) as u16);
            result.push((0xDC00 + (c & 0x3FF)) as u16);
        } else {
            result.push(code as u16);
        }
    }
    result
}

/// `closeBraceInfoFor`: the closer for a begin token, by its lexeme.
pub fn close_brace_info_for(store: &TokenStore, begin: TokenId) -> &'static TokenType {
    let type_ = store.type_(begin);
    if type_ == TokenType::OPEN_PAREN {
        TokenType::CLOSE_PAREN
    } else if type_ == TokenType::OPEN_SQUARE_BRACKET {
        TokenType::CLOSE_SQUARE_BRACKET
    } else if type_ == TokenType::OPEN_CURLY_BRACKET {
        TokenType::CLOSE_CURLY_BRACKET
    } else if type_ == TokenType::LT {
        TokenType::GT
    } else if type_ == TokenType::STRING_INTERPOLATION_EXPRESSION {
        TokenType::CLOSE_CURLY_BRACKET
    } else {
        panic!("Null check operator used on a null value")
    }
}

/// `class LineStarts extends Object with ListMixin<int>`.
///
/// Upstream stores the offsets in a `Uint16List` and switches to a
/// `Uint32List` when one exceeds 65535; that saves memory without changing
/// any value, and a `u32` vector holds every value either would.
#[derive(Debug, Default)]
pub struct LineStarts {
    pub array: Vec<u32>,
}

impl LineStarts {
    pub fn new(number_of_bytes_hint: usize) -> LineStarts {
        // Let's assume the average Dart file is 300 bytes per line.
        let expected_number_of_lines = 1 + number_of_bytes_hint / 22;
        let mut line_starts = LineStarts {
            array: Vec::with_capacity(expected_number_of_lines),
        };
        line_starts.add(0);
        line_starts
    }

    #[inline(always)]
    pub fn add(&mut self, value: i32) {
        self.array.push(value as u32);
    }

    pub fn length(&self) -> i32 {
        self.array.len() as i32
    }

    pub fn is_empty(&self) -> bool {
        self.array.is_empty()
    }

    pub fn get(&self, index: i32) -> i32 {
        self.array[index as usize] as i32
    }

    pub fn last(&self) -> i32 {
        *self.array.last().unwrap() as i32
    }

    /// `copyToTypedDataWithoutLastElement`.
    pub fn copy_to_typed_data_without_last_element(&self) -> Vec<u32> {
        self.array[..self.array.len() - 1].to_vec()
    }
}

#[derive(Clone, Copy, Debug)]
pub struct ScannerConfiguration {
    /// Whether the triple-shift operator `>>>` is enabled.
    pub enable_triple_shift: bool,

    /// Whether the `augment` keyword is enabled.
    pub enable_augmentations: bool,
}
