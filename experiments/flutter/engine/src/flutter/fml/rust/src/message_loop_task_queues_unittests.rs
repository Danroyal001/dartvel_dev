// Port of flutter/fml/message_loop_task_queues_unittests.cc.
//
// Wakeables are held by the test in an `Arc` and registered as `Weak`, as the
// port of MessageLoopTaskQueues takes them (upstream: a unique_ptr and a raw
// pointer). Captured locals that tasks write become shared atomics, since a
// `closure` is 'static.

use std::sync::atomic::{AtomicI32, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, Weak};

use crate::closure::closure;
use crate::message_loop_task_queues::{MessageLoopTaskQueues, kUnmerged};
use crate::synchronization::count_down_latch::CountDownLatch;
use crate::synchronization::waitable_event::AutoResetWaitableEvent;
use crate::task_queue_id::TaskQueueId;
use crate::task_source_grade::TaskSourceGrade;
use crate::time::chrono_timestamp_provider::chrono_ticks_since_epoch;
use crate::time::time_delta::TimeDelta;
use crate::time::time_point::TimePoint;
use crate::wakeable::Wakeable;

pub(crate) struct TestWakeable {
    wake_up_call_: Box<dyn Fn(TimePoint) + Send + Sync>,
}

impl TestWakeable {
    pub(crate) fn new(call: impl Fn(TimePoint) + Send + Sync + 'static) -> Arc<TestWakeable> {
        Arc::new(TestWakeable { wake_up_call_: Box::new(call) })
    }
}

impl Wakeable for TestWakeable {
    fn wake_up(&self, time_point: TimePoint) {
        (self.wake_up_call_)(time_point);
    }
}

pub(crate) fn weak(w: &Arc<TestWakeable>) -> Weak<dyn Wakeable> {
    let weak: Weak<dyn Wakeable> = Arc::downgrade(w) as Weak<dyn Wakeable>;
    weak
}

pub(crate) fn noop() -> closure {
    crate::closure::closure::new(|| {})
}

fn set(value: &Arc<AtomicI32>, to: i32) -> closure {
    let value = value.clone();
    crate::closure::closure::new(move || value.store(to, Ordering::SeqCst))
}

const U: TaskSourceGrade = TaskSourceGrade::kUnspecified;

#[test]
fn starts_with_no_pending_tasks() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();
    assert!(!task_queue.has_pending_tasks(queue_id));
}

#[test]
fn register_one_task() {
    let time = TimePoint::max();
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();

    let wakeable = TestWakeable::new(move |wake_time| assert!(wake_time == time));
    task_queue.set_wakeable(queue_id, weak(&wakeable));

    task_queue.register_task(queue_id, noop(), time, U);
    assert!(task_queue.has_pending_tasks(queue_id));
    assert!(task_queue.get_num_pending_tasks(queue_id) == 1);
}

#[test]
fn register_two_tasks_and_count() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();
    task_queue.register_task(queue_id, noop(), chrono_ticks_since_epoch(), U);
    task_queue.register_task(queue_id, noop(), TimePoint::max(), U);
    assert!(task_queue.has_pending_tasks(queue_id));
    assert!(task_queue.get_num_pending_tasks(queue_id) == 2);
}

#[test]
fn register_tasks_on_merged_queues_and_count() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let platform_queue = task_queue.create_task_queue();
    let raster_queue = task_queue.create_task_queue();
    // A task in platform_queue
    task_queue.register_task(platform_queue, noop(), TimePoint::now(), U);
    // A task in raster_queue
    task_queue.register_task(raster_queue, noop(), TimePoint::now(), U);
    assert!(task_queue.get_num_pending_tasks(platform_queue) == 1);
    assert!(task_queue.get_num_pending_tasks(raster_queue) == 1);

    assert!(!task_queue.owns(platform_queue, raster_queue));
    task_queue.merge(platform_queue, raster_queue);
    assert!(task_queue.owns(platform_queue, raster_queue));

    assert!(task_queue.has_pending_tasks(platform_queue));
    assert!(task_queue.get_num_pending_tasks(platform_queue) == 2);
    // The task count of subsumed queue is 0
    assert!(!task_queue.has_pending_tasks(raster_queue));
    assert!(task_queue.get_num_pending_tasks(raster_queue) == 0);

    task_queue.unmerge(platform_queue, raster_queue);
    assert!(!task_queue.owns(platform_queue, raster_queue));
    assert!(task_queue.get_num_pending_tasks(platform_queue) == 1);
    assert!(task_queue.get_num_pending_tasks(raster_queue) == 1);
}

