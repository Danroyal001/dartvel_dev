// Port of lib/src/parser/declaration_kind.dart.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum DeclarationKind {
    /// A top level declaration.
    TopLevel,

    /// A class declaration. Not including a named mixin declaration.
    Class,

    /// A mixin declaration. Not including a named mixin declaration.
    Mixin,

    /// An extension declaration.
    Extension,

    /// An extension type declaration.
    ExtensionType,

    /// An enum.
    Enum,
}

impl std::fmt::Display for DeclarationKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "DeclarationKind.{self:?}")
    }
}

/// Enum to specify in which declaration a header occurs.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum DeclarationHeaderKind {
    /// Class declaration header, for instance `extends S with M implements I`.
    Class,

    /// Extension type declaration header, for instance `implements I`.
    ExtensionType,
}

impl std::fmt::Display for DeclarationHeaderKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "DeclarationHeaderKind.{self:?}")
    }
}
