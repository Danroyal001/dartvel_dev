// Port of flutter/fml/platform/posix/process_posix.cc.

/// getpid(), which std calls for `std::process::id()`.
pub fn get_current_proc_id() -> i32 {
    std::process::id() as i32
}
