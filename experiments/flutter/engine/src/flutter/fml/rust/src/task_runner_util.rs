// Port of flutter/fml/task_runner_util.h and flutter/fml/task_runner_util.cc.

use std::sync::{Arc, Weak};

use crate::closure::closure;
use crate::memory::ref_ptr::RefPtr;
use crate::task_runner::{BasicTaskRunner, TaskRunner};

/// A BasicTaskRunner that posts to a TaskRunner.
pub struct WrapperBasicTaskRunner {
    task_runner_: RefPtr<TaskRunner>,
}

impl WrapperBasicTaskRunner {
    pub fn new(task_runner: RefPtr<TaskRunner>) -> Self {
        WrapperBasicTaskRunner { task_runner_: task_runner }
    }
}

impl BasicTaskRunner for WrapperBasicTaskRunner {
    fn post_task(&self, task: closure) {
        self.task_runner_.post_task(task);
    }
}

type IsUsable = dyn Fn() -> bool + Send + Sync;

/// A BasicTaskRunner whose tasks run only while `is_usable` says so, checked
/// when each task runs, and never once this runner is gone.
pub struct ConditionalBasicTaskRunner {
    task_runner_: RefPtr<TaskRunner>,
    is_usable_: Arc<Box<IsUsable>>,
}

impl ConditionalBasicTaskRunner {
    pub fn new(
        task_runner: RefPtr<TaskRunner>,
        is_usable: impl Fn() -> bool + Send + Sync + 'static,
    ) -> Self {
        ConditionalBasicTaskRunner {
            task_runner_: task_runner,
            is_usable_: Arc::new(Box::new(is_usable)),
        }
    }
}

impl BasicTaskRunner for ConditionalBasicTaskRunner {
    fn post_task(&self, task: closure) {
        let weak_is_usable: Weak<Box<IsUsable>> = Arc::downgrade(&self.is_usable_);
        let task_wrapper: closure = Arc::new(move || {
            let is_usable = weak_is_usable.upgrade();
            if is_usable.is_some_and(|is_usable| is_usable()) {
                task();
            }
        });
        self.task_runner_.post_task(task_wrapper);
    }
}
