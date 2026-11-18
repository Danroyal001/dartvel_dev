// Port of flutter/fml/file.h and flutter/fml/file.cc.
//
// The POSIX definitions of what file.h declares are in
// platform/posix/file_posix.rs (upstream's platform/posix/file_posix.cc) and
// re-exported here, so callers name them `fml::file::...` as upstream names
// them `fml::...`.
//
// Paths are byte strings (`impl AsRef<[u8]>`: `&str`, `String`, `&[u8]`,
// `Vec<u8>` all work), handed to the C library as upstream hands it a
// `const char*`: up to the first NUL. A null path, which upstream answers with
// an invalid descriptor, cannot be written in Rust. The C++ overloads that
// take a base directory get an `_at` suffix, after the POSIX calls they wrap
// (`OpenFile(base, path, ...)` is `open_file_at`); the ones without resolve
// the path against the working directory.

use crate::fml_dcheck_at;
use crate::fml_log_at;
use crate::unique_fd::UniqueFD;

pub use crate::platform::posix::file_posix::*;

const FILE: &str = "flutter/fml/file.cc";

#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FilePermission {
    kRead,
    kWrite,
    kReadWrite,
}

/// Signature of a callback on a file in `directory` with `filename` (relative
/// to `directory`). The returned bool should be false if and only if further
/// traversal should be stopped. For example, a file-search visitor may return
/// false when the file is found so no more visiting is needed.
pub type FileVisitor<'a> = dyn FnMut(&UniqueFD, &[u8]) -> bool + 'a;

fn create_directory_from(
    base_directory: &UniqueFD,
    components: &[impl AsRef<[u8]>],
    permission: FilePermission,
    index: usize,
) -> UniqueFD {
    fml_dcheck_at!(FILE, 16, "index <= components.size()", index <= components.len());

    let file_path = components[index].as_ref();

    let directory = open_directory_at(base_directory, file_path, true, permission);

    if !directory.is_valid() {
        return UniqueFD::default();
    }

    if index == components.len() - 1 {
        return directory;
    }

    create_directory_from(&directory, components, permission, index + 1)
}

pub fn create_directory(
    base_directory: &UniqueFD,
    components: &[impl AsRef<[u8]>],
    permission: FilePermission,
) -> UniqueFD {
    if !is_directory(base_directory) {
        return UniqueFD::default();
    }

    if components.is_empty() {
        return UniqueFD::default();
    }

    create_directory_from(base_directory, components, permission, 0)
}

/// A directory made by `create_temporary_directory`, emptied and removed
/// when dropped.
pub struct ScopedTemporaryDirectory {
    path_: String,
    dir_fd_: UniqueFD,
}

impl ScopedTemporaryDirectory {
    pub fn new() -> ScopedTemporaryDirectory {
        let path_ = create_temporary_directory();
        let mut dir_fd_ = UniqueFD::default();
        if !path_.is_empty() {
            dir_fd_ = open_directory(&path_, false, FilePermission::kRead);
        }
        ScopedTemporaryDirectory { path_, dir_fd_ }
    }

    pub fn path(&self) -> &String {
        &self.path_
    }

    pub fn fd(&self) -> &UniqueFD {
        &self.dir_fd_
    }
}

impl Default for ScopedTemporaryDirectory {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for ScopedTemporaryDirectory {
    fn drop(&mut self) {
        // POSIX requires the directory to be empty before UnlinkDirectory.
        if !self.path_.is_empty() && !remove_files_in_directory(&self.dir_fd_) {
            fml_log_at!(kLogError, FILE, 58, "Could not clean directory: {}", self.path_);
        }

        // Windows has to close UniqueFD first before UnlinkDirectory
        self.dir_fd_.reset_invalid();
        if !self.path_.is_empty() && !unlink_directory(&self.path_) {
            fml_log_at!(kLogError, FILE, 66, "Could not remove directory: {}", self.path_);
        }
    }
}

/// Recursively call `visitor` on all files inside the `directory`. Return
/// false if and only if the visitor returns false during the traversal.
pub fn visit_files_recursively(directory: &UniqueFD, visitor: &mut FileVisitor) -> bool {
    fn recursive_visitor(directory: &UniqueFD, filename: &[u8], visitor: &mut FileVisitor) -> bool {
        if !visitor(directory, filename) {
            return false;
        }
        if is_directory_at(directory, filename) {
            let sub_dir = open_directory_read_only(directory, filename);
            if !sub_dir.is_valid() {
                fml_log_at!(
                    kLogError,
                    FILE,
                    82,
                    "Can't open sub-directory: {}",
                    String::from_utf8_lossy(filename)
                );
                return true;
            }
            return visit_files(&sub_dir, &mut |d: &UniqueFD, f: &[u8]| {
                recursive_visitor(d, f, &mut *visitor)
            });
        }
        true
    }
    visit_files(directory, &mut |d: &UniqueFD, f: &[u8]| recursive_visitor(d, f, &mut *visitor))
}

/// Helper method that calls `open_file_at` with create_if_necessary = false
/// and permission = kRead.
pub fn open_file_read_only(base_directory: &UniqueFD, path: impl AsRef<[u8]>) -> UniqueFD {
    open_file_at(base_directory, path, false, FilePermission::kRead)
}

/// Helper method that calls `open_directory_at` with create_if_necessary =
/// false and permission = kRead.
pub fn open_directory_read_only(base_directory: &UniqueFD, path: impl AsRef<[u8]>) -> UniqueFD {
    open_directory_at(base_directory, path, false, FilePermission::kRead)
}

/// Helper method to recursively remove files and subdirectories inside the
/// directory. The directory itself will not be removed.
///
/// Return true if and only if all files have been successfully removed.
pub fn remove_files_in_directory(directory: &UniqueFD) -> bool {
    fn recursive_cleanup(directory: &UniqueFD, filename: &[u8]) -> bool {
        let removed;
        if is_directory_at(directory, filename) {
            let sub_dir = open_directory_read_only(directory, filename);
            removed = visit_files(&sub_dir, &mut recursive_cleanup)
                && unlink_directory_at(directory, filename);
        } else {
            removed = unlink_file_at(directory, filename);
        }
        removed
    }
    visit_files(directory, &mut recursive_cleanup)
}

/// Helper method to recursively remove files and subdirectories inside the
/// directory. The directory itself will also be removed.
///
/// Return true if and only if all files have been successfully removed.
pub fn remove_directory_recursively(parent: &UniqueFD, directory_name: impl AsRef<[u8]>) -> bool {
    let directory_name = directory_name.as_ref();
    let dir = open_directory_at(parent, directory_name, false, FilePermission::kReadWrite);
    remove_files_in_directory(&dir) && unlink_directory_at(parent, directory_name)
}
