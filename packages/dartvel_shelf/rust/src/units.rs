//! Deferred code units a web-server binary carries inside itself.
//!
//! `gen_snapshot --loading_unit_manifest` splits a program into a root unit
//! and one ELF per group of libraries reached only through `deferred as`
//! imports; the VM asks the embedder for unit N the first time an isolate
//! calls `loadLibrary()` on such an import. A web-server binary carries its
//! units as sections of its own file, each on a 64 KiB boundary, and this is
//! the embedder's side of that: a deferred-load handler that maps unit N
//! straight from its range of the executable with the runtime's own ELF
//! loader and hands it to the VM.
//!
//! It is here rather than in Dart because the VM calls the handler on
//! whichever isolate asked, and a Dart callback belongs to the isolate that
//! made it: an image resized on a helper isolate would call into the main
//! isolate's callback and abort. A plain C function has no such tie.
//!
//! The runtime exports its embedding API (`Dart_LoadELF`,
//! `Dart_DeferredLoadComplete`, ...) from the executable, so they are found
//! with `dlsym` rather than linked: the library also loads into programs
//! that export none of them, and then simply has no units.

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CString};
use std::sync::Mutex;

use once_cell::sync::OnceCell;

type DartHandle = *mut c_void;
type LoadElf = unsafe extern "C" fn(
    *const c_char,
    u64,
    *mut *const c_char,
    *mut *const u8,
    *mut *const u8,
    *mut *const u8,
    *mut *const u8,
) -> *mut c_void;
type Complete = unsafe extern "C" fn(isize, *const u8, *const u8) -> DartHandle;
type CompleteError = unsafe extern "C" fn(isize, *const c_char, bool) -> DartHandle;
type IsError = unsafe extern "C" fn(DartHandle) -> bool;
type GetError = unsafe extern "C" fn(DartHandle) -> *const c_char;
type LookupLibrary = unsafe extern "C" fn(DartHandle) -> DartHandle;
type NewString = unsafe extern "C" fn(*const c_char) -> DartHandle;
type NewInteger = unsafe extern "C" fn(i64) -> DartHandle;
type NewBoolean = unsafe extern "C" fn(bool) -> DartHandle;
type Null = unsafe extern "C" fn() -> DartHandle;
type Invoke = unsafe extern "C" fn(DartHandle, DartHandle, i32, *mut DartHandle) -> DartHandle;

struct Api {
    load_elf: LoadElf,
    complete: Complete,
    complete_error: CompleteError,
    is_error: IsError,
    get_error: GetError,
    lookup_library: LookupLibrary,
    new_string: NewString,
    new_integer: NewInteger,
    new_boolean: NewBoolean,
    null: Null,
    invoke: Invoke,
}

/// A unit: where it lies, and once mapped, its snapshot's two halves.
struct Unit {
    path: CString,
    offset: u64,
    mapped: Option<(usize, usize)>,
    /// Whether the VM took it: from then on the isolate group has its code.
    completed: bool,
}

static API: OnceCell<Option<Api>> = OnceCell::new();
static UNITS: OnceCell<Mutex<HashMap<isize, Unit>>> = OnceCell::new();

fn units() -> &'static Mutex<HashMap<isize, Unit>> {
    UNITS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(unix)]
fn api() -> Option<&'static Api> {
    API.get_or_init(|| unsafe {
        let find = |name: &str| {
            let name = CString::new(name).ok()?;
            let found = libc::dlsym(libc::RTLD_DEFAULT, name.as_ptr());
            if found.is_null() { None } else { Some(found) }
        };
        Some(Api {
            load_elf: std::mem::transmute::<*mut c_void, LoadElf>(find("Dart_LoadELF")?),
            complete: std::mem::transmute::<*mut c_void, Complete>(find("Dart_DeferredLoadComplete")?),
            complete_error: std::mem::transmute::<*mut c_void, CompleteError>(
                find("Dart_DeferredLoadCompleteError")?,
            ),
            is_error: std::mem::transmute::<*mut c_void, IsError>(find("Dart_IsError")?),
            get_error: std::mem::transmute::<*mut c_void, GetError>(find("Dart_GetError")?),
            lookup_library: std::mem::transmute::<*mut c_void, LookupLibrary>(find("Dart_LookupLibrary")?),
            new_string: std::mem::transmute::<*mut c_void, NewString>(find("Dart_NewStringFromCString")?),
            new_integer: std::mem::transmute::<*mut c_void, NewInteger>(find("Dart_NewInteger")?),
            new_boolean: std::mem::transmute::<*mut c_void, NewBoolean>(find("Dart_NewBoolean")?),
            null: std::mem::transmute::<*mut c_void, Null>(find("Dart_Null")?),
            invoke: std::mem::transmute::<*mut c_void, Invoke>(find("Dart_Invoke")?),
        })
    })
    .as_ref()
}

#[cfg(not(unix))]
fn api() -> Option<&'static Api> {
    None
}

/// Whether this process's runtime exports what loading a unit takes.
#[no_mangle]
pub extern "C" fn aw_units_supported() -> i32 {
    api().is_some() as i32
}

