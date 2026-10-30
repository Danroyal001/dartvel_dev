// Port of flutter/fml/platform/linux/paths_linux.cc.

use std::os::unix::ffi::OsStrExt;

use crate::unique_fd::UniqueFD;

/// The link /proc/self/exe names, read as upstream reads it: into a
/// PATH_MAX buffer, so a longer target comes back cut at PATH_MAX bytes.
pub fn get_executable_path() -> (bool, Vec<u8>) {
    const PATH_SIZE: usize = 4096; // PATH_MAX
    match std::fs::read_link("/proc/self/exe") {
        Err(_) => (false, Vec::new()),
        Ok(path) => {
            let bytes = path.as_os_str().as_bytes();
            (true, bytes[..bytes.len().min(PATH_SIZE)].to_vec())
        }
    }
}

pub fn get_caches_directory() -> UniqueFD {
    // Unsupported on this platform.
    UniqueFD::default()
}
