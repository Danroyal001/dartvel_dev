// The dartvel CLI's syntax check (not a ported file).
//
// Answers one question per Dart file: does `parseString` report anything?
// The answer comes from the Rust port of the Dart analyzer's `parseString`
// in ../analyzer. This crate never decides that a file is wrong on its own:
// the CLI treats `Flagged` as "ask the Dart analyzer" and `Deferred` as "the
// Rust side did not look", so a gap in the port can cost time and never a
// wrong verdict.
#![forbid(unsafe_code)]

use std::panic::{self, AssertUnwindSafe};
use std::path::Path;
use std::rc::Rc;

use analyzer::dart::analysis::utilities::parse_string;

/// Files larger than this are left to the Dart analyzer. A token costs 28
/// bytes and a node 32, so this bounds the helper's memory at well under a
/// gigabyte; no hand-written Dart file comes near it.
pub const LARGEST_SOURCE_BYTES: usize = 16 * 1024 * 1024;

/// One diagnostic of the parse, as the Dart analyzer names and places it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyntaxDiagnostic {
    /// The analyzer's `uniqueName` of the diagnostic code.
    pub unique_name: String,
    /// Offset in UTF-16 code units, as the analyzer counts.
    pub offset: i32,
    pub length: i32,
    pub message: String,
}

/// Why the Rust side did not look at a file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DeferReason {
    /// The file could not be read.
    Unreadable,
    /// The bytes are not valid UTF-8. Dart decides what that means.
    NotUtf8,
    /// The file starts with a byte order mark, which Dart's decoder drops.
    ByteOrderMark,
    /// Larger than [LARGEST_SOURCE_BYTES].
    TooLarge,
    /// The port panicked. Upstream throws in the same places, and a panic
    /// is also what a slip in the port looks like; either way Dart decides.
    ParserPanic,
    /// Nested deeper than [DEEPEST_NESTING]. The Dart analyzer runs out of
    /// stack on such a file and says so (`stack_overflow`), or throws; this
    /// parser has a larger stack and would not, so it does not answer.
    DeeplyNested,
}

impl DeferReason {
    /// The word the helper prints for this reason.
    pub fn label(self) -> &'static str {
        match self {
            DeferReason::Unreadable => "unreadable",
            DeferReason::NotUtf8 => "not-utf8",
            DeferReason::ByteOrderMark => "byte-order-mark",
            DeferReason::TooLarge => "too-large",
            DeferReason::ParserPanic => "parser-panic",
            DeferReason::DeeplyNested => "deeply-nested",
        }
    }
}

/// What the Rust parser found in one file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SyntaxOutcome {
    /// Parsed with no diagnostic.
    Clean,
    /// Parsed with these diagnostics.
    Flagged(Vec<SyntaxDiagnostic>),
    /// Not looked at.
    Deferred(DeferReason),
}

/// Reads and checks the file at [path].
pub fn check_file(path: &Path) -> SyntaxOutcome {
    match std::fs::read(path) {
        Ok(bytes) => check_source_bytes(&bytes),
        Err(_) => SyntaxOutcome::Deferred(DeferReason::Unreadable),
    }
}

/// Checks the bytes of one Dart file. Never panics.
pub fn check_source_bytes(bytes: &[u8]) -> SyntaxOutcome {
    if bytes.len() > LARGEST_SOURCE_BYTES {
        return SyntaxOutcome::Deferred(DeferReason::TooLarge);
    }
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return SyntaxOutcome::Deferred(DeferReason::ByteOrderMark);
    }
    let Ok(text) = std::str::from_utf8(bytes) else {
        return SyntaxOutcome::Deferred(DeferReason::NotUtf8);
    };
    let code_units: Vec<u16> = text.encode_utf16().collect();
    let parsed = panic::catch_unwind(AssertUnwindSafe(|| {
        let result = parse_string(Rc::from(code_units), None, None);
        if deepest_nesting(&result.ast.parents) > DEEPEST_NESTING {
            return None;
        }
        Some(
            result
                .errors
                .iter()
                .map(|diagnostic| SyntaxDiagnostic {
                    unique_name: diagnostic.diagnostic_code.unique_name.to_string(),
                    offset: diagnostic.offset,
                    length: diagnostic.length,
                    message: diagnostic.message.clone(),
                })
                .collect::<Vec<SyntaxDiagnostic>>(),
        )
    }));
    match parsed {
        Ok(Some(diagnostics)) if diagnostics.is_empty() => SyntaxOutcome::Clean,
        Ok(Some(diagnostics)) => SyntaxOutcome::Flagged(diagnostics),
        Ok(None) => SyntaxOutcome::Deferred(DeferReason::DeeplyNested),
        Err(_) => SyntaxOutcome::Deferred(DeferReason::ParserPanic),
    }
}

