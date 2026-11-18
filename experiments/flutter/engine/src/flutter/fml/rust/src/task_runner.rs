// Port of flutter/fml/task_runner.h and flutter/fml/task_runner.cc.
//
// `BasicTaskRunner` is a trait. `TaskRunner`'s methods are virtual upstream
// so that the embedder can supply its own runners; that subclassing waits
// for the shell's port, and `TaskRunner` is a struct over a message loop.

use crate::closure::closure;
use crate::fml_dcheck_at;
use crate::memory::ref_counted::RefCountedThreadSafe;
use crate::memory::ref_ptr::RefPtr;
use crate::memory::task_runner_checker::TaskRunnerChecker;
use crate::message_loop::MessageLoop;
use crate::message_loop_impl::MessageLoopImpl;
use crate::task_queue_id::TaskQueueId;
use crate::time::time_delta::TimeDelta;
use crate::time::time_point::TimePoint;

const FILE: &str = "flutter/fml/task_runner.cc";

/// An interface over the ability to schedule tasks on a TaskRunner.
pub trait BasicTaskRunner {
    /// Schedules `task` to be executed on the TaskRunner's associated event
    /// loop.
    fn post_task(&self, task: closure);
}

/// The object for scheduling tasks on a `fml::MessageLoop`.
///
/// Typically there is one TaskRunner associated with each thread. When one
/// wants to execute an operation on that thread they post a task to the
/// TaskRunner.
pub struct TaskRunner {
    loop_: RefPtr<dyn MessageLoopImpl>,
}

impl RefCountedThreadSafe for TaskRunner {}

impl TaskRunner {
    pub(crate) fn new(loop_: RefPtr<dyn MessageLoopImpl>) -> TaskRunner {
        TaskRunner { loop_ }
    }

    pub fn post_task(&self, task: closure) {
        self.loop_.post_task(task, TimePoint::now());
    }

    pub fn post_task_for_time(&self, task: closure, target_time: TimePoint) {
        self.loop_.post_task(task, target_time);
    }

    /// Schedules a task to be run on the MessageLoop after the time `delay`
    /// has passed.
    /// There is latency between when the task is schedule and actually
    /// executed so that the actual execution time is: now + delay +
    /// message_loop_latency, where message_loop_latency is undefined and
    /// could be tens of milliseconds.
    pub fn post_delayed_task(&self, task: closure, delay: TimeDelta) {
        self.loop_.post_task(task, TimePoint::now() + delay);
    }

    /// Returns `true` when the current executing thread's TaskRunner matches
    /// this instance.
    pub fn runs_tasks_on_current_thread(&self) -> bool {
        if !MessageLoop::is_initialized_for_current_thread() {
            return false;
        }

        let current_queue_id = MessageLoop::get_current_task_queue_id();
        let loop_queue_id = self.loop_.get_task_queue_id();

        TaskRunnerChecker::runs_on_the_same_thread(current_queue_id, loop_queue_id)
    }

    /// Returns the unique identifier associated with the TaskRunner.
    pub fn get_task_queue_id(&self) -> TaskQueueId {
        fml_dcheck_at!(FILE, 40, "loop_", self.loop_.as_bool());
        self.loop_.get_task_queue_id()
    }

    /// Executes the `task` directly if the TaskRunner `runner` is the
    /// TaskRunner associated with the current executing thread.
    pub fn run_now_or_post_task(runner: &RefPtr<TaskRunner>, task: closure) {
        fml_dcheck_at!(FILE, 59, "runner", runner.as_bool());
        if runner.runs_tasks_on_current_thread() {
            task.call();
        } else {
            runner.post_task(task);
        }
    }

    /// Like `run_now_or_post_task`, except that if the task can be
    /// immediately executed, an empty task will still be posted to the
    /// runner afterwards.
    ///
    /// This is used to ensure that messages posted to Dart from the platform
    /// thread always flush the Dart event loop.
    pub fn run_now_and_flush_messages(runner: &RefPtr<TaskRunner>, task: closure) {
        fml_dcheck_at!(FILE, 71, "runner", runner.as_bool());
        if runner.runs_tasks_on_current_thread() {
            task.call();
            // Post an empty task to make the UI message loop run its task
            // observers. The observers will execute any Dart microtasks queued
            // by the platform message handler.
            runner.post_task(closure::new(|| {}));
        } else {
            runner.post_task(task);
        }
    }
}

impl BasicTaskRunner for TaskRunner {
    fn post_task(&self, task: closure) {
        TaskRunner::post_task(self, task);
    }
}
