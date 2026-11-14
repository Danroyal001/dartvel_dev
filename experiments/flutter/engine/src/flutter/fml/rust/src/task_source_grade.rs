// Port of flutter/fml/task_source_grade.h.
#![allow(non_camel_case_types)]

/// Categories of work dispatched to `MessageLoopTaskQueues` dispatcher. By
/// specifying the `TaskSourceGrade`, you indicate the task's importance to the
/// dispatcher.
#[allow(non_camel_case_types, clippy::enum_variant_names)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum TaskSourceGrade {
    /// This `TaskSourceGrade` indicates that a task is critical to user
    /// interaction.
    kUserInteraction,
    /// This `TaskSourceGrade` indicates that a task corresponds to servicing a
    /// dart event loop task. These aren't critical to user interaction.
    kDartEventLoop,
    /// The absence of a specialized `TaskSourceGrade`.
    kUnspecified,
}

/// `std::hash<TaskSourceGrade>`: the hash of the underlying `int`.
impl crate::hash_combine::StdHash for TaskSourceGrade {
    fn std_hash(&self) -> usize {
        (*self as i32) as usize
    }
}
