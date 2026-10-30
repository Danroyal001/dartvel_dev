// Port of flutter/fml/thread.h and flutter/fml/thread.cc.
//
// `ThreadHandle` starts the thread with the standard library, which creates
// a pthread with the requested stack size as upstream does with
// pthread_attr_setstacksize (and so cannot fail to apply it). Setting the
// current thread's name on Linux and Android writes /proc/thread-self/comm,
// which is what pthread_setname_np does for another thread and has the same
// effect (the kernel keeps 15 bytes) as its prctl path for the calling one;
// on Apple platforms it calls pthread_setname_np. Windows' and Fuchsia's
// branches are not ported; on those the name is not set (FML_DLOG).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use crate::fml_check_at;
use crate::memory::ref_ptr::RefPtr;
use crate::message_loop::MessageLoop;
use crate::synchronization::waitable_event::AutoResetWaitableEvent;
use crate::task_runner::TaskRunner;

const FILE: &str = "flutter/fml/thread.cc";

type ThreadFunction = Box<dyn FnOnce() + Send>;

pub struct ThreadHandle {
    thread_: Option<std::thread::JoinHandle<()>>,
}

impl ThreadHandle {
    pub fn new(function: ThreadFunction) -> Self {
        let result = std::thread::Builder::new()
            .stack_size(Thread::get_default_stack_size())
            .spawn(function);
        fml_check_at!(FILE, 70, "result == 0", result.is_ok());
        ThreadHandle { thread_: result.ok() }
    }

    pub fn join(&mut self) {
        if let Some(thread) = self.thread_.take() {
            // A panic on the thread has no pthread_join counterpart; it has
            // already been reported.
            let _ = thread.join();
        }
    }
}

/// Valid values for priority of Thread.
#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub enum ThreadPriority {
    /// Suitable for threads that shouldn't disrupt high priority work.
    kBackground,
    /// Default priority level.
    kNormal,
    /// Suitable for threads which generate data for the display.
    kDisplay,
    /// Suitable for thread which raster data.
    kRaster,
}

/// The ThreadConfig is the thread info include thread name, thread priority.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ThreadConfig {
    pub name: String,
    pub priority: ThreadPriority,
}

impl ThreadConfig {
    pub fn new(name: &str, priority: ThreadPriority) -> Self {
        ThreadConfig { name: name.to_string(), priority }
    }

    pub fn named(name: &str) -> Self {
        Self::new(name, ThreadPriority::kNormal)
    }
}

impl Default for ThreadConfig {
    fn default() -> Self {
        Self::new("", ThreadPriority::kNormal)
    }
}

pub type ThreadConfigSetter = Arc<dyn Fn(&ThreadConfig) + Send + Sync>;

pub struct Thread {
    thread_: Mutex<ThreadHandle>,
    task_runner_: RefPtr<TaskRunner>,
    joined_: AtomicBool,
}

fn set_thread_name(name: &str) {
    if name.is_empty() {
        return;
    }
    #[cfg(any(target_os = "linux", target_os = "android"))]
    {
        // Linux thread names are limited to 16 characters including the
        // terminating null.
        const K_LINUX_MAX_THREAD_NAME_LEN: usize = 15;
        let bytes = name.as_bytes();
        let bytes = &bytes[..bytes.len().min(K_LINUX_MAX_THREAD_NAME_LEN)];
        // Like pthread_setname_np, a failure is not reported to the caller.
        let _ = std::fs::write("/proc/thread-self/comm", bytes);
    }
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        unsafe extern "C" {
            fn pthread_setname_np(name: *const std::os::raw::c_char) -> i32;
        }
        if let Ok(name) = std::ffi::CString::new(name) {
            // SAFETY: `name` is a NUL-terminated string that outlives the call,
            // which copies it.
            unsafe {
                pthread_setname_np(name.as_ptr());
            }
        }
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "android",
        target_os = "macos",
        target_os = "ios"
    )))]
    {
        crate::fml_dlog_at!(
            kLogInfo,
            FILE,
            130,
            "Could not set the thread name to '{}' on this platform.",
            name
        );
    }
}

impl Default for Thread {
    fn default() -> Self {
        Self::new("")
    }
}

impl Thread {
    pub fn new(name: &str) -> Self {
        Self::with_setter(
            Arc::new(Thread::set_current_thread_name),
            ThreadConfig::named(name),
        )
    }

    pub fn with_setter(setter: ThreadConfigSetter, config: ThreadConfig) -> Self {
        let latch = Arc::new(AutoResetWaitableEvent::new());
        let runner: Arc<Mutex<RefPtr<TaskRunner>>> = Arc::new(Mutex::new(RefPtr::null()));
        let thread_ = {
            let latch = latch.clone();
            let runner = runner.clone();
            ThreadHandle::new(Box::new(move || {
                setter(&config);
                MessageLoop::ensure_initialized_for_current_thread();
                let loop_ = MessageLoop::get_current();
                *runner.lock().unwrap_or_else(|e| e.into_inner()) = loop_.get_task_runner();
                latch.signal();
                loop_.run();
            }))
        };
        latch.wait();
        let task_runner_ = runner.lock().unwrap_or_else(|e| e.into_inner()).clone();
        Thread { thread_: Mutex::new(thread_), task_runner_, joined_: AtomicBool::new(false) }
    }

    pub fn get_task_runner(&self) -> RefPtr<TaskRunner> {
        self.task_runner_.clone()
    }

    pub fn join(&self) {
        if self.joined_.swap(true, Ordering::SeqCst) {
            return;
        }
        self.task_runner_.post_task(Arc::new(|| MessageLoop::get_current().terminate()));
        self.thread_.lock().unwrap_or_else(|e| e.into_inner()).join();
    }

    pub fn set_current_thread_name(config: &ThreadConfig) {
        set_thread_name(&config.name);
    }

    pub fn get_default_stack_size() -> usize {
        1024 * 1024 * 2
    }
}

impl Drop for Thread {
    fn drop(&mut self) {
        self.join();
    }
}
