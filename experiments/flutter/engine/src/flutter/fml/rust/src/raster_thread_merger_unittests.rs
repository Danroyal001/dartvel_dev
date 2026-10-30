// Port of flutter/fml/raster_thread_merger_unittests.cc.
//
// Assertions made inside tasks are recorded and checked on the test's thread
// (a panic on a loop thread would only end that thread).

use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, Mutex};

use crate::memory::ref_ptr::RefPtr;
use crate::message_loop::MessageLoop;
use crate::raster_thread_merger::{RasterThreadMerger, RasterThreadStatus};
use crate::synchronization::count_down_latch::CountDownLatch;
use crate::synchronization::waitable_event::AutoResetWaitableEvent;
use crate::task_queue_id::TaskQueueId;
use crate::thread::Thread;

/// A thread with an initialized, never-run message loop, kept until dropped.
pub(crate) struct TaskQueueWrapper {
    pub loop_: MessageLoop,
    term: Arc<AutoResetWaitableEvent>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl TaskQueueWrapper {
    pub fn new() -> Self {
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
        latch.wait();
        let loop_ = slot.lock().unwrap().take().unwrap();
        TaskQueueWrapper { loop_, term, thread: Some(thread) }
    }

    pub fn get_task_queue_id(&self) -> TaskQueueId {
        self.loop_.get_task_runner().get_task_queue_id()
    }
}

impl Drop for TaskQueueWrapper {
    fn drop(&mut self) {
        self.term.signal();
        self.thread.take().unwrap().join().unwrap();
    }
}

/// A thread that runs its message loop until terminated.
pub(crate) struct RunningLoop {
    pub loop_: MessageLoop,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl RunningLoop {
    pub fn new() -> Self {
        let slot: Arc<Mutex<Option<MessageLoop>>> = Arc::default();
        let latch = Arc::new(AutoResetWaitableEvent::new());
        let thread = {
            let (slot, latch) = (slot.clone(), latch.clone());
            std::thread::spawn(move || {
                MessageLoop::ensure_initialized_for_current_thread();
                let loop_ = MessageLoop::get_current();
                *slot.lock().unwrap() = Some(loop_.clone());
                let l = latch.clone();
                loop_.get_task_runner().post_task(Arc::new(move || l.signal()));
                loop_.run();
            })
        };
        latch.wait();
        let loop_ = slot.lock().unwrap().take().unwrap();
        RunningLoop { loop_, thread: Some(thread) }
    }

    pub fn id(&self) -> TaskQueueId {
        self.loop_.get_task_runner().get_task_queue_id()
    }

    pub fn terminate_and_join(&mut self) {
        let l = self.loop_.clone();
        self.loop_.get_task_runner().post_task(Arc::new(move || l.terminate()));
        self.thread.take().unwrap().join().unwrap();
    }
}

/// Records failed expectations made off the test's thread.
#[derive(Clone, Default)]
pub(crate) struct Expectations(Arc<Mutex<Vec<String>>>);

impl Expectations {
    pub fn expect(&self, ok: bool, what: &str) {
        if !ok {
            self.0.lock().unwrap().push(what.to_string());
        }
    }
    pub fn check(&self) {
        let failures = self.0.lock().unwrap();
        assert!(failures.is_empty(), "failed: {failures:?}");
    }
}

#[test]
fn remain_merged_till_lease_expires() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    let raster_thread_merger = RasterThreadMerger::new(qid1, qid2);
    const K_NUM_FRAMES_MERGED: usize = 5;

    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.merge_with_lease(K_NUM_FRAMES_MERGED);

    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(raster_thread_merger.is_merged());
        raster_thread_merger.decrement_lease();
    }

    assert!(!raster_thread_merger.is_merged());
}

