// Port of lib/dart/element/element.dart (`LibraryLanguageVersion` only).

/// The language version of a library: the version of its package, and the
/// version a `// @dart = x.y` comment overrides it with.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct LibraryLanguageVersion {
    pub package: (i64, i64),
    pub override_: Option<(i64, i64)>,
}

impl LibraryLanguageVersion {
    pub fn effective(&self) -> (i64, i64) {
        self.override_.unwrap_or(self.package)
    }
}
