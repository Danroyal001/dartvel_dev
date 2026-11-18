// Port of flutter/fml/closure.h.

use std::mem::{MaybeUninit, align_of, size_of};
use std::sync::Arc;

/// The inline buffer: three words, as libc++'s `std::function` keeps
/// (`__buf_` is `3 * sizeof(void*)` beside the vtable pointer, so the whole
/// object is four words in both).
type Storage = MaybeUninit<[usize; 3]>;

/// What `closure` knows of the value in its buffer: libc++'s `__base`
/// vtable for `std::function<void()>`, less the target and type queries the
/// port does not use. Moving needs no entry: a Rust value moves by copying
/// its bytes, which is what moving the buffer does.
///
/// # Safety
///
/// Each entry may be called only with a buffer that holds the initialized
/// value this vtable was made for (`clone`'s second argument: a buffer to
/// write a copy into), and `drop` leaves the buffer uninitialized.
struct VTable {
    call: unsafe fn(*const Storage),
    clone: unsafe fn(*const Storage, *mut Storage),
    drop: unsafe fn(*mut Storage),
}

/// Whether a `T` fits the buffer, in size and in alignment.
const fn fits<T>() -> bool {
    size_of::<T>() <= size_of::<Storage>() && align_of::<T>() <= align_of::<Storage>()
}

/// The vtable of a `T` stored inline. `T` is either the caller's callable or,
/// when that does not fit, a `Box` of it (the heap fallback), so this is the
/// only place a type is erased.
struct Inline<T>(std::marker::PhantomData<T>);

impl<T: Fn() + Clone + Send + Sync + 'static> Inline<T> {
    const VTABLE: VTable = VTable {
        // SAFETY (all three): a `closure` with this vtable holds an
        // initialized `T` at the start of its buffer, written by
        // `closure::inline::<T>` (which checked `fits::<T>()`, so the buffer
        // is large and aligned enough), and keeps it initialized until its
        // `Drop` runs `drop` once. `call` and `clone` only read it through a
        // shared reference; `clone` writes a new `T` into an uninitialized
        // buffer of the same layout.
        call: |p| unsafe { (*p.cast::<T>())() },
        clone: |src, dst| unsafe { dst.cast::<T>().write((*src.cast::<T>()).clone()) },
        drop: |p| unsafe { p.cast::<T>().drop_in_place() },
    };
}

/// `std::function<void()>`: a copyable callable. Upstream's empty
/// std::function is `Option<closure>` where it can occur.
///
/// As libc++'s `std::function` does, it keeps a callable of up to three words
/// (and word alignment) in place, so posting a task that captures a
/// reference or two allocates nothing, and boxes larger ones. Copying copies
/// the captures, as copying a `std::function` does; captures that cannot be
/// cloned are shared instead through [`closure::shared`].
#[allow(non_camel_case_types)]
pub struct closure {
    storage: Storage,
    vtable: &'static VTable,
}

// SAFETY: every constructor requires the stored callable to be `Send + Sync`
// (`Inline<T>::VTABLE` exists only for such `T`, and a `Box` of one is too),
// and `closure` gives out no access to it beyond calling it through `&self`,
// cloning it, and dropping it, each of which those bounds make thread-safe.
unsafe impl Send for closure {}
// SAFETY: as for `Send` above.
unsafe impl Sync for closure {}

impl closure {
    /// Stores `f` in place when it fits, otherwise on the heap.
    #[inline]
    pub fn new<F: Fn() + Clone + Send + Sync + 'static>(f: F) -> closure {
        if fits::<F>() { closure::inline(f) } else { closure::inline(Box::new(f)) }
    }

    /// For a callable whose captures cannot be cloned: it is shared by every
    /// copy through one reference count (what `Arc<dyn Fn()>` did for all of
    /// them).
    #[inline]
    pub fn shared<F: Fn() + Send + Sync + 'static>(f: F) -> closure {
        let f = Arc::new(f);
        closure::inline(move || f())
    }

    #[inline]
    fn inline<T: Fn() + Clone + Send + Sync + 'static>(value: T) -> closure {
        assert!(fits::<T>());
        let mut storage = Storage::uninit();
        // SAFETY: `fits::<T>()` holds, so the buffer is large and aligned
        // enough for a `T`; it is uninitialized, so nothing is overwritten.
        unsafe { storage.as_mut_ptr().cast::<T>().write(value) };
        closure { storage, vtable: &Inline::<T>::VTABLE }
    }

    /// `operator()`.
    #[inline]
    pub fn call(&self) {
        // SAFETY: `vtable` was made for the value in `storage` (see
        // `Inline::VTABLE`).
        unsafe { (self.vtable.call)(&self.storage) }
    }
}

impl Clone for closure {
    #[inline]
    fn clone(&self) -> closure {
        let mut storage = Storage::uninit();
        // SAFETY: `vtable` was made for the value in `self.storage`, and
        // `storage` has the same layout. Should the clone panic, `storage`
        // is never wrapped in a `closure`, so nothing drops it.
        unsafe { (self.vtable.clone)(&self.storage, &mut storage) };
        closure { storage, vtable: self.vtable }
    }
}

impl Drop for closure {
    #[inline]
    fn drop(&mut self) {
        // SAFETY: `vtable` was made for the value in `storage`, which is
        // dropped this once.
        unsafe { (self.vtable.drop)(&mut self.storage) }
    }
}

/// Wraps a closure that is invoked in the destructor unless released by the
/// caller.
///
/// This is especially useful in dealing with C-style APIs where a cleanup
/// function needs to be called in every error path.
///
/// Moving a `ScopedCleanupClosure` moves the closure with it (Rust moves never
/// run the moved-from value's destructor), which is what upstream's move
/// constructor and move assignment implement by hand. Move-assigning onto a
/// holder that already has a closure drops that closure without invoking it,
/// as upstream's `closure_ = other.Release()` does.
#[derive(Default)]
pub struct ScopedCleanupClosure {
    closure_: Option<closure>,
}

impl ScopedCleanupClosure {
    pub fn new(closure: closure) -> Self {
        ScopedCleanupClosure { closure_: Some(closure) }
    }

    /// Upstream's `operator=(ScopedCleanupClosure&&)`.
    pub fn assign(&mut self, mut other: ScopedCleanupClosure) {
        self.closure_ = other.release();
    }

    /// `explicit operator bool`.
    pub fn as_bool(&self) -> bool {
        self.closure_.is_some()
    }

    pub fn set_closure(&mut self, closure: closure) -> Option<closure> {
        self.closure_.replace(closure)
    }

    pub fn release(&mut self) -> Option<closure> {
        self.closure_.take()
    }

    pub fn reset(&mut self) {
        if let Some(closure) = self.closure_.take() {
            closure.call();
        }
    }
}

impl Drop for ScopedCleanupClosure {
    fn drop(&mut self) {
        self.reset();
    }
}
