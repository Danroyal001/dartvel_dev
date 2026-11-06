// Port of flutter/fml/wakeable.h.

use crate::time::time_point::TimePoint;

/// Interface over the ability to `wake_up` a `fml::MessageLoopImpl`.
/// See `fml::MessageLoopTaskQueues`.
pub trait Wakeable: Send + Sync {
    fn wake_up(&self, time_point: TimePoint);
}
