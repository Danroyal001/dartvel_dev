// Port of lib/dart/element/nullability_suffix.dart.

/// Suffix indicating the nullability of a type.
#[allow(non_camel_case_types)]
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum NullabilitySuffix {
    /// An indication that the canonical representation of the type under
    /// consideration ends with `?`.
    question,
    /// An indication that the canonical representation of the type under
    /// consideration ends with `*` (legacy, no longer produced).
    star,
    /// An indication that the canonical representation of the type under
    /// consideration does not end with either `?` or `*`.
    none,
}
