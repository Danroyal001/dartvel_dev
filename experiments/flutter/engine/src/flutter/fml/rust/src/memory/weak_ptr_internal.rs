// Port of flutter/fml/memory/weak_ptr_internal.h and
// flutter/fml/memory/weak_ptr_internal.cc.
//
// `is_valid_` is a plain bool upstream, read and written on the factory's
// thread only; it is an atomic here because the flag is shared through a
// RefPtr, which Rust requires to be Sync. Relaxed matches the plain bool.

use std::sync::atomic::{AtomicBool, Ordering};

/// `WeakPtr<T>`s have a reference to a `WeakPtrFlag` to determine whether
/// they are valid (non-null) or not.
pub struct WeakPtrFlag {
    is_valid_: AtomicBool,
}

impl Default for WeakPtrFlag {
    fn default() -> Self {
        Self::new()
    }
}

impl WeakPtrFlag {
    pub fn new() -> Self {
        WeakPtrFlag { is_valid_: AtomicBool::new(true) }
    }

    pub fn is_valid(&self) -> bool {
        self.is_valid_.load(Ordering::Relaxed)
    }

    pub fn invalidate(&self) {
        // Invalidation should happen exactly once.
        debug_assert!(self.is_valid());
        self.is_valid_.store(false, Ordering::Relaxed);
    }
}

impl Drop for WeakPtrFlag {
    fn drop(&mut self) {
        // Should be invalidated before destruction.
        if !std::thread::panicking() {
            debug_assert!(!self.is_valid());
        }
    }
}

impl super::ref_counted::RefCountedThreadSafe for WeakPtrFlag {}
