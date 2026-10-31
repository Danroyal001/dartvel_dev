// Port of flutter/fml/memory/ref_counted_unittest.cc.
//
// This file tests both ref_counted.rs and ref_ptr.rs. Upstream's "from raw
// pointer" cases become clones (a RefPtr cannot be made from a raw pointer
// in safe Rust), `created->AddRef()`/`Release()` become holding and dropping
// an extra RefPtr, MySubclass is a second type behind a `dyn MyClassLike`,
// and `created` is the object's address. The self-move and DebugChecks cases
// test C++ move semantics and debug deaths that Rust's ownership rules out.

#![allow(unused_assignments)] // The assignments mirror upstream's.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use super::ref_counted::internal::RefCountedThreadSafeBase;
use super::ref_ptr::{RefPtr, make_ref_counted};

trait MyClassLike: Send + Sync {}

struct MyClass {
    was_destroyed_: Option<Arc<AtomicBool>>,
}

impl MyClass {
    fn new(was_destroyed: Option<&Arc<AtomicBool>>) -> Self {
        MyClass { was_destroyed_: was_destroyed.cloned() }
    }
}

impl Drop for MyClass {
    fn drop(&mut self) {
        if let Some(w) = &self.was_destroyed_ {
            w.store(true, Ordering::SeqCst);
        }
    }
}

impl MyClassLike for MyClass {}

struct MySubclass {
    _base: MyClass,
}

impl MySubclass {
    fn new(was_destroyed: Option<&Arc<AtomicBool>>) -> Self {
        MySubclass { _base: MyClass::new(was_destroyed) }
    }
}

impl MyClassLike for MySubclass {}

fn flag() -> Arc<AtomicBool> {
    Arc::new(AtomicBool::new(false))
}

fn is(f: &Arc<AtomicBool>) -> bool {
    f.load(Ordering::SeqCst)
}

fn base<T: MyClassLike + 'static>(r: RefPtr<T>) -> RefPtr<dyn MyClassLike> {
    r.upcast(|p| p as Arc<dyn MyClassLike>)
}

