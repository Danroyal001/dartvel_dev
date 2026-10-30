// Port of flutter/fml/platform/posix/paths_posix.cc.

use std::os::unix::ffi::OsStrExt;

use crate::fml_check_at;

const FILE: &str = "flutter/fml/platform/posix/paths_posix.cc";

const K_FILE_URL_PREFIX: &[u8] = b"file://";

fn get_current_directory() -> Vec<u8> {
    // std's current_dir calls getcwd, growing its buffer past PATH_MAX where
    // upstream's fixed buffer would fail the check; a working directory that
    // long is not one the engine runs in.
    let buffer = std::env::current_dir();
    fml_check_at!(FILE, 23, "getcwd(buffer, sizeof(buffer))", buffer.is_ok());
    buffer.unwrap().as_os_str().as_bytes().to_vec()
}

pub fn absolute_path(path: impl AsRef<[u8]>) -> Vec<u8> {
    let path = path.as_ref();
    if !path.is_empty() {
        if path[0] == b'/' {
            // Path is already absolute.
            return path.to_vec();
        }
        let mut result = get_current_directory();
        result.push(b'/');
        result.extend_from_slice(path);
        result
    } else {
        // Path is empty.
        get_current_directory()
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
