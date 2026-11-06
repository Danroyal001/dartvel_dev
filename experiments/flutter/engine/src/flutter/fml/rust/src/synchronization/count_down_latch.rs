// Port of flutter/fml/synchronization/count_down_latch.h and
// flutter/fml/synchronization/count_down_latch.cc.

use std::sync::atomic::{AtomicUsize, Ordering};

use super::waitable_event::ManualResetWaitableEvent;

pub struct CountDownLatch {
    count_: AtomicUsize,
    waitable_event_: ManualResetWaitableEvent,
}

impl CountDownLatch {
    pub fn new(count: usize) -> Self {
        let latch = CountDownLatch {
            count_: AtomicUsize::new(count),
            waitable_event_: ManualResetWaitableEvent::new(),
        };
        if count == 0 {
            latch.waitable_event_.signal();
        }
        latch
    }

    pub fn wait(&self) {
        self.waitable_event_.wait();
    }

    pub fn count_down(&self) {
        // `--count_` on a std::atomic_size_t: wraps below zero.
        if self.count_.fetch_sub(1, Ordering::SeqCst).wrapping_sub(1) == 0 {
            self.waitable_event_.signal();
        }
    }
}
