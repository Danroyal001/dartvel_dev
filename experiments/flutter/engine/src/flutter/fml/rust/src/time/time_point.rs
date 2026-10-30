// Port of flutter/fml/time/time_point.h and flutter/fml/time/time_point.cc.
//
// Now() reads the same clock as libc++'s std::chrono::steady_clock
// (CLOCK_MONOTONIC on Linux and Android, CLOCK_UPTIME_RAW on Apple), because
// the engine compares it with timestamps the platform hands it (vsync,
// input events) in that clock. Rust's std has no way to read that clock's
// epoch, so it is called through the C library; see `steady_clock_now`.
// Fuchsia's zx_clock_get_monotonic branch is not ported.

use std::cmp::Ordering;
use std::ops::{Add, Sub};
use std::sync::RwLock;
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};

use super::time_delta::TimeDelta;

pub type ClockSource = fn() -> TimePoint;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct TimePoint {
    ticks_: i64,
}

// `std::atomic<TimePoint::ClockSource> gSteadyClockSource`. A function
// pointer cannot be loaded from an atomic without `unsafe`, so the pointer
// sits behind a lock and a flag keeps Now()'s common path to one relaxed
// load.
#[allow(non_upper_case_globals)]
static gSteadyClockSourceSet: AtomicBool = AtomicBool::new(false);
#[allow(non_upper_case_globals)]
static gSteadyClockSource: RwLock<Option<ClockSource>> = RwLock::new(None);

impl TimePoint {
    pub fn set_clock_source(source: Option<ClockSource>) {
        let mut guard = gSteadyClockSource.write().unwrap_or_else(|e| e.into_inner());
        *guard = source;
        gSteadyClockSourceSet.store(source.is_some(), AtomicOrdering::SeqCst);
    }

    pub fn now() -> TimePoint {
        if gSteadyClockSourceSet.load(AtomicOrdering::Relaxed) {
            let source = *gSteadyClockSource.read().unwrap_or_else(|e| e.into_inner());
            if let Some(source) = source {
                return source();
            }
        }
        let nanos = steady_clock_now();
        TimePoint::from_ticks(nanos)
    }

    pub fn current_wall_time() -> TimePoint {
        // std::chrono::system_clock: nanoseconds since the Unix epoch, negative
        // before it.
        let now = std::time::SystemTime::now();
        let nanos = match now.duration_since(std::time::UNIX_EPOCH) {
            Ok(d) => d.as_nanos() as i64,
            Err(e) => -(e.duration().as_nanos() as i64),
        };
        TimePoint::from_ticks(nanos)
    }

    pub const fn min() -> TimePoint {
        TimePoint { ticks_: i64::MIN }
    }

    pub const fn max() -> TimePoint {
        TimePoint { ticks_: i64::MAX }
    }

    pub const fn from_epoch_delta(ticks: TimeDelta) -> TimePoint {
        TimePoint { ticks_: ticks.to_nanoseconds() }
    }

    /// Expects ticks in nanos.
    pub const fn from_ticks(ticks: i64) -> TimePoint {
        TimePoint { ticks_: ticks }
    }

    pub const fn to_epoch_delta(self) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.ticks_)
    }
}

/// Compute the difference between two time points.
impl Sub for TimePoint {
    type Output = TimeDelta;
    fn sub(self, other: TimePoint) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.ticks_.wrapping_sub(other.ticks_))
    }
}

impl Add<TimeDelta> for TimePoint {
    type Output = TimePoint;
    fn add(self, duration: TimeDelta) -> TimePoint {
        TimePoint::from_ticks(self.ticks_.wrapping_add(duration.to_nanoseconds()))
    }
}

impl Sub<TimeDelta> for TimePoint {
    type Output = TimePoint;
    fn sub(self, duration: TimeDelta) -> TimePoint {
        TimePoint::from_ticks(self.ticks_.wrapping_sub(duration.to_nanoseconds()))
    }
}

impl PartialOrd for TimePoint {
    fn partial_cmp(&self, other: &TimePoint) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for TimePoint {
    fn cmp(&self, other: &TimePoint) -> Ordering {
        self.ticks_.cmp(&other.ticks_)
    }
}

/// `NanosSinceEpoch(std::chrono::steady_clock::now())` as libc++ computes it.
#[cfg(any(target_os = "linux", target_os = "android"))]
pub(crate) fn steady_clock_now() -> i64 {
    use super::time_delta::timespec;
    unsafe extern "C" {
        fn clock_gettime(clock_id: i32, tp: *mut timespec) -> i32;
    }
    const CLOCK_MONOTONIC: i32 = 1;
    let mut ts = timespec::default();
    // SAFETY: `ts` is a live, writable `struct timespec` with the C layout
    // (`#[repr(C)]`, 64-bit time_t and long on the targets this cfg admits),
    // and clock_gettime writes only that struct. CLOCK_MONOTONIC cannot fail
    // on Linux; libc++ treats a failure as fatal, so does this.
    let rc = unsafe { clock_gettime(CLOCK_MONOTONIC, &mut ts) };
    assert_eq!(rc, 0, "clock_gettime(CLOCK_MONOTONIC) failed");
    TimeDelta::from_timespec(ts).to_nanoseconds()
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub(crate) fn steady_clock_now() -> i64 {
    unsafe extern "C" {
        fn clock_gettime_nsec_np(clock_id: u32) -> u64;
    }
    const CLOCK_UPTIME_RAW: u32 = 8;
    // SAFETY: clock_gettime_nsec_np takes a clock id by value and touches no
    // memory of ours.
    unsafe { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) as i64 }
}

#[cfg(not(any(
    target_os = "linux",
    target_os = "android",
    target_os = "macos",
    target_os = "ios"
)))]
pub(crate) fn steady_clock_now() -> i64 {
    // Monotonic, but with a process-local epoch: not comparable with platform
    // timestamps. Only the targets above are supported.
    use std::sync::OnceLock;
    static ORIGIN: OnceLock<std::time::Instant> = OnceLock::new();
    ORIGIN.get_or_init(std::time::Instant::now).elapsed().as_nanos() as i64 + 1
}
