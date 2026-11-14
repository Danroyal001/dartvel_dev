// Port of flutter/fml/message_loop_unittests.cc.
//
// Upstream's tests capture locals by reference; these share them through
// `Arc`s. `ASSERT_*` inside a task becomes an assert whose failure is
// recorded and checked on the test's thread, since a panic on a loop thread
// would only end that thread.

use std::collections::BTreeSet;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use crate::concurrent_message_loop::ConcurrentMessageLoop;
use crate::message_loop::MessageLoop;
use crate::synchronization::count_down_latch::CountDownLatch;
use crate::synchronization::waitable_event::AutoResetWaitableEvent;
use crate::task_runner::BasicTaskRunner;
use crate::time::chrono_timestamp_provider::chrono_ticks_since_epoch;
use crate::time::time_delta::TimeDelta;

#[test]
fn get_current() {
    std::thread::spawn(|| {
        MessageLoop::ensure_initialized_for_current_thread();
        assert!(MessageLoop::get_current().get_task_runner().as_bool());
    })
    .join()
    .unwrap();
}

#[test]
fn different_threads_have_different_loops() {
    let spawn = || {
        let slot: Arc<Mutex<Option<MessageLoop>>> = Arc::default();
        let latch = Arc::new(AutoResetWaitableEvent::new());
        let term = Arc::new(AutoResetWaitableEvent::new());
        let thread = {
            let (slot, latch, term) = (slot.clone(), latch.clone(), term.clone());
            std::thread::spawn(move || {
                MessageLoop::ensure_initialized_for_current_thread();
                *slot.lock().unwrap() = Some(MessageLoop::get_current());
                latch.signal();
                term.wait();
            })
        };
        (slot, latch, term, thread)
    };
    let (loop1, latch1, term1, thread1) = spawn();
    let (loop2, latch2, term2, thread2) = spawn();
    latch1.wait();
    latch2.wait();
    let loop1 = loop1.lock().unwrap().take().unwrap();
    let loop2 = loop2.lock().unwrap().take().unwrap();
    assert!(!loop1.ptr_eq(&loop2));
    term1.signal();
    term2.signal();
    thread1.join().unwrap();
    thread2.join().unwrap();
}

#[test]
fn can_run_and_terminate() {
    let started = Arc::new(AtomicBool::new(false));
    let terminated = Arc::new(AtomicBool::new(false));
    {
        let (started, terminated) = (started.clone(), terminated.clone());
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            let loop_ = MessageLoop::get_current();
            assert!(loop_.get_task_runner().as_bool());
            loop_.get_task_runner().post_task(crate::closure::closure::new(move || {
                MessageLoop::get_current().terminate();
                terminated.store(true, Ordering::SeqCst);
            }));
            loop_.run();
            started.store(true, Ordering::SeqCst);
        })
        .join()
        .unwrap();
    }
    assert!(started.load(Ordering::SeqCst));
    assert!(terminated.load(Ordering::SeqCst));
}

/// Runs `count` tasks posted by `post` on a fresh loop thread; each checks
/// that it runs in posting order and the last terminates the loop.
fn run_in_order(post: impl Fn(&MessageLoop, crate::closure::closure) + Send + 'static) {
    const COUNT: usize = 100;
    let started = Arc::new(AtomicBool::new(false));
    let terminated = Arc::new(AtomicBool::new(false));
    {
        let (started, terminated) = (started.clone(), terminated.clone());
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            let loop_ = MessageLoop::get_current();
            let current = Arc::new(AtomicUsize::new(0));
            let in_order = Arc::new(AtomicBool::new(true));
            for i in 0..COUNT {
                let (current, in_order, terminated) =
                    (current.clone(), in_order.clone(), terminated.clone());
                post(
                    &loop_,
                    crate::closure::closure::new(move || {
                        if current.load(Ordering::SeqCst) != i {
                            in_order.store(false, Ordering::SeqCst);
                        }
                        current.fetch_add(1, Ordering::SeqCst);
                        if COUNT == i + 1 {
                            MessageLoop::get_current().terminate();
                            terminated.store(true, Ordering::SeqCst);
                        }
                    }),
                );
            }
            loop_.run();
            assert!(in_order.load(Ordering::SeqCst));
            assert_eq!(current.load(Ordering::SeqCst), COUNT);
            started.store(true, Ordering::SeqCst);
        })
        .join()
        .unwrap();
    }
    assert!(started.load(Ordering::SeqCst));
    assert!(terminated.load(Ordering::SeqCst));
}

