// Port of flutter/fml/memory/task_runner_checker_unittest.cc.

use std::sync::{Arc, Mutex};

use crate::memory::task_runner_checker::TaskRunnerChecker;
use crate::message_loop::MessageLoop;
use crate::message_loop_task_queues::MessageLoopTaskQueues;
use crate::raster_thread_merger::RasterThreadMerger;
use crate::raster_thread_merger_unittests::{Expectations, RunningLoop, TaskQueueWrapper};
use crate::synchronization::waitable_event::AutoResetWaitableEvent;

#[test]
fn runs_on_current_task_runner() {
    let checker = TaskRunnerChecker::new();
    assert!(checker.runs_on_creation_task_runner());
}

#[test]
fn fails_the_check_if_on_different_task_runner() {
    let checker = Arc::new(TaskRunnerChecker::new());
    assert!(checker.runs_on_creation_task_runner());
    let mut another = RunningLoop::new();
    let latch = Arc::new(AutoResetWaitableEvent::new());
    let e = Expectations::default();
    {
        let (checker, latch, e) = (checker.clone(), latch.clone(), e.clone());
        another.loop_.get_task_runner().post_task(crate::closure::closure::new(move || {
            e.expect(!checker.runs_on_creation_task_runner(), "RunsOnCreationTaskRunner");
            latch.signal();
        }));
    }
    latch.wait();
    another.terminate_and_join();
    e.check();
    assert!(checker.runs_on_creation_task_runner());
}

#[test]
fn same_task_runner_runs_on_the_same_thread() {
    MessageLoop::ensure_initialized_for_current_thread();
    let loop1 = MessageLoop::get_current();
    let loop2 = MessageLoop::get_current();
    let a = loop1.get_task_runner().get_task_queue_id();
    let b = loop2.get_task_runner().get_task_queue_id();
    assert!(TaskRunnerChecker::runs_on_the_same_thread(a, b));
}

#[test]
fn runs_on_different_threads_returns_false() {
    MessageLoop::ensure_initialized_for_current_thread();
    let loop1 = MessageLoop::get_current();
    let a = loop1.get_task_runner().get_task_queue_id();
    let result = std::thread::spawn(move || {
        MessageLoop::ensure_initialized_for_current_thread();
        let loop2 = MessageLoop::get_current();
        let b = loop2.get_task_runner().get_task_queue_id();
        TaskRunnerChecker::runs_on_the_same_thread(a, b)
    })
    .join()
    .unwrap();
    assert!(!result);
}

#[test]
fn merged_task_runners_runs_on_the_same_thread() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    let raster_thread_merger = RasterThreadMerger::new(qid1, qid2);
    const K_NUM_FRAMES_MERGED: usize = 5;

    raster_thread_merger.merge_with_lease(K_NUM_FRAMES_MERGED);

    // merged, running on the same thread
    assert!(TaskRunnerChecker::runs_on_the_same_thread(qid1, qid2));

    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(raster_thread_merger.is_merged());
        raster_thread_merger.decrement_lease();
    }

    assert!(!raster_thread_merger.is_merged());

    // un-merged, not running on the same thread
    assert!(!TaskRunnerChecker::runs_on_the_same_thread(qid1, qid2));
}

#[test]
fn passes_runs_on_creation_task_runner_if_on_different_task_runner() {
    let mut loop1 = RunningLoop::new();
    let mut loop2 = RunningLoop::new();
    let qid1 = loop1.id();
    let qid2 = loop2.id();
    MessageLoopTaskQueues::get_instance().merge(qid1, qid2);

    let checker: Arc<Mutex<Option<TaskRunnerChecker>>> = Arc::default();
    let e = Expectations::default();

    let latch3 = Arc::new(AutoResetWaitableEvent::new());
    {
        let (checker, latch, e) = (checker.clone(), latch3.clone(), e.clone());
        loop2.loop_.get_task_runner().post_task(crate::closure::closure::new(move || {
            let created = TaskRunnerChecker::new();
            e.expect(created.runs_on_creation_task_runner(), "3: RunsOnCreationTaskRunner");
            *checker.lock().unwrap() = Some(created);
            latch.signal();
        }));
    }
    latch3.wait();

    MessageLoopTaskQueues::get_instance().unmerge(qid1, qid2);

    let latch4 = Arc::new(AutoResetWaitableEvent::new());
    {
        let (checker, latch, e) = (checker.clone(), latch4.clone(), e.clone());
        loop2.loop_.get_task_runner().post_task(crate::closure::closure::new(move || {
            let ok = checker.lock().unwrap().as_ref().unwrap().runs_on_creation_task_runner();
            e.expect(ok, "4: RunsOnCreationTaskRunner");
            latch.signal();
        }));
    }
    latch4.wait();

    loop1.terminate_and_join();
    loop2.terminate_and_join();
    e.check();
}