#[test]
fn preserve_task_ordering() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();
    let test_val = Arc::new(AtomicI32::new(0));

    // order: 0
    task_queue.register_task(queue_id, set(&test_val, 1), chrono_ticks_since_epoch(), U);

    // order: 1
    task_queue.register_task(queue_id, set(&test_val, 2), chrono_ticks_since_epoch(), U);

    let now = chrono_ticks_since_epoch();
    let mut expected_value = 1;
    loop {
        let Some(invocation) = task_queue.get_next_task_to_run(queue_id, now) else {
            break;
        };
        invocation.call();
        assert!(test_val.load(Ordering::SeqCst) == expected_value);
        expected_value += 1;
    }
}

#[test]
fn register_tasks_on_merged_queues_preserve_task_ordering() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let platform_queue = task_queue.create_task_queue();
    let raster1_queue = task_queue.create_task_queue();
    let raster2_queue = task_queue.create_task_queue();
    let test_val = Arc::new(AtomicI32::new(0));

    // order 0 in raster1_queue
    task_queue.register_task(raster1_queue, set(&test_val, 0), TimePoint::now(), U);

    // order 1 in platform_queue
    task_queue.register_task(platform_queue, set(&test_val, 1), TimePoint::now(), U);

    // order 2 in raster2_queue
    task_queue.register_task(raster2_queue, set(&test_val, 2), TimePoint::now(), U);

    task_queue.merge(platform_queue, raster1_queue);
    assert!(task_queue.owns(platform_queue, raster1_queue));
    task_queue.merge(platform_queue, raster2_queue);
    assert!(task_queue.owns(platform_queue, raster2_queue));
    let now = TimePoint::now();
    let mut expected_value = 0;
    // Right order:
    // "test_val = 0" in raster1_queue
    // "test_val = 1" in platform_queue
    // "test_val = 2" in raster2_queue
    loop {
        let Some(invocation) = task_queue.get_next_task_to_run(platform_queue, now) else {
            break;
        };
        invocation.call();
        assert!(test_val.load(Ordering::SeqCst) == expected_value);
        expected_value += 1;
    }
}

#[test]
fn unmerge_respect_the_original_task_ordering_in_queues() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let platform_queue = task_queue.create_task_queue();
    let raster_queue = task_queue.create_task_queue();
    let test_val = Arc::new(AtomicI32::new(0));

    // order 0 in platform_queue
    task_queue.register_task(platform_queue, set(&test_val, 0), TimePoint::now(), U);
    // order 1 in platform_queue
    task_queue.register_task(platform_queue, set(&test_val, 1), TimePoint::now(), U);
    // order 2 in raster_queue
    task_queue.register_task(raster_queue, set(&test_val, 2), TimePoint::now(), U);
    // order 3 in raster_queue
    task_queue.register_task(raster_queue, set(&test_val, 3), TimePoint::now(), U);
    // order 4 in platform_queue
    task_queue.register_task(platform_queue, set(&test_val, 4), TimePoint::now(), U);
    // order 5 in raster_queue
    task_queue.register_task(raster_queue, set(&test_val, 5), TimePoint::now(), U);

    assert!(task_queue.merge(platform_queue, raster_queue));
    assert!(task_queue.owns(platform_queue, raster_queue));

    let now = TimePoint::now();
    // The right order after merged and consumed 3 tasks:
    // "test_val = 0" in platform_queue
    // "test_val = 1" in platform_queue
    // "test_val = 2" in raster_queue (running on platform)
    for i in 0..3 {
        let invocation = task_queue.get_next_task_to_run(platform_queue, now);
        assert!(invocation.is_some());
        invocation.unwrap().call();
        assert!(test_val.load(Ordering::SeqCst) == i);
    }
    assert!(task_queue.get_num_pending_tasks(platform_queue) == 3);
    assert!(task_queue.get_num_pending_tasks(raster_queue) == 0);

    assert!(task_queue.unmerge(platform_queue, raster_queue));
    assert!(!task_queue.owns(platform_queue, raster_queue));

    // The right order after unmerged and left 3 tasks:
    // "test_val = 3" in raster_queue
    // "test_val = 4" in platform_queue
    // "test_val = 5" in raster_queue

    // platform_queue has 1 task left: "test_val = 4"
    {
        assert!(task_queue.get_num_pending_tasks(platform_queue) == 1);
        let invocation = task_queue.get_next_task_to_run(platform_queue, now);
        assert!(invocation.is_some());
        invocation.unwrap().call();
        assert!(test_val.load(Ordering::SeqCst) == 4);
        assert!(task_queue.get_num_pending_tasks(platform_queue) == 0);
    }

    // raster_queue has 2 tasks left: "test_val = 3" and "test_val = 5"
    {
        assert!(task_queue.get_num_pending_tasks(raster_queue) == 2);
        let invocation = task_queue.get_next_task_to_run(raster_queue, now);
        assert!(invocation.is_some());
        invocation.unwrap().call();
        assert!(test_val.load(Ordering::SeqCst) == 3);
    }
    {
        assert!(task_queue.get_num_pending_tasks(raster_queue) == 1);
        let invocation = task_queue.get_next_task_to_run(raster_queue, now);
        assert!(invocation.is_some());
        invocation.unwrap().call();
        assert!(test_val.load(Ordering::SeqCst) == 5);
        assert!(task_queue.get_num_pending_tasks(raster_queue) == 0);
    }
}

