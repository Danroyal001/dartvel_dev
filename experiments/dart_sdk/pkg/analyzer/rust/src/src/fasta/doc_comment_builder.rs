// Port of lib/src/fasta/doc_comment_builder.dart.
//
// Strings are UTF-16 code units, as Dart strings are, so that indices into a
// comment's text are offsets in the file.
//
// Upstream scans each comment reference and each doc import with a scanner
// of its own and keeps the tokens it made. Here tokens live in the token
// store of the file, so the tokens of such a scan are appended to it
// (`import_tokens`), and a doc import is parsed by a parser that borrows the
// file's token store, node store and diagnostic reporter for the time of the
// parse. `DocImportStringScanner`, which moves the offsets the scanner gives
// its tokens into the file, moves the offsets of the appended tokens instead
// (comment and error tokens, whose offsets upstream's override does not
// reach, are left where they are).
#![allow(clippy::all, unused_variables, dead_code)]

use std::rc::Rc;

use fe_analyzer_shared::parser::experimental_features::ExperimentalFeatures;
use fe_analyzer_shared::parser::parser_impl::Parser;
use fe_analyzer_shared::parser::token_stream_rewriter::{
    TokenStreamRewriter, TokenStreamRewriterImpl,
};
use fe_analyzer_shared::parser::util::{is_letter, is_letter_or_digit, is_whitespace, optional};
use fe_analyzer_shared::scanner::scanner::{ScannerResult, scan_string};
use fe_analyzer_shared::scanner::token::{Lexeme, NO_TOKEN, TokenId, TokenStore, TokenType};
use fe_analyzer_shared::scanner::token_constants::KEYWORD_TOKEN;

use crate::dart::analysis::features::FeatureSet;
use crate::dart::ast::doc_comment::*;
use crate::dart::element::element::LibraryLanguageVersion;
use crate::source::line_info::LineInfo;
use crate::src::dart::analysis::experiments::ExperimentalFeaturesStatus;
use crate::src::dart::ast::ast::*;
use crate::src::dart::ast::ast_store::{AstStore, NO_NODE, NodeId};
use crate::src::diagnostic::diagnostic_g as diag;
use crate::src::error::listener::DiagnosticReporter;
use crate::src::fasta::ast_builder::AstBuilder;