#[test]
fn is_not_on_rasterizing_thread() {
    let mut loop1 = RunningLoop::new();
    let mut loop2 = RunningLoop::new();
    let qid1 = loop1.id();
    let qid2 = loop2.id();
    let raster_thread_merger = RasterThreadMerger::new(qid1, qid2);
    let e = Expectations::default();

    let check = |runner_loop: &RunningLoop,
                 latch: &Arc<CountDownLatch>,
                 rasterizing: bool,
                 platform: bool,
                 qid: TaskQueueId| {
        let (m, l, e) = (raster_thread_merger.clone(), latch.clone(), e.clone());
        runner_loop.loop_.get_task_runner().post_task(Arc::new(move || {
            e.expect(m.is_on_rasterizing_thread() == rasterizing, "IsOnRasterizingThread");
            e.expect(m.is_on_platform_thread() == platform, "IsOnPlatformThread");
            e.expect(MessageLoop::get_current_task_queue_id() == qid, "GetCurrentTaskQueueId");
            l.count_down();
        }));
    };

    let pre_merge = Arc::new(CountDownLatch::new(2));
    check(&loop1, &pre_merge, false, true, qid1);
    check(&loop2, &pre_merge, true, false, qid2);
    pre_merge.wait();

    raster_thread_merger.merge_with_lease(1);

    let post_merge = Arc::new(CountDownLatch::new(2));
    check(&loop1, &post_merge, true, true, qid1);
    // this will be false since this is going to be run
    // on loop1 really.
    check(&loop2, &post_merge, true, true, qid1);
    post_merge.wait();

    raster_thread_merger.decrement_lease();

    let post_unmerge = Arc::new(CountDownLatch::new(2));
    check(&loop1, &post_unmerge, false, true, qid1);
    check(&loop2, &post_unmerge, true, false, qid2);
    post_unmerge.wait();

    loop1.terminate_and_join();
    loop2.terminate_and_join();
    e.check();
}

#[test]
fn lease_extension() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();

    let raster_thread_merger =
        RasterThreadMerger::new(queue1.get_task_queue_id(), queue2.get_task_queue_id());
    const K_NUM_FRAMES_MERGED: usize = 5;

    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.merge_with_lease(K_NUM_FRAMES_MERGED);

    // let there be one more turn till the leases expire.
    for _ in 0..K_NUM_FRAMES_MERGED - 1 {
        assert!(raster_thread_merger.is_merged());
        raster_thread_merger.decrement_lease();
    }

    // extend the lease once.
    raster_thread_merger.extend_lease_to(K_NUM_FRAMES_MERGED);

    // we will NOT last for 1 extra turn, we just set it.
    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(raster_thread_merger.is_merged());
        raster_thread_merger.decrement_lease();
    }

    assert!(!raster_thread_merger.is_merged());
}

#[test]
fn wait_until_merged() {
    let raster_thread_merger: Arc<Mutex<RefPtr<RasterThreadMerger>>> = Arc::default();

    let create_thread_merger_latch = Arc::new(AutoResetWaitableEvent::new());
    let loop_platform: Arc<Mutex<Option<MessageLoop>>> = Arc::default();
    let latch_platform = Arc::new(AutoResetWaitableEvent::new());
    let term_platform = Arc::new(AutoResetWaitableEvent::new());
    let latch_merged = Arc::new(AutoResetWaitableEvent::new());
    let thread_platform = {
        let (m, cl, lp, lat, term, merged) = (
            raster_thread_merger.clone(),
            create_thread_merger_latch.clone(),
            loop_platform.clone(),
            latch_platform.clone(),
            term_platform.clone(),
            latch_merged.clone(),
        );
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            *lp.lock().unwrap() = Some(MessageLoop::get_current());
            lat.signal();
            cl.wait();
            let merger = m.lock().unwrap().clone();
            merger.wait_until_merged();
            merged.signal();
            term.wait();
        })
    };

    const K_NUM_FRAMES_MERGED: usize = 5;
    let term_raster = Arc::new(AutoResetWaitableEvent::new());
    let thread_raster = {
        let (m, cl, lp, lat, term) = (
            raster_thread_merger.clone(),
            create_thread_merger_latch.clone(),
            loop_platform.clone(),
            latch_platform.clone(),
            term_raster.clone(),
        );
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            let loop_raster = MessageLoop::get_current();
            lat.wait();
            let qid_platform =
                lp.lock().unwrap().as_ref().unwrap().get_task_runner().get_task_queue_id();
            let qid_raster = loop_raster.get_task_runner().get_task_queue_id();
            let merger = RasterThreadMerger::new(qid_platform, qid_raster);
            *m.lock().unwrap() = merger.clone();
            assert!(!merger.is_merged());
            cl.signal();
            merger.merge_with_lease(K_NUM_FRAMES_MERGED);
            term.wait();
        })
    };

    latch_merged.wait();
    let merger = raster_thread_merger.lock().unwrap().clone();
    assert!(merger.is_merged());

    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(merger.is_merged());
        merger.decrement_lease();
    }

    assert!(!merger.is_merged());

    term_platform.signal();
    term_raster.signal();
    thread_platform.join().unwrap();
    thread_raster.join().unwrap();
}

