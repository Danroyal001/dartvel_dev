// Port of flutter/fml/thread_unittests.cc.
//
// The thread's name is read from /proc/thread-self/comm, which is what
// pthread_getname_np reads. The stack size and scheduling tests call the
// same pthread functions upstream's do (test-only `unsafe`, each block
// documented).

use std::os::raw::c_int;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use crate::thread::{Thread, ThreadConfig, ThreadPriority};

fn current_thread_name() -> String {
    let name = std::fs::read_to_string("/proc/thread-self/comm").unwrap();
    name.trim_end_matches('\n').to_string()
}

#[test]
fn can_start_and_end() {
    let thread = Thread::default();
    assert!(thread.get_task_runner().as_bool());
}

#[test]
fn can_start_and_end_with_explicit_join() {
    let thread = Thread::default();
    assert!(thread.get_task_runner().as_bool());
    thread.join();
}

#[test]
fn has_a_running_message_loop() {
    let thread = Thread::default();
    let done = Arc::new(AtomicBool::new(false));
    let d = done.clone();
    thread.get_task_runner().post_task(Arc::new(move || d.store(true, Ordering::SeqCst)));
    thread.join();
    assert!(done.load(Ordering::SeqCst));
}

#[repr(C, align(8))]
struct PthreadAttr([u8; 64]);

unsafe extern "C" {
    fn pthread_self() -> usize;
    fn pthread_getattr_np(thread: usize, attr: *mut PthreadAttr) -> c_int;
    fn pthread_attr_getstacksize(attr: *const PthreadAttr, stacksize: *mut usize) -> c_int;
    fn pthread_attr_destroy(attr: *mut PthreadAttr) -> c_int;
}

#[test]
fn has_expected_stack_size() {
    let stack_size = Arc::new(AtomicUsize::new(0));
    let thread = Thread::default();

    let s = stack_size.clone();
    thread.get_task_runner().post_task(Arc::new(move || {
        let mut attr = PthreadAttr([0; 64]);
        let mut size = 0usize;
        // SAFETY: `attr` is larger than and as aligned as glibc's
        // pthread_attr_t on the 64-bit targets (56 bytes on x86-64, 64 on
        // AArch64); pthread_getattr_np initializes it, the getter reads it and
        // writes `size`, and it is destroyed once, as upstream's test does.
        unsafe {
            pthread_getattr_np(pthread_self(), &mut attr);
            pthread_attr_getstacksize(&attr, &mut size);
            pthread_attr_destroy(&mut attr);
        }
        s.store(size, Ordering::SeqCst);
    }));
    thread.join();

    // Actual stack size will be aligned to page size, this assumes no
    // supported platform has a page size larger than 16k. On Linux reducing
    // the default stack size (8MB) does not seem to have any effect.
    const K_PAGE_SIZE: usize = 16384;
    assert!(
        stack_size.load(Ordering::SeqCst) / K_PAGE_SIZE
            >= Thread::get_default_stack_size() / K_PAGE_SIZE
    );
}

#[test]
fn thread_name_created_with_config() {
    let name = "Thread1";
    let thread = Thread::new(name);

    let done = Arc::new(AtomicBool::new(false));
    let seen = Arc::new(Mutex::new(String::new()));
    let (d, s) = (done.clone(), seen.clone());
    thread.get_task_runner().post_task(Arc::new(move || {
        d.store(true, Ordering::SeqCst);
        *s.lock().unwrap() = current_thread_name();
    }));
    thread.join();
    assert!(done.load(Ordering::SeqCst));
    assert_eq!(*seen.lock().unwrap(), name);
}

#[repr(C)]
#[derive(Default)]
struct SchedParam {
    sched_priority: c_int,
}

const SCHED_OTHER: c_int = 0;

unsafe extern "C" {
    fn sched_get_priority_min(policy: c_int) -> c_int;
    fn sched_get_priority_max(policy: c_int) -> c_int;
    fn pthread_setschedparam(thread: usize, policy: c_int, param: *const SchedParam) -> c_int;
    fn pthread_getschedparam(thread: usize, policy: *mut c_int, param: *mut SchedParam) -> c_int;
}

fn clamp_priority(priority: c_int, policy: c_int) -> c_int {
    // SAFETY: both take a policy by value and touch no memory of ours.
    let (min, max) = unsafe { (sched_get_priority_min(policy), sched_get_priority_max(policy)) };
    priority.clamp(min, max)
}

fn mock_thread_config_setter(config: &ThreadConfig) {
    // set thread name
    Thread::set_current_thread_name(config);

    let policy = SCHED_OTHER;
    let param = SchedParam {
        sched_priority: match config.priority {
            ThreadPriority::kDisplay => clamp_priority(10, policy),
            _ => clamp_priority(1, policy),
        },
    };
    // SAFETY: `param` is a live `struct sched_param`, only read by the call.
    unsafe {
        pthread_setschedparam(pthread_self(), policy, &param);
    }
}

fn current_sched() -> (c_int, c_int) {
    let mut policy = -1;
    let mut param = SchedParam::default();
    // SAFETY: both out-parameters are live and writable.
    unsafe {
        pthread_getschedparam(pthread_self(), &mut policy, &mut param);
    }
    (policy, param.sched_priority)
}

#[test]
fn thread_priority_created_with_config() {
    let thread1_name = "Thread1";
    let thread2_name = "Thread2";

    let thread = Thread::with_setter(
        Arc::new(mock_thread_config_setter),
        ThreadConfig::new(thread1_name, ThreadPriority::kNormal),
    );
    let done = Arc::new(AtomicBool::new(false));

    let seen1 = Arc::new(Mutex::new((String::new(), 0, 0)));
    let (d, s) = (done.clone(), seen1.clone());
    thread.get_task_runner().post_task(Arc::new(move || {
        d.store(true, Ordering::SeqCst);
        let (policy, priority) = current_sched();
        *s.lock().unwrap() = (current_thread_name(), policy, priority);
    }));

    let thread2 = Thread::with_setter(
        Arc::new(mock_thread_config_setter),
        ThreadConfig::new(thread2_name, ThreadPriority::kDisplay),
    );
    let seen2 = Arc::new(Mutex::new((String::new(), 0, 0)));
    let (d, s) = (done.clone(), seen2.clone());
    thread2.get_task_runner().post_task(Arc::new(move || {
        d.store(true, Ordering::SeqCst);
        let (policy, priority) = current_sched();
        *s.lock().unwrap() = (current_thread_name(), policy, priority);
    }));
    thread.join();
    thread2.join();
    assert!(done.load(Ordering::SeqCst));

    let (name, policy, priority) = seen1.lock().unwrap().clone();
    assert_eq!(name, thread1_name);
    assert_eq!(policy, SCHED_OTHER);
    assert_eq!(priority, clamp_priority(1, policy));
    let (name, policy, priority) = seen2.lock().unwrap().clone();
    assert_eq!(name, thread2_name);
    assert_eq!(policy, SCHED_OTHER);
    assert_eq!(priority, clamp_priority(10, policy));
}

#[test]
fn linux_long_thread_name_truncated() {
    let name = "VeryLongThreadNameTest";
    let thread = Thread::new(name);

    let seen = Arc::new(Mutex::new(String::new()));
    let s = seen.clone();
    thread.get_task_runner().post_task(Arc::new(move || {
        *s.lock().unwrap() = current_thread_name();
    }));
    thread.join();
    const K_THREAD_NAME_LEN: usize = 16;
    assert_eq!(*seen.lock().unwrap(), name[..K_THREAD_NAME_LEN - 1]);
}
