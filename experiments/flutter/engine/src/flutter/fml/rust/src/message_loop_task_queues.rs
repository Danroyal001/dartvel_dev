// Port of flutter/fml/message_loop_task_queues.h and
// flutter/fml/message_loop_task_queues.cc.
//
// Upstream keeps a raw `Wakeable*` it does not own; the message loop that
// registers itself unregisters by disposing its queue. Here it is a
// `Weak<dyn Wakeable>`: an owning `Arc` would keep every loop alive through
// the singleton, and a Weak that can no longer be upgraded is skipped where
// upstream would call through a dangling pointer. `queue_entries_.at()` on
// an unknown id throws std::out_of_range upstream and panics here.
//
// Upstream slips kept: the thread-local task source grade is set only on the
// thread that creates the singleton and on threads that have run a task, so
// GetCurrentTaskSourceGrade on any other thread dereferences null (panics
// here); `order_` is an `int` that is widened to `size_t`.

use std::cell::Cell;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Mutex, MutexGuard, OnceLock, Weak};

use crate::closure::closure;
use crate::delayed_task::DelayedTask;
use crate::fml_log_at;
use crate::task_queue_id::TaskQueueId;
use crate::task_source::{TaskSource, TopTask};
use crate::task_source_grade::TaskSourceGrade;
use crate::time::time_point::TimePoint;
use crate::wakeable::Wakeable;

const FILE: &str = "flutter/fml/message_loop_task_queues.cc";

#[allow(non_upper_case_globals)]
pub const kUnmerged: TaskQueueId = TaskQueueId::new(TaskQueueId::K_UNMERGED);

thread_local! {
    // iOS prior to version 9 prevents c++11 thread_local and __thread
    // specifier, having us resort to boxed enum containers.
    static TLS_TASK_SOURCE_GRADE: Cell<Option<TaskSourceGrade>> = const { Cell::new(None) };
}

pub type TaskObservers = BTreeMap<isize, closure>;

/// A collection of tasks and observers associated with one TaskQueue.
///
/// Often a TaskQueue has a one-to-one relationship with a fml::MessageLoop,
/// this isn't the case when TaskQueues are merged via
/// `fml::MessageLoopTaskQueues::merge`.
pub struct TaskQueueEntry {
    pub wakeable: Option<Weak<dyn Wakeable>>,
    pub task_observers: TaskObservers,
    pub task_source: Box<TaskSource>,

    /// Set of the TaskQueueIds which is owned by this TaskQueue. If the set is
    /// empty, this TaskQueue does not own any other TaskQueues.
    pub owner_of: BTreeSet<TaskQueueId>,

    /// Identifies the TaskQueue that subsumes this TaskQueue. If it is
    /// kUnmerged it indicates that this TaskQueue is not owned by any other
    /// TaskQueue.
    pub subsumed_by: TaskQueueId,

    pub created_for: TaskQueueId,
}

impl TaskQueueEntry {
    pub fn new(created_for: TaskQueueId) -> Self {
        TaskQueueEntry {
            wakeable: None,
            task_observers: TaskObservers::new(),
            task_source: Box::new(TaskSource::new(created_for)),
            owner_of: BTreeSet::new(),
            subsumed_by: kUnmerged,
            created_for,
        }
    }
}

#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlushType {
    kSingle,
    kAll,
}

struct Locked {
    queue_entries_: BTreeMap<TaskQueueId, Box<TaskQueueEntry>>,
    task_queue_id_counter_: usize,
}

/// A singleton container for all tasks and observers associated with all
/// fml::MessageLoops.
///
/// This also wakes up the loop at the required times.
pub struct MessageLoopTaskQueues {
    queue_mutex_: Mutex<Locked>,
    order_: AtomicI32,
}

impl Locked {
    fn at(&self, queue_id: TaskQueueId) -> &TaskQueueEntry {
        self.queue_entries_.get(&queue_id).expect("map::at:  key not found")
    }

    fn at_mut(&mut self, queue_id: TaskQueueId) -> &mut TaskQueueEntry {
        self.queue_entries_.get_mut(&queue_id).expect("map::at:  key not found")
    }

    fn wake_up_unlocked(&self, queue_id: TaskQueueId, time: TimePoint) {
        if let Some(wakeable) = &self.at(queue_id).wakeable {
            if let Some(wakeable) = wakeable.upgrade() {
                wakeable.wake_up(time);
            }
        }
    }

