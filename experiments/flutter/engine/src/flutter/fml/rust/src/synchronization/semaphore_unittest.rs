// Port of flutter/fml/synchronization/semaphore_unittest.cc.
//
// IndefiniteWait posts the signal to an fml::Thread for a target time; a
// thread sleeping until that time stands in for it.

use super::semaphore::Semaphore;
use crate::time::time_delta::TimeDelta;
use crate::time::time_point::TimePoint;

#[test]
fn simple_validity() {
    let sem = Semaphore::new(100);
    assert!(sem.is_valid());
}

#[test]
fn wait_on_zero() {
    let sem = Semaphore::new(0);
    assert!(!sem.try_wait());
}

#[test]
fn wait_on_zero_signal_then_wait() {
    let sem = Semaphore::new(0);
    assert!(!sem.try_wait());
    std::thread::scope(|s| {
        s.spawn(|| sem.signal());
    });
    assert!(sem.try_wait());
    assert!(!sem.try_wait());
}

#[test]
fn indefinite_wait() {
    let start = TimePoint::now();
    const WAIT_IN_SECONDS: f64 = 0.25;
    let sem = Semaphore::new(0);
    assert!(sem.is_valid());
    let target = start + TimeDelta::from_seconds_f(WAIT_IN_SECONDS);
    std::thread::scope(|s| {
        s.spawn(|| {
            let remaining = target - TimePoint::now();
            if remaining > TimeDelta::zero() {
                std::thread::sleep(std::time::Duration::from_nanos(
                    remaining.to_nanoseconds() as u64,
                ));
            }
            sem.signal();
        });
        assert!(sem.wait());
        let delta = TimePoint::now() - start;
        assert!(delta.to_seconds_f() >= WAIT_IN_SECONDS);
    });
}

// Not upstream: sem_init's SEM_VALUE_MAX limit, which the POSIX branch
// inherits.
#[test]
fn count_above_sem_value_max_is_invalid() {
    let sem = Semaphore::new(i32::MAX as u32 + 1);
    assert!(!sem.is_valid());
    assert!(!sem.try_wait());
    assert!(Semaphore::new(i32::MAX as u32).is_valid());
}