#[test]
fn handle_task_queues_are_the_same() {
    let queue = TaskQueueWrapper::new();
    let qid1 = queue.get_task_queue_id();
    let qid2 = qid1;
    let raster_thread_merger = RasterThreadMerger::new(qid1, qid2);
    // Statically merged.
    assert!(raster_thread_merger.is_merged());

    // Test decrement lease and unmerge are both no-ops.
    // The task queues should be always merged.
    const K_NUM_FRAMES_MERGED: usize = 5;
    raster_thread_merger.merge_with_lease(K_NUM_FRAMES_MERGED);

    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(raster_thread_merger.is_merged());
        raster_thread_merger.decrement_lease();
    }

    assert!(raster_thread_merger.is_merged());

    // Wait until merged should also return immediately.
    raster_thread_merger.wait_until_merged();
    assert!(raster_thread_merger.is_merged());
}

#[test]
fn enable() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let raster_thread_merger =
        RasterThreadMerger::new(queue1.get_task_queue_id(), queue2.get_task_queue_id());

    raster_thread_merger.disable();
    raster_thread_merger.merge_with_lease(1);
    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.enable();
    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.merge_with_lease(1);
    assert!(raster_thread_merger.is_merged());

    raster_thread_merger.decrement_lease();
    assert!(!raster_thread_merger.is_merged());
}

#[test]
fn disable() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let raster_thread_merger =
        RasterThreadMerger::new(queue1.get_task_queue_id(), queue2.get_task_queue_id());

    raster_thread_merger.disable();
    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.merge_with_lease(1);
    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.enable();
    raster_thread_merger.merge_with_lease(1);
    assert!(raster_thread_merger.is_merged());

    raster_thread_merger.disable();
    raster_thread_merger.un_merge_now_if_last_one();
    assert!(raster_thread_merger.is_merged());

    {
        let decrement_result = raster_thread_merger.decrement_lease();
        assert_eq!(RasterThreadStatus::kRemainsMerged, decrement_result);
    }

    assert!(raster_thread_merger.is_merged());

    raster_thread_merger.enable();
    raster_thread_merger.un_merge_now_if_last_one();
    assert!(!raster_thread_merger.is_merged());

    raster_thread_merger.merge_with_lease(1);

    assert!(raster_thread_merger.is_merged());

    {
        let decrement_result = raster_thread_merger.decrement_lease();
        assert_eq!(RasterThreadStatus::kUnmergedNow, decrement_result);
    }

    assert!(!raster_thread_merger.is_merged());
}

#[test]
fn is_enabled() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let raster_thread_merger =
        RasterThreadMerger::new(queue1.get_task_queue_id(), queue2.get_task_queue_id());
    assert!(raster_thread_merger.is_enabled());

    raster_thread_merger.disable();
    assert!(!raster_thread_merger.is_enabled());

    raster_thread_merger.enable();
    assert!(raster_thread_merger.is_enabled());
}

#[test]
fn two_mergers_with_same_thread_pair_share_enabled_state() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    let merger1 = RasterThreadMerger::create_or_share_thread_merger(&RefPtr::null(), qid1, qid2);
    let merger2 = RasterThreadMerger::create_or_share_thread_merger(&merger1, qid1, qid2);
    assert!(merger1.is_enabled());
    assert!(merger2.is_enabled());

    merger1.disable();
    assert!(!merger1.is_enabled());
    assert!(!merger2.is_enabled());

    merger2.enable();
    assert!(merger1.is_enabled());
    assert!(merger2.is_enabled());
}

