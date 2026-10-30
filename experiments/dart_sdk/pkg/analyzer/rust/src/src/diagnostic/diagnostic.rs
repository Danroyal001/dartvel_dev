// Port of lib/src/diagnostic/diagnostic.dart (the parts parsing uses).
//
// A diagnostic code keeps its `name`, `uniqueName` and the templates of its
// problem and correction messages; a diagnostic made from it carries its
// arguments, as the strings they print as, until the reporter formats the
// messages (see lib/diagnostic/diagnostic.dart).

/// `DiagnosticCode` (in _fe_analyzer_shared's base/errors.dart), as the
/// analyzer's codes are.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct DiagnosticCode {
    pub name: &'static str,
    pub unique_name: &'static str,
    /// `problemMessage`: the template of the problem message.
    pub problem_message: &'static str,
    /// `correctionMessage`: the template of the correction, if any.
    pub correction_message: Option<&'static str>,
}

impl DiagnosticCode {
    /// `DiagnosticWithoutArguments.atOffset`.
    pub fn at_offset(&self, offset: i32, length: i32) -> LocatedDiagnostic {
        self.with_arguments(Vec::new()).at_offset(offset, length)
    }

    /// `DiagnosticWithArguments.withArguments(...)`, with the arguments as
    /// the strings they print as.
    pub fn with_arguments(&self, arguments: Vec<String>) -> LocatableDiagnostic {
        LocatableDiagnostic {
            code: *self,
            arguments,
        }
    }
}

/// A diagnostic code with its arguments, not yet located.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct LocatableDiagnostic {
    pub code: DiagnosticCode,
    pub arguments: Vec<String>,
}

impl LocatableDiagnostic {
    pub fn at_offset(self, offset: i32, length: i32) -> LocatedDiagnostic {
        LocatedDiagnostic {
            code: self.code,
            arguments: self.arguments,
            offset,
            length,
        }
    }
}

/// A diagnostic code with its arguments and location.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct LocatedDiagnostic {
    pub code: DiagnosticCode,
    pub arguments: Vec<String>,
    pub offset: i32,
    pub length: i32,
}