fn units(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

/// `content.startsWith(prefix, index)`.
fn starts_with_at(content: &[u16], prefix: &str, index: usize) -> bool {
    let p = units(prefix);
    index <= content.len() && content[index..].starts_with(&p)
}

/// `content.indexOf(pattern, start)`, or -1.
fn index_of(content: &[u16], pattern: &[u16], start: usize) -> i64 {
    if start > content.len() {
        return -1;
    }
    if pattern.is_empty() {
        return start as i64;
    }
    let mut i = start;
    while i + pattern.len() <= content.len() {
        if &content[i..i + pattern.len()] == pattern {
            return i as i64;
        }
        i += 1;
    }
    -1
}

/// Dart's `String.trim()`: the whitespace it removes.
fn is_dart_trim_whitespace(c: u16) -> bool {
    matches!(
        c,
        0x09..=0x0D
            | 0x20
            | 0x85
            | 0xA0
            | 0x1680
            | 0x2000..=0x200A
            | 0x2028
            | 0x2029
            | 0x202F
            | 0x205F
            | 0x3000
            | 0xFEFF
    )
}

fn dart_trim(text: &[u16]) -> &[u16] {
    let mut start = 0;
    let mut end = text.len();
    while start < end && is_dart_trim_whitespace(text[start]) {
        start += 1;
    }
    while end > start && is_dart_trim_whitespace(text[end - 1]) {
        end -= 1;
    }
    &text[start..end]
}

/// Appends the tokens of [result] (scanned from another string) to
/// [tokens] and returns the first; ids inside the tokens are moved along.
pub fn import_tokens(tokens: &mut TokenStore, result: ScannerResult, offset_delta: i32) -> TokenId {
    let source = result.store;
    let base = tokens.tokens.len() as u32;
    let remap = |t: TokenId| if t == NO_TOKEN { NO_TOKEN } else { t + base };
    for (index, data) in source.tokens.iter().enumerate() {
        let mut data = data.clone();
        let lexeme = match data.lexeme() {
            Lexeme::Fixed => Lexeme::Fixed,
            other => {
                let text = source.lexeme_text(other, data.type_index);
                Lexeme::Owned(tokens.add_string(text))
            }
        };
        data.set_lexeme(lexeme);
        data.next = remap(data.next);
        data.previous = remap(data.previous);
        data.end_token = remap(data.end_token);
        if data.has_extras {
            let mut extras = source.extras[&(index as TokenId)];
            extras.preceding_comments = remap(extras.preceding_comments);
            extras.parent = remap(extras.parent);
            extras.before_synthetic = remap(extras.before_synthetic);
            tokens.extras.insert(base + index as TokenId, extras);
        }
        let runtime_type = data.runtime_type;
        if offset_delta != 0 && !runtime_type.is_comment_token() && !runtime_type.is_error_token() {
            data.offset += offset_delta;
        }
        tokens.tokens.push(data);
    }
    remap(result.tokens)
}

/// `parser.syntheticPreviousToken(token)`.
fn synthetic_previous_token(tokens: &mut TokenStore, token: TokenId) -> TokenId {
    if tokens.previous(token) != NO_TOKEN {
        return tokens.previous(token);
    }
    let before = tokens.eof(-1, NO_TOKEN);
    tokens.set_next_field(before, token);
    before
}

fn find_comment_reference_end(comment: &[u16], mut index: usize, end: usize) -> usize {
    let c = |i: usize| comment[i] as i32;
    if index >= end || !is_letter(c(index)) {
        return index;
    }
    while index < end && is_letter_or_digit(c(index)) {
        index += 1;
    }
    if index >= end || c(index) != 0x2E {
        return index;
    }
    index += 1;
    if index >= end || !is_letter(c(index)) {
        return index;
    }
    index += 1;
    while index < end && is_letter_or_digit(c(index)) {
        index += 1;
    }
    index
}

fn is_equal_sign(character: i32) -> bool {
    character == 0x3D
}

/// Whether the [comment] can contain a link reference after [right_index].
fn is_link_text(comment: &[u16], right_index: usize, can_be_link_reference: bool) -> bool {
    let length = comment.len();
    let mut index = right_index + 1;
    if index >= length {
        return false;
    }
    let mut ch = comment[index] as i32;
    if ch == 0x28 {
        return true;
    }
    if can_be_link_reference && ch == 0x3A {
        return true;
    }
    while is_whitespace(ch) {
        index += 1;
        if index >= length {
            return false;
        }
        ch = comment[index] as i32;
    }
    ch == 0x5B
}

fn is_right_curly_brace(character: i32) -> bool {
    character == 0x7D
}

/// Reads past whitespace in [content], returning the index after the last
/// whitespace character.
fn read_whitespace(content: &[u16], mut index: usize) -> usize {
    let length = content.len();
    if index >= length {
        return index;
    }
    while is_whitespace(content[index] as i32) {
        index += 1;
        if index >= length {
            return index;
        }
    }
    index
}

/// Given a comment reference without a closing `]`, search for a possible
/// place where `]` should be.
pub struct DocCommentBuilder<'a> {
    ast: &'a mut AstStore,
    tokens: &'a mut TokenStore,
    diagnostic_reporter: Option<&'a mut DiagnosticReporter>,
    uri: Rc<str>,
    feature_set: FeatureSet,
    language_version: LibraryLanguageVersion,
    line_info: &'a LineInfo,
    references: Vec<NodeId>,
    code_blocks: Vec<MdCodeBlock>,
    doc_imports: Vec<DocImport>,
    doc_directives: Vec<DocDirective>,
    has_nodoc: bool,
    start_token: TokenId,
    character_sequence: CharacterSequence,
    block_doc_directive_builder_stack: Vec<BlockDocDirectiveBuilder>,
}

