// Port of flutter/fml/mapping.h and flutter/fml/mapping.cc.
//
// `FileMapping`'s constructor and destructor, which upstream defines per
// platform, are in platform/posix/mapping_posix.rs (an `impl FileMapping`).
//
// A `Mapping` hands out a raw pointer, as upstream's does, because what is
// behind it differs: an mmap'd file (which may not be readable at all), a
// symbol's address with size 0, memory someone else owns. `Mapping` is an
// `unsafe trait` for that reason: its implementations promise that the
// pointer is null or points at `get_size()` bytes that stay mapped while the
// mapping is borrowed, which `write_atomically` relies on. Reading them is
// left to the caller, as upstream leaves it.

use crate::fml_check_at;
use crate::memory::ref_ptr::RefPtr;
use crate::native_library::NativeLibrary;
use crate::unique_fd::UniqueFD;

const FILE: &str = "flutter/fml/mapping.cc";

/// # Safety
///
/// `get_mapping()` must be null or point at `get_size()` bytes that stay
/// mapped for as long as the mapping is borrowed.
pub unsafe trait Mapping {
    fn get_size(&self) -> usize;

    fn get_mapping(&self) -> *const u8;

    /// Whether calling madvise(DONTNEED) on the mapping is non-destructive.
    /// Generally true for file-mapped memory and false for anonymous memory.
    fn is_dont_need_safe(&self) -> bool;
}

#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Protection {
    kRead,
    kWrite,
    kExecute,
}

/// A file mapped into memory (`FileMapping`).
pub struct FileMapping {
    pub(crate) valid_: bool,
    pub(crate) size_: usize,
    pub(crate) mapping_: *mut u8,
    pub(crate) mutable_mapping_: *mut u8,
}

// SAFETY: a FileMapping owns its mmap region outright (no thread affinity);
// reading or writing through its pointers is the caller's business, as with
// upstream's.
unsafe impl Send for FileMapping {}
// SAFETY: as above; `&FileMapping` only reads the pointers' values.
unsafe impl Sync for FileMapping {}

impl FileMapping {
    pub fn get_mutable_mapping(&self) -> *mut u8 {
        self.mutable_mapping_
    }

    pub fn create_read_only(path: impl AsRef<[u8]>) -> Option<Box<FileMapping>> {
        Self::create_read_only_at(
            &crate::file::open_file(path, false, crate::file::FilePermission::kRead),
            "",
        )
    }

    pub fn create_read_only_at(
        base_fd: &UniqueFD,
        sub_path: impl AsRef<[u8]>,
    ) -> Option<Box<FileMapping>> {
        let sub_path = sub_path.as_ref();
        if !sub_path.is_empty() {
            return Self::create_read_only_at(
                &crate::file::open_file_at(
                    base_fd,
                    sub_path,
                    false,
                    crate::file::FilePermission::kRead,
                ),
                "",
            );
        }

        let mapping = Box::new(FileMapping::new(base_fd, &[Protection::kRead]));

        if !mapping.is_valid() {
            return None;
        }

        Some(mapping)
    }

    pub fn create_read_execute(path: impl AsRef<[u8]>) -> Option<Box<FileMapping>> {
        Self::create_read_execute_at(
            &crate::file::open_file(path, false, crate::file::FilePermission::kRead),
            "",
        )
    }

    pub fn create_read_execute_at(
        base_fd: &UniqueFD,
        sub_path: impl AsRef<[u8]>,
    ) -> Option<Box<FileMapping>> {
        let sub_path = sub_path.as_ref();
        if !sub_path.is_empty() {
            return Self::create_read_execute_at(
                &crate::file::open_file_at(
                    base_fd,
                    sub_path,
                    false,
                    crate::file::FilePermission::kRead,
                ),
                "",
            );
        }

        let mapping =
            Box::new(FileMapping::new(base_fd, &[Protection::kRead, Protection::kExecute]));

        if !mapping.is_valid() {
            return None;
        }

        Some(mapping)
    }

    pub fn is_valid(&self) -> bool {
        self.valid_
    }
}

// SAFETY: mapping_ is null or the start of an mmap of size_ bytes that lives
// until the FileMapping is dropped.
unsafe impl Mapping for FileMapping {
    fn get_size(&self) -> usize {
        self.size_
    }

    fn get_mapping(&self) -> *const u8 {
        self.mapping_
    }

    fn is_dont_need_safe(&self) -> bool {
        self.mutable_mapping_.is_null()
    }
}

/// Bytes the mapping owns (`DataMapping`).
pub struct DataMapping {
    data_: Vec<u8>,
}

impl DataMapping {
    pub fn new(data: Vec<u8>) -> DataMapping {
        DataMapping { data_: data }
    }

    /// `DataMapping(const std::string&)`.
    pub fn from_string(string: impl AsRef<[u8]>) -> DataMapping {
        DataMapping { data_: string.as_ref().to_vec() }
    }
}

// SAFETY: the pointer is null or the vector's buffer, which holds get_size()
// bytes and lives as long as the DataMapping.
unsafe impl Mapping for DataMapping {
    fn get_size(&self) -> usize {
        self.data_.len()
    }

    fn get_mapping(&self) -> *const u8 {
        // libc++'s vector::data() is null until the vector allocates; an
        // empty DataMapping's mapping is null upstream (and write_atomically
        // refuses it), so it is here.
        if self.data_.capacity() == 0 { std::ptr::null() } else { self.data_.as_ptr() }
    }

    fn is_dont_need_safe(&self) -> bool {
        false
    }
}

pub type ReleaseProc = Box<dyn Fn(*const u8, usize) + Send + Sync>;

