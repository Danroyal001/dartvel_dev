// Port of flutter/fml/synchronization/waitable_event_unittest.cc.

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

use super::waitable_event::{AutoResetWaitableEvent, ManualResetWaitableEvent};
use crate::time::time_delta::TimeDelta;

const K_EPSILON_TIMEOUT: TimeDelta = TimeDelta::from_milliseconds(20);
const K_TINY_TIMEOUT: TimeDelta = TimeDelta::from_milliseconds(100);
const K_ACTION_TIMEOUT: TimeDelta = TimeDelta::from_milliseconds(10000);

// rand(): any cheap per-process sequence will do.
fn rand() -> u32 {
    static STATE: AtomicU64 = AtomicU64::new(0x2545F4914F6CDD1D);
    let mut x = STATE.fetch_add(0x9e3779b97f4a7c15, Ordering::Relaxed);
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    (x >> 33) as u32
}

// Sleeps for a "very small" amount of time.
fn sleep_for(duration: TimeDelta) {
    std::thread::sleep(std::time::Duration::from_nanos(duration.to_nanoseconds() as u64));
}

fn epsilon_random_sleep() {
    let duration = TimeDelta::from_milliseconds((rand() % 20) as i64);
    sleep_for(duration);
}

// AutoResetWaitableEvent ------------------------------------------------------

#[test]
fn auto_reset_basic() {
    let ev = AutoResetWaitableEvent::new();
    assert!(!ev.is_signaled_for_test());
    ev.signal();
    assert!(ev.is_signaled_for_test());
    ev.wait();
    assert!(!ev.is_signaled_for_test());
    ev.reset();
    assert!(!ev.is_signaled_for_test());
    ev.signal();
    assert!(ev.is_signaled_for_test());
    ev.reset();
    assert!(!ev.is_signaled_for_test());
    assert!(ev.wait_with_timeout(TimeDelta::zero()));
    assert!(!ev.is_signaled_for_test());
    assert!(ev.wait_with_timeout(TimeDelta::from_milliseconds(1)));
    assert!(!ev.is_signaled_for_test());
    ev.signal();
    assert!(ev.is_signaled_for_test());
    assert!(!ev.wait_with_timeout(TimeDelta::zero()));
    assert!(!ev.is_signaled_for_test());
    assert!(ev.wait_with_timeout(TimeDelta::from_milliseconds(1)));
    assert!(!ev.is_signaled_for_test());
    ev.signal();
    assert!(!ev.wait_with_timeout(TimeDelta::from_milliseconds(1)));
    assert!(!ev.is_signaled_for_test());
}

#[test]
fn auto_reset_multiple_waiters() {
    let ev = AutoResetWaitableEvent::new();

    for _ in 0..5 {
        let wake_count = AtomicU32::new(0);
        std::thread::scope(|s| {
            let mut threads = Vec::with_capacity(4);
            for _ in 0..4 {
                threads.push(s.spawn(|| {
                    if rand() % 2 == 0 {
                        ev.wait();
                    } else {
                        assert!(!ev.wait_with_timeout(K_ACTION_TIMEOUT));
                    }
                    wake_count.fetch_add(1, Ordering::SeqCst);
                    // Note: We can't say anything about the signaled state of
                    // |ev| here, since the main thread may have already
                    // signaled it again.
                }));
            }

            // Unfortunately, we can't really wait for the threads to be
            // waiting, so we just sleep for a bit, and count on them having
            // started and advanced to waiting.
            sleep_for(K_TINY_TIMEOUT + K_TINY_TIMEOUT);

            for j in 0..threads.len() as u32 {
                let old_wake_count = wake_count.load(Ordering::SeqCst);
                assert_eq!(j, old_wake_count);

                // Each |Signal()| should wake exactly one thread.
                ev.signal();

                // Poll for |wake_count| to change.
                while wake_count.load(Ordering::SeqCst) == old_wake_count {
                    sleep_for(K_EPSILON_TIMEOUT);
                }

                assert!(!ev.is_signaled_for_test());

                // And once it's changed, wait a little longer, to see if any
                // other threads are awoken (they shouldn't be).
                sleep_for(K_EPSILON_TIMEOUT);

                assert_eq!(old_wake_count + 1, wake_count.load(Ordering::SeqCst));

                assert!(!ev.is_signaled_for_test());
            }

            // Having done that, if we signal |ev| now, it should stay signaled.
            ev.signal();
            sleep_for(K_EPSILON_TIMEOUT);
            assert!(ev.is_signaled_for_test());
        });
        ev.reset();
    }
}

// ManualResetWaitableEvent ----------------------------------------------------

#[test]
fn manual_reset_basic() {
    let ev = ManualResetWaitableEvent::new();
    assert!(!ev.is_signaled_for_test());
    ev.signal();
    assert!(ev.is_signaled_for_test());
    ev.wait();
    assert!(ev.is_signaled_for_test());
    ev.reset();
    assert!(!ev.is_signaled_for_test());
    assert!(ev.wait_with_timeout(TimeDelta::zero()));
    assert!(!ev.is_signaled_for_test());
    assert!(ev.wait_with_timeout(TimeDelta::from_milliseconds(1)));
    assert!(!ev.is_signaled_for_test());
    ev.signal();
    assert!(ev.is_signaled_for_test());
    assert!(!ev.wait_with_timeout(TimeDelta::zero()));
    assert!(ev.is_signaled_for_test());
    assert!(!ev.wait_with_timeout(TimeDelta::from_milliseconds(1)));
    assert!(ev.is_signaled_for_test());
}

#[test]
fn manual_reset_signal_multiple() {
    let ev = ManualResetWaitableEvent::new();

    for _ in 0..10 {
        for num_waiters in 1..5 {
            std::thread::scope(|s| {
                for _ in 0..num_waiters {
                    s.spawn(|| {
                        epsilon_random_sleep();

                        if rand() % 2 == 0 {
                            ev.wait();
                        } else {
                            assert!(!ev.wait_with_timeout(K_ACTION_TIMEOUT));
                        }
                    });
                }

                epsilon_random_sleep();

                ev.signal();

                // The threads will only terminate once they've successfully
                // waited (or timed out).
            });

            ev.reset();
        }
    }
}
