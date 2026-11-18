// Port of flutter/fml/native_library.h.
//
// The POSIX definitions (dlopen, dlsym, dlclose) are in
// platform/posix/native_library_posix.rs. A `NativeLibrary` lives in a
// `RefPtr` (an `Arc`), as upstream's is reference counted thread-safely.
// Symbol names are `&str`, read up to the first NUL as upstream's
// `const char*` is.

use std::ffi::c_void;

use crate::fml_dlog_at;
use crate::memory::ref_counted::RefCountedThreadSafe;

/// Where upstream's inline `ResolveSymbol` logs from: the header's path as
/// the engine's build includes it.
const FILE: &str = "flutter/fml/native_library.h";

pub type Handle = *mut c_void;
pub type SymbolHandle = *mut c_void;

pub struct NativeLibrary {
    pub(crate) handle_: Handle,
    pub(crate) close_handle_: bool,
}

// SAFETY: a dlopen handle may be used from any thread (the dynamic linker
// locks internally); the library only reads it after construction.
unsafe impl Send for NativeLibrary {}
// SAFETY: as above.
unsafe impl Sync for NativeLibrary {}

impl RefCountedThreadSafe for NativeLibrary {}

impl NativeLibrary {
    /// `ResolveFunction<T>`: the symbol's address as a `T`, which must be a
    /// function pointer type (checked to be pointer-sized).
    ///
    /// # Safety
    ///
    /// `T` must be the type of the function the symbol names; calling it
    /// through any other type is undefined behaviour, as upstream's
    /// `reinterpret_cast` is.
    pub unsafe fn resolve_function<T: Copy>(&self, symbol: &str) -> Option<T> {
        assert_eq!(std::mem::size_of::<T>(), std::mem::size_of::<SymbolHandle>());
        let resolved_symbol = self.resolve(symbol);
        if resolved_symbol.is_null() {
            return None;
        }
        // SAFETY: T is pointer-sized (asserted) and, by the caller's
        // contract, the function pointer type of this symbol.
        Some(unsafe { std::mem::transmute_copy::<SymbolHandle, T>(&resolved_symbol) })
    }

    pub fn resolve_symbol(&self, symbol: &str) -> *const u8 {
        let resolved_symbol = self.resolve(symbol) as *const u8;
        if resolved_symbol.is_null() {
            fml_dlog_at!(
                kLogInfo,
                FILE,
                50,
                "Could not resolve symbol in library: {}",
                symbol.split('\0').next().unwrap_or("")
            );
        }
        resolved_symbol
    }

    pub(crate) fn get_handle(&self) -> Handle {
        self.handle_
    }
}
