// Port of flutter/fml/time/time_point_unittest.cc.
//
// DartClockIsMonotonic exercises flutter/runtime's DartTimestampProvider,
// which is outside fml and not ported yet.

use super::chrono_timestamp_provider::chrono_ticks_since_epoch;
use super::time_point::TimePoint;

#[test]
fn time_point_control() {
    assert!(TimePoint::min() < chrono_ticks_since_epoch());
    assert!(TimePoint::max() > chrono_ticks_since_epoch());
}