/// Records that unit `id` is the ELF at `offset` in the file `path` (UTF-8,
/// `path_len` bytes). Returns 0, or 1 for a path that is not a C string.
///
/// # Safety
/// `path` must be valid for `path_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn aw_units_register(id: isize, path: *const u8, path_len: usize, offset: u64) -> i32 {
    if path.is_null() {
        return 1;
    }
    let bytes = std::slice::from_raw_parts(path, path_len).to_vec();
    let Ok(path) = CString::new(bytes) else { return 1 };
    units().lock().unwrap_or_else(|e| e.into_inner()).insert(id, Unit { path, offset, mapped: None, completed: false });
    0
}

/// How many units have been mapped so far.
#[no_mangle]
pub extern "C" fn aw_units_loaded() -> i32 {
    units().lock().unwrap_or_else(|e| e.into_inner()).values().filter(|u| u.completed).count() as i32
}

/// The VM's deferred-load handler: maps unit `id` from the executable the
/// first time any isolate asks, and completes that isolate's load with it.
///
/// Another isolate of the same group that asks later is also sent here --
/// the VM keeps whether a prefix is loaded per isolate, and whether a unit
/// is loaded per group -- and the VM refuses to take the same unit twice
/// ("Unit already loaded"). The group already has the code, so that isolate
/// only needs its own pending `loadLibrary()` completed: this calls its
/// `dart:core` `_completeLoads(id, null, false)`, which is what the VM
/// itself calls after taking a unit.
///
/// Serialized: an isolate asking while another is still taking the unit
/// waits until it has, rather than running code the group does not yet have.
///
/// # Safety
/// Called by the VM, on the isolate that asked, with that isolate entered
/// and an API scope open.
#[no_mangle]
pub unsafe extern "C" fn aw_units_load(id: isize) -> DartHandle {
    let Some(api) = api() else {
        return std::ptr::null_mut();
    };
    let fail = |why: String| {
        eprintln!("dartvel: {why}");
        let message = CString::new(why).unwrap_or_default();
        (api.complete_error)(id, message.as_ptr(), false)
    };
    let report = |done: DartHandle| {
        if (api.is_error)(done) {
            let why = (api.get_error)(done);
            if !why.is_null() {
                eprintln!("dartvel: code unit {id}: {}", std::ffi::CStr::from_ptr(why).to_string_lossy());
            }
        }
        done
    };
    let mut table = units().lock().unwrap_or_else(|e| e.into_inner());
    let Some(unit) = table.get_mut(&id) else {
        drop(table);
        return fail(format!("this binary carries no code unit {id}"));
    };
    if unit.completed {
        let core = CString::new("dart:core").unwrap_or_default();
        let name = CString::new("_completeLoads").unwrap_or_default();
        let library = (api.lookup_library)((api.new_string)(core.as_ptr()));
        let mut arguments = [(api.new_integer)(id as i64), (api.null)(), (api.new_boolean)(false)];
        return report((api.invoke)(library, (api.new_string)(name.as_ptr()), 3, arguments.as_mut_ptr()));
    }
    let (data, text) = match unit.mapped {
        Some(mapped) => mapped,
        None => {
            let mut error: *const c_char = std::ptr::null();
            let (mut vm_data, mut vm_text, mut data, mut text) =
                (std::ptr::null(), std::ptr::null(), std::ptr::null(), std::ptr::null());
            // Never unloaded: the VM runs this code from here on.
            let loaded = (api.load_elf)(
                unit.path.as_ptr(),
                unit.offset,
                &mut error,
                &mut vm_data,
                &mut vm_text,
                &mut data,
                &mut text,
            );
            if loaded.is_null() {
                let why = if error.is_null() {
                    "unknown error".to_string()
                } else {
                    std::ffi::CStr::from_ptr(error).to_string_lossy().into_owned()
                };
                drop(table);
                return fail(format!("code unit {id} could not be mapped: {why}"));
            }
            // A unit's snapshot is reported under whichever pair of symbols
            // the loader found it by.
            let data = if data.is_null() { vm_data } else { data };
            let text = if text.is_null() { vm_text } else { text };
            unit.mapped = Some((data as usize, text as usize));
            (data as usize, text as usize)
        }
    };
    let done = (api.complete)(id, data as *const u8, text as *const u8);
    if !(api.is_error)(done) {
        unit.completed = true;
    }
    drop(table);
    report(done)
}

/// Whether unit `id` has been taken by the VM.
#[no_mangle]
pub extern "C" fn aw_units_completed(id: isize) -> i32 {
    units().lock().unwrap_or_else(|e| e.into_inner()).get(&id).map_or(0, |u| u.completed as i32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_unit_is_recorded_and_not_mapped_until_asked_for() {
        let path = b"/srv/app/server";
        assert_eq!(unsafe { aw_units_register(7, path.as_ptr(), path.len(), 65536) }, 0);
        let table = units().lock().unwrap();
        let unit = table.get(&7).unwrap();
        assert_eq!(unit.offset, 65536);
        assert_eq!(unit.path.as_bytes(), path);
        assert!(unit.mapped.is_none());
        assert!(!unit.completed);
    }

    #[test]
    fn a_path_with_a_nul_is_refused() {
        let path = b"/srv/a\0b";
        assert_eq!(unsafe { aw_units_register(8, path.as_ptr(), path.len(), 0) }, 1);
    }

    #[test]
    fn a_test_binary_exports_no_dart_api() {
        // cargo's test harness is not a Dart runtime: nothing to load with.
        assert_eq!(aw_units_supported(), 0);
    }
}
