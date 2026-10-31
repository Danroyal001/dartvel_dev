// Port of flutter/fml/platform/posix/file_posix.cc.
//
// Each function makes the C library calls upstream makes, in the same order,
// so that the descriptors, the files and `errno` come out as upstream's do.
// `fml::UniqueFD{AT_FDCWD}` is kept as upstream builds it: a UniqueFD
// holding -100, which is not its invalid value (-1), so dropping it calls
// close(-100), which fails with EBADF. Callers of the overloads without a
// base directory see that errno, as upstream's do.

use std::ffi::CStr;
use std::os::raw::c_char;

use crate::eintr_wrapper::handle_eintr;
use crate::file::{FilePermission, FileVisitor};
use crate::fml_dlog_at;
use crate::mapping::Mapping;
use crate::platform::posix::libc::{self, with_c_str};
use crate::trace_event0;
use crate::unique_fd::{UniqueDir, UniqueFD};

const FILE: &str = "flutter/fml/platform/posix/file_posix.cc";

/// Makes "/tmp/flutter_XXXXXXXX"; the empty string if mkdtemp fails.
pub fn create_temporary_directory() -> String {
    let mut directory_name = *b"/tmp/flutter_XXXXXXXX\0";
    // SAFETY: mkdtemp rewrites the X's of the NUL-terminated template in
    // place, within the buffer, and returns a pointer into it or null.
    let result = unsafe { libc::mkdtemp(directory_name.as_mut_ptr() as *mut c_char) };
    if result.is_null() {
        return String::new();
    }
    // mkdtemp's replacement characters are ASCII letters and digits.
    String::from_utf8_lossy(&directory_name[..directory_name.len() - 1]).into_owned()
}

fn to_posix_access_flags(permission: FilePermission) -> i32 {
    let mut flags = 0;
    match permission {
        FilePermission::kRead => flags |= libc::O_RDONLY, // read only
        FilePermission::kWrite => flags |= libc::O_WRONLY, // write only
        FilePermission::kReadWrite => flags |= libc::O_RDWR, // read-write
    }
    flags
}

fn to_posix_create_mode_flags(permission: FilePermission) -> libc::mode_t {
    let mut mode = 0;
    match permission {
        FilePermission::kRead => mode |= libc::S_IRUSR,
        FilePermission::kWrite => mode |= libc::S_IWUSR,
        FilePermission::kReadWrite => mode |= libc::S_IRUSR | libc::S_IWUSR,
    }
    mode
}

/// `openat` on a NUL-terminated path.
fn openat(dirfd: i32, path: &CStr, flags: i32, mode: libc::mode_t) -> i32 {
    handle_eintr(|| {
        // SAFETY: `path` is NUL-terminated and outlives the call; openat
        // reads it and touches no other memory of ours.
        unsafe { libc::openat(dirfd, path.as_ptr(), flags, mode) }
    })
}

/// This can open a directory on POSIX, but not on Windows.
pub fn open_file(
    path: impl AsRef<[u8]>,
    create_if_necessary: bool,
    permission: FilePermission,
) -> UniqueFD {
    open_file_at(&UniqueFD::new(libc::AT_FDCWD), path, create_if_necessary, permission)
}

/// This can open a directory on POSIX, but not on Windows.
pub fn open_file_at(
    base_directory: &UniqueFD,
    path: impl AsRef<[u8]>,
    create_if_necessary: bool,
    permission: FilePermission,
) -> UniqueFD {
    trace_event0!("flutter", "fml::OpenFile");
    with_c_str(path.as_ref(), b"", |path| {
        let flags;
        let mode;

        if create_if_necessary && !file_exists_c(base_directory, path) {
            flags = to_posix_access_flags(permission) | libc::O_CREAT | libc::O_TRUNC;
            mode = to_posix_create_mode_flags(permission);
        } else {
            flags = to_posix_access_flags(permission);
            mode = 0; // Not creating since it already exists.
        }

        UniqueFD::new(openat(base_directory.get(), path, flags, mode))
    })
}

pub fn open_directory(
    path: impl AsRef<[u8]>,
    create_if_necessary: bool,
    permission: FilePermission,
) -> UniqueFD {
    open_directory_at(&UniqueFD::new(libc::AT_FDCWD), path, create_if_necessary, permission)
}

