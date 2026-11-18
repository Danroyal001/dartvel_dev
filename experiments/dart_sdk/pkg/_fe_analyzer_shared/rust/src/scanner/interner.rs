// Port of lib/src/scanner/interner.dart.

/// Interns strings, so that equal strings share one instance.
pub trait Interner {
    fn intern(&self, string: String) -> String;
}

/// The interner that does nothing.
pub struct NullInterner;

impl Interner for NullInterner {
    fn intern(&self, string: String) -> String {
        string
    }
}
