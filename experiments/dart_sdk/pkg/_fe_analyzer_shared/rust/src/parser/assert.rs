// Port of lib/src/parser/assert.dart.

/// Syntactic forms of `assert`.
///
/// An assertion can legally occur as a statement. However, assertions are also
/// experimentally allowed in initializers. For improved error recovery, we
/// also attempt to parse asserts as expressions.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Assert {
    Expression,
    Initializer,
    Statement,
}

impl std::fmt::Display for Assert {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Assert.{self:?}")
    }
}