impl<'a> DocCommentBuilder<'a> {
    pub fn new(
        ast: &'a mut AstStore,
        tokens: &'a mut TokenStore,
        diagnostic_reporter: Option<&'a mut DiagnosticReporter>,
        uri: Rc<str>,
        feature_set: FeatureSet,
        language_version: LibraryLanguageVersion,
        line_info: &'a LineInfo,
        start_token: TokenId,
    ) -> DocCommentBuilder<'a> {
        let character_sequence = CharacterSequence::new(tokens, start_token);
        DocCommentBuilder {
            ast,
            tokens,
            diagnostic_reporter,
            uri,
            feature_set,
            language_version,
            line_info,
            references: Vec::new(),
            code_blocks: Vec::new(),
            doc_imports: Vec::new(),
            doc_directives: Vec::new(),
            has_nodoc: false,
            start_token,
            character_sequence,
            block_doc_directive_builder_stack: Vec::new(),
        }
    }

    fn report(&mut self, diagnostic: crate::src::diagnostic::diagnostic::LocatedDiagnostic) {
        if let Some(reporter) = self.diagnostic_reporter.as_mut() {
            reporter.report(diagnostic);
        }
    }

    pub fn build(mut self) -> NodeId {
        self.parse_doc_comment();
        let mut tokens = vec![self.start_token];
        let mut token = self.start_token;
        if self.tokens.lexeme_string(token).starts_with("///") {
            token = self.tokens.next(token);
            while token != NO_TOKEN {
                if self.tokens.lexeme_string(token).starts_with("///") {
                    tokens.push(token);
                }
                token = self.tokens.next(token);
            }
        }
        let references = std::mem::take(&mut self.references);
        let code_blocks = std::mem::take(&mut self.code_blocks);
        let doc_imports = std::mem::take(&mut self.doc_imports);
        let doc_directives = std::mem::take(&mut self.doc_directives);
        self.ast.add(CommentImpl {
            tokens,
            references,
            code_blocks,
            doc_imports,
            doc_directives,
            has_nodoc: self.has_nodoc,
        })
    }

    fn end_block_doc_directive_tag(
        &mut self,
        parser: &mut DirectiveParser,
        type_: DocDirectiveType,
    ) {
        let closing_tag = parser.directive(type_, self.diagnostic_reporter.as_deref_mut());
        let mut i = self.block_doc_directive_builder_stack.len();
        while i > 0 {
            i -= 1;
            if self.block_doc_directive_builder_stack[i].matches(&closing_tag) {
                let mut builder = self.block_doc_directive_builder_stack.remove(i);
                builder.closing_tag = Some(closing_tag.clone());
                // Add all inner doc directives to the higher directive.
                let built = builder.build();
                let higher_directive = &mut self.block_doc_directive_builder_stack[i - 1];
                higher_directive.push(built);
                for doc_directive in builder.inner_doc_directives {
                    higher_directive.push(doc_directive);
                }
                // Close all unclosed directives above.
                while self.block_doc_directive_builder_stack.len() > i {
                    let builder = self.block_doc_directive_builder_stack.remove(i);
                    if let Some(opening_tag) = &builder.opening_tag {
                        let d = diag::docDirectiveMissingClosingTag
                            .with_arguments(vec![
                                opening_tag.type_.opposing_name().unwrap().to_string(),
                            ])
                            .at_offset(opening_tag.offset, opening_tag.end - opening_tag.offset);
                        self.report(d);
                    }
                    let built = builder.build();
                    let higher_directive = &mut self.block_doc_directive_builder_stack[i - 1];
                    higher_directive.push(built);
                    for doc_directive in builder.inner_doc_directives {
                        higher_directive.push(doc_directive);
                    }
                }
                return;
            }
        }

        // No matching opening tag was found.
        let d = diag::docDirectiveMissingOpeningTag
            .with_arguments(vec![closing_tag.type_.name().to_string()])
            .at_offset(closing_tag.offset, closing_tag.end - closing_tag.offset);
        self.report(d);
        self.push_doc_directive(DocDirective::SimpleDocDirective(SimpleDocDirective {
            tag: closing_tag,
        }));
    }

    /// Determines if [content] can represent a fenced codeblock delimiter.
    fn fenced_code_block_delimiter(&self, content: &[u16], minimum_tick_count: usize) -> i64 {
        if content.is_empty() {
            return -1;
        }
        let index = read_whitespace(content, 0);
        let length = content.len();
        if index + 3 > length {
            return -1;
        }
        let ticks: Vec<u16> = vec![0x60; minimum_tick_count];
        if content[index..index + 3] == ticks[..] {
            index as i64
        } else {
            -1
        }
    }

    fn parse_block_doc_directive_tag(
        &mut self,
        parser: &mut DirectiveParser,
        type_: DocDirectiveType,
    ) {
        let opening = parser.directive(type_, self.diagnostic_reporter.as_deref_mut());
        self.block_doc_directive_builder_stack
            .push(BlockDocDirectiveBuilder::new(Some(opening)));
    }

    fn parse_doc_comment(&mut self) {
        let mut is_previous_line_empty = true;
        let mut line_info = self.character_sequence.next(self.tokens);
        self.block_doc_directive_builder_stack
            .push(BlockDocDirectiveBuilder::placeholder());
        while let Some((offset, content)) = line_info {
            let whitespace_end_index = read_whitespace(&content, 0);
            if is_previous_line_empty && whitespace_end_index >= 4 {
                line_info = self.parse_indented_code_block(&content);
                if let Some((_, c)) = &line_info {
                    is_previous_line_empty = c.is_empty();
                }
                continue;
            }

            if self.parse_fenced_code_block(&content) {
                is_previous_line_empty = false;
            } else if self.parse_doc_directive_tag(whitespace_end_index, &content) {
                is_previous_line_empty = false;
            } else if self.parse_doc_import(whitespace_end_index, &content) {
                is_previous_line_empty = false;
            } else if self.parse_nodoc(whitespace_end_index, &content) {
                is_previous_line_empty = false;
            } else if self.tokens.type_(self.start_token) == TokenType::MULTI_LINE_COMMENT
                && content == units("/**")
            {
                is_previous_line_empty = true;
            } else {
                self.parse_references(offset, &content);
                is_previous_line_empty = content.is_empty();
            }
            line_info = self.character_sequence.next(self.tokens);
        }

        // Resolve any unclosed block directives.
        while self.block_doc_directive_builder_stack.len() > 1 {
            let builder = self.block_doc_directive_builder_stack.pop().unwrap();
            if let Some(opening_tag) = &builder.opening_tag {
                let d = diag::docDirectiveMissingClosingTag
                    .with_arguments(vec![opening_tag.type_.opposing_name().unwrap().to_string()])
                    .at_offset(opening_tag.offset, opening_tag.end - opening_tag.offset);
                self.report(d);
            }
            self.push_block_doc_directive_and_inner_directives(builder);
        }

        let block_doc_directive_builder = self.block_doc_directive_builder_stack.remove(0);
        self.doc_directives
            .extend(block_doc_directive_builder.inner_doc_directives);
    }

    /// Tries to parse a doc directive tag at the beginning of a line.
    fn parse_doc_directive_tag(&mut self, mut index: usize, content: &[u16]) -> bool {
        const OPENING_LENGTH: usize = 2;
        if !starts_with_at(content, "{@", index) {
            return false;
        }
        let start_offset = self.character_sequence.offset + index as i32;
        index += OPENING_LENGTH;
        let length = content.len();
        if index >= length {
            return false;
        }
        let name_index = index;
        loop {
            let character = content[index] as i32;
            if is_whitespace(character) || is_right_curly_brace(character) {
                break;
            }
            index += 1;
            if index >= length {
                break;
            }
        }
        let name_end = index;
        index = read_whitespace(content, index);
        let name = String::from_utf16_lossy(&content[name_index..name_end]);
        let seq_offset = self.character_sequence.offset;
        let mut parser = DirectiveParser {
            offset: start_offset,
            content_offset: seq_offset,
            name_offset: seq_offset + name_index as i32,
            name_end: seq_offset + name_end as i32,
            content: content.to_vec(),
            length: content.len(),
            index,
            end: None,
        };

        match name.as_str() {
            "animation" => {
                let d = parser.simple_directive(
                    DocDirectiveType::animation,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            "canonicalFor" => {
                let d = parser.simple_directive(
                    DocDirectiveType::canonicalFor,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            "category" => {
                let d = parser.simple_directive(
                    DocDirectiveType::category,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            "end-inject-html" => {
                self.end_block_doc_directive_tag(&mut parser, DocDirectiveType::endInjectHtml);
                return true;
            }
            "end-tool" => {
                self.end_block_doc_directive_tag(&mut parser, DocDirectiveType::endTool);
                return true;
            }
            "endtemplate" => {
                self.end_block_doc_directive_tag(&mut parser, DocDirectiveType::endTemplate);
                return true;
            }
            "example" => {
                let d = parser.simple_directive(
                    DocDirectiveType::example,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            "inject-html" => {
                self.parse_block_doc_directive_tag(&mut parser, DocDirectiveType::injectHtml);
                return true;
            }
            "macro" => {
                let d = parser.simple_directive(
                    DocDirectiveType::macro_,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            "subCategory" => {
                let d = parser.simple_directive(
                    DocDirectiveType::subCategory,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            "template" => {
                self.parse_block_doc_directive_tag(&mut parser, DocDirectiveType::template);
                return true;
            }
            "tool" => {
                self.parse_block_doc_directive_tag(&mut parser, DocDirectiveType::tool);
                return true;
            }
            "youtube" => {
                let d = parser.simple_directive(
                    DocDirectiveType::youtube,
                    self.diagnostic_reporter.as_deref_mut(),
                );
                self.push_doc_directive(d);
                return true;
            }
            _ => {}
        }
        let d = diag::docDirectiveUnknown
            .with_arguments(vec![name])
            .at_offset(
                seq_offset + name_index as i32,
                (name_end - name_index) as i32,
            );
        self.report(d);
        false
    }

    /// Tries to parse a doc import at the beginning of a line of a doc comment,
    /// returning whether this was successful.
    fn parse_doc_import(&mut self, mut index: usize, content: &[u16]) -> bool {
        const DOC_IMPORT_LENGTH: usize = 11; // '@docImport '.length
        const IMPORT_LENGTH: i32 = 7; // 'import '.length
        if !starts_with_at(content, "@docImport ", index) {
            return false;
        }

        index = read_whitespace(content, index + DOC_IMPORT_LENGTH);
        let mut synthetic_import = units("import ");
        synthetic_import.extend_from_slice(&content[index..]);

        // TODO(srawlins): Handle multiple lines.
        let offset_in_unit = self.character_sequence.offset + (index as i32 - IMPORT_LENGTH);

        let experimental_features = ExperimentalFeaturesStatus::new(self.feature_set.clone());
        let result = scan_string(
            Rc::from(synthetic_import),
            Some(experimental_features.build_scanner_configuration()),
            true,
            || None,
        );
        // `_toOffsetInUnit` with one entry in the source map:
        // `offsetInUnit + (offset - 0)`.
        let token = import_tokens(self.tokens, result, offset_in_unit);

        // Parse with a parser and builder of their own, which build into this
        // file's stores.
        let reporter = self.diagnostic_reporter.as_deref_mut().map(std::mem::take);
        let mut doc_import_listener = AstBuilder::new(
            reporter,
            self.uri.clone(),
            true, /* isFullAst */
            self.feature_set.clone(),
            self.language_version,
            self.line_info.clone(),
            None,
        );
        doc_import_listener.ast = std::mem::take(self.ast);
        let store = std::mem::take(self.tokens);
        let mut parser = Parser::new(
            Box::new(doc_import_listener),
            store,
            true,
            Box::new(experimental_features),
        );
        parser.parse_unit(token);
        *self.tokens = std::mem::take(&mut parser.tokens);
        let mut listener: Box<dyn std::any::Any> = parser.listener;
        let doc_import_listener = loop {
            match listener.downcast::<AstBuilder>() {
                Ok(builder) => break builder,
                Err(other) => {
                    let forwarding = other
                        .downcast::<fe_analyzer_shared::parser::forwarding_listener::ForwardingListener>()
                        .expect("AstBuilder");
                    listener = forwarding.listener.expect("forwarded listener");
                }
            }
        };
        let mut doc_import_listener = *doc_import_listener;
        *self.ast = std::mem::take(&mut doc_import_listener.ast);
        if let (Some(target), Some(reporter)) = (
            self.diagnostic_reporter.as_deref_mut(),
            doc_import_listener
                .diagnostic_reporter
                .diagnostic_reporter
                .take(),
        ) {
            *target = reporter;
        }

        if doc_import_listener.directives.is_empty() {
            return false;
        }
        let directive = doc_import_listener.directives[0];

        if let AstNodeImpl::ImportDirectiveImpl(_) = self.ast.node(directive) {
            self.doc_imports.push(DocImport {
                offset: self.character_sequence.offset,
                import: directive,
            });
            return true;
        }

        false
    }

    /// Parses a fenced code block, starting with [content].
    fn parse_fenced_code_block(&mut self, content: &[u16]) -> bool {
        let index = self.fenced_code_block_delimiter(content, 3);
        if index == -1 {
            return false;
        }
        let mut index = index as usize;
        let mut tick_count = 0;
        let length = content.len();
        while content[index] == 0x60 {
            tick_count += 1;
            index += 1;
            if index >= length {
                break;
            }
        }
        let info_string = if index == length {
            None
        } else {
            InfoString::parse(&content[index..])
        };
        let mut fenced_code_block_lines = vec![MdCodeBlockLine {
            offset: self.character_sequence.offset,
            length: content.len() as i32,
        }];

        let mut line_info = self.character_sequence.next(self.tokens);
        while let Some((offset, content)) = &line_info {
            fenced_code_block_lines.push(MdCodeBlockLine {
                offset: *offset,
                length: content.len() as i32,
            });
            let fenced_code_block_index = self.fenced_code_block_delimiter(content, tick_count);
            if fenced_code_block_index > -1 {
                // End the fenced code block.
                break;
            }
            line_info = self.character_sequence.next(self.tokens);
        }

        self.code_blocks.push(MdCodeBlock {
            info_string,
            lines: fenced_code_block_lines,
            type_: CodeBlockType::fenced,
        });
        true
    }

    /// Parses an indented code block, starting with [content].
    fn parse_indented_code_block(&mut self, content: &[u16]) -> Option<(i32, Vec<u16>)> {
        let mut code_block_lines = vec![MdCodeBlockLine {
            offset: self.character_sequence.offset,
            length: content.len() as i32,
        }];

        let mut line_info = self.character_sequence.next(self.tokens);
        while let Some((offset, content)) = &line_info {
            let whitespace_end_index = read_whitespace(content, 0);
            if whitespace_end_index >= 4 {
                code_block_lines.push(MdCodeBlockLine {
                    offset: *offset,
                    length: content.len() as i32,
                });
            } else {
                self.code_blocks.push(MdCodeBlock {
                    info_string: None,
                    lines: code_block_lines,
                    type_: CodeBlockType::indented,
                });
                return line_info;
            }
            line_info = self.character_sequence.next(self.tokens);
        }

        // The indented code block ended at the end of the comment.
        self.code_blocks.push(MdCodeBlock {
            info_string: None,
            lines: code_block_lines,
            type_: CodeBlockType::indented,
        });
        line_info
    }

    /// Tries to parse a `@nodoc` doc directive at the beginning of a line.
    fn parse_nodoc(&mut self, index: usize, content: &[u16]) -> bool {
        const NODOC_LENGTH: usize = 6;
        if !starts_with_at(content, "@nodoc", index) {
            return false;
        }
        if content.len() == index + NODOC_LENGTH || content[index + NODOC_LENGTH] == 0x20 {
            self.has_nodoc = true;
            return true;
        }
        false
    }

    /// Parses the [source] text, found at [offset] in a single comment reference.
    fn parse_one_comment_reference(
        &mut self,
        source: &[u16],
        offset: i32,
        mut is_synthetic: bool,
    ) -> NodeId {
        let result = scan_string(Rc::from(source.to_vec()), None, true, || None);
        if result.has_errors {
            return NO_NODE;
        }
        let token = import_tokens(self.tokens, result, 0);
        let t = &mut *self.tokens;
        let mut token = token;
        let mut begin = token;
        let mut first_token = NO_TOKEN;
        let mut first_period = NO_TOKEN;
        let mut second_token = NO_TOKEN;
        let mut second_period = NO_TOKEN;
        if t.is_identifier(token) && optional(t, ".", t.next(token)) {
            second_token = token;
            second_period = t.next(token);
            if t.is_identifier(t.next(second_period))
                && optional(t, ".", t.next(t.next(second_period)))
            {
                first_token = second_token;
                first_period = second_period;
                second_token = t.next(second_period);
                second_period = t.next(second_token);
            }
            let identifier = t.next(second_period);
            if t.kind(identifier) == KEYWORD_TOKEN && optional(t, "new", identifier) {
                // Treat `new` after `.` is as an identifier so that it can represent an
                // unnamed constructor. This support is separate from the
                // constructor-tearoffs feature.
                let lexeme = t.lexeme(identifier);
                let char_offset = t.char_offset(identifier);
                let replacement = t.string_token(TokenType::IDENTIFIER, lexeme, char_offset);
                TokenStreamRewriterImpl.replace_token_following(t, second_period, replacement);
            }
            token = t.next(second_period);
        }
        if t.is_eof(token) {
            // Recovery: Insert a synthetic identifier for code completion.
            let previous = if second_period != NO_TOKEN {
                second_period
            } else {
                synthetic_previous_token(t, token)
            };
            token = TokenStreamRewriterImpl.insert_synthetic_identifier(t, previous, "");
            is_synthetic = true;
            if begin == t.next(token) {
                begin = token;
            }
        }

        let mut operator_keyword = NO_TOKEN;
        if optional(t, "operator", token) {
            operator_keyword = token;
            token = t.next(token);
        }

        if t.is_user_definable_operator(token) {
            if t.is_eof(t.next(token)) {
                return self.parse_one_comment_reference_rest(
                    begin,
                    offset,
                    first_token,
                    first_period,
                    second_token,
                    second_period,
                    token,
                    operator_keyword,
                    is_synthetic,
                );
            }
        } else {
            if operator_keyword != NO_TOKEN {
                token = operator_keyword;
            }
            if t.is_eof(t.next(token)) {
                if t.is_identifier(token) {
                    return self.parse_one_comment_reference_rest(
                        begin,
                        offset,
                        first_token,
                        first_period,
                        second_token,
                        second_period,
                        token,
                        NO_TOKEN,
                        is_synthetic,
                    );
                }
                // TODO(brianwilkerson): If we want to support `this`, `null`,
                // `true` and `false`, we will need to extend the definition of
                // CommentReference to take an expression.
            }
        }
        NO_NODE
    }

    /// Parses the parameters into a [CommentReferenceImpl].
    fn parse_one_comment_reference_rest(
        &mut self,
        begin: TokenId,
        reference_offset: i32,
        first_token: TokenId,
        first_period: TokenId,
        second_token: TokenId,
        second_period: TokenId,
        identifier_or_operator: TokenId,
        operator_keyword: TokenId,
        is_synthetic: bool,
    ) -> NodeId {
        // Adjust the token offsets to match the enclosing comment token.
        let mut token = begin;
        loop {
            let offset = self.tokens.offset(token);
            self.tokens.set_offset(token, offset + reference_offset);
            token = self.tokens.next(token);
            if self.tokens.is_eof(token) {
                break;
            }
        }

        let mut components = Vec::new();
        if first_token != NO_TOKEN {
            components.push(self.ast.add(CommentReferenceComponentImpl {
                period: NO_TOKEN,
                operator_keyword: NO_TOKEN,
                name: first_token,
            }));
        }
        if second_token != NO_TOKEN {
            components.push(self.ast.add(CommentReferenceComponentImpl {
                period: first_period,
                operator_keyword: NO_TOKEN,
                name: second_token,
            }));
        }
        components.push(self.ast.add(CommentReferenceComponentImpl {
            period: second_period,
            operator_keyword,
            name: identifier_or_operator,
        }));
        self.ast.add(CommentReferenceImpl {
            components,
            is_synthetic,
        })
    }

    /// Parses the comment references in [content] which starts at [offset].
    fn parse_references(&mut self, offset: i32, content: &[u16]) {
        let mut index: usize = 0;
        let end = content.len();
        let mut seen_only_whitespace = true;
        while index < end {
            let ch = content[index] as i32;
            if ch == 0x5B {
                index += 1;
                if index < end && content[index] == 0x3A {
                    // Skip old-style code block, e.g. `/// Text [:int:]`.
                    let found = index_of(content, &units(":]"), index + 1) + 1;
                    if found == 0 || found as usize > end {
                        break;
                    }
                    index = found as usize;
                } else {
                    let reference_start = index;
                    let found = index_of(content, &[0x5D], index);
                    let mut is_synthetic = false;
                    if found == -1 || found as usize >= end {
                        // Recovery: terminating ']' is not typed yet.
                        index = find_comment_reference_end(content, reference_start, end);
                        is_synthetic = true;
                    } else {
                        index = found as usize;
                    }
                    if is_link_text(content, index, seen_only_whitespace) {
                        // TODO(brianwilkerson): Handle the case where there's a library
                        // URI in the link text.
                    } else {
                        let reference = self.parse_one_comment_reference(
                            &content[reference_start..index],
                            offset + reference_start as i32,
                            is_synthetic,
                        );
                        if reference != NO_NODE {
                            self.references.push(reference);
                        }
                    }
                }
                seen_only_whitespace = false;
            } else if ch == 0x60 {
                // Skip inline code block if there is both starting '`' and ending '`'.
                let end_code_block = index_of(content, &[0x60], index + 1);
                if end_code_block != -1 && (end_code_block as usize) < end {
                    index = end_code_block as usize;
                }
                seen_only_whitespace = false;
            } else if !is_whitespace(ch) {
                seen_only_whitespace = false;
            }
            index += 1;
        }
    }

    fn push_block_doc_directive_and_inner_directives(&mut self, builder: BlockDocDirectiveBuilder) {
        let built = builder.build();
        self.push_doc_directive(built);
        for doc_directive in builder.inner_doc_directives {
            self.push_doc_directive(doc_directive);
        }
    }

    fn push_doc_directive(&mut self, doc_directive: DocDirective) {
        self.block_doc_directive_builder_stack
            .last_mut()
            .unwrap()
            .push(doc_directive);
    }
}

struct BlockDocDirectiveBuilder {
    opening_tag: Option<DocDirectiveTag>,
    closing_tag: Option<DocDirectiveTag>,
    inner_doc_directives: Vec<DocDirective>,
}

impl BlockDocDirectiveBuilder {
    fn new(opening_tag: Option<DocDirectiveTag>) -> BlockDocDirectiveBuilder {
        BlockDocDirectiveBuilder {
            opening_tag,
            closing_tag: None,
            inner_doc_directives: Vec::new(),
        }
    }

    fn placeholder() -> BlockDocDirectiveBuilder {
        BlockDocDirectiveBuilder::new(None)
    }

    fn build(&self) -> DocDirective {
        let Some(opening_tag) = &self.opening_tag else {
            panic!("Attempting to build a block doc directive with no opening tag.");
        };
        DocDirective::BlockDocDirective(BlockDocDirective {
            opening_tag: opening_tag.clone(),
            closing_tag: self.closing_tag.clone(),
        })
    }

    fn matches(&self, tag: &DocDirectiveTag) -> bool {
        match &self.opening_tag {
            Some(opening_tag) => opening_tag.type_.opposing_name() == Some(tag.type_.name()),
            None => false,
        }
    }

    fn push(&mut self, doc_directive: DocDirective) {
        self.inner_doc_directives.push(doc_directive);
    }
}

/// `_CharacterSequence`: the lines of a doc comment.
enum CharacterSequenceKind {
    FromMultiLineComment { token: TokenId, end: i32 },
    FromSingleLineComment { token: TokenId },
}

struct CharacterSequence {
    offset: i32,
    kind: CharacterSequenceKind,
}

impl CharacterSequence {
    fn new(tokens: &TokenStore, token: TokenId) -> CharacterSequence {
        let is_from_single_line_comment = tokens.lexeme_string(token).starts_with("///");
        CharacterSequence {
            offset: -1,
            kind: if is_from_single_line_comment {
                CharacterSequenceKind::FromSingleLineComment { token }
            } else {
                CharacterSequenceKind::FromMultiLineComment { token, end: -1 }
            },
        }
    }

    fn next(&mut self, tokens: &TokenStore) -> Option<(i32, Vec<u16>)> {
        match &mut self.kind {
            CharacterSequenceKind::FromMultiLineComment { token, end } => {
                let lexeme = tokens.lexeme(*token);
                let token_offset = tokens.char_offset(*token);
                let ends_with_close = lexeme.ends_with(&units("*/"));
                if self.offset == -1 {
                    // Initial call to next().
                    self.offset = token_offset;
                    let mut end_index = index_of_end_of_line(&lexeme, 0);
                    if end_index == lexeme.len() && ends_with_close {
                        end_index -= 2;
                    }
                    *end = token_offset + end_index as i32;
                    let index_in_lexeme = (self.offset - token_offset) as usize;
                    return Some((self.offset, lexeme[index_in_lexeme..end_index].to_vec()));
                }

                if *end == token_offset + lexeme.len() as i32 - 2 && ends_with_close {
                    return None;
                }

                // Skip over the newline.
                self.offset = *end + 1;
                if (self.offset - token_offset) as usize >= lexeme.len() {
                    return None;
                }
                // Skip leading whitespace.
                while is_whitespace(lexeme[(self.offset - token_offset) as usize] as i32) {
                    self.offset += 1;
                    if (self.offset - token_offset) as usize >= lexeme.len() {
                        return None;
                    }
                }

                let mut end_index =
                    index_of_end_of_line(&lexeme, (self.offset - token_offset) as usize);
                let line_includes_end_of_comment = end_index == lexeme.len() && ends_with_close;
                if line_includes_end_of_comment {
                    end_index -= 2;
                }
                *end = token_offset + end_index as i32;

                if starts_with_at(&lexeme, "* ", (self.offset - token_offset) as usize) {
                    self.offset += 2;
                } else if *end == self.offset + 1
                    && lexeme[(self.offset - token_offset) as usize] == 0x2A
                {
                    self.offset += 1;
                }

                if line_includes_end_of_comment && self.offset == *end {
                    return None;
                }

                Some((
                    self.offset,
                    lexeme[(self.offset - token_offset) as usize..end_index].to_vec(),
                ))
            }
            CharacterSequenceKind::FromSingleLineComment { token } => {
                if self.offset == -1 {
                    self.offset = tokens.char_offset(*token);
                } else {
                    loop {
                        let next_token = tokens.next(*token);
                        if next_token == NO_TOKEN {
                            return None;
                        }
                        *token = next_token;
                        self.offset = tokens.offset(next_token);
                        if tokens.lexeme_string(*token).starts_with("///") {
                            break;
                        }
                    }
                }
                let lexeme = tokens.lexeme(*token);
                let prefix_length = if starts_with_at(&lexeme, "/// ", 0) {
                    4
                } else {
                    3
                };
                self.offset += prefix_length as i32;
                Some((self.offset, lexeme[prefix_length..].to_vec()))
            }
        }
    }
}

/// `_CharacterSequenceFromMultiLineComment._indexOfEndOfLine`.
fn index_of_end_of_line(content: &[u16], start: usize) -> usize {
    let found = index_of(content, &[0x0A], start);
    if found == -1 {
        content.len()
    } else {
        let mut end_index = found as usize;
        if end_index > start && content[end_index - 1] == 0x0D {
            end_index -= 1;
        }
        end_index
    }
}

/// `_DirectiveParser`.
struct DirectiveParser {
    offset: i32,
    content_offset: i32,
    name_offset: i32,
    name_end: i32,
    content: Vec<u16>,
    length: usize,
    index: usize,
    end: Option<i32>,
}

impl DirectiveParser {
    fn directive(
        &mut self,
        type_: DocDirectiveType,
        reporter: Option<&mut DiagnosticReporter>,
    ) -> DocDirectiveTag {
        if self.index == self.length {
            self.end = Some(self.offset + self.index as i32);
        }
        let (positional_arguments, named_arguments) = self.parse_arguments(reporter);
        DocDirectiveTag {
            offset: self.offset,
            end: self.end.expect("Null check operator used on a null value"),
            name_offset: self.name_offset,
            name_end: self.name_end,
            type_,
            positional_arguments,
            named_arguments,
        }
    }

    fn simple_directive(
        &mut self,
        type_: DocDirectiveType,
        reporter: Option<&mut DiagnosticReporter>,
    ) -> DocDirective {
        DocDirective::SimpleDocDirective(SimpleDocDirective {
            tag: self.directive(type_, reporter),
        })
    }

    fn parse_argument(&mut self) -> DocDirectiveArgument {
        let mut only_letters_or_digits = true;
        let argument_start = self.index;
        while self.index < self.length {
            let character = self.content[self.index] as i32;
            if is_whitespace(character) {
                break;
            }
            if is_right_curly_brace(character) {
                break;
            }
            if is_equal_sign(character) && only_letters_or_digits {
                let argument_name = self.content[argument_start..self.index].to_vec();
                self.index += 1;
                if self.index == self.length {
                    return DocDirectiveArgument {
                        offset: self.content_offset + argument_start as i32,
                        end: self.content_offset + self.index as i32,
                        name: Some(argument_name),
                        value: Vec::new(),
                    };
                }
                let argument_value_start = self.index;
                while self.index < self.length {
                    let character = self.content[self.index] as i32;
                    if is_whitespace(character) {
                        break;
                    }
                    if is_right_curly_brace(character) {
                        break;
                    }
                    self.index += 1;
                }
                return DocDirectiveArgument {
                    offset: self.content_offset + argument_start as i32,
                    end: self.content_offset + self.index as i32,
                    name: Some(argument_name),
                    value: self.content[argument_value_start..self.index].to_vec(),
                };
            }
            if !is_letter_or_digit(character) {
                only_letters_or_digits = false;
            }
            self.index += 1;
        }
        DocDirectiveArgument {
            offset: self.content_offset + argument_start as i32,
            end: self.content_offset + self.index as i32,
            name: None,
            value: self.content[argument_start..self.index].to_vec(),
        }
    }

    fn parse_arguments(
        &mut self,
        reporter: Option<&mut DiagnosticReporter>,
    ) -> (Vec<DocDirectiveArgument>, Vec<DocDirectiveArgument>) {
        if self.end.is_some() {
            return (Vec::new(), Vec::new());
        }
        let mut positional_arguments = Vec::new();
        let mut named_arguments = Vec::new();
        while self.index < self.length {
            if is_right_curly_brace(self.content[self.index] as i32) {
                self.index += 1;
                self.end = Some(self.offset + self.index as i32);
                return (positional_arguments, named_arguments);
            }
            let argument = self.parse_argument();
            if argument.name.is_none() {
                positional_arguments.push(argument);
            } else {
                named_arguments.push(argument);
            }
            self.index = read_whitespace(&self.content, self.index);
        }

        // We've hit EOL without closing brace.
        self.end = Some(self.offset + self.index as i32);
        if let Some(reporter) = reporter {
            reporter.report(
                diag::docDirectiveMissingClosingBrace
                    .at_offset(self.offset + self.index as i32 - 1, 1),
            );
        }
        (positional_arguments, named_arguments)
    }
}

/// `_InfoString`: the trimmed info string, or null.
struct InfoString;

impl InfoString {
    fn parse(text: &[u16]) -> Option<Vec<u16>> {
        let text = dart_trim(text);
        if text.is_empty() {
            return None;
        }
        Some(text.to_vec())
    }
}
