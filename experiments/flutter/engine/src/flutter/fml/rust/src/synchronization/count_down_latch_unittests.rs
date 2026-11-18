// Port of flutter/fml/synchronization/count_down_latch_unittests.cc.
//
// CanWait posts its tasks to an fml::Thread, which is not ported yet; a
// thread running the same tasks in order stands in for it.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;

use super::count_down_latch::CountDownLatch;

#[test]
fn can_wait_on_zero() {
    let latch = CountDownLatch::new(0);
    latch.wait();
}

#[test]
fn can_wait() {
    const COUNT: usize = 100;
    let current_count = AtomicUsize::new(0);
    let latch = CountDownLatch::new(COUNT);
    std::thread::scope(|s| {
        let (runner, tasks) = mpsc::channel::<Box<dyn FnOnce() + Send + '_>>();
        s.spawn(move || {
            for task in tasks {
                task();
            }
        });
        for _ in 0..COUNT {
            let (latch, current_count) = (&latch, &current_count);
            runner
                .send(Box::new(move || {
                    std::thread::sleep(std::time::Duration::from_micros(100));
                    current_count.fetch_add(1, Ordering::SeqCst);
                    latch.count_down();
                }))
                .unwrap();
        }
        latch.wait();
        assert_eq!(current_count.load(Ordering::SeqCst), COUNT);
    });
}