#[test]
fn constructors() {
    {
        // Default.
        let r: RefPtr<MyClass> = RefPtr::default();
        assert!(r.get().is_none());
        assert!(!r.as_bool());
    }
    {
        // Nullptr.
        let r: RefPtr<MyClass> = RefPtr::null();
        assert!(r.get().is_none());
        assert!(!r.as_bool());
    }
    {
        let was_destroyed = flag();
        {
            // Adopt, then RVO.
            let r = make_ref_counted(MyClass::new(Some(&was_destroyed)));
            assert!(!r.as_ptr().is_null());
            assert!(r.as_bool());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
    {
        let was_destroyed = flag();
        {
            let r1 = make_ref_counted(MyClass::new(Some(&was_destroyed)));
            let created = r1.as_ptr();
            // Copy.
            let r2 = r1.clone();
            assert_eq!(created, r1.as_ptr());
            assert_eq!(created, r2.as_ptr());
            assert!(r1.as_bool());
            assert!(r2.as_bool());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
    {
        let was_destroyed = flag();
        {
            // Adopt, then "move".
            let sub = make_ref_counted(MySubclass::new(Some(&was_destroyed)));
            let created = sub.as_ptr();
            let r = base(sub);
            assert_eq!(created, r.as_ptr());
            assert!(r.as_bool());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
    {
        let was_destroyed = flag();
        {
            let r1 = make_ref_counted(MySubclass::new(Some(&was_destroyed)));
            // "Copy".
            let r2 = base(r1.clone());
            assert_eq!(r1.as_ptr(), r2.as_ptr());
            assert!(r1.as_bool());
            assert!(r2.as_bool());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
}

#[test]
fn null_assignment_to_null() {
    let mut r1: RefPtr<dyn MyClassLike> = RefPtr::null();
    // No-op null assignment using |nullptr|.
    r1 = RefPtr::null();
    assert!(r1.get().is_none());
    let r2: RefPtr<dyn MyClassLike> = RefPtr::null();
    // No-op null assignment using copy constructor.
    r1 = r2.clone();
    assert!(r1.get().is_none());
    assert!(r2.get().is_none());
    // No-op null assignment using move constructor.
    r1 = r2;
    assert!(!r1.as_bool());
    let r3: RefPtr<MySubclass> = RefPtr::null();
    // No-op null assignment using "copy" constructor.
    r1 = base(r3.clone());
    assert!(r1.get().is_none());
    assert!(r3.get().is_none());
    // No-op null assignment using "move" constructor.
    r1 = base(r3);
    assert!(!r1.as_bool());
}

#[test]
fn non_null_assignment_to_null() {
    {
        let was_destroyed = flag();
        {
            let r1 = make_ref_counted(MyClass::new(Some(&was_destroyed)));
            let mut r2: RefPtr<MyClass> = RefPtr::null();
            assert!(!r2.as_bool());
            // Copy assignment (to null ref pointer).
            r2 = r1.clone();
            assert_eq!(r1.as_ptr(), r2.as_ptr());
            assert!(r1.as_bool());
            assert!(r2.as_bool());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
    {
        let was_destroyed = flag();
        {
            let mut r1 = make_ref_counted(MyClass::new(Some(&was_destroyed)));
            let created = r1.as_ptr();
            let mut r2: RefPtr<MyClass> = RefPtr::null();
            // Move assignment (to null ref pointer).
            r2.swap(&mut r1);
            assert!(r1.get().is_none());
            assert_eq!(created, r2.as_ptr());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
    {
        let was_destroyed = flag();
        {
            let r1 = make_ref_counted(MySubclass::new(Some(&was_destroyed)));
            let mut r2: RefPtr<dyn MyClassLike> = RefPtr::null();
            assert!(!r2.as_bool());
            // "Copy" assignment (to null ref pointer).
            r2 = base(r1.clone());
            assert_eq!(r1.as_ptr(), r2.as_ptr());
            assert!(!is(&was_destroyed));
        }
        assert!(is(&was_destroyed));
    }
}

#[test]
fn null_assignment_to_non_null() {
    let was_destroyed = flag();
    let mut r1 = make_ref_counted(MyClass::new(Some(&was_destroyed)));
    // Null assignment (to non-null ref pointer) using |nullptr|.
    r1 = RefPtr::null();
    assert!(r1.get().is_none());
    assert!(is(&was_destroyed));

    let was_destroyed = flag();
    r1 = make_ref_counted(MyClass::new(Some(&was_destroyed)));
    let r2: RefPtr<MyClass> = RefPtr::null();
    // Null assignment (to non-null ref pointer) using copy constructor.
    r1 = r2.clone();
    assert!(r1.get().is_none());
    assert!(r2.get().is_none());
    assert!(is(&was_destroyed));
}

#[test]
fn non_null_assignment_to_non_null() {
    let was_destroyed1 = flag();
    let was_destroyed2 = flag();
    {
        let r1 = make_ref_counted(MyClass::new(Some(&was_destroyed1)));
        let mut r2 = make_ref_counted(MyClass::new(Some(&was_destroyed2)));
        assert!(r2.as_bool());
        // Copy assignment (to non-null ref pointer).
        r2 = r1.clone();
        assert_eq!(r1.as_ptr(), r2.as_ptr());
        assert!(!is(&was_destroyed1));
        assert!(is(&was_destroyed2));
    }
    assert!(is(&was_destroyed1));

    let was_destroyed1 = flag();
    let was_destroyed2 = flag();
    {
        let r1 = make_ref_counted(MySubclass::new(Some(&was_destroyed1)));
        let mut r2 = base(make_ref_counted(MyClass::new(Some(&was_destroyed2))));
        assert!(r2.as_bool());
        // "Move" assignment (to non-null ref pointer).
        r2 = base(r1);
        assert!(r2.as_bool());
        assert!(!is(&was_destroyed1));
        assert!(is(&was_destroyed2));
    }
    assert!(is(&was_destroyed1));
}

#[test]
#[allow(clippy::self_assignment, clippy::redundant_clone)]
fn self_assignment() {
    let was_destroyed = flag();
    {
        let mut r = make_ref_counted(MyClass::new(Some(&was_destroyed)));
        let created = r.as_ptr();
        r = r.clone();
        assert_eq!(created, r.as_ptr());
        assert!(!is(&was_destroyed));
    }
    assert!(is(&was_destroyed));
}

#[test]
fn swap() {
    let mut r1 = make_ref_counted(MyClass::new(None));
    let created1 = r1.as_ptr();
    let mut r2 = make_ref_counted(MyClass::new(None));
    let created2 = r2.as_ptr();
    assert_ne!(created1, created2);
    r1.swap(&mut r2);
    assert_eq!(created2, r1.as_ptr());
    assert_eq!(created1, r2.as_ptr());
}

#[test]
fn get_and_dereference_operators() {
    let r = make_ref_counted(MyClass::new(None));
    let created = r.as_ptr();
    let ptr = r.get().unwrap() as *const MyClass as *const ();
    assert_eq!(created, ptr);
    let reference: &MyClass = &r;
    assert_eq!(created, reference as *const MyClass as *const ());
}

#[test]
fn add_ref_release() {
    let was_destroyed = flag();
    let extra;
    {
        let r = make_ref_counted(MyClass::new(Some(&was_destroyed)));
        extra = r.clone(); // AddRef
    }
    assert!(!is(&was_destroyed));
    drop(extra); // Release
    assert!(is(&was_destroyed));
}

#[test]
fn mix() {
    let was_destroyed = flag();
    let mut r1 = make_ref_counted(MySubclass::new(Some(&was_destroyed)));
    assert!(!is(&was_destroyed));
    assert!(r1.has_one_ref());

    let mut r2 = r1.clone();
    assert!(!is(&was_destroyed));
    assert!(!r1.has_one_ref());

    r1 = RefPtr::null();
    assert!(!is(&was_destroyed));
    assert!(r2.has_one_ref());

    {
        let r3 = r2.clone();
        assert!(!r3.has_one_ref());
        {
            let _r4 = r3.clone();
            r2 = RefPtr::null();
            assert!(!is(&was_destroyed));
            assert!(!r3.has_one_ref());
        }
        assert!(!is(&was_destroyed));
        assert!(r3.has_one_ref());

        r1 = r3.clone();
        assert!(!is(&was_destroyed));
        assert!(!r3.has_one_ref());
    }
    assert!(!is(&was_destroyed));
    assert!(r1.has_one_ref());
    assert!(!r2.as_bool());

    r1 = RefPtr::null();
    assert!(!r1.as_bool());
    assert!(is(&was_destroyed));
}

struct MyPublicClass {
    has_num_: bool,
    num_: i32,
}

impl MyPublicClass {
    fn new() -> Self {
        MyPublicClass { has_num_: false, num_: 0 }
    }
    fn with_num(num: i32) -> Self {
        MyPublicClass { has_num_: true, num_: num }
    }
    fn has_num(&self) -> bool {
        self.has_num_
    }
    fn num(&self) -> i32 {
        self.num_
    }
}

#[test]
fn public_ctor_and_dtor() {
    let mut r1 = make_ref_counted(MyPublicClass::new());
    assert!(r1.as_bool());
    assert!(!r1.has_num());

    let mut r2 = make_ref_counted(MyPublicClass::with_num(123));
    assert!(r2.as_bool());
    assert!(r2.has_num());
    assert_eq!(123, r2.num());
    assert_ne!(r1.as_ptr(), r2.as_ptr());

    r1 = r2.clone();
    assert!(r1.has_num());
    assert_eq!(123, r1.num());
    assert_eq!(r1.as_ptr(), r2.as_ptr());

    r2 = RefPtr::null();
    assert!(!r2.as_bool());
    assert!(r1.has_num());
    assert_eq!(123, r1.num());

    r1 = RefPtr::null();
    assert!(!r1.as_bool());
}

// Not upstream: RefCountedThreadSafeBase's counting, which upstream tests only
// through RefPtr.
#[test]
fn base_counts_and_releases_at_zero() {
    let b = RefCountedThreadSafeBase::new();
    b.adopt();
    assert!(b.has_one_ref());
    b.add_ref();
    assert!(!b.has_one_ref());
    assert!(!b.release());
    assert!(b.has_one_ref());
    assert!(b.release());
}
