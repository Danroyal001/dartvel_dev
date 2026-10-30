// Port of flutter/fml/message_loop_task_queues_merge_unmerge_unittests.cc.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::message_loop_task_queues::MessageLoopTaskQueues;
use crate::message_loop_task_queues_unittests::{TestWakeable, noop, weak};
use crate::synchronization::count_down_latch::CountDownLatch;
use crate::synchronization::waitable_event::AutoResetWaitableEvent;
use crate::task_queue_id::TaskQueueId;
use crate::task_source_grade::TaskSourceGrade;
use crate::time::chrono_timestamp_provider::chrono_ticks_since_epoch;

const U: TaskSourceGrade = TaskSourceGrade::kUnspecified;

fn count_remaining_tasks(
    task_queue: &MessageLoopTaskQueues,
    queue_id: TaskQueueId,
    run_invocation: bool,
) -> i32 {
    let now = chrono_ticks_since_epoch();
    let mut count = 0;
    loop {
        let Some(invocation) = task_queue.get_next_task_to_run(queue_id, now) else {
            break;
        };
        count += 1;
        if run_invocation {
            invocation();
        }
    }
    count
}

#[test]
fn after_merge_primary_tasks_serviced_on_primary() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    task_queue.register_task(queue_id_1, noop(), chrono_ticks_since_epoch(), U);
    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_1));

    task_queue.merge(queue_id_1, queue_id_2);
    task_queue.register_task(queue_id_1, noop(), chrono_ticks_since_epoch(), U);

    assert_eq!(2, task_queue.get_num_pending_tasks(queue_id_1));
    assert_eq!(0, task_queue.get_num_pending_tasks(queue_id_2));
}

#[test]
fn after_merge_secondary_tasks_also_serviced_on_primary() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    task_queue.register_task(queue_id_2, noop(), chrono_ticks_since_epoch(), U);
    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_2));

    task_queue.merge(queue_id_1, queue_id_2);
    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_1));
    assert_eq!(0, task_queue.get_num_pending_tasks(queue_id_2));
}

#[test]
fn merge_unmerge_tasks_preserved() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    task_queue.register_task(queue_id_1, noop(), chrono_ticks_since_epoch(), U);
    task_queue.register_task(queue_id_2, noop(), chrono_ticks_since_epoch(), U);

    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_1));
    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_2));

    task_queue.merge(queue_id_1, queue_id_2);

    assert_eq!(2, task_queue.get_num_pending_tasks(queue_id_1));
    assert_eq!(0, task_queue.get_num_pending_tasks(queue_id_2));

    task_queue.unmerge(queue_id_1, queue_id_2);

    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_1));
    assert_eq!(1, task_queue.get_num_pending_tasks(queue_id_2));
}

/// Multiple standalone engines scene
#[test]
fn one_can_own_multiple_queues_and_unmerge_independently() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();
    let queue_id_3 = task_queue.create_task_queue();

    // merge
    assert!(task_queue.merge(queue_id_1, queue_id_2));
    assert!(task_queue.owns(queue_id_1, queue_id_2));
    assert!(!task_queue.owns(queue_id_1, queue_id_3));

    assert!(task_queue.merge(queue_id_1, queue_id_3));
    assert!(task_queue.owns(queue_id_1, queue_id_2));
    assert!(task_queue.owns(queue_id_1, queue_id_3));

    // unmerge
    assert!(task_queue.unmerge(queue_id_1, queue_id_2));
    assert!(!task_queue.owns(queue_id_1, queue_id_2));
    assert!(task_queue.owns(queue_id_1, queue_id_3));

    assert!(task_queue.unmerge(queue_id_1, queue_id_3));
    assert!(!task_queue.owns(queue_id_1, queue_id_2));
    assert!(!task_queue.owns(queue_id_1, queue_id_3));
}

/// Multiple standalone engines scene
#[test]
fn cannot_merge_same_queue_to_two_different_owners() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    let queue = task_queue.create_task_queue();
    let owner_1 = task_queue.create_task_queue();
    let owner_2 = task_queue.create_task_queue();

    assert!(task_queue.merge(owner_1, queue));
    assert!(!task_queue.merge(owner_2, queue));
}

#[test]
fn merge_fail_if_already_subsumed() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();
    let queue_id_3 = task_queue.create_task_queue();

    assert!(task_queue.merge(queue_id_1, queue_id_2));
    assert!(!task_queue.merge(queue_id_2, queue_id_3));
    assert!(!task_queue.merge(queue_id_2, queue_id_1));
}

#[test]
fn merge_fail_if_already_owns_but_try_to_be_subsumed() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();
    let queue_id_3 = task_queue.create_task_queue();

    task_queue.merge(queue_id_1, queue_id_2);
    // A recursively linked merging will fail
    assert!(!task_queue.merge(queue_id_3, queue_id_1));
}