fn test_notify_observers(queue_id: TaskQueueId) {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let observers = task_queue.get_observers_to_notify(queue_id);
    for observer in observers {
        observer.call();
    }
}

#[test]
fn add_remove_notify_observers() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();

    let test_val = Arc::new(AtomicI32::new(0));
    let key: isize = 123;

    task_queue.add_task_observer(queue_id, key, set(&test_val, 1));
    test_notify_observers(queue_id);
    assert!(test_val.load(Ordering::SeqCst) == 1);

    test_val.store(0, Ordering::SeqCst);
    task_queue.remove_task_observer(queue_id, key);
    test_notify_observers(queue_id);
    assert!(test_val.load(Ordering::SeqCst) == 0);
}

#[test]
fn wake_up_independent_of_time() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();

    let num_wakes = Arc::new(AtomicI32::new(0));
    let n = num_wakes.clone();
    let wakeable = TestWakeable::new(move |_wake_time| {
        n.fetch_add(1, Ordering::SeqCst);
    });
    task_queue.set_wakeable(queue_id, weak(&wakeable));

    task_queue.register_task(queue_id, noop(), chrono_ticks_since_epoch(), U);
    task_queue.register_task(queue_id, noop(), TimePoint::max(), U);

    assert!(num_wakes.load(Ordering::SeqCst) == 2);
}

#[test]
fn woken_up_with_newer_time() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();
    let latch = Arc::new(CountDownLatch::new(2));

    let expected = Arc::new(Mutex::new(TimePoint::max()));

    let (l, e) = (latch.clone(), expected.clone());
    let wakeable = TestWakeable::new(move |wake_time| {
        assert!(wake_time == *e.lock().unwrap());
        l.count_down();
    });

    task_queue.set_wakeable(queue_id, weak(&wakeable));

    task_queue.register_task(queue_id, noop(), TimePoint::max(), U);

    let now = chrono_ticks_since_epoch();
    *expected.lock().unwrap() = now;
    task_queue.register_task(queue_id, noop(), now, U);

    latch.wait();
}

#[test]
fn notify_observers_while_creating_queues() {
    let task_queues = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queues.create_task_queue();
    let first_observer_executing = Arc::new(AutoResetWaitableEvent::new());
    let before_second_observer = Arc::new(AutoResetWaitableEvent::new());

    let (f, b) = (first_observer_executing.clone(), before_second_observer.clone());
    task_queues.add_task_observer(
        queue_id,
        queue_id.value() as isize + 1,
        crate::closure::closure::new(move || {
            f.signal();
            b.wait();
        }),
    );

    for i in 0..100 {
        task_queues.add_task_observer(queue_id, queue_id.value() as isize + i + 2, noop());
    }

    std::thread::scope(|s| {
        s.spawn(|| test_notify_observers(queue_id));

        first_observer_executing.wait();

        for _ in 0..100 {
            task_queues.create_task_queue();
        }

        before_second_observer.signal();
    });
}

