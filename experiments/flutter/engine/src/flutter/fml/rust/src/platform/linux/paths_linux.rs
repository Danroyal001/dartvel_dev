// Port of flutter/fml/platform/linux/paths_linux.cc.

use crate::platform::posix::libc;
use crate::unique_fd::UniqueFD;

/// The link /proc/self/exe names, read as upstream reads it: into a
/// PATH_MAX buffer, so a longer target comes back cut at PATH_MAX bytes.
pub fn get_executable_path() -> (bool, Vec<u8>) {
    const PATH_SIZE: usize = 4096; // PATH_MAX
    let mut path = [0u8; PATH_SIZE];
    // SAFETY: the name is a NUL-terminated literal and `path` is PATH_SIZE
    // writable bytes, the size readlink is given; it keeps no pointer.
    let read_size =
        unsafe { libc::readlink(c"/proc/self/exe".as_ptr(), path.as_mut_ptr().cast(), PATH_SIZE) };
    if read_size == -1 {
        return (false, Vec::new());
    }
    (true, path[..read_size as usize].to_vec())
}

pub fn get_caches_directory() -> UniqueFD {
    // Unsupported on this platform.
    UniqueFD::default()
}
