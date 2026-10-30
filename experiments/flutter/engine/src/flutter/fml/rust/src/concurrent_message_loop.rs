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
use crate::thread::{Thread, ThreadConfig};

const FILE: &str = "flutter/fml/concurrent_message_loop.cc";

struct State {
    tasks_: VecDeque<closure>,
    worker_thread_ids_: Vec<ThreadId>,
    thread_tasks_: HashMap<ThreadId, Vec<closure>>,
    shutdown_: bool,
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
            }),
            tasks_condition_: Condvar::new(),
        });
        let mut workers_ = Vec::with_capacity(worker_count_);
        for i in 0..worker_count_ {
            let shared = shared_.clone();
            workers_.push(std::thread::spawn(move || {
                Thread::set_current_thread_name(&ThreadConfig::named(&format!(
                    "io.worker.{}",
                    i + 1
                )));
                worker_main(&shared);
            }));
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

        crate::trace_event0!("flutter", "ConcurrentWorkerWake");
            execute_task(&task);
            return;
        }

        state.tasks_.push_back(task);

        // Unlock the mutex before notifying the condition variable because that
        // mutex has to be acquired on the other thread anyway. Waiting in this
        // scope till it is acquired there is a pessimization.
        drop(state);

        self.shared_.tasks_condition_.notify_one();
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
    loop {
        let lock = shared.lock();
        let mut state = shared
            .tasks_condition_
            .wait_while(lock, |s| s.tasks_.is_empty() && !s.shutdown_ && !has_thread_tasks_locked(s))
            .unwrap_or_else(|e| e.into_inner());

        // Shutdown cannot be read with the task mutex unlocked.
        let shutdown_now = state.shutdown_;
        let task = state.tasks_.pop_front();
        let mut thread_tasks = Vec::new();

        if has_thread_tasks_locked(&state) {
            thread_tasks = get_thread_tasks_locked(&mut state);
        }

        // Don't hold onto the mutex while tasks are being executed as they
        // could themselves try to post more tasks to the message loop.
        drop(state);

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

fn has_thread_tasks_locked(state: &State) -> bool {
    state.thread_tasks_.contains_key(&std::thread::current().id())
}

fn get_thread_tasks_locked(state: &mut State) -> Vec<closure> {
    state.thread_tasks_.remove(&std::thread::current().id()).unwrap_or_default()
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
