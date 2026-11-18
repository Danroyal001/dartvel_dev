// Port of flutter/fml/time/time_delta.h.
//
// Arithmetic wraps on overflow. Upstream's signed overflow is undefined
// behaviour in C++; every compiler and target the engine ships with wraps,
// and the oracle is built with -fwrapv to pin that down. Division and
// remainder by zero, and i64::MIN / -1, trap in both.
//
// FromSecondsF/FromMillisecondsF convert a double to int64_t; a value out of
// range is undefined behaviour in C++, and the port converts it as the
// compiled C++ does (`double_to_i64`). The oracle only feeds them values in
// range.

use std::cmp::Ordering;
use std::ops::{Add, Div, Mul, Rem, Sub};

/// `static_cast<int64_t>(double)` as the compiled C++ performs it: on x86-64
/// the cvttsd2si instruction, which gives INT64_MIN for NaN and for anything
/// out of range (and costs nothing beyond itself, where Rust's saturating
/// `as` adds compares); elsewhere Rust's `as`, which saturates and maps NaN
/// to 0 as AArch64's fcvtzs does.
#[inline(always)]
fn double_to_i64(value: f64) -> i64 {
    #[cfg(all(target_arch = "x86_64", target_feature = "sse2"))]
    {
        use std::arch::x86_64::{_mm_cvttsd_si64, _mm_set_sd};
        // SAFETY: both intrinsics need only SSE2, which this cfg guarantees
        // is enabled (it is part of the x86-64 baseline); they read and
        // write registers only.
        unsafe { _mm_cvttsd_si64(_mm_set_sd(value)) }
    }
    #[cfg(not(all(target_arch = "x86_64", target_feature = "sse2")))]
    {
        value as i64
    }
}

/// `std::chrono::duration<double, std::milli>`.
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
pub struct Milliseconds(pub f64);

impl Milliseconds {
    pub const fn count(self) -> f64 {
        self.0
    }
}

/// `Milliseconds(1s) / 60`.
#[allow(non_upper_case_globals)]
pub const kDefaultFrameBudget: Milliseconds = Milliseconds(1000.0 / 60.0);

/// The arithmetic types `RefreshRateToFrameBudget` is instantiated with; each
/// converts to `double` as C++'s usual arithmetic conversions do.
pub trait RefreshRate: Copy {
    fn to_f64(self) -> f64;
}

macro_rules! refresh_rate {
    ($($t:ty),*) => {$(
        impl RefreshRate for $t {
            fn to_f64(self) -> f64 {
                self as f64
            }
        }
    )*};
}
refresh_rate!(i8, i16, i32, i64, isize, u8, u16, u32, u64, usize, f32, f64);

pub fn refresh_rate_to_frame_budget<T: RefreshRate>(refresh_rate: T) -> Milliseconds {
    Milliseconds(1000.0 / refresh_rate.to_f64())
}

/// `struct timespec` on the 64-bit targets the port builds for.
#[allow(non_camel_case_types)]
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct timespec {
    pub tv_sec: i64,
    pub tv_nsec: std::os::raw::c_long,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct TimeDelta {
    delta_: i64,
}

impl TimeDelta {
    pub const fn zero() -> TimeDelta {
        TimeDelta { delta_: 0 }
    }
    pub const fn min() -> TimeDelta {
        TimeDelta { delta_: i64::MIN }
    }
    pub const fn max() -> TimeDelta {
        TimeDelta { delta_: i64::MAX }
    }
    pub const fn from_nanoseconds(nanos: i64) -> TimeDelta {
        TimeDelta { delta_: nanos }
    }
    pub const fn from_microseconds(micros: i64) -> TimeDelta {
        Self::from_nanoseconds(micros.wrapping_mul(1000))
    }
    pub const fn from_milliseconds(millis: i64) -> TimeDelta {
        Self::from_microseconds(millis.wrapping_mul(1000))
    }
    pub const fn from_seconds(seconds: i64) -> TimeDelta {
        Self::from_milliseconds(seconds.wrapping_mul(1000))
    }

    pub fn from_seconds_f(seconds: f64) -> TimeDelta {
        Self::from_nanoseconds(double_to_i64(seconds * (1000.0 * 1000.0 * 1000.0)))
    }

    pub fn from_milliseconds_f(millis: f64) -> TimeDelta {
        Self::from_nanoseconds(double_to_i64(millis * (1000.0 * 1000.0)))
    }

    pub const fn to_nanoseconds(self) -> i64 {
        self.delta_
    }
    pub const fn to_microseconds(self) -> i64 {
        self.to_nanoseconds() / 1000
    }
    pub const fn to_milliseconds(self) -> i64 {
        self.to_microseconds() / 1000
    }
    pub const fn to_seconds(self) -> i64 {
        self.to_milliseconds() / 1000
    }

    pub fn to_nanoseconds_f(self) -> f64 {
        self.delta_ as f64
    }
    pub fn to_microseconds_f(self) -> f64 {
        self.delta_ as f64 / 1000.0
    }
    pub fn to_milliseconds_f(self) -> f64 {
        self.delta_ as f64 / (1000.0 * 1000.0)
    }
    pub fn to_seconds_f(self) -> f64 {
        self.delta_ as f64 / (1000.0 * 1000.0 * 1000.0)
    }

    pub const fn from_timespec(ts: timespec) -> TimeDelta {
        TimeDelta::from_seconds(ts.tv_sec)
            .add_const(TimeDelta::from_nanoseconds(ts.tv_nsec as i64))
    }

    pub fn to_timespec(self) -> timespec {
        const K_NANOSECONDS_PER_SECOND: i64 = 1000000000;
        timespec {
            tv_sec: self.to_seconds(),
            tv_nsec: (self.delta_ % K_NANOSECONDS_PER_SECOND) as std::os::raw::c_long,
        }
    }

    const fn add_const(self, other: TimeDelta) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.delta_.wrapping_add(other.delta_))
    }
}

impl Sub for TimeDelta {
    type Output = TimeDelta;
    fn sub(self, other: TimeDelta) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.delta_.wrapping_sub(other.delta_))
    }
}

impl Add for TimeDelta {
    type Output = TimeDelta;
    fn add(self, other: TimeDelta) -> TimeDelta {
        self.add_const(other)
    }
}

impl Div<i64> for TimeDelta {
    type Output = TimeDelta;
    fn div(self, divisor: i64) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.delta_ / divisor)
    }
}

impl Div<TimeDelta> for TimeDelta {
    type Output = i64;
    fn div(self, other: TimeDelta) -> i64 {
        self.delta_ / other.delta_
    }
}

impl Mul<i64> for TimeDelta {
    type Output = TimeDelta;
    fn mul(self, multiplier: i64) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.delta_.wrapping_mul(multiplier))
    }
}

impl Rem for TimeDelta {
    type Output = TimeDelta;
    fn rem(self, other: TimeDelta) -> TimeDelta {
        TimeDelta::from_nanoseconds(self.delta_ % other.delta_)
    }
}

// `operator<=>` = default.
impl PartialOrd for TimeDelta {
    fn partial_cmp(&self, other: &TimeDelta) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for TimeDelta {
    fn cmp(&self, other: &TimeDelta) -> Ordering {
        self.delta_.cmp(&other.delta_)
    }
}