#[test]
fn run_expired_tasks_while_first_task_merges_threads() {
    let mut platform = RunningLoop::new();
    let qid_platform = platform.id();
    let e = Expectations::default();

    {
        let e = e.clone();
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            let loop_raster = MessageLoop::get_current();
            let qid_raster = loop_raster.get_task_runner().get_task_queue_id();
            let post_merge = Arc::new(CountDownLatch::new(2));
            let raster_thread_merger = RasterThreadMerger::new(qid_platform, qid_raster);
            {
                let (m, l, e) = (raster_thread_merger.clone(), post_merge.clone(), e.clone());
                loop_raster.get_task_runner().post_task(Arc::new(move || {
                    e.expect(m.is_on_rasterizing_thread(), "1: IsOnRasterizingThread");
                    e.expect(!m.is_on_platform_thread(), "1: !IsOnPlatformThread");
                    e.expect(MessageLoop::get_current_task_queue_id() == qid_raster, "1: queue");
                    m.merge_with_lease(1);
                    l.count_down();
                }));
            }
            {
                let (m, l, e) = (raster_thread_merger.clone(), post_merge.clone(), e.clone());
                loop_raster.get_task_runner().post_task(Arc::new(move || {
                    e.expect(m.is_on_rasterizing_thread(), "2: IsOnRasterizingThread");
                    e.expect(m.is_on_platform_thread(), "2: IsOnPlatformThread");
                    e.expect(MessageLoop::get_current_task_queue_id() == qid_platform, "2: queue");
                    m.decrement_lease();
                    l.count_down();
                }));
            }

            loop_raster.run_expired_tasks_now();
            post_merge.wait();
        })
        .join()
        .unwrap();
    }

    platform.terminate_and_join();
    e.check();
}

#[test]
fn run_expired_tasks_while_first_task_un_merges_threads() {
    let platform_thread = Thread::new("test_platform_thread");
    let qid_platform = platform_thread.get_task_runner().get_task_queue_id();
    let e = Expectations::default();

    {
        let e = e.clone();
        std::thread::spawn(move || {
            MessageLoop::ensure_initialized_for_current_thread();
            let loop_raster = MessageLoop::get_current();
            let qid_raster = loop_raster.get_task_runner().get_task_queue_id();

            let merge_latch = Arc::new(AutoResetWaitableEvent::new());
            let raster_thread_merger = RasterThreadMerger::new(qid_platform, qid_raster);
            {
                let (m, l) = (raster_thread_merger.clone(), merge_latch.clone());
                loop_raster.get_task_runner().post_task(Arc::new(move || {
                    m.merge_with_lease(1);
                    l.signal();
                }));
            }

            loop_raster.run_expired_tasks_now();
            merge_latch.wait();

            // threads should be merged at this point.
            let unmerge_latch = Arc::new(AutoResetWaitableEvent::new());
            {
                let (m, l, e) = (raster_thread_merger.clone(), unmerge_latch.clone(), e.clone());
                loop_raster.get_task_runner().post_task(Arc::new(move || {
                    e.expect(m.is_on_rasterizing_thread(), "1: IsOnRasterizingThread");
                    e.expect(m.is_on_platform_thread(), "1: IsOnPlatformThread");
                    e.expect(MessageLoop::get_current_task_queue_id() == qid_platform, "1: queue");
                    m.decrement_lease();
                    l.signal();
                }));
            }

            let post_unmerge_latch = Arc::new(AutoResetWaitableEvent::new());
            {
                let (m, l, e) =
                    (raster_thread_merger.clone(), post_unmerge_latch.clone(), e.clone());
                loop_raster.get_task_runner().post_task(Arc::new(move || {
                    e.expect(m.is_on_rasterizing_thread(), "2: IsOnRasterizingThread");
                    e.expect(!m.is_on_platform_thread(), "2: !IsOnPlatformThread");
                    e.expect(MessageLoop::get_current_task_queue_id() == qid_raster, "2: queue");
                    l.signal();
                }));
            }

            unmerge_latch.wait();
            loop_raster.run_expired_tasks_now();

            post_unmerge_latch.wait();
        })
        .join()
        .unwrap();
    }
    e.check();
}