    // Subsumed queues will never have pending tasks.
    // Owning queues will consider both their and their subsumed tasks.
    fn has_pending_tasks_unlocked(&self, queue_id: TaskQueueId) -> bool {
        let entry = self.at(queue_id);
        let is_subsumed = entry.subsumed_by != kUnmerged;
        if is_subsumed {
            return false;
        }

        if !entry.task_source.is_empty() {
            return true;
        }

        let subsumed_set = &entry.owner_of;
        subsumed_set.iter().any(|&subsumed| !self.at(subsumed).task_source.is_empty())
    }

    fn get_next_wake_time_unlocked(&self, queue_id: TaskQueueId) -> TimePoint {
        self.peek_next_task_unlocked(queue_id).task.get_target_time()
    }

    fn peek_next_task_unlocked<'a>(&'a self, owner: TaskQueueId) -> TopTask<'a> {
        debug_assert!(self.has_pending_tasks_unlocked(owner));
        let entry = self.at(owner);
        if entry.owner_of.is_empty() {
            assert!(!entry.task_source.is_empty(), "Check failed: !entry->task_source->IsEmpty().");
            return entry.task_source.top();
        }

        // Use optional for the memory of TopTask object.
        let mut top_task: Option<TopTask<'a>> = None;

        let mut top_task_updater = |source: &'a TaskSource| {
            if !source.is_empty() {
                let other_task = source.top();
                if top_task.is_none_or(|t| t.task.gt(other_task.task)) {
                    top_task = Some(other_task);
                }
            }
        };

        let owner_tasks = &*entry.task_source;
        top_task_updater(owner_tasks);

        for &subsumed in &entry.owner_of {
            let subsumed_tasks = &*self.at(subsumed).task_source;
            top_task_updater(subsumed_tasks);
        }
        // At least one task at the top because PeekNextTaskUnlocked() is
        // called after HasPendingTasksUnlocked()
        top_task.expect("Check failed: top_task.has_value().")
    }
}

impl MessageLoopTaskQueues {
    // Lifecycle.

