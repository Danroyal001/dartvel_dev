// Port of lib/src/parser/formal_parameter_kind.dart.
#![allow(non_camel_case_types)]

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FormalParameterKind {
    requiredPositional,
    requiredNamed,
    optionalNamed,
    optionalPositional,
}

impl FormalParameterKind {
    pub fn is_required_positional(self) -> bool {
        FormalParameterKind::requiredPositional == self
    }

    pub fn is_optional_named(self) -> bool {
        FormalParameterKind::optionalNamed == self
    }

    pub fn is_optional_positional(self) -> bool {
        FormalParameterKind::optionalPositional == self
    }

    pub fn is_required_named(self) -> bool {
        FormalParameterKind::requiredNamed == self
    }

    pub fn is_required(self) -> bool {
        self.is_required_positional() || self.is_required_named()
    }

    pub fn is_optional(self) -> bool {
        self.is_optional_positional() || self.is_optional_named()
    }

    pub fn is_positional(self) -> bool {
        self.is_required_positional() || self.is_optional_positional()
    }

    pub fn is_named(self) -> bool {
        self.is_required_named() || self.is_optional_named()
    }
}

impl std::fmt::Display for FormalParameterKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "FormalParameterKind.{self:?}")
    }
}
