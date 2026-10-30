// Port of lib/diagnostic/diagnostic.dart (`Diagnostic` only).

use std::hash::{Hash, Hasher};

use fe_analyzer_shared::base::errors::format_list;

use crate::src::diagnostic::diagnostic::DiagnosticCode;

/// A diagnostic, as reported by the analyzer.
#[derive(Clone, Debug)]
pub struct Diagnostic {
    pub diagnostic_code: DiagnosticCode,
    pub offset: i32,
    pub length: i32,
    /// The message to be displayed for this diagnostic.
    pub message: String,
    /// The correction to be displayed for this diagnostic, if any.
    pub correction_message: Option<String>,
}

impl Diagnostic {
    /// `Diagnostic.tmp`: the messages are the code's templates applied to
    /// the [arguments].
    pub fn tmp(
        offset: i32,
        length: i32,
        diagnostic_code: DiagnosticCode,
        arguments: &[String],
    ) -> Diagnostic {
        let format = |template: &str| {
            let pattern: Vec<u16> = template.encode_utf16().collect();
            String::from_utf16_lossy(&format_list(&pattern, arguments))
        };
        Diagnostic {
            diagnostic_code,
            offset,
            length,
            message: format(diagnostic_code.problem_message),
            correction_message: diagnostic_code.correction_message.map(format),
        }
    }
}

/// Two diagnostics are equal when their codes, offsets, lengths and
/// messages are (and their sources, which here are always the same).
impl PartialEq for Diagnostic {
    fn eq(&self, other: &Diagnostic) -> bool {
        self.diagnostic_code == other.diagnostic_code
            && self.offset == other.offset
            && self.length == other.length
            && self.message == other.message
    }
}

impl Eq for Diagnostic {}

impl Hash for Diagnostic {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.offset.hash(state);
        self.message.hash(state);
    }
}
