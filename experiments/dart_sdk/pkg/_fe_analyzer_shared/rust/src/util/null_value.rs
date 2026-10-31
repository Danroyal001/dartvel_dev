// Port of lib/src/util/null_value.dart.

/// A null value, marked with the kind of value it stands for. Listeners
/// that build trees push these where a value is absent.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct NullValue(pub &'static str);

impl std::fmt::Display for NullValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "NullValue<{}>", self.0)
    }
}
