// Port of lib/error/listener.dart (`RecordingDiagnosticListener`).

use std::collections::HashSet;

use crate::diagnostic::diagnostic::Diagnostic;

/// A diagnostic listener that records the diagnostics that are reported to
/// it, once each (upstream keeps them in a `Set`, in insertion order).
#[derive(Default, Debug)]
pub struct RecordingDiagnosticListener {
    seen: HashSet<Diagnostic>,
    diagnostics: Vec<Diagnostic>,
}

impl RecordingDiagnosticListener {
    pub fn diagnostics(&self) -> &[Diagnostic] {
        &self.diagnostics
    }

    pub fn on_diagnostic(&mut self, diagnostic: Diagnostic) {
        if self.seen.insert(diagnostic.clone()) {
            self.diagnostics.push(diagnostic);
        }
    }
}
