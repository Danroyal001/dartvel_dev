// Port of flutter/fml/concurrent_message_loop.h,
// flutter/fml/concurrent_message_loop.cc and
// flutter/fml/concurrent_message_loop_factory.cc.
//
// The workers hold the loop's shared state (`Shared`), not the loop, so that
// dropping the last `Arc<ConcurrentMessageLoop>` still terminates and joins
// them as upstream's destructor does. `ExecuteTask` is virtual upstream (for
// tests); it is a plain method here. Upstream returns early from
// PostTask and PostTaskToAllWorkers for an empty std::function; a `closure`
// cannot be empty.

use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Condvar, Mutex, MutexGuard, Weak};
use std::thread::ThreadId;

use crate::closure::closure;
use crate::fml_dlog_at;
use crate::task_runner::BasicTaskRunner;

const FILE: &str = "flutter/fml/concurrent_message_loop.cc";

struct State {
    tasks_: VecDeque<closure>,
    worker_thread_ids_: Vec<ThreadId>,
    thread_tasks_: HashMap<ThreadId, Vec<closure>>,
    shutdown_: bool,
    // Not upstream's: workers blocked in the wait, and notifications sent to
    // them that no worker has woken for yet (see post_task).
    waiting_workers_: usize,
    pending_wakes_: usize,
}

struct Shared {
    tasks_mutex_: Mutex<State>,
    tasks_condition_: Condvar,
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.tasks_mutex_.lock().unwrap_or_else(|e| e.into_inner())
    }
}

pub struct ConcurrentMessageLoop {
    worker_count_: usize,
    workers_: Mutex<Vec<std::thread::JoinHandle<()>>>,
    shared_: Arc<Shared>,
    weak_self_: Weak<ConcurrentMessageLoop>,
}

/// `std::thread::hardware_concurrency()` as libc++ computes it:
/// `sysconf(_SC_NPROCESSORS_ONLN)`, which glibc reads from
/// /sys/devices/system/cpu/online. Elsewhere, the standard library's count.
pub fn hardware_concurrency() -> usize {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    if let Ok(online) = std::fs::read_to_string("/sys/devices/system/cpu/online") {
        let mut count = 0;
        for range in online.trim().split(',') {
            let mut ends = range.split('-');
            let first = ends.next().and_then(|s| s.parse::<usize>().ok());
            let last = ends.next().and_then(|s| s.parse::<usize>().ok());
            match (first, last) {
                (Some(a), Some(b)) if b >= a => count += b - a + 1,
                (Some(_), None) => count += 1,
                _ => {}
            }
        }
        if count > 0 {
            return count;
        }
    }
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(0)
}

impl ConcurrentMessageLoop {
    pub fn create(worker_count: usize) -> Arc<ConcurrentMessageLoop> {
        let worker_count_ = worker_count.max(1);
        let shared_ = Arc::new(Shared {
            tasks_mutex_: Mutex::new(State {
                tasks_: VecDeque::new(),
                worker_thread_ids_: Vec::new(),
                thread_tasks_: HashMap::new(),
                shutdown_: false,
                waiting_workers_: 0,
                pending_wakes_: 0,
            }),
            tasks_condition_: Condvar::new(),
        });
        let mut workers_ = Vec::with_capacity(worker_count_);
        for i in 0..worker_count_ {
            let shared = shared_.clone();
            // Upstream names the thread from inside it
            // (SetCurrentThreadName); std's builder does the same at the
            // thread's start, with one prctl where writing
            // /proc/thread-self/comm takes an open, a write and a close.
            // Both cut the name at 15 bytes.
            let worker = std::thread::Builder::new()
                .name(format!("io.worker.{}", i + 1))
                .spawn(move || worker_main(&shared))
                .expect("failed to spawn thread");
            workers_.push(worker);
        }
        shared_.lock().worker_thread_ids_ = workers_.iter().map(|w| w.thread().id()).collect();
        Arc::new_cyclic(|weak| ConcurrentMessageLoop {
            worker_count_,
            workers_: Mutex::new(workers_),
            shared_,
            weak_self_: weak.clone(),
        })
    }

    /// `Create()` with its default: one worker per hardware thread.
    pub fn create_default() -> Arc<ConcurrentMessageLoop> {
        Self::create(hardware_concurrency())
    }

    pub fn get_worker_count(&self) -> usize {
        self.worker_count_
    }

    pub fn get_task_runner(&self) -> Arc<ConcurrentTaskRunner> {
        Arc::new(ConcurrentTaskRunner::new(self.weak_self_.clone()))
    }

    pub fn terminate(&self) {
        let mut state = self.shared_.lock();
        state.shutdown_ = true;
        self.shared_.tasks_condition_.notify_all();
    }

