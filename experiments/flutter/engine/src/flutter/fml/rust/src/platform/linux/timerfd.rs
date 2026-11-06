// Port of flutter/fml/platform/linux/timerfd.h and
// flutter/fml/platform/linux/timerfd.cc.
//
// The C library's timerfd_create and timerfd_settime are called directly; the
// syscall fallback upstream keeps for Android before API 19 is not needed by
// the targets this port builds for.

use std::os::raw::{c_int, c_void};

use crate::eintr_wrapper::handle_eintr;
use crate::fml_dlog_at;
use crate::time::time_delta::timespec;
use crate::time::time_point::TimePoint;

const FILE: &str = "flutter/fml/platform/linux/timerfd.cc";

pub const TFD_TIMER_ABSTIME: c_int = 1 << 0;
pub const TFD_TIMER_CANCEL_ON_SET: c_int = 1 << 1;
/// `O_CLOEXEC` on Linux.
pub const TFD_CLOEXEC: c_int = 0o2000000;
/// `O_NONBLOCK` on Linux.
pub const TFD_NONBLOCK: c_int = 0o4000;

const NSEC_PER_SEC: u64 = 1000000000;

#[allow(non_camel_case_types)]
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct itimerspec {
    pub it_interval: timespec,
    pub it_value: timespec,
}

// SAFETY: declarations only, each matching its prototype in <sys/timerfd.h>
// for the LP64 Linux/Apple targets this crate builds for; every call
// below is in its own unsafe block that says why it is sound.
unsafe extern "C" {
    #[link_name = "timerfd_create"]
    fn c_timerfd_create(clockid: c_int, flags: c_int) -> c_int;
    #[link_name = "timerfd_settime"]
    fn c_timerfd_settime(
        fd: c_int,
        flags: c_int,
        new_value: *const itimerspec,
        old_value: *mut itimerspec,
    ) -> c_int;
    fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
}

pub fn timerfd_create(clockid: c_int, flags: c_int) -> c_int {
    // SAFETY: timerfd_create takes two integers and touches no memory of ours.
    unsafe { c_timerfd_create(clockid, flags) }
}

/// Rearms the timer to expire at the given time point.
pub fn timer_rearm(fd: c_int, time_point: TimePoint) -> bool {
    let mut nano_secs = time_point.to_epoch_delta().to_nanoseconds() as u64;

    // "0" will disarm the timer, desired behavior is to immediately
    // trigger the timer.
    if nano_secs < 1 {
        nano_secs = 1;
    }

    let mut spec = itimerspec::default();
    spec.it_value.tv_sec = (nano_secs / NSEC_PER_SEC) as i64;
    spec.it_value.tv_nsec = (nano_secs % NSEC_PER_SEC) as std::os::raw::c_long;
    spec.it_interval = spec.it_value; // single expiry.

    // SAFETY: `spec` is a live `struct itimerspec` (repr(C), two timespecs of
    // 64-bit fields on the targets this module builds for) that the call only
    // reads; the old value pointer is null, which timerfd_settime allows.
    let result =
        unsafe { c_timerfd_settime(fd, TFD_TIMER_ABSTIME, &spec, std::ptr::null_mut()) };
    if result != 0 {
        fml_dlog_at!(kLogError, FILE, 54, "timerfd_settime err:{}", strerror_last());
    }
    result == 0
}

/// Drains the timer FD and returns true if it has expired. This may be false
/// in case the timer read is non-blocking and this routine was called before
/// the timer expiry.
pub fn timer_drain(fd: c_int) -> bool {
    // 8 bytes must be read from a signaled timer file descriptor when signaled.
    let mut fire_count: u64 = 0;
    let size = handle_eintr(|| {
        // SAFETY: `fire_count` is a live, writable u64 and the call writes at
        // most `size_of::<u64>()` bytes into it.
        unsafe {
            read(fd, (&mut fire_count as *mut u64).cast::<c_void>(), std::mem::size_of::<u64>())
        }
    });
    if size != std::mem::size_of::<u64>() as isize {
        return false;
    }
    fire_count > 0
}

/// `strerror(errno)`: the message `std::io::Error` carries, without its
/// " (os error N)" suffix.
fn strerror_last() -> String {
    let error = std::io::Error::last_os_error();
    let text = error.to_string();
    match text.rfind(" (os error ") {
        Some(at) => text[..at].to_string(),
        None => text,
    }
}
