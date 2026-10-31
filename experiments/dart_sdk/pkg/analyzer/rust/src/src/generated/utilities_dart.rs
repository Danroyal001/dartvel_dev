// Port of lib/src/generated/utilities_dart.dart (`ParameterKind` only).
#![allow(non_camel_case_types)]

/// The kind of a parameter. A parameter can be either positional or named,
/// and can be either required or optional.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ParameterKind {
    /// A positional required parameter.
    REQUIRED,
    /// A positional optional parameter.
    POSITIONAL,
    /// A named required parameter.
    NAMED_REQUIRED,
    /// A named optional parameter.
    NAMED,
}

impl ParameterKind {
    pub fn name(self) -> &'static str {
        match self {
            ParameterKind::REQUIRED => "REQUIRED",
            ParameterKind::POSITIONAL => "POSITIONAL",
            ParameterKind::NAMED_REQUIRED => "NAMED_REQUIRED",
            ParameterKind::NAMED => "NAMED",
        }
    }

    pub fn is_positional(self) -> bool {
        matches!(self, ParameterKind::REQUIRED | ParameterKind::POSITIONAL)
    }

    pub fn is_required_positional(self) -> bool {
        self == ParameterKind::REQUIRED
    }

    pub fn is_optional_positional(self) -> bool {
        self == ParameterKind::POSITIONAL
    }

    pub fn is_named(self) -> bool {
        matches!(self, ParameterKind::NAMED_REQUIRED | ParameterKind::NAMED)
    }

    pub fn is_required_named(self) -> bool {
        self == ParameterKind::NAMED_REQUIRED
    }

    pub fn is_optional_named(self) -> bool {
        self == ParameterKind::NAMED
    }

    pub fn is_required(self) -> bool {
        matches!(
            self,
            ParameterKind::REQUIRED | ParameterKind::NAMED_REQUIRED
        )
    }

    pub fn is_optional(self) -> bool {
        matches!(self, ParameterKind::POSITIONAL | ParameterKind::NAMED)
    }
}
