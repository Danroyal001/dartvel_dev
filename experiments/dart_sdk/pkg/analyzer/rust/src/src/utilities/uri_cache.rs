// Port of lib/src/utilities/uri_cache.dart, with what it uses of
// `_fe_analyzer_shared`'s util/resolve_relative_uri.dart and of `dart:core`'s
// `Uri`.
//
// Upstream caches the parsed `Uri` objects to share them; here a URI is its
// string, and `Uri` is the subset of `dart:core`'s class that resolving
// directive URIs reads: parsing into scheme, authority, path, query and
// fragment, `isAbsolute`, and `resolveUri` (RFC 3986 section 5.2, with
// `dart:core`'s handling of a base without authority whose path is
// relative).

use std::rc::Rc;

/// A parsed URI reference (`dart:core`'s `Uri`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Uri {
    pub scheme: String,
    pub authority: Option<String>,
    pub path: String,
    pub query: Option<String>,
    pub fragment: Option<String>,
}

fn is_scheme_start(c: u8) -> bool {
    c.is_ascii_alphabetic()
}

fn is_scheme_char(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'+' || c == b'-' || c == b'.'
}

impl Uri {
    /// `Uri.tryParse`: `None` for what `dart:core` rejects that the
    /// analyzer's inputs can contain (an empty scheme, a space, a character
    /// outside ASCII is percent-encoded upstream and kept here).
    pub fn try_parse(text: &str) -> Option<Uri> {
        let bytes = text.as_bytes();
        let mut scheme = String::new();
        let mut rest = text;
        // A scheme is letters, digits, `+`, `-` and `.` up to the first `:`
        // that comes before any `/`, `?` or `#`.
        if let Some(colon) = text.find(':') {
            let head = &bytes[..colon];
            let before_delimiter = !head.iter().any(|&c| c == b'/' || c == b'?' || c == b'#');
            if before_delimiter {
                if colon == 0 || !is_scheme_start(head[0]) || !head.iter().all(|&c| is_scheme_char(c)) {
                    return None;
                }
                scheme = text[..colon].to_ascii_lowercase();
                rest = &text[colon + 1..];
            }
        }
        let mut fragment = None;
        if let Some(hash) = rest.find('#') {
            fragment = Some(rest[hash + 1..].to_string());
            rest = &rest[..hash];
        }
        let mut query = None;
        if let Some(q) = rest.find('?') {
            query = Some(rest[q + 1..].to_string());
            rest = &rest[..q];
        }
        let mut authority = None;
        if let Some(after) = rest.strip_prefix("//") {
            let end = after.find('/').unwrap_or(after.len());
            authority = Some(after[..end].to_string());
            rest = &after[end..];
        }
        Some(Uri {
            scheme,
            authority,
            path: rest.to_string(),
            query,
            fragment,
        })
    }

    /// `isAbsolute` as `resolveRelative` reads it: has a scheme (and no
    /// fragment, which `dart:core` also requires).
    pub fn is_absolute(&self) -> bool {
        !self.scheme.is_empty() && self.fragment.is_none()
    }

    pub fn has_scheme(&self) -> bool {
        !self.scheme.is_empty()
    }

    /// `resolveUri`.
    pub fn resolve_uri(&self, reference: &Uri) -> Uri {
        let (scheme, authority, path, query);
        if reference.has_scheme() {
            scheme = reference.scheme.clone();
            authority = reference.authority.clone();
            path = remove_dot_segments(&reference.path, reference.authority.is_some());
            query = reference.query.clone();
        } else {
            scheme = self.scheme.clone();
            if reference.authority.is_some() {
                authority = reference.authority.clone();
                path = remove_dot_segments(&reference.path, true);
                query = reference.query.clone();
            } else {
                authority = self.authority.clone();
                if reference.path.is_empty() {
                    path = self.path.clone();
                    query = reference.query.clone().or_else(|| self.query.clone());
                } else {
                    if reference.path.starts_with('/') {
                        path = remove_dot_segments(&reference.path, true);
                    } else {
                        let merged = if self.authority.is_some() && self.path.is_empty() {
                            format!("/{}", reference.path)
                        } else {
                            match self.path.rfind('/') {
                                Some(i) => format!("{}{}", &self.path[..i + 1], reference.path),
                                None => reference.path.clone(),
                            }
                        };
                        let absolute = self.authority.is_some() || self.path.starts_with('/');
                        path = remove_dot_segments(&merged, absolute);
                    }
                    query = reference.query.clone();
                }
            }
        }
        Uri {
            scheme,
            authority,
            path,
            query,
            fragment: reference.fragment.clone(),
        }
    }

    pub fn to_string(&self) -> String {
        let mut s = String::new();
        if !self.scheme.is_empty() {
            s.push_str(&self.scheme);
            s.push(':');
        }
        if let Some(authority) = &self.authority {
            s.push_str("//");
            s.push_str(authority);
        }
        s.push_str(&self.path);
        if let Some(query) = &self.query {
            s.push('?');
            s.push_str(query);
        }
        if let Some(fragment) = &self.fragment {
            s.push('#');
            s.push_str(fragment);
        }
        s
    }
}

/// RFC 3986 `remove_dot_segments`; for a relative path (`absolute` false),
/// `dart:core`'s `_normalizeRelativePath`, which keeps leading `..`.
fn remove_dot_segments(path: &str, absolute: bool) -> String {
    if !path.contains('.') {
        return path.to_string();
    }
    let leading_slash = path.starts_with('/');
    let mut output: Vec<&str> = Vec::new();
    let segments: Vec<&str> = path.split('/').collect();
    let start = if leading_slash { 1 } else { 0 };
    let mut append_slash = false;
    for (i, &segment) in segments.iter().enumerate().skip(start) {
        append_slash = false;
        if segment == ".." {
            if !output.is_empty() && output.last() != Some(&"..") {
                output.pop();
                append_slash = true;
            } else if !absolute {
                output.push("..");
            } else {
                append_slash = true;
            }
        } else if segment == "." {
            append_slash = true;
        } else {
            output.push(segment);
        }
        let _ = i;
    }
    if append_slash {
        output.push("");
    }
    let joined = output.join("/");
    if leading_slash {
        format!("/{joined}")
    } else {
        joined
    }
}

/// `resolveRelativeUri` of `_fe_analyzer_shared`: `dart:core` is resolved
/// against as `dart:core/`.
pub fn resolve_relative_uri(base: &Uri, contained: &Uri) -> Uri {
    if contained.is_absolute() {
        return contained.clone();
    }
    let mut base = base.clone();
    if base.scheme == "dart" && !base.path.contains('/') {
        base.path = format!("{}/", base.path);
    }
    base.resolve_uri(contained)
}

/// `UriCache.resolveRelative`, on strings.
pub fn resolve_relative(base: &str, contained: &Uri) -> Rc<str> {
    if contained.is_absolute() {
        return Rc::from(contained.to_string());
    }
    let base = Uri::try_parse(base).expect("a file's URI parses");
    Rc::from(resolve_relative_uri(&base, contained).to_string())
}