/// A syntax tree deeper than this is left to the Dart analyzer. Nothing a
/// person writes comes near it; see `DeferReason::DeeplyNested`.
pub const DEEPEST_NESTING: usize = 500;

/// The depth of the deepest node of a tree given as each node's parent
/// (`AstStore::parents`): a node with no parent is at depth 1.
pub fn deepest_nesting(parents: &[u32]) -> usize {
    const UNKNOWN: u32 = 0;
    let mut depths: Vec<u32> = vec![UNKNOWN; parents.len()];
    let mut deepest: u32 = 0;
    let mut chain: Vec<usize> = Vec::new();
    for start in 0..parents.len() {
        // Walk up until a node whose depth is known, or the root.
        let mut node = start;
        let mut depth_above = 0;
        loop {
            if depths[node] != UNKNOWN {
                depth_above = depths[node];
                break;
            }
            chain.push(node);
            let parent = parents[node] as usize;
            // A parent outside the tree is "no parent"; a walk longer than
            // the tree is a cycle, which a tree does not have.
            if parent >= parents.len() || chain.len() > parents.len() {
                break;
            }
            node = parent;
        }
        while let Some(unresolved) = chain.pop() {
            depth_above += 1;
            depths[unresolved] = depth_above;
        }
        deepest = deepest.max(depths[start]);
    }
    deepest as usize
}

/// The helper's protocol version, first on its greeting line. The CLI
/// refuses a helper that greets with another number.
pub const PROTOCOL_VERSION: u32 = 1;

/// The greeting the helper prints before any result.
pub fn greeting() -> String {
    format!("dartvel_syntax\t{PROTOCOL_VERSION}")
}

/// The lines the helper prints for the file numbered [index].
///
/// `clean`, `flagged` (with the number of diagnostics) or `deferred` (with
/// the reason), tab-separated; with [with_diagnostics], each diagnostic of
/// a flagged file follows on a line of its own.
pub fn result_lines(index: usize, outcome: &SyntaxOutcome, with_diagnostics: bool) -> Vec<String> {
    match outcome {
        SyntaxOutcome::Clean => vec![format!("clean\t{index}")],
        SyntaxOutcome::Deferred(reason) => vec![format!("deferred\t{index}\t{}", reason.label())],
        SyntaxOutcome::Flagged(diagnostics) => {
            let mut lines = vec![format!("flagged\t{index}\t{}", diagnostics.len())];
            if with_diagnostics {
                for diagnostic in diagnostics {
                    lines.push(format!(
                        "diagnostic\t{index}\t{}\t{}\t{}\t{}",
                        diagnostic.unique_name,
                        diagnostic.offset,
                        diagnostic.length,
                        escape_field(&diagnostic.message),
                    ));
                }
            }
            lines
        }
    }
}

/// Keeps a field on one line and in one column: backslash, tab, line feed
/// and carriage return are written as `\\`, `\t`, `\n` and `\r`.
pub fn escape_field(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    for character in text.chars() {
        match character {
            '\\' => escaped.push_str("\\\\"),
            '\t' => escaped.push_str("\\t"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            other => escaped.push(other),
        }
    }
    escaped
}
