// Port of flutter/fml/task_runner_util_unittests.cc.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use crate::synchronization::waitable_event::AutoResetWaitableEvent;
use crate::task_runner::BasicTaskRunner;
use crate::task_runner_util::{ConditionalBasicTaskRunner, WrapperBasicTaskRunner};
use crate::thread::Thread;

#[test]
fn wrapper_basic_task_runner_post_task() {
    let thread = Thread::default();

    let wrapper = WrapperBasicTaskRunner::new(thread.get_task_runner());

    let wrapper_thread_id = Arc::new(Mutex::new(None));
    let w = wrapper_thread_id.clone();
    wrapper.post_task(Arc::new(move || {
        *w.lock().unwrap() = Some(std::thread::current().id());
    }));

    thread.join();

    let id = wrapper_thread_id.lock().unwrap().expect("the task ran");
    assert_ne!(id, std::thread::current().id());
}

#[test]
fn conditional_basic_task_runner_post_task() {
    let thread = Thread::default();
    let active = Arc::new(AtomicBool::new(true));
    let a = active.clone();
    let runner =
        ConditionalBasicTaskRunner::new(thread.get_task_runner(), move || a.load(Ordering::SeqCst));

    let latch = Arc::new(AutoResetWaitableEvent::new());
    let task1_called = Arc::new(AtomicBool::new(false));
    let (t1, l) = (task1_called.clone(), latch.clone());
    runner.post_task(Arc::new(move || {
        t1.store(true, Ordering::SeqCst);
        l.signal();
    }));
    latch.wait();

    active.store(false, Ordering::SeqCst);

    let task2_called = Arc::new(AtomicBool::new(false));
    let t2 = task2_called.clone();
    runner.post_task(Arc::new(move || t2.store(true, Ordering::SeqCst)));

    let l = latch.clone();
    thread.get_task_runner().post_task(Arc::new(move || l.signal()));
    latch.wait();

    thread.join();

    assert!(task1_called.load(Ordering::SeqCst));
    assert!(!task2_called.load(Ordering::SeqCst));
}