    pub fn get_instance() -> &'static MessageLoopTaskQueues {
        static INSTANCE: OnceLock<MessageLoopTaskQueues> = OnceLock::new();
        INSTANCE.get_or_init(MessageLoopTaskQueues::new)
    }

    fn new() -> Self {
        TLS_TASK_SOURCE_GRADE.with(|g| g.set(Some(TaskSourceGrade::kUnspecified)));
        MessageLoopTaskQueues {
            queue_mutex_: Mutex::new(Locked {
                queue_entries_: BTreeMap::new(),
                task_queue_id_counter_: 0,
            }),
            order_: AtomicI32::new(0),
        }
    }

    fn lock(&self) -> MutexGuard<'_, Locked> {
        self.queue_mutex_.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn create_task_queue(&self) -> TaskQueueId {
        let mut guard = self.lock();
        let loop_id = TaskQueueId::new(guard.task_queue_id_counter_);
        guard.task_queue_id_counter_ += 1;
        guard.queue_entries_.insert(loop_id, Box::new(TaskQueueEntry::new(loop_id)));
        loop_id
    }

    pub fn dispose(&self, queue_id: TaskQueueId) {
        let mut guard = self.lock();
        let queue_entry = guard.at(queue_id);
        debug_assert!(queue_entry.subsumed_by == kUnmerged);
        let subsumed_set: Vec<TaskQueueId> = queue_entry.owner_of.iter().copied().collect();
        for subsumed in subsumed_set {
            guard.queue_entries_.remove(&subsumed);
        }
        // Erase owner queue_id at last to avoid &subsumed_set from being invalid
        guard.queue_entries_.remove(&queue_id);
    }

    pub fn dispose_tasks(&self, queue_id: TaskQueueId) {
        let mut guard = self.lock();
        let queue_entry = guard.at_mut(queue_id);
        debug_assert!(queue_entry.subsumed_by == kUnmerged);
        queue_entry.task_source.shut_down();
        let subsumed_set: Vec<TaskQueueId> = queue_entry.owner_of.iter().copied().collect();
        for subsumed in subsumed_set {
            guard.at_mut(subsumed).task_source.shut_down();
        }
    }

    // Tasks methods.

    pub fn register_task(
        &self,
        queue_id: TaskQueueId,
        task: closure,
        target_time: TimePoint,
        task_source_grade: TaskSourceGrade,
    ) {
        let mut guard = self.lock();
        let order = self.order_.fetch_add(1, Ordering::SeqCst) as isize as usize;
        let queue_entry = guard.at_mut(queue_id);
        queue_entry
            .task_source
            .register_task(DelayedTask::new(order, task, target_time, task_source_grade));
        let mut loop_to_wake = queue_id;
        if queue_entry.subsumed_by != kUnmerged {
            loop_to_wake = queue_entry.subsumed_by;
        }

        // This can happen when the secondary tasks are paused.
        if guard.has_pending_tasks_unlocked(loop_to_wake) {
            guard.wake_up_unlocked(loop_to_wake, guard.get_next_wake_time_unlocked(loop_to_wake));
        }
    }

    pub fn has_pending_tasks(&self, queue_id: TaskQueueId) -> bool {
        self.lock().has_pending_tasks_unlocked(queue_id)
    }

    pub fn get_next_task_to_run(
        &self,
        queue_id: TaskQueueId,
        from_time: TimePoint,
    ) -> Option<closure> {
        let mut guard = self.lock();
        if !guard.has_pending_tasks_unlocked(queue_id) {
            return None;
        }
        let top = guard.peek_next_task_unlocked(queue_id);
        let top_queue_id = top.task_queue_id;
        let top_target_time = top.task.get_target_time();
        let invocation = top.task.get_task().clone();
        let task_source_grade = top.task.get_task_source_grade();

        if !guard.has_pending_tasks_unlocked(queue_id) {
            guard.wake_up_unlocked(queue_id, TimePoint::max());
        } else {
            guard.wake_up_unlocked(queue_id, guard.get_next_wake_time_unlocked(queue_id));
        }

        if top_target_time > from_time {
            return None;
        }
        guard.at_mut(top_queue_id).task_source.pop_task(task_source_grade);
        TLS_TASK_SOURCE_GRADE.with(|g| g.set(Some(task_source_grade)));
        Some(invocation)
    }

    pub fn get_num_pending_tasks(&self, queue_id: TaskQueueId) -> usize {
        let guard = self.lock();
        let queue_entry = guard.at(queue_id);
        if queue_entry.subsumed_by != kUnmerged {
            return 0;
        }

        let mut total_tasks = 0;
        total_tasks += queue_entry.task_source.get_num_pending_tasks();

        for &subsumed in &queue_entry.owner_of {
            let subsumed_entry = guard.at(subsumed);
            total_tasks += subsumed_entry.task_source.get_num_pending_tasks();
        }
        total_tasks
    }

    pub fn get_current_task_source_grade() -> TaskSourceGrade {
        TLS_TASK_SOURCE_GRADE
            .with(|g| g.get())
            .expect("tls_task_source_grade is null on this thread")
    }

    // Observers methods.

    pub fn add_task_observer(&self, queue_id: TaskQueueId, key: isize, callback: closure) {
        self.lock().at_mut(queue_id).task_observers.insert(key, callback);
    }

    pub fn remove_task_observer(&self, queue_id: TaskQueueId, key: isize) {
        self.lock().at_mut(queue_id).task_observers.remove(&key);
    }

    pub fn get_observers_to_notify(&self, queue_id: TaskQueueId) -> Vec<closure> {
        let guard = self.lock();
        let mut observers = Vec::new();

        if guard.at(queue_id).subsumed_by != kUnmerged {
            return observers;
        }

        for observer in guard.at(queue_id).task_observers.values() {
            observers.push(observer.clone());
        }

        for &subsumed in &guard.at(queue_id).owner_of {
            for observer in guard.at(subsumed).task_observers.values() {
                observers.push(observer.clone());
            }
        }

        observers
    }

    // Misc.

    pub fn set_wakeable(&self, queue_id: TaskQueueId, wakeable: Weak<dyn Wakeable>) {
        let mut guard = self.lock();
        assert!(
            guard.at(queue_id).wakeable.is_none(),
            "Check failed: !queue_entries_.at(queue_id)->wakeable. Wakeable can only be set once."
        );
        guard.at_mut(queue_id).wakeable = Some(wakeable);
    }

    // Invariants for merge and un-merge
    //  1. RegisterTask will always submit to the queue_id that is passed
    //     to it. It is not aware of whether a queue is merged or not. Same with
    //     task observers.
    //  2. When we get the tasks to run now, we look at both the queue_ids
    //     for the owner and the subsumed task queues.
    //  3. One TaskQueue can subsume multiple other TaskQueues. A TaskQueue can
    //     be in exactly one of the following three states:
    //     a. Be an owner of multiple other TaskQueues.
    //     b. Be subsumed by a TaskQueue (an owner can never be subsumed).
    //     c. Be independent, i.e, neither owner nor be subsumed.
    //
    //  Methods currently aware of the merged state of the queues:
    //  HasPendingTasks, GetNextTaskToRun, GetNumPendingTasks
    pub fn merge(&self, owner: TaskQueueId, subsumed: TaskQueueId) -> bool {
        if owner == subsumed {
            return true;
        }
        let mut guard = self.lock();
        let owner_entry = guard.at(owner);
        let subsumed_entry = guard.at(subsumed);
        let subsumed_set = &owner_entry.owner_of;
        if subsumed_set.contains(&subsumed) {
            return true;
        }

        // Won't check owner_entry->owner_of, because it may contains items when
        // merged with other different queues.

        // Ensure owner_entry->subsumed_by being kUnmerged
        if owner_entry.subsumed_by != kUnmerged {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                229,
                "Thread merging failed: owner_entry was already subsumed by others, owner={}, subsumed={}, owner->subsumed_by={}",
                owner,
                subsumed,
                owner_entry.subsumed_by
            );
            return false;
        }
        // Ensure subsumed_entry->owner_of being empty
        if !subsumed_entry.owner_of.is_empty() {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                237,
                "Thread merging failed: subsumed_entry already owns others, owner={}, subsumed={}, subsumed->owner_of.size()={}",
                owner,
                subsumed,
                subsumed_entry.owner_of.len()
            );
            return false;
        }
        // Ensure subsumed_entry->subsumed_by being kUnmerged
        if subsumed_entry.subsumed_by != kUnmerged {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                245,
                "Thread merging failed: subsumed_entry was already subsumed by others, owner={}, subsumed={}, subsumed->subsumed_by={}",
                owner,
                subsumed,
                subsumed_entry.subsumed_by
            );
            return false;
        }
        // All checking is OK, set merged state.
        guard.at_mut(owner).owner_of.insert(subsumed);
        guard.at_mut(subsumed).subsumed_by = owner;

        if guard.has_pending_tasks_unlocked(owner) {
            guard.wake_up_unlocked(owner, guard.get_next_wake_time_unlocked(owner));
        }

        true
    }

    /// Will return false if the owner has not been merged before, or owner
    /// was subsumed by others, or subsumed wasn't subsumed by others, or owner
    /// didn't own the given subsumed queue id.
    pub fn unmerge(&self, owner: TaskQueueId, subsumed: TaskQueueId) -> bool {
        let mut guard = self.lock();
        let owner_entry = guard.at(owner);
        if owner_entry.owner_of.is_empty() {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                267,
                "Thread unmerging failed: owner_entry doesn't own anyone, owner={}, subsumed={}",
                owner,
                subsumed
            );
            return false;
        }
        if owner_entry.subsumed_by != kUnmerged {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                273,
                "Thread unmerging failed: owner_entry was subsumed by others, owner={}, subsumed={}, owner_entry->subsumed_by={}",
                owner,
                subsumed,
                owner_entry.subsumed_by
            );
            return false;
        }
        if guard.at(subsumed).subsumed_by == kUnmerged {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                280,
                "Thread unmerging failed: subsumed_entry wasn't subsumed by others, owner={}, subsumed={}",
                owner,
                subsumed
            );
            return false;
        }
        if !owner_entry.owner_of.contains(&subsumed) {
            fml_log_at!(
                K_LOG_WARNING,
                FILE,
                286,
                "Thread unmerging failed: owner_entry didn't own the given subsumed queue id, owner={}, subsumed={}",
                owner,
                subsumed
            );
            return false;
        }

        guard.at_mut(subsumed).subsumed_by = kUnmerged;
        guard.at_mut(owner).owner_of.remove(&subsumed);

        if guard.has_pending_tasks_unlocked(owner) {
            guard.wake_up_unlocked(owner, guard.get_next_wake_time_unlocked(owner));
        }

        if guard.has_pending_tasks_unlocked(subsumed) {
            guard.wake_up_unlocked(subsumed, guard.get_next_wake_time_unlocked(subsumed));
        }

        true
    }

    /// Returns `true` if `owner` owns the `subsumed` task queue.
    pub fn owns(&self, owner: TaskQueueId, subsumed: TaskQueueId) -> bool {
        let guard = self.lock();
        if owner == kUnmerged || subsumed == kUnmerged {
            return false;
        }
        guard.at(owner).owner_of.contains(&subsumed)
    }

    /// Returns the subsumed task queue if any or `TaskQueueId::kUnmerged`
    /// otherwise.
    pub fn get_subsumed_task_queue_id(&self, owner: TaskQueueId) -> BTreeSet<TaskQueueId> {
        self.lock().at(owner).owner_of.clone()
    }

    pub fn pause_secondary_source(&self, queue_id: TaskQueueId) {
        self.lock().at_mut(queue_id).task_source.pause_secondary();
    }

    pub fn resume_secondary_source(&self, queue_id: TaskQueueId) {
        let mut guard = self.lock();
        guard.at_mut(queue_id).task_source.resume_secondary();
        // Schedule a wake as needed.
        if guard.has_pending_tasks_unlocked(queue_id) {
            guard.wake_up_unlocked(queue_id, guard.get_next_wake_time_unlocked(queue_id));
        }
    }
}
