// Port of lib/src/context/packages.dart: `Packages` read from a
// `package_config.json` file.
//
// Upstream reads the file with package:package_config; here the JSON is read
// by the small reader below, which accepts what that format uses (objects,
// arrays, strings with escapes, numbers, booleans and null). A package is
// its name and the folders of its root and its `lib`; `languageVersion` is
// not read yet (every library is parsed at the latest language version).

use std::path::{Path, PathBuf};
use std::rc::Rc;

use crate::src::utilities::uri_cache::{Uri, resolve_relative_uri};

/// `Package`.
#[derive(Clone, Debug)]
pub struct Package {
    pub name: Rc<str>,
    pub root_folder: PathBuf,
    pub lib_folder: PathBuf,
}

/// `Packages`.
#[derive(Clone, Debug, Default)]
pub struct Packages {
    pub packages: Vec<Package>,
}

impl Packages {
    /// `operator []`.
    pub fn get(&self, name: &str) -> Option<&Package> {
        self.packages.iter().find(|p| &*p.name == name)
    }
}

/// `parsePackageConfigJsonFile`: the packages of [file], or none when it
/// cannot be read or parsed.
pub fn parse_package_config_json_file(file: &Path) -> Packages {
    let Ok(content) = std::fs::read_to_string(file) else {
        return Packages::default();
    };
    let Some(json) = Json::parse(&content) else {
        return Packages::default();
    };
    let config_uri = Uri::try_parse(&format!("file://{}", file.display())).unwrap();
    let mut packages = Vec::new();
    let Some(Json::Array(list)) = json.get("packages") else {
        return Packages::default();
    };
    for entry in list {
        let (Some(Json::String(name)), Some(Json::String(root_uri))) =
            (entry.get("name"), entry.get("rootUri"))
        else {
            continue;
        };
        let mut root = root_uri.clone();
        if !root.ends_with('/') {
            root.push('/');
        }
        let root = resolve_relative_uri(&config_uri, &Uri::try_parse(&root).unwrap());
        let package_uri = match entry.get("packageUri") {
            Some(Json::String(s)) => s.clone(),
            _ => String::new(),
        };
        let lib = resolve_relative_uri(&root, &Uri::try_parse(&package_uri).unwrap());
        packages.push(Package {
            name: Rc::from(name.as_str()),
            root_folder: normalized_path(&root.path),
            lib_folder: normalized_path(&lib.path),
        });
    }
    Packages { packages }
}

/// `fileUriToNormalizedPath`: the path, without a trailing separator.
fn normalized_path(path: &str) -> PathBuf {
    PathBuf::from(path.strip_suffix('/').unwrap_or(path))
}

/// A JSON value.
#[derive(Clone, Debug)]
pub enum Json {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    pub fn parse(text: &str) -> Option<Json> {
        let mut reader = JsonReader { bytes: text.as_bytes(), pos: 0 };
        let value = reader.value()?;
        reader.skip_whitespace();
        if reader.pos != reader.bytes.len() {
            return None;
        }
        Some(value)
    }

    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Object(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
}

struct JsonReader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl JsonReader<'_> {
    fn skip_whitespace(&mut self) {
        while self.pos < self.bytes.len() && matches!(self.bytes[self.pos], b' ' | b'\t' | b'\n' | b'\r') {
            self.pos += 1;
        }
    }

    fn peek(&mut self) -> Option<u8> {
        self.skip_whitespace();
        self.bytes.get(self.pos).copied()
    }

    fn expect(&mut self, literal: &str) -> Option<()> {
        if self.bytes[self.pos..].starts_with(literal.as_bytes()) {
            self.pos += literal.len();
            Some(())
        } else {
            None
        }
    }

    fn value(&mut self) -> Option<Json> {
        match self.peek()? {
            b'{' => {
                self.pos += 1;
                let mut entries = Vec::new();
                if self.peek()? == b'}' {
                    self.pos += 1;
                    return Some(Json::Object(entries));
                }
                loop {
                    if self.peek()? != b'"' {
                        return None;
                    }
                    let key = self.string()?;
                    if self.peek()? != b':' {
                        return None;
                    }
                    self.pos += 1;
                    let value = self.value()?;
                    entries.push((key, value));
                    match self.peek()? {
                        b',' => self.pos += 1,
                        b'}' => {
                            self.pos += 1;
                            return Some(Json::Object(entries));
                        }
                        _ => return None,
                    }
                }
            }
            b'[' => {
                self.pos += 1;
                let mut values = Vec::new();
                if self.peek()? == b']' {
                    self.pos += 1;
                    return Some(Json::Array(values));
                }
                loop {
                    values.push(self.value()?);
                    match self.peek()? {
                        b',' => self.pos += 1,
                        b']' => {
                            self.pos += 1;
                            return Some(Json::Array(values));
                        }
                        _ => return None,
                    }
                }
            }
            b'"' => self.string().map(Json::String),
            b't' => self.expect("true").map(|_| Json::Bool(true)),
            b'f' => self.expect("false").map(|_| Json::Bool(false)),
            b'n' => self.expect("null").map(|_| Json::Null),
            _ => {
                let start = self.pos;
                while self.pos < self.bytes.len()
                    && matches!(self.bytes[self.pos], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9')
                {
                    self.pos += 1;
                }
                std::str::from_utf8(&self.bytes[start..self.pos]).ok()?.parse().ok().map(Json::Number)
            }
        }
    }

    fn string(&mut self) -> Option<String> {
        self.pos += 1;
        let mut units: Vec<u16> = Vec::new();
        loop {
            let c = *self.bytes.get(self.pos)?;
            self.pos += 1;
            match c {
                b'"' => return String::from_utf16(&units).ok(),
                b'\\' => {
                    let e = *self.bytes.get(self.pos)?;
                    self.pos += 1;
                    match e {
                        b'"' => units.push(b'"' as u16),
                        b'\\' => units.push(b'\\' as u16),
                        b'/' => units.push(b'/' as u16),
                        b'b' => units.push(8),
                        b'f' => units.push(12),
                        b'n' => units.push(b'\n' as u16),
                        b'r' => units.push(b'\r' as u16),
                        b't' => units.push(b'\t' as u16),
                        b'u' => {
                            let hex = std::str::from_utf8(self.bytes.get(self.pos..self.pos + 4)?).ok()?;
                            units.push(u16::from_str_radix(hex, 16).ok()?);
                            self.pos += 4;
                        }
                        _ => return None,
                    }
                }
                _ => {
                    // Copy the UTF-8 sequence that starts here.
                    let start = self.pos - 1;
                    let mut end = self.pos;
                    while end < self.bytes.len() && (self.bytes[end] & 0xC0) == 0x80 {
                        end += 1;
                    }
                    let s = std::str::from_utf8(&self.bytes[start..end]).ok()?;
                    units.extend(s.encode_utf16());
                    self.pos = end;
                }
            }
        }
    }
}