#[test]
fn queue_do_not_own_itself() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id = task_queue.create_task_queue();
    assert!(!task_queue.owns(queue_id, queue_id));
}

#[test]
fn queue_do_not_own_unmerged_task_queue_id() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    assert!(!task_queue.owns(task_queue.create_task_queue(), kUnmerged));
    assert!(!task_queue.owns(kUnmerged, task_queue.create_task_queue()));
    assert!(!task_queue.owns(kUnmerged, kUnmerged));
}

#[test]
fn queue_owns_merged_task_queue_id() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let platform_queue = task_queue.create_task_queue();
    let raster_queue = task_queue.create_task_queue();
    assert!(!task_queue.owns(platform_queue, raster_queue));
    assert!(!task_queue.owns(raster_queue, platform_queue));
    task_queue.merge(platform_queue, raster_queue);
    assert!(task_queue.owns(platform_queue, raster_queue));
    assert!(!task_queue.owns(raster_queue, platform_queue));
}

/// Verifies that tasks can be added to task queues concurrently.
#[test]
fn concurrent_queue_and_task_creating_counts() {
    let task_queues = MessageLoopTaskQueues::get_instance();

    // kThreadCount threads post kThreadTaskCount tasks each to kTaskQueuesCount
    // task queues. Each thread picks a task queue randomly for each task.
    const K_THREAD_COUNT: usize = 4;
    const K_TASK_QUEUES_COUNT: usize = 2;
    const K_THREAD_TASK_COUNT: usize = 500;

    let task_queue_ids: Vec<TaskQueueId> =
        (0..K_TASK_QUEUES_COUNT).map(|_| task_queues.create_task_queue()).collect();
    assert_eq!(task_queue_ids.len(), K_TASK_QUEUES_COUNT);

    let tasks_posted_latch = CountDownLatch::new(K_THREAD_COUNT);
    let rand = AtomicUsize::new(12345);

    let thread_main = || {
        for _ in 0..K_THREAD_TASK_COUNT {
            let r = rand.fetch_add(0x9e3779b9, Ordering::Relaxed) >> 7;
            let current_task_queue_id = task_queue_ids[r % K_TASK_QUEUES_COUNT];
            // The timepoint doesn't matter as the queue is never going to be
            // drained.
            let task_timepoint = chrono_ticks_since_epoch();
            task_queues.register_task(current_task_queue_id, noop(), task_timepoint, U);
        }
        tasks_posted_latch.count_down();
    };

    std::thread::scope(|s| {
        for _ in 0..K_THREAD_COUNT {
            s.spawn(thread_main);
        }
    });

    // All tasks have been posted by now. Check that they are all pending.
    let pending_tasks: usize =
        task_queue_ids.iter().map(|&queue| task_queues.get_num_pending_tasks(queue)).sum();
    assert_eq!(pending_tasks, K_THREAD_COUNT * K_THREAD_TASK_COUNT);
}

#[test]
fn register_task_wakes_up_owner_queue() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let platform_queue = task_queue.create_task_queue();
    let raster_queue = task_queue.create_task_queue();

    let wakes = Arc::new(Mutex::new(Vec::<TimePoint>::new()));
    let w = wakes.clone();
    let wakeable1 = TestWakeable::new(move |wake_time| w.lock().unwrap().push(wake_time));
    let wakeable2 = TestWakeable::new(|_wake_time| {
        // The raster queue is owned by the platform queue.
        panic!("the raster queue is owned by the platform queue");
    });
    task_queue.set_wakeable(platform_queue, weak(&wakeable1));
    task_queue.set_wakeable(raster_queue, weak(&wakeable2));

    let time1 = chrono_ticks_since_epoch() + TimeDelta::from_milliseconds(1);
    let time2 = chrono_ticks_since_epoch() + TimeDelta::from_milliseconds(2);

    assert_eq!(0, wakes.lock().unwrap().len());

    task_queue.register_task(platform_queue, noop(), time1, U);

    assert_eq!(1, wakes.lock().unwrap().len());
    assert_eq!(time1, wakes.lock().unwrap()[0]);

    task_queue.merge(platform_queue, raster_queue);

    task_queue.register_task(raster_queue, noop(), time2, U);

    assert_eq!(3, wakes.lock().unwrap().len());
    assert_eq!(time1, wakes.lock().unwrap()[1]);
    assert_eq!(time1, wakes.lock().unwrap()[2]);
}
