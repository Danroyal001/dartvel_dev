// Port of flutter/fml/platform/posix/native_library_posix.cc.

use std::ffi::CStr;

use crate::fml_dlog_at;
use crate::fml_log_at;
use crate::memory::ref_ptr::{RefPtr, adopt_ref};
use crate::native_library::{Handle, NativeLibrary, SymbolHandle};
use crate::platform::posix::libc::{self, c_string};

const FILE: &str = "flutter/fml/platform/posix/native_library_posix.cc";

/// The dynamic linker's last error, as text. The callers below ask only
/// after a failure, when there is one.
fn dlerror_text() -> String {
    // SAFETY: dlerror returns null or a NUL-terminated string the linker
    // owns until the next dl* call on this thread; it is copied at once.
    let error = unsafe { libc::dlerror() };
    if error.is_null() {
        return String::new();
    }
    // SAFETY: non-null, NUL-terminated, see above.
    unsafe { CStr::from_ptr(error) }.to_string_lossy().into_owned()
}

fn clear_dlerror() {
    // SAFETY: dlerror only reads and clears the thread's error state.
    unsafe {
        libc::dlerror();
    }
}

impl NativeLibrary {
    fn from_path(path: &str) -> NativeLibrary {
        let c_path = c_string(path.as_bytes());
        clear_dlerror();
        // SAFETY: `c_path` is NUL-terminated and outlives the call. Loading a
        // library runs its initializers, as upstream's dlopen does: that is
        // what the caller asked for.
        let handle_ = unsafe { libc::dlopen(c_path.as_ptr(), libc::RTLD_NOW) };
        if handle_.is_null() {
            fml_dlog_at!(
                kLogError,
                FILE,
                16,
                "Could not open library '{}' due to error '{}'.",
                c_path.to_string_lossy(),
                dlerror_text()
            );
        }
        NativeLibrary { handle_, close_handle_: true }
    }

    pub fn create(path: &str) -> RefPtr<NativeLibrary> {
        let library = adopt_ref(NativeLibrary::from_path(path));
        if !library.get_handle().is_null() { library } else { RefPtr::null() }
    }

    /// # Safety
    ///
    /// `handle` must be null, `RTLD_DEFAULT`, or a live handle from dlopen;
    /// with `close_handle_when_done` the library takes over closing it.
    pub unsafe fn create_with_handle(
        handle: Handle,
        close_handle_when_done: bool,
    ) -> RefPtr<NativeLibrary> {
        let library = adopt_ref(NativeLibrary { handle_: handle, close_handle_: close_handle_when_done });
        if !library.get_handle().is_null() { library } else { RefPtr::null() }
    }

    pub fn create_for_current_process() -> RefPtr<NativeLibrary> {
        adopt_ref(NativeLibrary { handle_: libc::RTLD_DEFAULT, close_handle_: false })
    }

    pub(crate) fn resolve(&self, symbol: &str) -> SymbolHandle {
        let symbol = c_string(symbol.as_bytes());
        // SAFETY: the handle is null (RTLD_DEFAULT) or live (dlclose runs
        // only on drop); `symbol` is NUL-terminated and outlives the call.
        unsafe { libc::dlsym(self.handle_, symbol.as_ptr()) }
    }
}

impl Drop for NativeLibrary {
    fn drop(&mut self) {
        if self.handle_.is_null() {
            return;
        }

        if self.close_handle_ {
            clear_dlerror();
            // SAFETY: the handle came from dlopen and is closed once, here;
            // no symbol of it is used through this library afterwards.
            if unsafe { libc::dlclose(self.handle_) } != 0 {
                self.handle_ = std::ptr::null_mut();
                fml_log_at!(
                    kLogError,
                    FILE,
                    33,
                    "Could not close library due to error '{}'.",
                    dlerror_text()
                );
            }
        }
    }
}
