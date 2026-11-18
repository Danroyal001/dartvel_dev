// Port of flutter/fml/closure_unittests.cc.

use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};

use crate::closure::ScopedCleanupClosure;

fn counter() -> (Arc<AtomicI32>, crate::closure::closure) {
    let invoked = Arc::new(AtomicI32::new(0));
    let i = invoked.clone();
    (invoked, crate::closure::closure::new(move || {
        i.fetch_add(1, Ordering::SeqCst);
    }))
}

#[test]
fn destructor_does_nothing_when_no_closure_set() {
    let _cleanup = ScopedCleanupClosure::default();

    // Nothing should happen.
}

#[test]
fn release_does_nothing_when_no_closure_set() {
    let mut cleanup = ScopedCleanupClosure::default();

    // Nothing should happen.
    assert!(cleanup.release().is_none());
}

#[test]
fn closure_invoked_on_destructor_when_set_in_constructor() {
    let (invoked, closure) = counter();

    {
        let _cleanup = ScopedCleanupClosure::new(closure);

        assert_eq!(0, invoked.load(Ordering::SeqCst));
    }

    assert_eq!(1, invoked.load(Ordering::SeqCst));
}

#[test]
fn closure_invoked_on_destructor_when_set() {
    let (invoked, closure) = counter();

    {
        let mut cleanup = ScopedCleanupClosure::default();
        cleanup.set_closure(closure);

        assert_eq!(0, invoked.load(Ordering::SeqCst));
    }

    assert_eq!(1, invoked.load(Ordering::SeqCst));
}

#[test]
fn closure_not_invoked_when_moved() {
    let (invoked, closure) = counter();

    {
        let cleanup = ScopedCleanupClosure::new(closure);
        let _cleanup2 = cleanup;

        assert_eq!(0, invoked.load(Ordering::SeqCst));
    }

    assert_eq!(1, invoked.load(Ordering::SeqCst));
}

#[test]
fn closure_not_invoked_when_moved_via_assignment() {
    let (invoked, closure) = counter();

    {
        let cleanup = ScopedCleanupClosure::new(closure);
        let mut cleanup2 = ScopedCleanupClosure::default();
        cleanup2.assign(cleanup);

        assert_eq!(0, invoked.load(Ordering::SeqCst));
    }

    assert_eq!(1, invoked.load(Ordering::SeqCst));
}

// Not upstream: move-assigning onto a holder that has a closure drops that
// closure without invoking it (`closure_ = other.Release()`), and the moved
// closure runs once.
#[test]
fn closure_replaced_by_move_assignment_is_not_invoked() {
    let (first, first_closure) = counter();
    let (second, second_closure) = counter();

    {
        let mut cleanup = ScopedCleanupClosure::new(first_closure);
        cleanup.assign(ScopedCleanupClosure::new(second_closure));

        assert_eq!(0, first.load(Ordering::SeqCst));
        assert_eq!(0, second.load(Ordering::SeqCst));
    }

    assert_eq!(0, first.load(Ordering::SeqCst));
    assert_eq!(1, second.load(Ordering::SeqCst));
}

// Not upstream: `closure`'s own storage. Each path (in place, boxed, shared)
// is called, cloned, moved and dropped, and every capture is counted, so a
// double drop, a leak or a call through the wrong vtable fails here and,
// under Miri, as undefined behaviour.

