// Port of flutter/fml/closure_unittests.cc.

use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};

use crate::closure::ScopedCleanupClosure;

fn counter() -> (Arc<AtomicI32>, crate::closure::closure) {
    let invoked = Arc::new(AtomicI32::new(0));
    let i = invoked.clone();
    (invoked, Arc::new(move || {
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
