// Port of flutter/fml/time/timestamp_provider.h.

use super::time_point::TimePoint;

pub trait TimestampProvider {
    /// Returns the number of ticks elapsed by a monotonic clock since epoch.
    fn now(&self) -> TimePoint;
}
