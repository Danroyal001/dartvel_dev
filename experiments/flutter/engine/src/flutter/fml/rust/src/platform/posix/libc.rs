// Not an upstream file: the C library declarations the POSIX ports in this
// directory call (file, mapping, native_library), in one place.
//
// Only the declarations live here; every call is made from the ported file,
// in an `unsafe` block with a SAFETY comment saying why it is sound. The
// struct layouts are the kernel's for Linux on x86-64 and AArch64 (the
// targets the crate builds for); another target fails to compile here rather
// than reading garbage.

#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_int, c_long, c_void};

pub type mode_t = u32;
pub type off_t = i64;

/// `struct stat` on Linux x86-64.
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
#[repr(C)]
#[derive(Clone, Copy)]
pub struct stat {
    pub st_dev: u64,
    pub st_ino: u64,
    pub st_nlink: u64,
    pub st_mode: u32,
    pub st_uid: u32,
    pub st_gid: u32,
    __pad0: c_int,
    pub st_rdev: u64,
    pub st_size: i64,
    pub st_blksize: i64,
    pub st_blocks: i64,
    pub st_atime: i64,
    pub st_atime_nsec: c_long,
    pub st_mtime: i64,
    pub st_mtime_nsec: c_long,
    pub st_ctime: i64,
    pub st_ctime_nsec: c_long,
    __unused: [c_long; 3],
}

/// `struct stat` on Linux AArch64 (the generic layout).
#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
#[repr(C)]
#[derive(Clone, Copy)]
pub struct stat {
    pub st_dev: u64,
    pub st_ino: u64,
    pub st_mode: u32,
    pub st_nlink: u32,
    pub st_uid: u32,
    pub st_gid: u32,
    pub st_rdev: u64,
    __pad1: u64,
    pub st_size: i64,
    pub st_blksize: c_int,
    __pad2: c_int,
    pub st_blocks: i64,
    pub st_atime: i64,
    pub st_atime_nsec: c_long,
    pub st_mtime: i64,
    pub st_mtime_nsec: c_long,
    pub st_ctime: i64,
    pub st_ctime_nsec: c_long,
    __unused: [c_int; 2],
}

impl stat {
    /// `struct stat = {}`.
    pub fn zeroed() -> stat {
        // SAFETY: `stat` is plain integers, for which all-zero bits are a
        // valid value.
        unsafe { std::mem::zeroed() }
    }
}

/// `struct dirent` on Linux (the same on x86-64 and AArch64).
#[repr(C)]
pub struct dirent {
    pub d_ino: u64,
    pub d_off: i64,
    pub d_reclen: u16,
    pub d_type: u8,
    pub d_name: [c_char; 256],
}

/// The C library's opaque `DIR`.
#[repr(C)]
pub struct DIR {
    _private: [u8; 0],
}

pub const AT_FDCWD: c_int = -100;
pub const AT_REMOVEDIR: c_int = 0x200;
pub const F_OK: c_int = 0;

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = 0o100;
pub const O_TRUNC: c_int = 0o1000;
#[cfg(target_arch = "x86_64")]
pub const O_DIRECTORY: c_int = 0o200000;
#[cfg(target_arch = "aarch64")]
pub const O_DIRECTORY: c_int = 0o40000;

pub const S_IFMT: u32 = 0o170000;
pub const S_IFDIR: u32 = 0o040000;
pub const S_IFREG: u32 = 0o100000;
pub const S_IRUSR: mode_t = 0o400;
pub const S_IWUSR: mode_t = 0o200;
pub const S_IXUSR: mode_t = 0o100;

pub const PROT_READ: c_int = 1;
pub const PROT_WRITE: c_int = 2;
pub const PROT_EXEC: c_int = 4;
pub const MAP_SHARED: c_int = 1;
pub const MAP_PRIVATE: c_int = 2;
pub const MAP_FAILED: *mut c_void = !0usize as *mut c_void;

pub const RTLD_NOW: c_int = 2;
pub const RTLD_DEFAULT: *mut c_void = std::ptr::null_mut();

pub fn s_isdir(mode: u32) -> bool {
    mode & S_IFMT == S_IFDIR
}

pub fn s_isreg(mode: u32) -> bool {
    mode & S_IFMT == S_IFREG
}

// SAFETY: declarations only, each matching its prototype in <fcntl.h>, <unistd.h>, <sys/stat.h>, <dirent.h>, <stdlib.h>, <string.h>, <sys/mman.h> and <dlfcn.h>
// for the LP64 Linux/Apple targets this crate builds for; every call
// below is in its own unsafe block that says why it is sound.
unsafe extern "C" {
    pub fn openat(dirfd: c_int, pathname: *const c_char, flags: c_int, ...) -> c_int;
    pub fn mkdirat(dirfd: c_int, pathname: *const c_char, mode: mode_t) -> c_int;
    pub fn dup(oldfd: c_int) -> c_int;
    pub fn fstat(fd: c_int, statbuf: *mut stat) -> c_int;
    #[link_name = "stat"]
    pub fn stat_path(pathname: *const c_char, statbuf: *mut stat) -> c_int;
    pub fn ftruncate(fd: c_int, length: off_t) -> c_int;
    pub fn unlinkat(dirfd: c_int, pathname: *const c_char, flags: c_int) -> c_int;
    pub fn faccessat(dirfd: c_int, pathname: *const c_char, mode: c_int, flags: c_int) -> c_int;
    pub fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
    pub fn fsync(fd: c_int) -> c_int;
    pub fn renameat(
        olddirfd: c_int,
        oldpath: *const c_char,
        newdirfd: c_int,
        newpath: *const c_char,
    ) -> c_int;
    pub fn fdopendir(fd: c_int) -> *mut DIR;
    pub fn readdir(dirp: *mut DIR) -> *mut dirent;
    pub fn rewinddir(dirp: *mut DIR);
    pub fn closedir(dirp: *mut DIR) -> c_int;
    pub fn mkdtemp(template: *mut c_char) -> *mut c_char;
    pub fn strerror(errnum: c_int) -> *const c_char;
    pub fn getcwd(buf: *mut c_char, size: usize) -> *mut c_char;
    pub fn readlink(pathname: *const c_char, buf: *mut c_char, bufsiz: usize) -> isize;

    pub fn mmap(
        addr: *mut c_void,
        length: usize,
        prot: c_int,
        flags: c_int,
        fd: c_int,
        offset: off_t,
    ) -> *mut c_void;
    pub fn munmap(addr: *mut c_void, length: usize) -> c_int;

    pub fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    pub fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    pub fn dlclose(handle: *mut c_void) -> c_int;
    pub fn dlerror() -> *const c_char;
}

/// `errno`, read the way upstream reads it after a failed call.
pub fn errno() -> c_int {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

/// `strerror(errno)` as text.
pub fn strerror_text(errnum: c_int) -> String {
    // SAFETY: strerror returns a pointer to a NUL-terminated string the C
    // library owns, valid until the next strerror call on this thread; it is
    // copied out before anything else runs here.
    unsafe { std::ffi::CStr::from_ptr(strerror(errnum)).to_string_lossy().into_owned() }
}

/// The C string upstream's `const char*` parameter is handed: the bytes up
/// to the first NUL, as C reads them.
pub fn c_string(bytes: &[u8]) -> std::ffi::CString {
    let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    std::ffi::CString::new(&bytes[..end]).expect("no NUL before the end")
}