#[test]
fn non_delayed_tasks_are_run_in_order() {
    run_in_order(|loop_, task| loop_.get_task_runner().post_task(task));
}

#[test]
fn delayed_tasks_at_same_time_are_run_in_order() {
    let now_plus_some = chrono_ticks_since_epoch() + TimeDelta::from_milliseconds(2);
    run_in_order(move |loop_, task| loop_.get_task_runner().post_task_for_time(task, now_plus_some));
}

#[test]
fn check_runs_task_on_current_thread() {
    let runner = Arc::new(Mutex::new(None));
    let latch = Arc::new(AutoResetWaitableEvent::new());
    let thread = {
        let (runner, latch) = (runner.clone(), latch.clone());
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            let loop_ = MessageLoop::get_current();
            *runner.lock().unwrap() = Some(loop_.get_task_runner());
            latch.signal();
            assert!(loop_.get_task_runner().runs_tasks_on_current_thread());
        })
    };
    latch.wait();
    let runner = runner.lock().unwrap().take().unwrap();
    assert!(runner.as_bool());
    assert!(!runner.runs_tasks_on_current_thread());
    thread.join().unwrap();
}

#[test]
fn task_observer_fire() {
    let started = Arc::new(AtomicBool::new(false));
    let terminated = Arc::new(AtomicBool::new(false));
    {
        let (started, terminated) = (started.clone(), terminated.clone());
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            const COUNT: usize = 25;
            let loop_ = MessageLoop::get_current();
            let task_count = Arc::new(AtomicUsize::new(0));
            let obs_count = Arc::new(AtomicUsize::new(0));
            let in_order = Arc::new(AtomicBool::new(true));
            for i in 0..COUNT {
                let (terminated, task_count, in_order) =
                    (terminated.clone(), task_count.clone(), in_order.clone());
                loop_.get_task_runner().post_task(crate::closure::closure::new(move || {
                    if task_count.load(Ordering::SeqCst) != i {
                        in_order.store(false, Ordering::SeqCst);
                    }
                    task_count.fetch_add(1, Ordering::SeqCst);
                    if COUNT == i + 1 {
                        MessageLoop::get_current().terminate();
                        terminated.store(true, Ordering::SeqCst);
                    }
                }));
            }
            let obs = obs_count.clone();
            loop_.add_task_observer(
                0,
                crate::closure::closure::new(move || {
                    obs.fetch_add(1, Ordering::SeqCst);
                }),
            );
            loop_.run();
            assert!(in_order.load(Ordering::SeqCst));
            assert_eq!(task_count.load(Ordering::SeqCst), COUNT);
            assert_eq!(obs_count.load(Ordering::SeqCst), COUNT);
            started.store(true, Ordering::SeqCst);
        })
        .join()
        .unwrap();
    }
    assert!(started.load(Ordering::SeqCst));
    assert!(terminated.load(Ordering::SeqCst));
}

#[test]
fn concurrent_message_loop_has_non_zero_workers() {
    let loop_ = ConcurrentMessageLoop::create(0 /* explicitly specify zero workers */);
    assert!(loop_.get_worker_count() > 0);
}

#[test]
fn can_create_and_shutdown_concurrent_message_loops_over_and_over() {
    for i in 0..10 {
        let loop_ = ConcurrentMessageLoop::create(i + 1);
        assert_eq!(loop_.get_worker_count(), i + 1);
    }
}

