// Not an upstream file: the port's stand-in for libc++'s `std::string` where
// its short-string optimisation decides the cost.
//
// libc++ keeps a string of up to 22 bytes inside the `std::string` itself, so
// copying a command line's short options and arguments never allocates. A
// Rust `String` always does. `SmallString` keeps the same 22 bytes inline and
// only puts longer text on the heap; it reads as a `str` and compares equal to
// `str` and `String`, so it is the `std::string` of the APIs that hold many
// short strings (`CommandLine`). It is immutable: whoever needs to edit text
// takes a `String`.

use std::borrow::Borrow;
use std::cmp::Ordering;
use std::fmt;
use std::hash::{Hash, Hasher};
use std::ops::Deref;

/// The longest text kept inline, libc++'s short-string capacity.
const INLINE: usize = 22;

#[derive(Clone)]
enum Repr {
    /// `len` bytes at the start of `buf`, copied whole from a `str`.
    Inline(u8, [u8; INLINE]),
    Heap(Box<str>),
}

/// A string of up to 22 bytes held without an allocation (see the file
/// comment).
#[derive(Clone)]
pub struct SmallString(Repr);

impl SmallString {
    pub const fn new() -> SmallString {
        SmallString(Repr::Inline(0, [0; INLINE]))
    }

    /// The concatenation of `parts`, inline when it fits.
    pub fn concat(parts: &[&str]) -> SmallString {
        let len: usize = parts.iter().map(|p| p.len()).sum();
        if len <= INLINE {
            let mut buf = [0u8; INLINE];
            let mut at = 0;
            for part in parts {
                buf[at..at + part.len()].copy_from_slice(part.as_bytes());
                at += part.len();
            }
            return SmallString(Repr::Inline(len as u8, buf));
        }
        let mut s = String::with_capacity(len);
        for part in parts {
            s.push_str(part);
        }
        SmallString(Repr::Heap(s.into_boxed_str()))
    }

    #[inline]
    pub fn as_str(&self) -> &str {
        match &self.0 {
            Repr::Inline(len, buf) => {
                let bytes = &buf[..*len as usize];
                // SAFETY: an Inline repr is only made by `from(&str)` and
                // `concat`, which copy the whole of one or more `str`s, so
                // `bytes` is a concatenation of complete UTF-8 strings and
                // so is UTF-8. Verified by the unit tests below and, under
                // debug assertions, by the check here.
                debug_assert!(std::str::from_utf8(bytes).is_ok());
                unsafe { std::str::from_utf8_unchecked(bytes) }
            }
            Repr::Heap(s) => s,
        }
    }
}

impl Default for SmallString {
    fn default() -> SmallString {
        SmallString::new()
    }
}

impl From<&str> for SmallString {
    #[inline]
    fn from(s: &str) -> SmallString {
        if s.len() <= INLINE {
            let mut buf = [0u8; INLINE];
            buf[..s.len()].copy_from_slice(s.as_bytes());
            SmallString(Repr::Inline(s.len() as u8, buf))
        } else {
            SmallString(Repr::Heap(s.into()))
        }
    }
}

impl From<&String> for SmallString {
    fn from(s: &String) -> SmallString {
        SmallString::from(s.as_str())
    }
}

impl From<String> for SmallString {
    fn from(s: String) -> SmallString {
        if s.len() <= INLINE { SmallString::from(s.as_str()) } else { SmallString(Repr::Heap(s.into_boxed_str())) }
    }
}

impl From<&SmallString> for SmallString {
    fn from(s: &SmallString) -> SmallString {
        s.clone()
    }
}

impl From<SmallString> for String {
    fn from(s: SmallString) -> String {
        match s.0 {
            Repr::Heap(s) => s.into_string(),
            Repr::Inline(..) => s.as_str().to_string(),
        }
    }
}

impl Deref for SmallString {
    type Target = str;
    #[inline]
    fn deref(&self) -> &str {
        self.as_str()
    }
}

impl AsRef<str> for SmallString {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}

impl AsRef<[u8]> for SmallString {
    fn as_ref(&self) -> &[u8] {
        self.as_str().as_bytes()
    }
}

impl Borrow<str> for SmallString {
    fn borrow(&self) -> &str {
        self.as_str()
    }
}

impl fmt::Debug for SmallString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self.as_str(), f)
    }
}

impl fmt::Display for SmallString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(self.as_str(), f)
    }
}

impl Hash for SmallString {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.as_str().hash(state)
    }
}

impl PartialEq for SmallString {
    #[inline]
    fn eq(&self, other: &SmallString) -> bool {
        self.as_str() == other.as_str()
    }
}

impl Eq for SmallString {}

impl PartialOrd for SmallString {
    fn partial_cmp(&self, other: &SmallString) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SmallString {
    fn cmp(&self, other: &SmallString) -> Ordering {
        self.as_str().cmp(other.as_str())
    }
}

macro_rules! eq_with {
    ($($t:ty),*) => {$(
        impl PartialEq<$t> for SmallString {
            #[inline]
            fn eq(&self, other: &$t) -> bool {
                self.as_str() == &other[..]
            }
        }
        impl PartialEq<SmallString> for $t {
            #[inline]
            fn eq(&self, other: &SmallString) -> bool {
                &self[..] == other.as_str()
            }
        }
    )*};
}
eq_with!(str, &str, String);

#[cfg(test)]
mod tests {
    use super::SmallString;

    #[test]
    fn inline_and_heap_read_back() {
        for text in ["", "a", "\u{e9}t\u{e9}", "exactly-22-bytes-long!", "twenty-three bytes long", &"x".repeat(300)] {
            let s = SmallString::from(text);
            assert_eq!(s, text);
            assert_eq!(s.len(), text.len());
            assert_eq!(SmallString::from(text.to_string()), text);
            assert_eq!(String::from(s.clone()), text);
        }
    }

    #[test]
    fn concat_joins_parts() {
        assert_eq!(SmallString::concat(&["--", "a", "=", "b"]), "--a=b");
        assert_eq!(SmallString::concat(&[]), "");
        let long = "y".repeat(40);
        assert_eq!(SmallString::concat(&["--", &long]), format!("--{long}"));
        assert_eq!(SmallString::concat(&["\u{e9}", "\u{fc}"]), "\u{e9}\u{fc}");
    }

    #[test]
    fn compares_as_str() {
        let a = SmallString::from("abc");
        assert!(a == *"abc" && "abc" == a && a == String::from("abc") && String::from("abc") == a);
        assert!(SmallString::from("abc") < SmallString::from("abd"));
        assert_eq!(SmallString::default(), "");
    }
}