#[test]
fn set_merge_unmerge_callback() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();

    let raster_thread_merger =
        RasterThreadMerger::new(queue1.get_task_queue_id(), queue2.get_task_queue_id());

    let callbacks = Arc::new(AtomicI32::new(0));
    let c = callbacks.clone();
    raster_thread_merger.set_merge_unmerge_callback(Arc::new(move || {
        c.fetch_add(1, Ordering::SeqCst);
    }));

    assert_eq!(0, callbacks.load(Ordering::SeqCst));

    raster_thread_merger.merge_with_lease(1);
    assert_eq!(1, callbacks.load(Ordering::SeqCst));

    raster_thread_merger.decrement_lease();
    assert_eq!(2, callbacks.load(Ordering::SeqCst));
}

#[test]
fn multiple_mergers_can_merge_same_thread_pair() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    // Two mergers will share one same inner merger
    let raster_thread_merger1 =
        RasterThreadMerger::create_or_share_thread_merger(&RefPtr::null(), qid1, qid2);
    let raster_thread_merger2 =
        RasterThreadMerger::create_or_share_thread_merger(&raster_thread_merger1, qid1, qid2);
    const K_NUM_FRAMES_MERGED: usize = 5;
    assert!(!raster_thread_merger1.is_merged());
    assert!(!raster_thread_merger2.is_merged());

    // Merge using the first merger
    raster_thread_merger1.merge_with_lease(K_NUM_FRAMES_MERGED);

    assert!(raster_thread_merger1.is_merged());
    assert!(raster_thread_merger2.is_merged());

    // let there be one more turn till the leases expire.
    for _ in 0..K_NUM_FRAMES_MERGED - 1 {
        // Check merge state using the two merger
        assert!(raster_thread_merger1.is_merged());
        assert!(raster_thread_merger2.is_merged());
        raster_thread_merger1.decrement_lease();
    }

    assert!(raster_thread_merger1.is_merged());
    assert!(raster_thread_merger2.is_merged());

    // extend the lease once with the first merger
    raster_thread_merger1.extend_lease_to(K_NUM_FRAMES_MERGED);

    // we will NOT last for 1 extra turn, we just set it.
    for _ in 0..K_NUM_FRAMES_MERGED {
        // Check merge state using the two merger
        assert!(raster_thread_merger1.is_merged());
        assert!(raster_thread_merger2.is_merged());
        raster_thread_merger1.decrement_lease();
    }

    assert!(!raster_thread_merger1.is_merged());
    assert!(!raster_thread_merger2.is_merged());
}

#[test]
fn the_last_caller_of_multiple_mergers_can_unmerge_now() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    // Two mergers will share one same inner merger
    let raster_thread_merger1 =
        RasterThreadMerger::create_or_share_thread_merger(&RefPtr::null(), qid1, qid2);
    let raster_thread_merger2 =
        RasterThreadMerger::create_or_share_thread_merger(&raster_thread_merger1, qid1, qid2);
    const K_NUM_FRAMES_MERGED: usize = 5;
    assert!(!raster_thread_merger1.is_merged());
    assert!(!raster_thread_merger2.is_merged());

    // Merge using the mergers
    raster_thread_merger1.merge_with_lease(K_NUM_FRAMES_MERGED);
    assert!(raster_thread_merger1.is_merged());
    assert!(raster_thread_merger2.is_merged());
    // Extend the second merger's lease
    raster_thread_merger2.extend_lease_to(K_NUM_FRAMES_MERGED);
    assert!(raster_thread_merger1.is_merged());
    assert!(raster_thread_merger2.is_merged());

    // Two callers state becomes one caller left.
    raster_thread_merger1.un_merge_now_if_last_one();
    // Check if still merged
    assert!(raster_thread_merger1.is_merged());
    assert!(raster_thread_merger2.is_merged());

    // One caller state becomes no callers left.
    raster_thread_merger2.un_merge_now_if_last_one();
    // Check if unmerged
    assert!(!raster_thread_merger1.is_merged());
    assert!(!raster_thread_merger2.is_merged());
}

