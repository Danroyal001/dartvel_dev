// Port of flutter/fml/task_source.h and flutter/fml/task_source.cc.

use crate::delayed_task::{DelayedTask, DelayedTaskQueue};
use crate::task_queue_id::TaskQueueId;
use crate::task_source_grade::TaskSourceGrade;

/// A Source of tasks for the `MessageLoopTaskQueues` task dispatcher. This is
/// a wrapper around a primary and secondary task heap with the difference
/// between them being that the secondary task heap can be paused and resumed
/// by the task dispatcher. `TaskSourceGrade` determines what task heap the
/// task is assigned to.
pub struct TaskSource {
    task_queue_id_: TaskQueueId,
    primary_task_queue_: DelayedTaskQueue,
    secondary_task_queue_: DelayedTaskQueue,
    secondary_pause_requests_: i32,
}

#[derive(Clone, Copy)]
pub struct TopTask<'a> {
    pub task_queue_id: TaskQueueId,
    pub task: &'a DelayedTask,
}

impl TaskSource {
    /// Construts a TaskSource with the given `task_queue_id`.
    pub fn new(task_queue_id: TaskQueueId) -> Self {
        TaskSource {
            task_queue_id_: task_queue_id,
            primary_task_queue_: DelayedTaskQueue::new(),
            secondary_task_queue_: DelayedTaskQueue::new(),
            secondary_pause_requests_: 0,
        }
    }

    /// Drops the pending tasks from both primary and secondary task heaps.
    pub fn shut_down(&mut self) {
        self.primary_task_queue_ = DelayedTaskQueue::new();
        self.secondary_task_queue_ = DelayedTaskQueue::new();
    }

    /// Adds a task to the corresponding task heap as dictated by the
    /// `TaskSourceGrade` of the `DelayedTask`.
    pub fn register_task(&mut self, task: DelayedTask) {
        match task.get_task_source_grade() {
            TaskSourceGrade::kUserInteraction => self.primary_task_queue_.push(task),
            TaskSourceGrade::kUnspecified => self.primary_task_queue_.push(task),
            TaskSourceGrade::kDartEventLoop => self.secondary_task_queue_.push(task),
        }
    }

    /// Pops the task heap corresponding to the `TaskSourceGrade`.
    pub fn pop_task(&mut self, grade: TaskSourceGrade) {
        // std::priority_queue::pop on an empty queue is undefined behaviour;
        // BinaryHeap::pop does nothing.
        match grade {
            TaskSourceGrade::kUserInteraction => self.primary_task_queue_.pop(),
            TaskSourceGrade::kUnspecified => self.primary_task_queue_.pop(),
            TaskSourceGrade::kDartEventLoop => self.secondary_task_queue_.pop(),
        };
    }

    /// Returns the number of pending tasks. Excludes the tasks from the
    /// secondary heap if it's paused.
    pub fn get_num_pending_tasks(&self) -> usize {
        let mut size = self.primary_task_queue_.len();
        if self.secondary_pause_requests_ == 0 {
            size += self.secondary_task_queue_.len();
        }
        size
    }

    /// Returns true if `GetNumPendingTasks` is zero.
    pub fn is_empty(&self) -> bool {
        self.get_num_pending_tasks() == 0
    }

    /// Returns the top task based on scheduled time, taking into account
    /// whether the secondary heap has been paused or not.
    pub fn top(&self) -> TopTask<'_> {
        assert!(!self.is_empty(), "Check failed: !IsEmpty().");
        if self.secondary_pause_requests_ > 0 || self.secondary_task_queue_.is_empty() {
            let primary_top = self.primary_task_queue_.peek().unwrap();
            TopTask { task_queue_id: self.task_queue_id_, task: primary_top }
        } else if self.primary_task_queue_.is_empty() {
            let secondary_top = self.secondary_task_queue_.peek().unwrap();
            TopTask { task_queue_id: self.task_queue_id_, task: secondary_top }
        } else {
            let primary_top = self.primary_task_queue_.peek().unwrap();
            let secondary_top = self.secondary_task_queue_.peek().unwrap();
            if primary_top.gt(secondary_top) {
                TopTask { task_queue_id: self.task_queue_id_, task: secondary_top }
            } else {
                TopTask { task_queue_id: self.task_queue_id_, task: primary_top }
            }
        }
    }

    /// Pause providing tasks from secondary task heap.
    pub fn pause_secondary(&mut self) {
        self.secondary_pause_requests_ += 1;
    }

    /// Resume providing tasks from secondary task heap.
    pub fn resume_secondary(&mut self) {
        self.secondary_pause_requests_ -= 1;
        debug_assert!(self.secondary_pause_requests_ >= 0);
    }
}