#[test]
fn unmerge_fails_on_subsumed_or_never_merged() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();
    let queue_id_3 = task_queue.create_task_queue();

    task_queue.merge(queue_id_1, queue_id_2);
    assert!(!task_queue.unmerge(queue_id_2, queue_id_3));
    assert!(!task_queue.unmerge(queue_id_1, queue_id_3));
    assert!(!task_queue.unmerge(queue_id_3, queue_id_1));
    assert!(!task_queue.unmerge(queue_id_2, queue_id_1));
}

#[test]
fn merge_invokes_both_wakeables() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    let latch = Arc::new(CountDownLatch::new(2));

    let l1 = latch.clone();
    let wakeable1 = TestWakeable::new(move |_| l1.count_down());
    let l2 = latch.clone();
    let wakeable2 = TestWakeable::new(move |_| l2.count_down());

    task_queue.set_wakeable(queue_id_1, weak(&wakeable1));
    task_queue.set_wakeable(queue_id_2, weak(&wakeable2));

    task_queue.register_task(queue_id_1, noop(), chrono_ticks_since_epoch(), U);

    task_queue.merge(queue_id_1, queue_id_2);

    count_remaining_tasks(task_queue, queue_id_1, false);

    latch.wait();
}

#[test]
fn merge_unmerge_invokes_both_wakeables_separately() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    let latch_1 = Arc::new(AutoResetWaitableEvent::new());
    let latch_2 = Arc::new(AutoResetWaitableEvent::new());

    let l1 = latch_1.clone();
    let wakeable1 = TestWakeable::new(move |_| l1.signal());
    let l2 = latch_2.clone();
    let wakeable2 = TestWakeable::new(move |_| l2.signal());

    task_queue.set_wakeable(queue_id_1, weak(&wakeable1));
    task_queue.set_wakeable(queue_id_2, weak(&wakeable2));

    task_queue.register_task(queue_id_1, noop(), chrono_ticks_since_epoch(), U);
    task_queue.register_task(queue_id_2, noop(), chrono_ticks_since_epoch(), U);

    task_queue.merge(queue_id_1, queue_id_2);
    task_queue.unmerge(queue_id_1, queue_id_2);

    count_remaining_tasks(task_queue, queue_id_1, false);

    latch_1.wait();

    count_remaining_tasks(task_queue, queue_id_2, false);

    latch_2.wait();
}

#[test]
fn get_tasks_to_run_now_blocks_merge() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    let wake_up_start = Arc::new(AutoResetWaitableEvent::new());
    let wake_up_end = Arc::new(AutoResetWaitableEvent::new());
    let merge_start = AutoResetWaitableEvent::new();
    let merge_end = AutoResetWaitableEvent::new();

    let (ws, we) = (wake_up_start.clone(), wake_up_end.clone());
    let wakeable = TestWakeable::new(move |_| {
        ws.signal();
        we.wait();
    });

    task_queue.register_task(queue_id_1, noop(), chrono_ticks_since_epoch(), U);
    task_queue.set_wakeable(queue_id_1, weak(&wakeable));

    let merge_done = AtomicBool::new(false);
    std::thread::scope(|s| {
        s.spawn(|| {
            count_remaining_tasks(task_queue, queue_id_1, false);
        });

        wake_up_start.wait();

        s.spawn(|| {
            merge_start.signal();
            task_queue.merge(queue_id_1, queue_id_2);
            merge_done.store(true, Ordering::SeqCst);
            merge_end.signal();
        });

        merge_start.wait();
        assert!(!merge_done.load(Ordering::SeqCst));
        wake_up_end.signal();

        merge_end.wait();
        assert!(merge_done.load(Ordering::SeqCst));
    });
}

#[test]
fn following_tasks_switch_queue_if_first_task_merges_threads() {
    let task_queue = MessageLoopTaskQueues::get_instance();

    let queue_id_1 = task_queue.create_task_queue();
    let queue_id_2 = task_queue.create_task_queue();

    let latch = Arc::new(CountDownLatch::new(2));

    let l1 = latch.clone();
    let wakeable1 = TestWakeable::new(move |_| l1.count_down());
    let l2 = latch.clone();
    let wakeable2 = TestWakeable::new(move |_| l2.count_down());

    task_queue.set_wakeable(queue_id_1, weak(&wakeable1));
    task_queue.set_wakeable(queue_id_2, weak(&wakeable2));

    task_queue.register_task(
        queue_id_2,
        Arc::new(move || {
            MessageLoopTaskQueues::get_instance().merge(queue_id_1, queue_id_2);
        }),
        chrono_ticks_since_epoch(),
        U,
    );
    task_queue.register_task(queue_id_2, noop(), chrono_ticks_since_epoch(), U);

    assert_eq!(count_remaining_tasks(task_queue, queue_id_2, true), 1);
    assert_eq!(count_remaining_tasks(task_queue, queue_id_1, true), 1);

    latch.wait();
}