mod storage {
    use std::mem::size_of;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicI32, Ordering};

    use crate::closure::closure;

    /// Counts its live copies in `live` and its calls in `calls`.
    struct Tracked<const N: usize> {
        live: Arc<AtomicI32>,
        calls: Arc<AtomicI32>,
        pad: [u8; N],
    }

    impl<const N: usize> Tracked<N> {
        fn new(live: &Arc<AtomicI32>, calls: &Arc<AtomicI32>) -> Self {
            live.fetch_add(1, Ordering::SeqCst);
            Tracked { live: live.clone(), calls: calls.clone(), pad: [7; N] }
        }
    }

    impl<const N: usize> Clone for Tracked<N> {
        fn clone(&self) -> Self {
            Tracked::new(&self.live, &self.calls)
        }
    }

    impl<const N: usize> Drop for Tracked<N> {
        fn drop(&mut self) {
            self.live.fetch_sub(1, Ordering::SeqCst);
        }
    }

    fn counters() -> (Arc<AtomicI32>, Arc<AtomicI32>) {
        (Arc::new(AtomicI32::new(0)), Arc::new(AtomicI32::new(0)))
    }

    /// Makes a closure over a `Tracked<N>` and runs it through every
    /// operation, checking the counts after each.
    fn exercise<const N: usize>() {
        let (live, calls) = counters();
        {
            let t = Tracked::<N>::new(&live, &calls);
            let c = closure::new(move || {
                assert!(t.pad.iter().all(|&b| b == 7));
                t.calls.fetch_add(1, Ordering::SeqCst);
            });
            assert_eq!(live.load(Ordering::SeqCst), 1);
            c.call();
            assert_eq!(calls.load(Ordering::SeqCst), 1);

            let copy = c.clone();
            assert_eq!(live.load(Ordering::SeqCst), 2);
            copy.call();
            assert_eq!(calls.load(Ordering::SeqCst), 2);

            // Moves: into a box, a vector that grows, and back out.
            let boxed = Box::new(c);
            let mut v = Vec::new();
            v.push(*boxed);
            for _ in 0..20 {
                v.push(copy.clone());
            }
            assert_eq!(live.load(Ordering::SeqCst), 22);
            for c in &v {
                c.call();
            }
            assert_eq!(calls.load(Ordering::SeqCst), 23);
            let moved = v.swap_remove(0);
            drop(v);
            assert_eq!(live.load(Ordering::SeqCst), 2);
            moved.call();
            drop(moved);
            assert_eq!(live.load(Ordering::SeqCst), 1);
        }
        assert_eq!(live.load(Ordering::SeqCst), 0);
        assert_eq!(calls.load(Ordering::SeqCst), 24);
    }

    #[test]
    fn is_the_size_of_libcxx_std_function() {
        assert_eq!(size_of::<closure>(), 4 * size_of::<usize>());
        assert_eq!(size_of::<Option<closure>>(), size_of::<closure>());
    }

    #[test]
    fn inline_capture() {
        // Two Arcs and 8 bytes: exactly the three words of the buffer.
        exercise::<8>();
    }

    #[test]
    fn heap_capture() {
        // Larger than the buffer: boxed.
        exercise::<64>();
    }

    #[test]
    fn zero_sized_capture() {
        static CALLS: AtomicI32 = AtomicI32::new(0);
        let c = closure::new(|| {
            CALLS.fetch_add(1, Ordering::SeqCst);
        });
        let d = c.clone();
        c.call();
        d.call();
        assert_eq!(CALLS.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn over_aligned_capture_is_boxed() {
        #[derive(Clone)]
        #[repr(align(64))]
        struct Aligned(u8);
        let a = Aligned(5);
        let c = closure::new(move || assert_eq!(a.0, 5));
        c.clone().call();
        c.call();
    }

    #[test]
    fn shared_capture_that_cannot_be_cloned() {
        let (live, calls) = counters();
        {
            // A Mutex is not Clone: every copy shares the one capture.
            let t = std::sync::Mutex::new(Tracked::<0>::new(&live, &calls));
            let c = closure::shared(move || {
                t.lock().unwrap().calls.fetch_add(1, Ordering::SeqCst);
            });
            let d = c.clone();
            c.call();
            d.call();
            assert_eq!(live.load(Ordering::SeqCst), 1);
            drop(c);
            d.call();
            assert_eq!(live.load(Ordering::SeqCst), 1);
        }
        assert_eq!(live.load(Ordering::SeqCst), 0);
        assert_eq!(calls.load(Ordering::SeqCst), 3);
    }

    #[test]
    fn panic_during_call_leaves_the_closure_whole() {
        for big in [false, true] {
            let (live, calls) = counters();
            {
                let t = Tracked::<0>::new(&live, &calls);
                let pad = [0u8; 64];
                let c = if big {
                    closure::new(move || {
                        let _ = pad;
                        if t.calls.fetch_add(1, Ordering::SeqCst) == 0 {
                            panic!("first call");
                        }
                    })
                } else {
                    closure::new(move || {
                        if t.calls.fetch_add(1, Ordering::SeqCst) == 0 {
                            panic!("first call");
                        }
                    })
                };
                let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| c.call()));
                assert!(r.is_err());
                c.call();
                assert_eq!(calls.load(Ordering::SeqCst), 2);
                assert_eq!(live.load(Ordering::SeqCst), 1);
            }
            assert_eq!(live.load(Ordering::SeqCst), 0);
        }
    }

    #[test]
    fn panic_during_clone_drops_nothing_twice() {
        struct PanicsOnClone(Arc<AtomicI32>);
        impl Clone for PanicsOnClone {
            fn clone(&self) -> Self {
                panic!("clone");
            }
        }
        impl Drop for PanicsOnClone {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        for big in [false, true] {
            let drops = Arc::new(AtomicI32::new(0));
            {
                let p = PanicsOnClone(drops.clone());
                let pad = [0u8; 64];
                let c = if big {
                    closure::new(move || {
                        let _ = (&p, pad);
                    })
                } else {
                    closure::new(move || {
                        let _ = &p;
                    })
                };
                let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| c.clone()));
                assert!(r.is_err());
                assert_eq!(drops.load(Ordering::SeqCst), 0);
                c.call();
            }
            assert_eq!(drops.load(Ordering::SeqCst), 1);
        }
    }

    #[test]
    fn calls_from_other_threads() {
        let (live, calls) = counters();
        {
            let t = Tracked::<0>::new(&live, &calls);
            let c = closure::new(move || {
                t.calls.fetch_add(1, Ordering::SeqCst);
            });
            std::thread::scope(|s| {
                for _ in 0..4 {
                    let mine = c.clone();
                    let shared = &c;
                    s.spawn(move || {
                        mine.call();
                        shared.call();
                    });
                }
            });
        }
        assert_eq!(calls.load(Ordering::SeqCst), 8);
        assert_eq!(live.load(Ordering::SeqCst), 0);
    }
}

