// Port of flutter/fml/delayed_task.h and flutter/fml/delayed_task.cc.

use std::cmp::Ordering;
use std::collections::BinaryHeap;

use crate::closure::closure;
use crate::task_source_grade::TaskSourceGrade;
use crate::time::time_point::TimePoint;

#[derive(Clone)]
pub struct DelayedTask {
    order_: usize,
    task_: closure,
    target_time_: TimePoint,
    task_source_grade_: TaskSourceGrade,
}

impl DelayedTask {
    pub fn new(
        order: usize,
        task: closure,
        target_time: TimePoint,
        task_source_grade: TaskSourceGrade,
    ) -> Self {
        DelayedTask { order_: order, task_: task, target_time_: target_time, task_source_grade_: task_source_grade }
    }

    pub fn get_task(&self) -> &closure {
        &self.task_
    }

    /// The task, moved out (the port's: upstream copies it with GetTask()).
    pub fn into_task(self) -> closure {
        self.task_
    }

    pub fn get_target_time(&self) -> TimePoint {
        self.target_time_
    }

    pub fn get_task_source_grade(&self) -> TaskSourceGrade {
        self.task_source_grade_
    }

    /// `operator>`.
    pub fn gt(&self, other: &DelayedTask) -> bool {
        if self.target_time_ == other.target_time_ {
            return self.order_ > other.order_;
        }
        self.target_time_ > other.target_time_
    }
}

// `std::priority_queue<DelayedTask, std::deque<DelayedTask>,
// std::greater<DelayedTask>>` is a min-heap under operator>; BinaryHeap is a
// max-heap, so Ord is operator> reversed: the task upstream's queue puts on
// top is the greatest here.
impl Ord for DelayedTask {
    fn cmp(&self, other: &DelayedTask) -> Ordering {
        if self.gt(other) {
            Ordering::Less
        } else if other.gt(self) {
            Ordering::Greater
        } else {
            Ordering::Equal
        }
    }
}

impl PartialOrd for DelayedTask {
    fn partial_cmp(&self, other: &DelayedTask) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for DelayedTask {
    fn eq(&self, other: &DelayedTask) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

impl Eq for DelayedTask {}

pub type DelayedTaskQueue = BinaryHeap<DelayedTask>;
