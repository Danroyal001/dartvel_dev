// Port of flutter/fml/memory/weak_ptr.h.
//
// A `WeakPtr<T>` holds a `Weak<T>` where upstream holds a `T*`, plus the same
// invalidation flag and (in debug builds) the same creation-thread check.
// `get()` returns the object only while the factory that vended the pointer
// is alive, as upstream does, and hands it out as an `Arc<T>` so it cannot
// be freed while used; upstream's `T*` (and `operator*`/`operator->`) has no
// safe counterpart. The factory takes the object as an `Arc<T>` or, for a
// factory stored inside the object it points to (upstream's usual
// `weak_factory_(this)` member), as the `Weak<T>` that `Arc::new_cyclic`
// hands out.
//
// TaskRunnerAffineWeakPtr and its factory check the task runner rather than
// the thread; they need MessageLoop, which is not ported yet.

use std::sync::{Arc, Weak};

use super::ref_ptr::{RefPtr, make_ref_counted};
use super::thread_checker::DebugThreadChecker;
use super::weak_ptr_internal::WeakPtrFlag;

/// Class for "weak pointers" that can be invalidated. Valid weak pointers
/// can only originate from a `WeakPtrFactory` (see below), though weak
/// pointers are copyable and movable.
///
/// Weak pointers are not in general thread-safe. They may only be *used* on
/// a single thread, namely the same thread as the "originating"
/// `WeakPtrFactory` (which can invalidate the weak pointers that it
/// generates).
///
/// However, weak pointers may be passed to other threads, reset on other
/// threads, or destroyed on other threads. They may also be reassigned on
/// other threads (in which case they should then only be used on the thread
/// corresponding to the new "originating" `WeakPtrFactory`).
pub struct WeakPtr<T: ?Sized> {
    ptr_: Option<Weak<T>>,
    flag_: RefPtr<WeakPtrFlag>,
    checker_: DebugThreadChecker,
}

impl<T: ?Sized> Default for WeakPtr<T> {
    fn default() -> Self {
        WeakPtr { ptr_: None, flag_: RefPtr::null(), checker_: DebugThreadChecker::default() }
    }
}

impl<T: ?Sized> Clone for WeakPtr<T> {
    fn clone(&self) -> Self {
        WeakPtr { ptr_: self.ptr_.clone(), flag_: self.flag_.clone(), checker_: self.checker_ }
    }
}

impl<T: ?Sized> WeakPtr<T> {
    pub fn new() -> Self {
        Self::default()
    }

    /// Upcasts, as upstream's converting constructors do: pass a closure that
    /// coerces, e.g. `|w| w as Weak<dyn Base>`.
    pub fn upcast<U: ?Sized>(self, f: impl FnOnce(Weak<T>) -> Weak<U>) -> WeakPtr<U> {
        WeakPtr { ptr_: self.ptr_.map(f), flag_: self.flag_, checker_: self.checker_ }
    }

    pub fn reset(&mut self) {
        self.flag_ = RefPtr::null();
    }

    // The following methods should only be called on the same thread as the
    // "originating" |WeakPtrFactory|.

    /// `explicit operator bool`.
    pub fn as_bool(&self) -> bool {
        self.check_thread_safety();
        self.flag_.get().is_some_and(|f| f.is_valid())
    }

    pub fn get(&self) -> Option<Arc<T>> {
        self.check_thread_safety();
        if self.as_bool() { self.ptr_.as_ref().and_then(Weak::upgrade) } else { None }
    }

    fn check_thread_safety(&self) {
        self.checker_.dcheck_creation_thread_is_current();
    }
}

/// Class that produces (valid) `WeakPtr<T>`s. Typically, this is used as a
/// member variable of `T` (preferably the last one -- see below), and `T`'s
/// methods control how weak pointers to it are vended. This class is not
/// thread-safe, and should only be created, destroyed and used on a single
/// thread.
pub struct WeakPtrFactory<T: ?Sized> {
    // Note: See weak_ptr_internal.h for an explanation of why we store the
    // pointer here, instead of in the "flag".
    ptr_: Weak<T>,
    flag_: RefPtr<WeakPtrFlag>,
    checker_: DebugThreadChecker,
}

impl<T: ?Sized> WeakPtrFactory<T> {
    pub fn new(ptr: &Arc<T>) -> Self {
        Self::from_weak(Arc::downgrade(ptr))
    }

    pub fn from_weak(ptr: Weak<T>) -> Self {
        WeakPtrFactory {
            ptr_: ptr,
            flag_: make_ref_counted(WeakPtrFlag::new()),
            checker_: DebugThreadChecker::new(),
        }
    }

    /// Gets a new weak pointer, which will be valid until this object is
    /// destroyed.
    pub fn get_weak_ptr(&self) -> WeakPtr<T> {
        WeakPtr { ptr_: Some(self.ptr_.clone()), flag_: self.flag_.Clone(), checker_: self.checker_ }
    }

    fn check_thread_safety(&self) {
        self.checker_.dcheck_creation_thread_is_current();
    }
}

impl<T: ?Sized> Drop for WeakPtrFactory<T> {
    fn drop(&mut self) {
        if !std::thread::panicking() {
            self.check_thread_safety();
        }
        self.flag_.invalidate();
    }
}
