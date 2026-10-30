// Port of lib/src/error/listener.dart (`DiagnosticReporter`, the part
// parsing uses).
//
// The reporter owns the listener it reports to, which for parsing is
// always a `RecordingDiagnosticListener`.

use crate::diagnostic::diagnostic::Diagnostic;
use crate::error::listener::RecordingDiagnosticListener;
use crate::src::diagnostic::diagnostic::LocatedDiagnostic;

#[derive(Default, Debug)]
pub struct DiagnosticReporter {
    pub diagnostic_listener: RecordingDiagnosticListener,
    pub lock_level: i32,
}

impl DiagnosticReporter {
    pub fn new(diagnostic_listener: RecordingDiagnosticListener) -> DiagnosticReporter {
        DiagnosticReporter {
            diagnostic_listener,
            lock_level: 0,
        }
    }

    /// Reports a diagnostic located by [LocatedDiagnostic].
    pub fn report(&mut self, located_diagnostic: LocatedDiagnostic) {
        self.report_error(Diagnostic {
            diagnostic_code: located_diagnostic.code,
            offset: located_diagnostic.offset,
            length: located_diagnostic.length,
            arguments: located_diagnostic.arguments,
        });
    }

    /// Report the given [diagnostic].
    pub fn report_error(&mut self, diagnostic: Diagnostic) {
        if self.lock_level != 0 {
            return;
        }
        self.diagnostic_listener.on_diagnostic(diagnostic);
    }
}