/// Memory someone else owns (`NonOwnedMapping`), with an optional callback
/// run when the mapping is dropped.
pub struct NonOwnedMapping {
    data_: *const u8,
    size_: usize,
    release_proc_: Option<ReleaseProc>,
    dontneed_safe_: bool,
}

// SAFETY: the mapping only holds the pointer; the constructor's contract
// makes the memory valid wherever the mapping goes.
unsafe impl Send for NonOwnedMapping {}
// SAFETY: as above.
unsafe impl Sync for NonOwnedMapping {}

impl NonOwnedMapping {
    /// # Safety
    ///
    /// `data` must be null or point at `size` bytes that stay valid until the
    /// mapping is dropped (and `release_proc`, if any, has run).
    pub unsafe fn new(
        data: *const u8,
        size: usize,
        release_proc: Option<ReleaseProc>,
        dontneed_safe: bool,
    ) -> NonOwnedMapping {
        NonOwnedMapping { data_: data, size_: size, release_proc_: release_proc, dontneed_safe_: dontneed_safe }
    }

    /// A mapping of memory that lives for the whole program.
    pub fn from_static(data: &'static [u8]) -> NonOwnedMapping {
        // SAFETY: `data` is valid for its length forever.
        unsafe { NonOwnedMapping::new(data.as_ptr(), data.len(), None, false) }
    }
}

impl Drop for NonOwnedMapping {
    fn drop(&mut self) {
        if let Some(release_proc) = &self.release_proc_ {
            release_proc(self.data_, self.size_);
        }
    }
}

// SAFETY: by NonOwnedMapping::new's contract.
unsafe impl Mapping for NonOwnedMapping {
    fn get_size(&self) -> usize {
        self.size_
    }

    fn get_mapping(&self) -> *const u8 {
        self.data_
    }

    fn is_dont_need_safe(&self) -> bool {
        self.dontneed_safe_
    }
}

/// Heap memory the mapping owns (`MallocMapping`). Upstream's buffer is
/// malloc'd and freed with free; here it is a boxed slice, so
/// `MallocMapping(data, size)` takes a `Box<[u8]>` and `Release` hands it
/// back. A zero-length copy is non-null, as malloc(0)'s result is.
#[derive(Default)]
pub struct MallocMapping {
    data_: Option<Box<[u8]>>,
}

impl MallocMapping {
    pub fn new() -> MallocMapping {
        MallocMapping { data_: None }
    }

    /// Creates a MallocMapping for a region of memory (without copying it).
    pub fn from_box(data: Box<[u8]>) -> MallocMapping {
        MallocMapping { data_: Some(data) }
    }

    /// Copies a region of memory into a MallocMapping.
    pub fn copy(begin: &[u8]) -> MallocMapping {
        let result = MallocMapping::from_box(begin.to_vec().into_boxed_slice());
        fml_check_at!(
            FILE,
            138,
            "result.GetMapping() != nullptr",
            !result.get_mapping().is_null()
        );
        result
    }

    /// Removes ownership of the data buffer.
    /// After this is called; the mapping will point to nullptr.
    #[must_use]
    pub fn release(&mut self) -> Option<Box<[u8]>> {
        self.data_.take()
    }

    /// The move constructor: takes `mapping`'s buffer, leaving it empty.
    pub fn take(mapping: &mut MallocMapping) -> MallocMapping {
        MallocMapping { data_: mapping.data_.take() }
    }
}

// SAFETY: the pointer is null or the boxed slice's, of get_size() bytes,
// owned by the mapping.
unsafe impl Mapping for MallocMapping {
    fn get_size(&self) -> usize {
        self.data_.as_ref().map_or(0, |d| d.len())
    }

    fn get_mapping(&self) -> *const u8 {
        self.data_.as_ref().map_or(std::ptr::null(), |d| d.as_ptr())
    }

    fn is_dont_need_safe(&self) -> bool {
        false
    }
}

/// A symbol in a native library (`SymbolMapping`): its address, with size 0.
pub struct SymbolMapping {
    native_library_: RefPtr<NativeLibrary>,
    mapping_: *const u8,
}

// SAFETY: the mapping holds the library (thread-safe reference counted) and
// the address of one of its symbols.
unsafe impl Send for SymbolMapping {}
// SAFETY: as above.
unsafe impl Sync for SymbolMapping {}

impl SymbolMapping {
    pub fn new(native_library: RefPtr<NativeLibrary>, symbol_name: Option<&str>) -> SymbolMapping {
        let mut mapping_ = std::ptr::null();
        if let (Some(library), Some(symbol_name)) = (native_library.get(), symbol_name) {
            mapping_ = library.resolve_symbol(symbol_name);

            if mapping_.is_null() {
                // Apparently, dart_bootstrap seems to account for the Mac behavior of
                // requiring the underscore prefixed symbol name on non-Mac platforms as
                // well. As a fallback, check the underscore prefixed variant of the
                // symbol name and allow callers to not have handle this on a per platform
                // toolchain quirk basis.
                let underscore_symbol_name = format!("_{symbol_name}");
                mapping_ = library.resolve_symbol(&underscore_symbol_name);
            }
        }
        SymbolMapping { native_library_: native_library, mapping_ }
    }

    pub fn native_library(&self) -> &RefPtr<NativeLibrary> {
        &self.native_library_
    }
}

// SAFETY: the pointer is null or a symbol's address with size 0: no bytes
// are promised. The library it lives in is held while the mapping lives.
unsafe impl Mapping for SymbolMapping {
    fn get_size(&self) -> usize {
        0
    }

    fn get_mapping(&self) -> *const u8 {
        self.mapping_
    }

    fn is_dont_need_safe(&self) -> bool {
        true
    }
}