// Not upstream: what the inline buffer is for. The test binary's allocator
// counts this thread's allocations, so a capture of up to three words must
// make, copy and drop a closure without one, and a larger one must allocate
// (once per copy), as libc++'s std::function does.
mod allocations {
    use std::alloc::{GlobalAlloc, Layout, System};
    use std::cell::Cell;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use crate::closure::closure;

    thread_local! {
        static ALLOCATIONS: Cell<usize> = const { Cell::new(0) };
    }

    struct Counting;

    // SAFETY: every call is forwarded unchanged to `System`, which upholds
    // `GlobalAlloc`'s contract; the counter is a const-initialized
    // thread-local `Cell`, which neither allocates nor reenters.
    unsafe impl GlobalAlloc for Counting {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            let _ = ALLOCATIONS.try_with(|n| n.set(n.get() + 1));
            // SAFETY: the caller's layout is passed through as it came.
            unsafe { System.alloc(layout) }
        }

        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            // SAFETY: `ptr` came from `alloc` above, so from `System`.
            unsafe { System.dealloc(ptr, layout) }
        }
    }

    #[global_allocator]
    static COUNTING: Counting = Counting;

    fn allocations_in(f: impl FnOnce()) -> usize {
        let before = ALLOCATIONS.with(Cell::get);
        f();
        ALLOCATIONS.with(Cell::get) - before
    }

    static RAN: AtomicUsize = AtomicUsize::new(0);

    #[test]
    fn three_words_of_captures_are_kept_in_place() {
        let (a, b, c) = (&RAN, 1usize, 2usize);
        let n = allocations_in(|| {
            let task = closure::new(move || {
                a.fetch_add(b + c, Ordering::Relaxed);
            });
            let copy = task.clone();
            task.call();
            copy.call();
        });
        assert_eq!(n, 0);
    }

    #[test]
    fn larger_captures_are_boxed() {
        let (a, b) = (&RAN, [1usize; 3]);
        let n = allocations_in(|| {
            let task = closure::new(move || {
                a.fetch_add(b[0] + b[2], Ordering::Relaxed);
            });
            let copy = task.clone();
            task.call();
            copy.call();
        });
        assert_eq!(n, 2);
    }
}
