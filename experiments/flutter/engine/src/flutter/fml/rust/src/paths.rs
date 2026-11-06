// Port of flutter/fml/paths.h and flutter/fml/paths.cc.
//
// The POSIX parts (AbsolutePath, GetDirectoryName, FromURI) are in
// platform/posix/paths_posix.rs and the Linux ones (GetExecutablePath,
// GetCachesDirectory) in platform/linux/paths_linux.rs, re-exported here.
// Paths are byte strings, as upstream's std::string is: an escape such as
// %FF yields a byte that is not UTF-8.

pub use crate::platform::posix::paths_posix::*;
#[cfg(target_os = "linux")]
pub use crate::platform::linux::paths_linux::*;

/// `JoinPaths({...})`: the components joined with '/'.
pub fn join_paths(components: &[impl AsRef<[u8]>]) -> Vec<u8> {
    let mut stream = Vec::new();
    let mut i = 0;
    let size = components.len();
    for component in components {
        i += 1;
        stream.extend_from_slice(component.as_ref());
        if i != size {
            stream.push(b'/');
        }
    }
    stream
}

pub fn sanitize_uri_escaped_characters(str: impl AsRef<[u8]>) -> Vec<u8> {
    let str = str.as_ref();
    let mut result = Vec::with_capacity(str.len());
    let mut i = 0;
    while i < str.len() {
        if str[i] == b'%' {
            // Upstream reads str[i + 1] and str[i + 2], where an index equal
            // to the size reads std::string's terminating NUL, which is not
            // a hex digit; `i > str.size() - 3` wraps for strings shorter
            // than three bytes, leaving those reads to reject them.
            let hex1 = str.get(i + 1).copied().unwrap_or(0);
            let hex2 = str.get(i + 2).copied().unwrap_or(0);
            if !hex1.is_ascii_hexdigit() || !hex2.is_ascii_hexdigit() {
                return Vec::new();
            }
            let c = (hex_value(hex1) << 4) | hex_value(hex2);
            if c == 0 {
                return Vec::new();
            }
            result.push(c);
            i += 2;
        } else {
            result.push(str[i]);
        }
        i += 1;
    }
    result
}

fn hex_value(c: u8) -> u8 {
    match c {
        b'0'..=b'9' => c - b'0',
        b'a'..=b'f' => c - b'a' + 10,
        _ => c - b'A' + 10,
    }
}

pub fn get_executable_directory_path() -> (bool, Vec<u8>) {
    let path = get_executable_path();
    if !path.0 {
        return (false, Vec::new());
    }
    (true, get_directory_name(&path.1))
}
