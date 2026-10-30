// Port of lib/src/parser/member_kind.dart.

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MemberKind {
    /// A catch block, not a real member.
    Catch,

    /// A factory
    Factory,

    /// Old-style typedef.
    FunctionTypeAlias,

    /// Old-style function-typed parameter, not a real member.
    FunctionTypedParameter,

    /// A generalized function type, not a real member.
    GeneralizedFunctionType,

    /// A local function.
    Local,

    /// An anonymous method.
    AnonymousMethod,

    /// A non-static method in a class (including constructors).
    NonStaticMethod,

    /// A static method in a class.
    StaticMethod,

    /// A top-level method.
    TopLevelMethod,

    /// A non-static method in an extension.
    ExtensionNonStaticMethod,

    /// A static method in an extension.
    ExtensionStaticMethod,

    /// A non-static method or constructor in an extension type.
    // TODO(johnniwinther): Can we separate constructors from instance methods?
    ExtensionTypeNonStaticMethod,

    /// A static method in an extension type.
    ExtensionTypeStaticMethod,

    /// An instance field in a class.
    NonStaticField,

    /// A static field in a class.
    StaticField,

    /// A top-level field.
    TopLevelField,

    /// Primary constructor.
    PrimaryConstructor,
}

impl std::fmt::Display for MemberKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "MemberKind.{self:?}")
    }
}
