// Port of flutter/fml/memory/ref_counted.h and
// flutter/fml/memory/ref_counted_internal.h.
//
// Objects that upstream derives from `RefCountedThreadSafe<T>` are held in
// an `Arc<T>` (see ref_ptr.rs), whose strong count plays the part of
// `RefCountedThreadSafeBase::ref_count_`; such types must be Send + Sync,
// which the `RefCountedThreadSafe` marker states. The base's count itself is
// kept for code that counts by hand, with upstream's memory orderings and
// its debug-only adoption and destruction checks.

use std::sync::atomic::{AtomicU32, Ordering, fence};

/// A base for (thread-safe) reference-counted types: implement it for a type
/// that is shared through `RefPtr`.
pub trait RefCountedThreadSafe: Send + Sync {}

pub mod internal {
    use super::*;

    /// See ref_counted.h for comments on the public methods.
    pub struct RefCountedThreadSafeBase {
        ref_count_: AtomicU32,
        #[cfg(debug_assertions)]
        adoption_required_: std::sync::atomic::AtomicBool,
        #[cfg(debug_assertions)]
        destruction_started_: std::sync::atomic::AtomicBool,
    }

    impl Default for RefCountedThreadSafeBase {
        fn default() -> Self {
            Self::new()
        }
    }

    impl RefCountedThreadSafeBase {
        /// Constructed with a reference count of 1, which must be adopted.
        pub fn new() -> Self {
            RefCountedThreadSafeBase {
                ref_count_: AtomicU32::new(1),
                #[cfg(debug_assertions)]
                adoption_required_: std::sync::atomic::AtomicBool::new(true),
                #[cfg(debug_assertions)]
                destruction_started_: std::sync::atomic::AtomicBool::new(false),
            }
        }

        pub fn add_ref(&self) {
            #[cfg(debug_assertions)]
            {
                debug_assert!(!self.adoption_required_.load(Ordering::Relaxed));
                debug_assert!(!self.destruction_started_.load(Ordering::Relaxed));
            }
            self.ref_count_.fetch_add(1, Ordering::Relaxed);
        }

        pub fn has_one_ref(&self) -> bool {
            self.ref_count_.load(Ordering::Acquire) == 1
        }

        pub fn assert_has_one_ref(&self) {
            debug_assert!(self.has_one_ref());
        }

        /// Returns true if the object should self-delete.
        pub fn release(&self) -> bool {
            #[cfg(debug_assertions)]
            {
                debug_assert!(!self.adoption_required_.load(Ordering::Relaxed));
                debug_assert!(!self.destruction_started_.load(Ordering::Relaxed));
            }
            debug_assert!(self.ref_count_.load(Ordering::Acquire) != 0);
            if self.ref_count_.fetch_sub(1, Ordering::Release) == 1 {
                fence(Ordering::Acquire);
                #[cfg(debug_assertions)]
                self.destruction_started_.store(true, Ordering::Relaxed);
                return true;
            }
            false
        }

        /// Marks the initial reference as adopted (debug builds only).
        pub fn adopt(&self) {
            #[cfg(debug_assertions)]
            {
                debug_assert!(self.adoption_required_.load(Ordering::Relaxed));
                self.adoption_required_.store(false, Ordering::Relaxed);
            }
        }
    }

    impl Drop for RefCountedThreadSafeBase {
        fn drop(&mut self) {
            #[cfg(debug_assertions)]
            if !std::thread::panicking() {
                debug_assert!(!self.adoption_required_.load(Ordering::Relaxed));
                // Should only be destroyed as a result of |Release()|.
                debug_assert!(self.destruction_started_.load(Ordering::Relaxed));
            }
        }
    }
}
