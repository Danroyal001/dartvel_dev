// Port of flutter/fml/time/chrono_timestamp_provider.h and
// flutter/fml/time/chrono_timestamp_provider.cc.

use super::time_point::{TimePoint, steady_clock_now};
use super::timestamp_provider::TimestampProvider;

/// TimestampProvider implementation that is backed by std::chrono::steady_clock
/// meant to be used only in tests for `fml`. Other components needing the
/// current time ticks since epoch should instantiate their own time stamp
/// provider backed by Dart clock.
pub struct ChronoTimestampProvider {
    _private: (),
}

static INSTANCE: ChronoTimestampProvider = ChronoTimestampProvider { _private: () };

impl ChronoTimestampProvider {
    pub fn instance() -> &'static ChronoTimestampProvider {
        &INSTANCE
    }
}

impl TimestampProvider for ChronoTimestampProvider {
    fn now(&self) -> TimePoint {
        TimePoint::from_ticks(steady_clock_now())
    }
}

pub fn chrono_ticks_since_epoch() -> TimePoint {
    ChronoTimestampProvider::instance().now()
}
