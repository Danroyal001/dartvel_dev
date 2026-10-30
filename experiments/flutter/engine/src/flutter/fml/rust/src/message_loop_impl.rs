// Port of flutter/fml/message_loop_impl.h and flutter/fml/message_loop_impl.cc.
//
// The abstract class is a trait: a platform loop implements `run`,
// `terminate` and `Wakeable::wake_up`, and holds a `MessageLoopImplBase`,
// the state upstream's base class keeps (the task queues, the queue id and
// the terminated flag); everything else is a provided method. The base
// registers the loop as its queue's wakeable through a `Weak` (see
// message_loop_task_queues.rs), so the loop is built with `Arc::new_cyclic`.
//
// Upstream's `PostTask` DCHECKs a non-null task and `AddTaskObserver` logs
// "Tried to add a null TaskObserver."; a `closure` cannot be null, so neither
// path exists here.

use std::sync::Weak;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::closure::closure;
use crate::fml_dcheck_at;
use crate::memory::ref_ptr::RefPtr;
use crate::message_loop::MessageLoop;
use crate::message_loop_task_queues::{FlushType, MessageLoopTaskQueues};
use crate::task_queue_id::TaskQueueId;
use crate::task_source_grade::TaskSourceGrade;
use crate::time::time_point::TimePoint;
use crate::wakeable::Wakeable;

const FILE: &str = "flutter/fml/message_loop_impl.cc";

/// The state of upstream's `MessageLoopImpl` base class.
pub struct MessageLoopImplBase {
    task_queue_: &'static MessageLoopTaskQueues,
    queue_id_: TaskQueueId,
    terminated_: AtomicBool,
}

impl MessageLoopImplBase {
    /// Creates the loop's task queue and registers `wakeable`, the loop being
    /// built, to be woken for it.
    pub fn new(wakeable: Weak<dyn Wakeable>) -> Self {
        let task_queue_ = MessageLoopTaskQueues::get_instance();
        let queue_id_ = task_queue_.create_task_queue();
        task_queue_.set_wakeable(queue_id_, wakeable);
        MessageLoopImplBase { task_queue_, queue_id_, terminated_: AtomicBool::new(false) }
    }
}

impl Drop for MessageLoopImplBase {
    fn drop(&mut self) {
        self.task_queue_.dispose(self.queue_id_);
    }
}

pub trait MessageLoopImpl: Wakeable {
    fn run(&self);

    fn terminate(&self);

    /// The base class's state.
    fn base(&self) -> &MessageLoopImplBase;

    fn post_task(&self, task: closure, target_time: TimePoint) {
        let base = self.base();
        if base.terminated_.load(Ordering::SeqCst) {
            // If the message loop has already been terminated, PostTask should
            // destruct |task| synchronously within this function.
            return;
        }
        base.task_queue_.register_task(
            base.queue_id_,
            task,
            target_time,
            TaskSourceGrade::kUnspecified,
        );
    }

    fn add_task_observer(&self, key: isize, callback: closure) {
        fml_dcheck_at!(
            FILE,
            70,
            "MessageLoop::GetCurrent().GetLoopImpl().get() == this",
            std::ptr::eq(MessageLoop::get_current().get_loop_impl().base(), self.base()),
            "Message loop task observer must be added on the same thread as the loop."
        );
        let base = self.base();
        base.task_queue_.add_task_observer(base.queue_id_, key, callback);
    }

    fn remove_task_observer(&self, key: isize) {
        fml_dcheck_at!(
            FILE,
            81,
            "MessageLoop::GetCurrent().GetLoopImpl().get() == this",
            std::ptr::eq(MessageLoop::get_current().get_loop_impl().base(), self.base()),
            "Message loop task observer must be removed from the same thread as the loop."
        );
        let base = self.base();
        base.task_queue_.remove_task_observer(base.queue_id_, key);
    }

    fn do_run(&self) {
        let base = self.base();
        if base.terminated_.load(Ordering::SeqCst) {
            // Message loops may be run only once.
            return;
        }

        // Allow the implementation to do its thing.
        self.run();

        // The loop may have been implicitly terminated. This can happen if the
        // implementation supports termination via platform specific APIs or
        // just error conditions. Set the terminated flag manually.
        base.terminated_.store(true, Ordering::SeqCst);

        // The message loop is shutting down. Check if there are expired tasks.
        // This is the last chance for expired tasks to be serviced. Make sure
        // the terminated flag is already set so we don't accrue additional
        // tasks now.
        self.run_expired_tasks_now();

        // When the message loop is in the process of shutting down, pending
        // tasks should be destructed on the message loop's thread. We have
        // just returned from the implementations |Run| method which we know is
        // on the correct thread. Drop all pending tasks on the floor.
        base.task_queue_.dispose_tasks(base.queue_id_);
    }

    fn do_terminate(&self) {
        self.base().terminated_.store(true, Ordering::SeqCst);
        self.terminate();
    }

    fn get_task_queue_id(&self) -> TaskQueueId {
        self.base().queue_id_
    }

    // Exposed for the embedder shell which allows clients to poll for events
    // instead of dedicating a thread to the message loop.
    fn run_expired_tasks_now(&self) {
        flush_tasks(self.base(), FlushType::kAll);
    }

    fn run_single_expired_task_now(&self) {
        flush_tasks(self.base(), FlushType::kSingle);
    }
}

fn flush_tasks(base: &MessageLoopImplBase, type_: FlushType) {
    let now = TimePoint::now();
    loop {
        let Some(invocation) = base.task_queue_.get_next_task_to_run(base.queue_id_, now) else {
            break;
        };
        invocation();
        let observers = base.task_queue_.get_observers_to_notify(base.queue_id_);
        for observer in &observers {
            observer();
        }
        if type_ == FlushType::kSingle {
            break;
        }
    }
}

impl dyn MessageLoopImpl {
    /// The platform's loop: `MessageLoopLinux` on Linux; `None` (upstream's
    /// nullptr) where the platform's loop is not ported.
    pub fn create() -> RefPtr<dyn MessageLoopImpl> {
        #[cfg(target_os = "linux")]
        {
            RefPtr::from(
                crate::platform::linux::message_loop_linux::MessageLoopLinux::create()
                    as std::sync::Arc<dyn MessageLoopImpl>,
            )
        }
        #[cfg(not(target_os = "linux"))]
        {
            RefPtr::null()
        }
    }
}
