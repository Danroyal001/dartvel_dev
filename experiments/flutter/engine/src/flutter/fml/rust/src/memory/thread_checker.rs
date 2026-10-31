// Port of flutter/fml/memory/thread_checker.h (and thread_checker.cc, which
// defines the thread-local flag).
//
// The Apple-only logging of thread names on a failed check is not ported.

use std::cell::Cell;
use std::thread::ThreadId;

thread_local! {
    static DISABLE_NEXT_FAILURE: Cell<bool> = const { Cell::new(false) };
}

/// A simple class that records the identity of the thread that it was created
/// on, and at later points can tell if the current thread is the same as its
/// creation thread. This class is thread-safe.
#[derive(Clone, Copy, Debug)]
pub struct ThreadChecker {
    self_: ThreadId,
}

impl Default for ThreadChecker {
    fn default() -> Self {
        Self::new()
    }
}

impl ThreadChecker {
    pub fn new() -> Self {
        ThreadChecker { self_: std::thread::current().id() }
    }

    pub fn disable_next_thread_check_failure() {
        DISABLE_NEXT_FAILURE.with(|f| f.set(true));
    }

    /// Returns true if the current thread is the thread this object was
    /// created on and false otherwise.
    pub fn is_creation_thread_current(&self) -> bool {
        let is_creation_thread_current = std::thread::current().id() == self.self_;
        if !is_creation_thread_current && DISABLE_NEXT_FAILURE.with(|f| f.replace(false)) {
            return true;
        }
        is_creation_thread_current
    }
}

/// `FML_DECLARE_THREAD_CHECKER(c)`: a ThreadChecker in debug builds, nothing
/// in release builds.
#[derive(Clone, Copy, Debug, Default)]
pub struct DebugThreadChecker {
    #[cfg(debug_assertions)]
    pub checker: ThreadChecker,
}

impl DebugThreadChecker {
    pub fn new() -> Self {
        DebugThreadChecker {
            #[cfg(debug_assertions)]
            checker: ThreadChecker::new(),
        }
    }

    /// `FML_DCHECK_CREATION_THREAD_IS_CURRENT(checker)`.
    #[inline]
    pub fn dcheck_creation_thread_is_current(&self) {
        #[cfg(debug_assertions)]
        assert!(
            self.checker.is_creation_thread_current(),
            "Check failed: (c).IsCreationThreadCurrent()."
        );
    }
}