#[test]
fn the_last_merged_caller_of_multiple_mergers_can_unmerge_now() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    // Two mergers will share one same inner merger
    let raster_thread_merger1 =
        RasterThreadMerger::create_or_share_thread_merger(&RefPtr::null(), qid1, qid2);

    const K_NUM_FRAMES_MERGED: usize = 1;
    assert!(!raster_thread_merger1.is_merged());

    // Merge using the mergers
    raster_thread_merger1.merge_with_lease(K_NUM_FRAMES_MERGED);
    assert!(raster_thread_merger1.is_merged());

    for _ in 0..K_NUM_FRAMES_MERGED {
        // Un-merge thread merger 1.
        raster_thread_merger1.decrement_lease();
    }
    assert!(!raster_thread_merger1.is_merged());

    let raster_thread_merger2 =
        RasterThreadMerger::create_or_share_thread_merger(&raster_thread_merger1, qid1, qid2);
    assert!(!raster_thread_merger2.is_merged());
    raster_thread_merger2.merge_with_lease(K_NUM_FRAMES_MERGED);
    assert!(raster_thread_merger2.is_merged());

    // One caller state becomes no callers left.
    raster_thread_merger2.un_merge_now_if_last_one();
    // Check if unmerged
    assert!(!raster_thread_merger1.is_merged());
    assert!(!raster_thread_merger2.is_merged());
}

/// This case tests multiple standalone engines using independent merger to
/// merge two different raster threads into the same platform thread.
#[test]
fn two_independent_mergers_can_merge_two_different_threads_into_same_platform_thread() {
    let queue1 = TaskQueueWrapper::new();
    let queue2 = TaskQueueWrapper::new();
    let queue3 = TaskQueueWrapper::new();
    let qid1 = queue1.get_task_queue_id();
    let qid2 = queue2.get_task_queue_id();
    let qid3 = queue3.get_task_queue_id();

    // Two mergers will NOT share same inner merger
    let merger_from_2_to_1 =
        RasterThreadMerger::create_or_share_thread_merger(&RefPtr::null(), qid1, qid2);
    let merger_from_3_to_1 =
        RasterThreadMerger::create_or_share_thread_merger(&merger_from_2_to_1, qid1, qid3);
    const K_NUM_FRAMES_MERGED: usize = 5;
    assert!(!merger_from_2_to_1.is_merged());
    assert!(!merger_from_3_to_1.is_merged());

    // Merge thread2 into thread1
    merger_from_2_to_1.merge_with_lease(K_NUM_FRAMES_MERGED);
    // Merge thread3 into thread1
    merger_from_3_to_1.merge_with_lease(K_NUM_FRAMES_MERGED);

    assert!(merger_from_2_to_1.is_merged());
    assert!(merger_from_3_to_1.is_merged());

    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(merger_from_2_to_1.is_merged());
        merger_from_2_to_1.decrement_lease();
    }

    assert!(!merger_from_2_to_1.is_merged());
    assert!(merger_from_3_to_1.is_merged());

    for _ in 0..K_NUM_FRAMES_MERGED {
        assert!(merger_from_3_to_1.is_merged());
        merger_from_3_to_1.decrement_lease();
    }

    assert!(!merger_from_2_to_1.is_merged());
    assert!(!merger_from_3_to_1.is_merged());

    merger_from_2_to_1.merge_with_lease(K_NUM_FRAMES_MERGED);
    assert!(merger_from_2_to_1.is_merged());
    assert!(!merger_from_3_to_1.is_merged());
    merger_from_3_to_1.merge_with_lease(K_NUM_FRAMES_MERGED);
    assert!(merger_from_2_to_1.is_merged());
    assert!(merger_from_3_to_1.is_merged());

    // Can unmerge independently
    merger_from_2_to_1.un_merge_now_if_last_one();
    assert!(!merger_from_2_to_1.is_merged());
    assert!(merger_from_3_to_1.is_merged());

    // Can unmerge independently
    merger_from_3_to_1.un_merge_now_if_last_one();
    assert!(!merger_from_2_to_1.is_merged());
    assert!(!merger_from_3_to_1.is_merged());
}

