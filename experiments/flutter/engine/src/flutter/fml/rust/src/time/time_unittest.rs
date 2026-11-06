// Port of flutter/fml/time/time_unittest.cc.

use super::chrono_timestamp_provider::chrono_ticks_since_epoch;
use super::time_delta::{TimeDelta, timespec};

fn expect_float_eq(expected: f64, actual: f64) {
    // gtest's EXPECT_FLOAT_EQ: within 4 ULPs as floats.
    let (e, a) = (expected as f32, actual as f32);
    let ulps = (e.to_bits() as i64 - a.to_bits() as i64).abs();
    assert!(ulps <= 4, "{expected} vs {actual}");
}

#[test]
fn time_now() {
    let start = chrono_ticks_since_epoch();
    for _ in 0..3 {
        let now = chrono_ticks_since_epoch();
        assert!(now >= start);
        std::thread::yield_now();
    }
}

#[test]
fn time_int_conversions() {
    // Integer conversions should all truncate, not round.
    let delta = TimeDelta::from_nanoseconds(102304506708);
    assert_eq!(102304506708, delta.to_nanoseconds());
    assert_eq!(102304506, delta.to_microseconds());
    assert_eq!(102304, delta.to_milliseconds());
    assert_eq!(102, delta.to_seconds());
}

#[test]
fn time_float_conversions() {
    // Float conversions should remain close to the original value.
    let delta = TimeDelta::from_nanoseconds(102304506708);
    expect_float_eq(102304506708.0, delta.to_nanoseconds_f());
    expect_float_eq(102304506.708, delta.to_microseconds_f());
    expect_float_eq(102304.506708, delta.to_milliseconds_f());
    expect_float_eq(102.304506708, delta.to_seconds_f());
}

#[test]
fn time_timespec_conversions() {
    let ts = timespec { tv_sec: 5, tv_nsec: 7 };
    let from_timespec = TimeDelta::from_timespec(ts);
    assert_eq!(5, from_timespec.to_seconds());
    assert_eq!(5 * 1000000000 + 7, from_timespec.to_nanoseconds());
    let to_timespec = from_timespec.to_timespec();
    assert_eq!(ts.tv_sec, to_timespec.tv_sec);
    assert_eq!(ts.tv_nsec, to_timespec.tv_nsec);
}
