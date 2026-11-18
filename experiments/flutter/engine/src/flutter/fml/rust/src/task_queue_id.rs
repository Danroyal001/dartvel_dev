// Port of flutter/fml/task_queue_id.h (the constants are defined in
// message_loop_task_queues.cc upstream).

/// `MessageLoopTaskQueues` task dispatcher's internal task queue identifier.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TaskQueueId {
    value_: usize,
}

impl TaskQueueId {
    /// This constant indicates whether a task queue has been subsumed by a
    /// task runner.
    pub const K_UNMERGED: usize = usize::MAX; // ULONG_MAX

    /// This constant indicates an invalid task queue. Used in embedder
    /// supplied task runners not associated with a task queue.
    pub const K_INVALID: usize = usize::MAX - 1;

    /// Intializes a task queue with the given value as it's ID.
    pub const fn new(value: usize) -> Self {
        TaskQueueId { value_: value }
    }

    pub const fn invalid() -> Self {
        TaskQueueId::new(Self::K_INVALID)
    }

    /// `operator size_t`.
    pub const fn value(self) -> usize {
        self.value_
    }

    pub const fn is_valid(self) -> bool {
        self.value_ != Self::K_INVALID
    }
}

impl From<TaskQueueId> for usize {
    fn from(id: TaskQueueId) -> usize {
        id.value_
    }
}

impl std::fmt::Display for TaskQueueId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.value_)
    }
}
