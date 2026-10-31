// Port of lib/src/parser/constructor_reference_context.dart.

/// Enum for the context in which a constructor occurs
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ConstructorReferenceContext {
    /// A constructor reference in the context of a constructor invocation with
    /// an explicit `new`.
    New,

    /// A constructor reference in the context of a constant constructor
    /// invocation with an explicit `const`.
    Const,

    /// A constructor reference in the context of a constructor invocation with an
    /// implicit `new` or `const`.
    Implicit,

    /// A constructor reference in the context of a redirecting factory body.
    RedirectingFactory,
}

impl std::fmt::Display for ConstructorReferenceContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ConstructorReferenceContext.{self:?}")
    }
}
