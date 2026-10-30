// Port of flutter/fml/platform/posix/paths_posix.cc.

use crate::fml_check_at;
use crate::platform::posix::libc;

const FILE: &str = "flutter/fml/platform/posix/paths_posix.cc";

const K_FILE_URL_PREFIX: &[u8] = b"file://";

/// `GetCurrentDirectory()` followed by `suffix`: getcwd into a PATH_MAX
/// buffer, as upstream calls it (so a longer working directory fails the
/// check, as upstream's does), copied out once into a string with room for
/// what `AbsolutePath` appends.
fn get_current_directory_then(suffix: &[&[u8]]) -> Vec<u8> {
    const PATH_MAX: usize = 4096;
    let mut buffer = [0u8; PATH_MAX];
    // SAFETY: `buffer` is PATH_MAX writable bytes and getcwd is told so; it
    // writes at most that many, NUL included, and keeps no pointer.
    let ok = !unsafe { libc::getcwd(buffer.as_mut_ptr().cast(), buffer.len()) }.is_null();
    fml_check_at!(FILE, 23, "getcwd(buffer, sizeof(buffer))", ok);
    let len = buffer.iter().position(|&c| c == 0).unwrap_or(PATH_MAX);
    let mut result = Vec::with_capacity(len + suffix.iter().map(|s| s.len()).sum::<usize>());
    result.extend_from_slice(&buffer[..len]);
    for part in suffix {
        result.extend_from_slice(part);
    }
    result
}

pub fn absolute_path(path: impl AsRef<[u8]>) -> Vec<u8> {
    let path = path.as_ref();
    if !path.is_empty() {
        if path[0] == b'/' {
            // Path is already absolute.
            return path.to_vec();
        }
        get_current_directory_then(&[b"/", path])
    } else {
        // Path is empty.
        get_current_directory_then(&[])
    }
}

pub fn get_directory_name(path: impl AsRef<[u8]>) -> Vec<u8> {
    let path = path.as_ref();
    match path.iter().rposition(|&c| c == b'/') {
        Some(0) => b"/".to_vec(),
        None => Vec::new(),
        Some(separator) => path[..separator].to_vec(),
    }
}

pub fn from_uri(uri: impl AsRef<[u8]>) -> Vec<u8> {
    let uri = uri.as_ref();
    if !uri.starts_with(K_FILE_URL_PREFIX) {
        return uri.to_vec();
    }

    let file_path = &uri[K_FILE_URL_PREFIX.len()..];
    crate::paths::sanitize_uri_escaped_characters(file_path)
}
