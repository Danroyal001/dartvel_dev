// Port of flutter/fml/string_conversion.h and flutter/fml/string_conversion.cc.
//
// Upstream converts with std::wstring_convert<std::codecvt_utf8_utf16<char16_t>>
// which, in libc++ (the engine's C++ library), is a strict converter: it
// throws std::range_error on any ill-formed input (overlong forms, encoded
// surrogates, code points past U+10FFFF, truncated sequences, unpaired
// surrogates) and passes a byte order mark through as U+FEFF. The `try_`
// functions return that failure; the others panic with libc++'s message,
// where upstream throws.
//
// Upstream slip, kept: both functions hand the converter `string.data()`,
// a bare pointer read up to the first NUL, so input is cut at the first NUL
// (and a view that is not NUL-terminated reads past its end, which the port
// does not reproduce: it stops at the end of the slice).

use std::path::Path;

/// `std::range_error` thrown by `std::wstring_convert`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RangeError(pub &'static str);

impl std::fmt::Display for RangeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}

impl std::error::Error for RangeError {}

/// Returns a string joined by the given delimiter.
pub fn join<S: AsRef<str>>(vec: &[S], delimiter: &str) -> String {
    let mut res = String::new();
    for (i, s) in vec.iter().enumerate() {
        res.push_str(s.as_ref());
        if i < vec.len() - 1 {
            res.push_str(delimiter);
        }
    }
    res
}

fn up_to_nul<T: Copy + PartialEq + Default>(s: &[T]) -> &[T] {
    let zero = T::default();
    match s.iter().position(|&c| c == zero) {
        Some(n) => &s[..n],
        None => s,
    }
}

/// Returns a UTF-8 encoded equivalent of a UTF-16 encoded input string.
pub fn try_utf16_to_utf8(string: &[u16]) -> Result<String, RangeError> {
    String::from_utf16(up_to_nul(string)).map_err(|_| RangeError("wstring_convert: to_bytes error"))
}

/// Returns a UTF-16 encoded equivalent of a UTF-8 encoded input string.
pub fn try_utf8_to_utf16(string: &[u8]) -> Result<Vec<u16>, RangeError> {
    match std::str::from_utf8(up_to_nul(string)) {
        Ok(s) => Ok(s.encode_utf16().collect()),
        Err(_) => Err(RangeError("wstring_convert: from_bytes error")),
    }
}

/// Returns a UTF-8 encoded equivalent of a UTF-16 encoded input string.
pub fn utf16_to_utf8(string: &[u16]) -> String {
    try_utf16_to_utf8(string).unwrap_or_else(|e| panic!("{e}"))
}

/// Returns a UTF-16 encoded equivalent of a UTF-8 encoded input string.
pub fn utf8_to_utf16(string: impl AsRef<[u8]>) -> Vec<u16> {
    try_utf8_to_utf16(string.as_ref()).unwrap_or_else(|e| panic!("{e}"))
}

/// Returns the pathname encoded in UTF-8 (`path.u8string()`): on POSIX the
/// path's bytes as they are.
pub fn path_to_utf8(path: &Path) -> Vec<u8> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        path.as_os_str().as_bytes().to_vec()
    }
    #[cfg(not(unix))]
    {
        path.to_string_lossy().into_owned().into_bytes()
    }
}