#[test]
fn can_create_concurrent_message_loop() {
    let loop_ = ConcurrentMessageLoop::create_default();
    let task_runner = loop_.get_task_runner();
    const K_COUNT: usize = 10;
    let latch = Arc::new(CountDownLatch::new(K_COUNT));
    let thread_ids = Arc::new(Mutex::new(BTreeSet::new()));
    for _ in 0..K_COUNT {
        let (latch, thread_ids) = (latch.clone(), thread_ids.clone());
        task_runner.post_task(crate::closure::closure::new(move || {
            // Upstream sleeps a second here so that the tasks spread over the
            // workers; a tenth of that does the same.
            std::thread::sleep(std::time::Duration::from_millis(100));
            thread_ids.lock().unwrap().insert(format!("{:?}", std::thread::current().id()));
            latch.count_down();
        }));
    }
    latch.wait();
    assert!(thread_ids.lock().unwrap().len() >= 1);
}

// Not upstream: a loop that has been terminated drops what is posted to it.
// No upstream test covers MessageLoopImpl::PostTask's terminated check.
#[test]
fn tasks_posted_after_termination_are_dropped() {
    std::thread::spawn(|| {
        MessageLoop::ensure_initialized_for_current_thread();
        let loop_ = MessageLoop::get_current();
        let runner = loop_.get_task_runner();
        runner.post_task(crate::closure::closure::new(|| MessageLoop::get_current().terminate()));
        loop_.run();
        let ran = Arc::new(AtomicBool::new(false));
        let r = ran.clone();
        runner.post_task(crate::closure::closure::new(move || r.store(true, Ordering::SeqCst)));
        assert_eq!(
            crate::message_loop_task_queues::MessageLoopTaskQueues::get_instance()
                .get_num_pending_tasks(runner.get_task_queue_id()),
            0
        );
        loop_.run_expired_tasks_now();
        assert!(!ran.load(Ordering::SeqCst));
    })
    .join()
    .unwrap();
}

// Not upstream: a task runner whose queue is merged into the current thread's
// runs its tasks on this thread. No upstream test covers
// TaskRunner::RunsTasksOnCurrentThread's use of the merged state.
#[test]
fn runs_tasks_on_current_thread_follows_merges() {
    let other = crate::raster_thread_merger_unittests::TaskQueueWrapper::new();
    std::thread::spawn(move || {
        MessageLoop::ensure_initialized_for_current_thread();
        let own = MessageLoop::get_current().get_task_runner().get_task_queue_id();
        let runner = other.loop_.get_task_runner();
        let queues = crate::message_loop_task_queues::MessageLoopTaskQueues::get_instance();
        assert!(!runner.runs_tasks_on_current_thread());
        assert!(queues.merge(own, runner.get_task_queue_id()));
        assert!(runner.runs_tasks_on_current_thread());
        assert!(queues.unmerge(own, runner.get_task_queue_id()));
        assert!(!runner.runs_tasks_on_current_thread());
        drop(other);
    })
    .join()
    .unwrap();
}

// Not upstream: tasks that fall due while the loop is being terminated still
// run, in the flush MessageLoopImpl::DoRun makes after the platform loop
// returns. Here the second task is posted by the first, after the flush that
// runs the first has read the time, so only that last flush can run it.
#[test]
fn tasks_due_when_the_loop_terminates_still_run() {
    let ran = Arc::new(AtomicBool::new(false));
    let r = ran.clone();
    std::thread::spawn(move || {
        MessageLoop::ensure_initialized_for_current_thread();
        let loop_ = MessageLoop::get_current();
        loop_.get_task_runner().post_task(crate::closure::closure::new(move || {
            let r = r.clone();
            // Make sure the clock moves past the running flush's.
            std::thread::sleep(std::time::Duration::from_millis(1));
            MessageLoop::get_current()
                .get_task_runner()
                .post_task(crate::closure::closure::new(move || r.store(true, Ordering::SeqCst)));
            MessageLoop::get_current().terminate();
        }));
        loop_.run();
    })
    .join()
    .unwrap();
    assert!(ran.load(Ordering::SeqCst));
}
