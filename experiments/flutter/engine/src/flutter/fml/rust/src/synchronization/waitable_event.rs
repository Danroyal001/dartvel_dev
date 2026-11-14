// Port of flutter/fml/synchronization/waitable_event.h and
// flutter/fml/synchronization/waitable_event.cc.

use std::sync::{Condvar, Mutex, MutexGuard};
use std::time::Duration;

use crate::time::time_delta::TimeDelta;
use crate::time::time_point::TimePoint;

/// `cv->wait_for(*locker, nanoseconds)` as libc++ does it: a duration that is
/// not positive times out at once, without waiting. Returns the guard and
/// whether it timed out.
fn wait_for<'a, T>(
    cv: &Condvar,
    locker: MutexGuard<'a, T>,
    timeout: TimeDelta,
) -> (MutexGuard<'a, T>, bool) {
    let nanos = timeout.to_nanoseconds();
    if nanos <= 0 {
        return (locker, true);
    }
    let (guard, result) = cv
        .wait_timeout(locker, Duration::from_nanos(nanos as u64))
        .unwrap_or_else(|e| e.into_inner());
    (guard, result.timed_out())
}

fn wait_with_timeout_impl<'a, T>(
    locker: MutexGuard<'a, T>,
    cv: &Condvar,
    condition: impl Fn(&T) -> bool,
    timeout: TimeDelta,
) -> (MutexGuard<'a, T>, bool) {
    if condition(&locker) {
        return (locker, false);
    }

    let mut locker = locker;
    let mut wait_remaining = timeout;
    let start = TimePoint::now();
    loop {
        let (guard, timed_out) = wait_for(cv, locker, wait_remaining);
        locker = guard;
        if timed_out {
            return (locker, true); // Definitely timed out.
        }

        // We may have been awoken.
        if condition(&locker) {
            return (locker, false);
        }

        // Or the wakeup may have been spurious.
        let now = TimePoint::now();
        debug_assert!(now >= start);
        let elapsed = now - start;
        // It's possible that we may have timed out anyway.
        if elapsed >= timeout {
            return (locker, true);
        }

        // Otherwise, recalculate the amount that we have left to wait.
        wait_remaining = timeout - elapsed;
    }
}

// AutoResetWaitableEvent ------------------------------------------------------

#[derive(Default)]
pub struct AutoResetWaitableEvent {
    cv_: Condvar,
    mutex_: Mutex<bool>, // signaled_
}

impl AutoResetWaitableEvent {
    pub fn new() -> Self {
        Self::default()
    }

    fn lock(&self) -> MutexGuard<'_, bool> {
        self.mutex_.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn signal(&self) {
        let mut signaled = self.lock();
        *signaled = true;
        self.cv_.notify_one();
    }

    pub fn reset(&self) {
        *self.lock() = false;
    }

    pub fn wait(&self) {
        let mut signaled = self.lock();
        while !*signaled {
            signaled = self.cv_.wait(signaled).unwrap_or_else(|e| e.into_inner());
        }
        *signaled = false;
    }

    pub fn wait_with_timeout(&self, timeout: TimeDelta) -> bool {
        let mut locker = self.lock();

        if *locker {
            *locker = false;
            return false;
        }

        // Potentially spurious wakeups are handled here.
        let mut wait_remaining = timeout;
        let start = TimePoint::now();
        loop {
            let (guard, timed_out) = wait_for(&self.cv_, locker, wait_remaining);
            locker = guard;
            if timed_out {
                return true; // Definitely timed out.
            }

            // We may have been awoken.
            if *locker {
                break;
            }

            // Or the wakeup may have been spurious.
            let now = TimePoint::now();
            debug_assert!(now >= start);
            let elapsed = now - start;
            // It's possible that we may have timed out anyway.
            if elapsed >= timeout {
                return true;
            }

            // Otherwise, recalculate the amount that we have left to wait.
            wait_remaining = timeout - elapsed;
        }

        *locker = false;
        false
    }

    pub fn is_signaled_for_test(&self) -> bool {
        *self.lock()
    }
}

// ManualResetWaitableEvent ----------------------------------------------------

#[derive(Default)]
struct ManualState {
    signaled_: bool,
    // Use an ID to indicate that a signal has been sent, so that a thread that
    // was woken (by a signal) and then saw the event reset still returns.
    signal_id_: u32,
}

#[derive(Default)]
pub struct ManualResetWaitableEvent {
    cv_: Condvar,
    mutex_: Mutex<ManualState>,
}

impl ManualResetWaitableEvent {
    pub fn new() -> Self {
        Self::default()
    }

    fn lock(&self) -> MutexGuard<'_, ManualState> {
        self.mutex_.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn signal(&self) {
        let mut state = self.lock();
        state.signaled_ = true;
        state.signal_id_ = state.signal_id_.wrapping_add(1);
        self.cv_.notify_all();
    }

    pub fn reset(&self) {
        self.lock().signaled_ = false;
    }

    pub fn wait(&self) {
        let mut locker = self.lock();

        if locker.signaled_ {
            return;
        }

        let last_signal_id = locker.signal_id_;
        loop {
            locker = self.cv_.wait(locker).unwrap_or_else(|e| e.into_inner());
            if locker.signal_id_ != last_signal_id {
                break;
            }
        }
    }

    pub fn wait_with_timeout(&self, timeout: TimeDelta) -> bool {
        let locker = self.lock();

        let last_signal_id = locker.signal_id_;
        // Disable thread-safety analysis for the lambda: We could annotate it
        // with |FML_EXCLUSIVE_LOCKS_REQUIRED(mutex_)|, but then the analyzer
        // currently isn't able to figure out that |WaitWithTimeoutImpl()| calls
        // it while holding |mutex_|.
        let (locker, rv) = wait_with_timeout_impl(
            locker,
            &self.cv_,
            |s: &ManualState| s.signaled_ || s.signal_id_ != last_signal_id,
            timeout,
        );
        debug_assert!(rv || locker.signaled_ || locker.signal_id_ != last_signal_id);
        rv
    }

    pub fn is_signaled_for_test(&self) -> bool {
        self.lock().signaled_
    }
}
