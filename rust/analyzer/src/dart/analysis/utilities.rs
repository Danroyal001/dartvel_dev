// Port of lib/dart/analysis/utilities.dart (`parseString`).

use std::rc::Rc;

use crate::dart::analysis::features::FeatureSet;
use crate::dart::element::element::LibraryLanguageVersion;
use crate::diagnostic::diagnostic::Diagnostic;
use crate::error::listener::RecordingDiagnosticListener;
use crate::source::line_info::LineInfo;
use crate::src::dart::analysis::experiments::ExperimentStatus;
use crate::src::dart::ast::ast_store::{AstStore, NodeId};
use crate::src::dart::scanner::scanner::Scanner;
use crate::src::error::listener::DiagnosticReporter;
use crate::src::generated::parser::Parser;
use fe_analyzer_shared::scanner::token::TokenStore;

/// `ParseStringResult`: the unit, the stores its nodes and tokens live in,
/// and the diagnostics.
pub struct ParseStringResult {
    pub content: Rc<[u16]>,
    pub unit: NodeId,
    pub ast: AstStore,
    pub tokens: TokenStore,
    pub errors: Vec<Diagnostic>,
    pub line_info: LineInfo,
}

/// Returns the result of parsing the given [content] as a compilation unit.
///
/// Diagnostics are always returned in the result; upstream's
/// `throwIfDiagnostics` is not ported.
pub fn parse_string(
    content: Rc<[u16]>,
    feature_set: Option<FeatureSet>,
    path: Option<&str>,
) -> ParseStringResult {
    let feature_set = feature_set.unwrap_or_else(FeatureSet::latest);
    let uri: Rc<str> = Rc::from(path.unwrap_or(""));
    let mut diagnostic_reporter = DiagnosticReporter::new(RecordingDiagnosticListener::default());
    let mut scanner = Scanner::new(content.clone());
    scanner.configure_features(feature_set.clone(), feature_set, None);
    let result = scanner.tokenize(&mut |d| diagnostic_reporter.report(d));
    let language_version = LibraryLanguageVersion {
        package: ExperimentStatus::current_version(),
        override_: scanner.override_version(),
    };
    let line_info = LineInfo::new(scanner.line_starts().to_vec());
    let parser = Parser::new(
        diagnostic_reporter,
        uri,
        result.store,
        scanner.feature_set(),
        language_version,
        line_info.clone(),
    );
    let (mut builder, tokens, unit) = parser.parse_compilation_unit(result.tokens);
    let reporter = builder
        .diagnostic_reporter
        .diagnostic_reporter
        .take()
        .expect("diagnostic reporter");
    ParseStringResult {
        content,
        unit,
        ast: std::mem::take(&mut builder.ast),
        tokens,
        errors: reporter.diagnostic_listener.diagnostics().to_vec(),
        line_info,
    }
}