pub fn open_directory_at(
    base_directory: &UniqueFD,
    path: impl AsRef<[u8]>,
    create_if_necessary: bool,
    permission: FilePermission,
) -> UniqueFD {
    with_c_str(path.as_ref(), b"", |path| {
        if create_if_necessary && !file_exists_c(base_directory, path) {
            // SAFETY: `path` is NUL-terminated and outlives the call.
            let rc = unsafe {
                libc::mkdirat(
                    base_directory.get(),
                    path.as_ptr(),
                    to_posix_create_mode_flags(permission) | libc::S_IXUSR,
                )
            };
            if rc != 0 {
                return UniqueFD::default();
            }
        }

        UniqueFD::new(openat(base_directory.get(), path, libc::O_RDONLY | libc::O_DIRECTORY, 0))
    })
}

pub fn duplicate(descriptor: i32) -> UniqueFD {
    UniqueFD::new(handle_eintr(|| {
        // SAFETY: dup takes a descriptor by value and touches no memory.
        unsafe { libc::dup(descriptor) }
    }))
}

pub fn is_directory(directory: &UniqueFD) -> bool {
    if !directory.is_valid() {
        return false;
    }

    let mut stat_result = libc::stat::zeroed();

    // SAFETY: fstat writes one `struct stat`, which `stat_result` is (laid
    // out as the kernel's for this target).
    if unsafe { libc::fstat(directory.get(), &mut stat_result) } != 0 {
        return false;
    }

    libc::s_isdir(stat_result.st_mode)
}

pub fn is_directory_at(base_directory: &UniqueFD, path: impl AsRef<[u8]>) -> bool {
    let file = crate::file::open_file_read_only(base_directory, path);
    file.is_valid() && is_directory(&file)
}

/// Returns whether the given path is a file.
pub fn is_file(path: impl AsRef<[u8]>) -> bool {
    let mut buf = libc::stat::zeroed();
    // SAFETY: `path` is NUL-terminated; stat writes one `struct stat`.
    if with_c_str(path.as_ref(), b"", |path| unsafe { libc::stat_path(path.as_ptr(), &mut buf) }) != 0 {
        return false;
    }

    libc::s_isreg(buf.st_mode)
}

pub fn truncate_file(file: &UniqueFD, size: usize) -> bool {
    if !file.is_valid() {
        return false;
    }

    // SAFETY: ftruncate takes a descriptor and a length and touches no
    // memory. (`size` converts as upstream's size_t to off_t does.)
    unsafe { libc::ftruncate(file.get(), size as libc::off_t) == 0 }
}

pub fn unlink_directory(path: impl AsRef<[u8]>) -> bool {
    unlink_directory_at(&UniqueFD::new(libc::AT_FDCWD), path)
}

pub fn unlink_directory_at(base_directory: &UniqueFD, path: impl AsRef<[u8]>) -> bool {
    with_c_str(path.as_ref(), b"", |path| {
        // SAFETY: `path` is NUL-terminated and outlives the call.
        unsafe { libc::unlinkat(base_directory.get(), path.as_ptr(), libc::AT_REMOVEDIR) == 0 }
    })
}

pub fn unlink_file(path: impl AsRef<[u8]>) -> bool {
    unlink_file_at(&UniqueFD::new(libc::AT_FDCWD), path)
}

pub fn unlink_file_at(base_directory: &UniqueFD, path: impl AsRef<[u8]>) -> bool {
    let code = with_c_str(path.as_ref(), b"", |path| {
        // SAFETY: `path` is NUL-terminated and outlives the call.
        unsafe { libc::unlinkat(base_directory.get(), path.as_ptr(), 0) }
    });
    if code != 0 {
        fml_dlog_at!(kLogError, FILE, 178, "{}", libc::strerror_text(libc::errno()));
    }
    code == 0
}

pub fn file_exists(base_directory: &UniqueFD, path: impl AsRef<[u8]>) -> bool {
    if !base_directory.is_valid() {
        return false;
    }

    with_c_str(path.as_ref(), b"", |path| file_exists_c(base_directory, path))
}

/// `FileExists` on a path already made a C string.
fn file_exists_c(base_directory: &UniqueFD, path: &CStr) -> bool {
    if !base_directory.is_valid() {
        return false;
    }

    // SAFETY: `path` is NUL-terminated and outlives the call.
    unsafe { libc::faccessat(base_directory.get(), path.as_ptr(), libc::F_OK, 0) == 0 }
}

