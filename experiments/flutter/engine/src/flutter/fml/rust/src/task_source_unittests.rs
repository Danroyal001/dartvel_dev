// Port of flutter/fml/task_source_unittests.cc.

use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};

use crate::closure::closure;
use crate::delayed_task::DelayedTask;
use crate::task_queue_id::TaskQueueId;
use crate::task_source::TaskSource;
use crate::task_source_grade::TaskSourceGrade;
use crate::time::chrono_timestamp_provider::chrono_ticks_since_epoch;
use crate::time::time_delta::TimeDelta;

fn noop() -> closure {
    Arc::new(|| {})
}

fn set(value: &Arc<AtomicI32>, to: i32) -> closure {
    let value = value.clone();
    Arc::new(move || value.store(to, Ordering::SeqCst))
}

#[test]
fn simple_initialization() {
    let mut task_source = TaskSource::new(TaskQueueId::new(1));
    task_source.register_task(DelayedTask::new(
        1,
        noop(),
        chrono_ticks_since_epoch(),
        TaskSourceGrade::kUnspecified,
    ));
    assert_eq!(task_source.get_num_pending_tasks(), 1);
}

#[test]
fn multiple_task_grades() {
    let mut task_source = TaskSource::new(TaskQueueId::new(1));
    task_source.register_task(DelayedTask::new(
        1,
        noop(),
        chrono_ticks_since_epoch(),
        TaskSourceGrade::kUnspecified,
    ));
    task_source.register_task(DelayedTask::new(
        2,
        noop(),
        chrono_ticks_since_epoch(),
        TaskSourceGrade::kUserInteraction,
    ));
    task_source.register_task(DelayedTask::new(
        3,
        noop(),
        chrono_ticks_since_epoch(),
        TaskSourceGrade::kDartEventLoop,
    ));
    assert_eq!(task_source.get_num_pending_tasks(), 3);
}

#[test]
fn simple_ordering() {
    let mut task_source = TaskSource::new(TaskQueueId::new(1));
    let time_stamp = chrono_ticks_since_epoch();
    let value = Arc::new(AtomicI32::new(0));
    task_source.register_task(DelayedTask::new(
        1,
        set(&value, 1),
        time_stamp,
        TaskSourceGrade::kUnspecified,
    ));
    task_source.register_task(DelayedTask::new(
        2,
        set(&value, 7),
        time_stamp + TimeDelta::from_milliseconds(1),
        TaskSourceGrade::kUnspecified,
    ));
    (task_source.top().task.get_task())();
    task_source.pop_task(TaskSourceGrade::kUnspecified);
    assert_eq!(value.load(Ordering::SeqCst), 1);
    (task_source.top().task.get_task())();
    task_source.pop_task(TaskSourceGrade::kUnspecified);
    assert_eq!(value.load(Ordering::SeqCst), 7);
}

#[test]
fn simple_ordering_multi_task_heaps() {
    let mut task_source = TaskSource::new(TaskQueueId::new(1));
    let time_stamp = chrono_ticks_since_epoch();
    let value = Arc::new(AtomicI32::new(0));
    task_source.register_task(DelayedTask::new(
        1,
        set(&value, 1),
        time_stamp,
        TaskSourceGrade::kDartEventLoop,
    ));
    task_source.register_task(DelayedTask::new(
        2,
        set(&value, 7),
        time_stamp + TimeDelta::from_milliseconds(1),
        TaskSourceGrade::kUserInteraction,
    ));
    let (task, grade) = {
        let top_task = task_source.top();
        (top_task.task.get_task().clone(), top_task.task.get_task_source_grade())
    };
    task();
    task_source.pop_task(grade);
    assert_eq!(value.load(Ordering::SeqCst), 1);
    let (task, grade) = {
        let second_task = task_source.top();
        (second_task.task.get_task().clone(), second_task.task.get_task_source_grade())
    };
    task();
    task_source.pop_task(grade);
    assert_eq!(value.load(Ordering::SeqCst), 7);
}

#[test]
fn ordering_multi_task_heaps_secondary_paused() {
    let mut task_source = TaskSource::new(TaskQueueId::new(1));
    let time_stamp = chrono_ticks_since_epoch();
    let value = Arc::new(AtomicI32::new(0));
    task_source.register_task(DelayedTask::new(
        1,
        set(&value, 1),
        time_stamp,
        TaskSourceGrade::kDartEventLoop,
    ));
    task_source.register_task(DelayedTask::new(
        2,
        set(&value, 7),
        time_stamp + TimeDelta::from_milliseconds(1),
        TaskSourceGrade::kUserInteraction,
    ));

    task_source.pause_secondary();

    let (task, grade) = {
        let top_task = task_source.top();
        (top_task.task.get_task().clone(), top_task.task.get_task_source_grade())
    };
    task();
    task_source.pop_task(grade);
    assert_eq!(value.load(Ordering::SeqCst), 7);

    assert!(task_source.is_empty());

    task_source.resume_secondary();

    let (task, grade) = {
        let second_task = task_source.top();
        (second_task.task.get_task().clone(), second_task.task.get_task_source_grade())
    };
    task();
    task_source.pop_task(grade);
    assert_eq!(value.load(Ordering::SeqCst), 1);
}
