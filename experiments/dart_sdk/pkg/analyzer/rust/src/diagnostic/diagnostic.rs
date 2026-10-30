// Port of lib/diagnostic/diagnostic.dart (`Diagnostic` only).

use crate::src::diagnostic::diagnostic::DiagnosticCode;

/// A diagnostic, as reported by the analyzer.
///
/// Upstream two diagnostics are equal when their code, offset, length,
/// message and source are; the message is the code's template applied to
/// [arguments], so here the arguments stand for it.
#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub struct Diagnostic {
    pub diagnostic_code: DiagnosticCode,
    pub offset: i32,
    pub length: i32,
    pub arguments: Vec<String>,
}