    pub fn post_task_to_all_workers(&self, task: closure) {
        let mut state = self.shared_.lock();
        let ids = state.worker_thread_ids_.clone();
        for worker_thread_id in ids {
            state.thread_tasks_.entry(worker_thread_id).or_default().push(task.clone());
        }
        self.shared_.tasks_condition_.notify_all();
    }

    pub fn runs_tasks_on_current_thread(&self) -> bool {
        let state = self.shared_.lock();
        let current = std::thread::current().id();
        state.worker_thread_ids_.iter().any(|&id| id == current)
    }

    fn post_task(&self, task: closure) {
        let mut state = self.shared_.lock();

        // Don't just drop tasks on the floor in case of shutdown.
        if state.shutdown_ {
            fml_dlog_at!(
                kLogWarning,
                FILE,
                54,
                "Tried to post a task to shutdown concurrent message loop. The task will be executed on the callers thread."
            );
            drop(state);
            execute_task(&task);
            return;
        }

        state.tasks_.push_back(task);
        // pthread_cond_signal makes no system call when no thread waits for
        // the signal; std's Condvar always makes one. So the port notifies
        // only when a worker is waiting that no earlier notification will
        // already wake: a woken worker takes tasks until the queue is empty
        // before it waits again, and a worker about to wait checks the queue
        // under this lock first, so no task is left without a worker.
        let wake = state.waiting_workers_ > state.pending_wakes_;
        if wake {
            state.pending_wakes_ += 1;
        }

        // Unlock the mutex before notifying the condition variable because that
        // mutex has to be acquired on the other thread anyway. Waiting in this
        // scope till it is acquired there is a pessimization.
        drop(state);

        if wake {
            self.shared_.tasks_condition_.notify_one();
        }
    }
}

impl Drop for ConcurrentMessageLoop {
    fn drop(&mut self) {
        self.terminate();
        let workers = std::mem::take(&mut *self.workers_.lock().unwrap_or_else(|e| e.into_inner()));
        for worker in workers {
            let _ = worker.join();
        }
    }
}

fn worker_main(shared: &Shared) {
    // std::this_thread::get_id(), read once: std::thread::current() clones
    // the thread's handle on every call.
    let me = std::thread::current().id();
    loop {
        let mut state = shared.lock();
        while state.tasks_.is_empty() && !state.shutdown_ && !has_thread_tasks_locked(&state, me) {
            state.waiting_workers_ += 1;
            state = shared.tasks_condition_.wait(state).unwrap_or_else(|e| e.into_inner());
            state.waiting_workers_ -= 1;
            state.pending_wakes_ = state.pending_wakes_.saturating_sub(1);
        }

        // Shutdown cannot be read with the task mutex unlocked.
        let shutdown_now = state.shutdown_;
        let task = state.tasks_.pop_front();
        let mut thread_tasks = Vec::new();

        if has_thread_tasks_locked(&state, me) {
            thread_tasks = get_thread_tasks_locked(&mut state, me);
        }

        // Don't hold onto the mutex while tasks are being executed as they
        // could themselves try to post more tasks to the message loop.
        drop(state);

        crate::trace_event0!("flutter", "ConcurrentWorkerWake");

        if let Some(task) = task {
            execute_task(&task);
        }

        for thread_task in &thread_tasks {
            execute_task(thread_task);
        }

        if shutdown_now {
            break;
        }
    }
}

fn execute_task(task: &closure) {
    task();
}

fn has_thread_tasks_locked(state: &State, me: ThreadId) -> bool {
    // The map is empty except after PostTaskToAllWorkers.
    !state.thread_tasks_.is_empty() && state.thread_tasks_.contains_key(&me)
}

fn get_thread_tasks_locked(state: &mut State, me: ThreadId) -> Vec<closure> {
    state.thread_tasks_.remove(&me).unwrap_or_default()
}

pub struct ConcurrentTaskRunner {
    weak_loop_: Weak<ConcurrentMessageLoop>,
}

impl ConcurrentTaskRunner {
    pub fn new(weak_loop: Weak<ConcurrentMessageLoop>) -> Self {
        ConcurrentTaskRunner { weak_loop_: weak_loop }
    }
}

impl BasicTaskRunner for ConcurrentTaskRunner {
    fn post_task(&self, task: closure) {
        if let Some(loop_) = self.weak_loop_.upgrade() {
            loop_.post_task(task);
            return;
        }

        fml_dlog_at!(
            kLogWarning,
            "flutter/fml/concurrent_message_loop.cc",
            166,
            "Tried to post to a concurrent message loop that has already died. Executing the task on the callers thread."
        );
        task();
    }
}
