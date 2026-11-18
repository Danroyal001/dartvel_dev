// Port of flutter/fml/message_loop.h and flutter/fml/message_loop.cc.
//
// Upstream's thread-local `std::unique_ptr<MessageLoop>` hands out
// `MessageLoop&`; here the thread-local holds the loop and `get_current`
// returns a handle to it: a `MessageLoop` is two reference-counted pointers
// (the implementation and its task runner), so a clone is the same loop and
// can be kept and used from other threads as upstream's tests keep a
// `MessageLoop*`. `ptr_eq` is upstream's comparison of those pointers.

use std::cell::RefCell;

use crate::closure::closure;
use crate::fml_check_at;
use crate::memory::ref_ptr::{RefPtr, make_ref_counted};
use crate::message_loop_impl::MessageLoopImpl;
use crate::task_queue_id::TaskQueueId;
use crate::task_runner::TaskRunner;

const FILE: &str = "flutter/fml/message_loop.cc";

thread_local! {
    static TLS_MESSAGE_LOOP: RefCell<Option<MessageLoop>> = const { RefCell::new(None) };
}

#[derive(Clone)]
pub struct MessageLoop {
    loop_: RefPtr<dyn MessageLoopImpl>,
    task_runner_: RefPtr<TaskRunner>,
}

impl MessageLoop {
    pub fn get_current() -> MessageLoop {
        let current = TLS_MESSAGE_LOOP.with(|l| l.borrow().clone());
        fml_check_at!(
            FILE,
            21,
            "loop != nullptr",
            current.is_some(),
            "MessageLoop::EnsureInitializedForCurrentThread was not called on this thread prior to message loop use."
        );
        current.expect("checked")
    }

    pub fn run(&self) {
        self.loop_.do_run();
    }

    pub fn terminate(&self) {
        self.loop_.do_terminate();
    }

    pub fn add_task_observer(&self, key: isize, callback: closure) {
        self.loop_.add_task_observer(key, callback);
    }

    pub fn remove_task_observer(&self, key: isize) {
        self.loop_.remove_task_observer(key);
    }

    pub fn get_task_runner(&self) -> RefPtr<TaskRunner> {
        self.task_runner_.clone()
    }

    // Exposed for the embedder shell which allows clients to poll for events
    // instead of dedicating a thread to the message loop.
    pub fn run_expired_tasks_now(&self) {
        self.loop_.run_expired_tasks_now();
    }

    pub fn ensure_initialized_for_current_thread() {
        TLS_MESSAGE_LOOP.with(|l| {
            if l.borrow().is_some() {
                // Already initialized.
                return;
            }
            let created = MessageLoop::new();
            *l.borrow_mut() = Some(created);
        });
    }

    /// Returns true if `ensure_initialized_for_current_thread` has been called
    /// on this thread already.
    pub fn is_initialized_for_current_thread() -> bool {
        TLS_MESSAGE_LOOP.with(|l| l.borrow().is_some())
    }

    /// Gets the unique identifier for the TaskQueue associated with the
    /// current thread.
    pub fn get_current_task_queue_id() -> TaskQueueId {
        let current = TLS_MESSAGE_LOOP.with(|l| l.borrow().as_ref().map(|l| l.loop_.clone()));
        fml_check_at!(
            FILE,
            78,
            "loop != nullptr",
            current.is_some(),
            "MessageLoop::EnsureInitializedForCurrentThread was not called on this thread prior to message loop use."
        );
        current.expect("checked").get_task_queue_id()
    }

    /// Whether two handles are the same thread's loop.
    pub fn ptr_eq(&self, other: &MessageLoop) -> bool {
        self.loop_ == other.loop_
    }

    fn new() -> MessageLoop {
        let loop_ = <dyn MessageLoopImpl>::create();
        let task_runner_ = make_ref_counted(TaskRunner::new(loop_.clone()));
        fml_check_at!(FILE, 42, "loop_", loop_.as_bool());
        fml_check_at!(FILE, 43, "task_runner_", task_runner_.as_bool());
        MessageLoop { loop_, task_runner_ }
    }

    pub(crate) fn get_loop_impl(&self) -> RefPtr<dyn MessageLoopImpl> {
        self.loop_.clone()
    }
}