pub fn write_atomically(
    base_directory: &UniqueFD,
    file_name: impl AsRef<[u8]>,
    data: &dyn Mapping,
) -> bool {
    if data.get_mapping().is_null() {
        return false;
    }

    with_c_str(file_name.as_ref(), b"", |file_name| {
        with_c_str(file_name.to_bytes(), b".temp", |temp_file_name| {
            write_atomically_c(base_directory, file_name, temp_file_name, data)
        })
    })
}

/// The rest of `WriteAtomically`, on the file name and the temporary file's
/// name made C strings.
fn write_atomically_c(
    base_directory: &UniqueFD,
    file_name: &CStr,
    temp_file_name: &CStr,
    data: &dyn Mapping,
) -> bool {
    let temp_file = open_file_at(
        base_directory,
        temp_file_name.to_bytes(),
        true,
        FilePermission::kReadWrite,
    );
    if !temp_file.is_valid() {
        return false;
    }

    if !truncate_file(&temp_file, data.get_size()) {
        return false;
    }

    let mut remaining = data.get_size() as isize;
    let mut offset: isize = 0;

    while remaining > 0 {
        let written = handle_eintr(|| {
            // SAFETY: by the `Mapping` contract, get_mapping() points at
            // get_size() bytes that stay mapped while `data` is borrowed;
            // [offset, offset + remaining) lies within them. The kernel reads
            // them (and fails with EFAULT, not a fault, where they are not
            // readable).
            unsafe {
                libc::write(
                    temp_file.get(),
                    data.get_mapping().offset(offset) as *const std::os::raw::c_void,
                    remaining as usize,
                )
            }
        });

        if written == -1 {
            return false;
        }

        remaining -= written;
        offset += written;
    }

    // SAFETY: fsync takes a descriptor and touches no memory.
    if unsafe { libc::fsync(temp_file.get()) } != 0 {
        return false;
    }

    // SAFETY: both names are NUL-terminated and outlive the call.
    unsafe {
        libc::renameat(
            base_directory.get(),
            temp_file_name.as_ptr(),
            base_directory.get(),
            file_name.as_ptr(),
        ) == 0
    }
}

/// Call `visitor` on all files inside the `directory` non-recursively. The
/// trivial file "." and ".." will not be visited.
///
/// Return false if and only if the visitor returns false during the
/// traversal.
pub fn visit_files(directory: &UniqueFD, visitor: &mut FileVisitor) -> bool {
    // SAFETY: dup takes a descriptor by value and touches no memory.
    let mut dup_fd = UniqueFD::new(unsafe { libc::dup(directory.get()) });
    if !dup_fd.is_valid() {
        fml_dlog_at!(
            kLogError,
            FILE,
            239,
            "Can't dup the directory fd. Error: {}",
            libc::strerror_text(libc::errno())
        );
        return true; // continue to visit other files
    }

    // SAFETY: fdopendir takes a descriptor by value and returns a DIR it
    // owns (with the descriptor) or null.
    let dir = UniqueDir::new(unsafe { libc::fdopendir(dup_fd.get()) });
    if !dir.is_valid() {
        fml_dlog_at!(
            kLogError,
            FILE,
            245,
            "Can't open the directory. Error: {}",
            libc::strerror_text(libc::errno())
        );
        return true; // continue to visit other files
    }

    // The directory fd will be closed by `closedir`.
    let _ = dup_fd.release();

    // Without `rewinddir`, `readir` will directly return NULL (end of dir is
    // reached) after a previuos `VisitFiles` call for the same `const
    // fml::UniqueFd& directory`.
    // SAFETY: `dir` is a valid DIR owned by `dir` for the whole loop.
    unsafe { libc::rewinddir(dir.get()) };
    loop {
        // SAFETY: as above; readdir returns null at the end or an entry that
        // stays valid until the next readdir or closedir on `dir`.
        let ent = unsafe { libc::readdir(dir.get()) };
        if ent.is_null() {
            break;
        }
        // SAFETY: `ent` is non-null and valid until the next readdir; its
        // d_name is NUL-terminated within the entry. The name is copied out
        // before the visitor (which may read the directory) runs: onto the
        // stack, as upstream's std::string keeps a short name inline (d_name
        // is 256 bytes with its NUL, so the copy always fits).
        let name = unsafe { CStr::from_ptr((*ent).d_name.as_ptr()) }.to_bytes();
        let mut copy = [0u8; 256];
        copy[..name.len()].copy_from_slice(name);
        let filename = &copy[..name.len()];
        if filename != b"." && filename != b".." && !visitor(directory, filename) {
            return false;
        }
    }

    true
}
