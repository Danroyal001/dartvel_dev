// Port of flutter/fml/memory/task_runner_checker.h and
// flutter/fml/memory/task_runner_checker.cc.

use std::collections::BTreeSet;

use crate::fml_check_at;
use crate::message_loop::MessageLoop;
use crate::message_loop_task_queues::MessageLoopTaskQueues;
use crate::task_queue_id::TaskQueueId;

const FILE: &str = "flutter/fml/memory/task_runner_checker.cc";

#[derive(Clone, Debug)]
pub struct TaskRunnerChecker {
    initialized_queue_id_: TaskQueueId,
    subsumed_queue_ids_: BTreeSet<TaskQueueId>,
}

impl Default for TaskRunnerChecker {
    fn default() -> Self {
        Self::new()
    }
}

impl TaskRunnerChecker {
    pub fn new() -> Self {
        let initialized_queue_id_ = Self::init_task_queue_id();
        let subsumed_queue_ids_ =
            MessageLoopTaskQueues::get_instance().get_subsumed_task_queue_id(initialized_queue_id_);
        TaskRunnerChecker { initialized_queue_id_, subsumed_queue_ids_ }
    }

    pub fn runs_on_creation_task_runner(&self) -> bool {
        fml_check_at!(
            FILE,
            18,
            "fml::MessageLoop::IsInitializedForCurrentThread()",
            MessageLoop::is_initialized_for_current_thread()
        );
        let current_queue_id = MessageLoop::get_current_task_queue_id();
        if Self::runs_on_the_same_thread(current_queue_id, self.initialized_queue_id_) {
            return true;
        }
        for &subsumed in &self.subsumed_queue_ids_ {
            if Self::runs_on_the_same_thread(current_queue_id, subsumed) {
                return true;
            }
        }
        false
    }

    pub fn runs_on_the_same_thread(queue_a: TaskQueueId, queue_b: TaskQueueId) -> bool {
        if queue_a == queue_b {
            return true;
        }

        let queues = MessageLoopTaskQueues::get_instance();
        if queues.owns(queue_a, queue_b) {
            return true;
        }
        if queues.owns(queue_b, queue_a) {
            return true;
        }
        false
    }

    fn init_task_queue_id() -> TaskQueueId {
        MessageLoop::ensure_initialized_for_current_thread();
        MessageLoop::get_current_task_queue_id()
    }
}

/// `FML_DECLARE_TASK_RUNNER_CHECKER(c)`: a TaskRunnerChecker in debug builds,
/// nothing in release builds.
#[derive(Clone, Debug, Default)]
pub struct DebugTaskRunnerChecker {
    #[cfg(debug_assertions)]
    pub checker: Option<TaskRunnerChecker>,
}

impl DebugTaskRunnerChecker {
    pub fn new() -> Self {
        DebugTaskRunnerChecker {
            #[cfg(debug_assertions)]
            checker: Some(TaskRunnerChecker::new()),
        }
    }

    /// `FML_DCHECK_TASK_RUNNER_IS_CURRENT(c)`.
    #[inline]
    pub fn dcheck_task_runner_is_current(&self) {
        #[cfg(debug_assertions)]
        if let Some(checker) = &self.checker {
            crate::fml_check_at!(
                "flutter/fml/memory/weak_ptr.h",
                195,
                "(c).RunsOnCreationTaskRunner()",
                checker.runs_on_creation_task_runner()
            );
        }
    }
}
