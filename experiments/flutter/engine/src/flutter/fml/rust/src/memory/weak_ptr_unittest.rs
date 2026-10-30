// Port of flutter/fml/memory/weak_ptr_unittest.cc.
//
// The pointed-to `int`/`Base` live in an `Arc` (see weak_ptr.rs);
// `EXPECT_EQ(&data, ptr.get())` compares addresses. Base/Derived become a
// trait and a type implementing it. The TaskRunnerAffineWeakPtr test needs
// MessageLoop and RasterThreadMerger, which are not ported yet.

#![allow(unused_assignments)] // The assignments mirror upstream's.

use std::sync::{Arc, Weak};

use super::weak_ptr::{WeakPtr, WeakPtrFactory};

fn addr<T: ?Sized>(p: Option<Arc<T>>) -> *const () {
    match p {
        Some(p) => Arc::as_ptr(&p) as *const (),
        None => std::ptr::null(),
    }
}

fn of<T: ?Sized>(data: &Arc<T>) -> *const () {
    Arc::as_ptr(data) as *const ()
}

#[test]
fn basic() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    assert_eq!(of(&data), addr(ptr.get()));
}

#[test]
fn copy_construction() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let ptr2 = ptr.clone();
    assert_eq!(of(&data), addr(ptr.get()));
    assert_eq!(of(&data), addr(ptr2.get()));
}

#[test]
fn move_construction() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let ptr2 = ptr;
    assert_eq!(of(&data), addr(ptr2.get()));
}

#[test]
fn copy_assignment() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let mut ptr2: WeakPtr<i32> = WeakPtr::new();
    assert!(ptr2.get().is_none());
    ptr2 = ptr.clone();
    assert_eq!(of(&data), addr(ptr.get()));
    assert_eq!(of(&data), addr(ptr2.get()));
}

#[test]
fn move_assignment() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let mut ptr2: WeakPtr<i32> = WeakPtr::new();
    assert!(ptr2.get().is_none());
    ptr2 = ptr;
    assert_eq!(of(&data), addr(ptr2.get()));
}

#[test]
fn testable() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let mut ptr: WeakPtr<i32> = WeakPtr::new();
    assert!(ptr.get().is_none());
    assert!(!ptr.as_bool());
    ptr = factory.get_weak_ptr();
    assert_eq!(of(&data), addr(ptr.get()));
    assert!(ptr.as_bool());
}

#[test]
fn out_of_scope() {
    let mut ptr: WeakPtr<i32> = WeakPtr::new();
    assert!(ptr.get().is_none());
    // The data outlives the factory here, so this checks the flag, not the
    // allocation.
    let data = Arc::new(0i32);
    {
        let factory = WeakPtrFactory::new(&data);
        ptr = factory.get_weak_ptr();
    }
    assert!(ptr.get().is_none());
    assert!(!ptr.as_bool());
}

#[test]
fn multiple() {
    let mut a: WeakPtr<i32> = WeakPtr::new();
    let mut b: WeakPtr<i32> = WeakPtr::new();
    let data = Arc::new(0i32);
    {
        let factory = WeakPtrFactory::new(&data);
        a = factory.get_weak_ptr();
        b = factory.get_weak_ptr();
        assert_eq!(of(&data), addr(a.get()));
        assert_eq!(of(&data), addr(b.get()));
    }
    assert!(a.get().is_none());
    assert!(b.get().is_none());
}

#[test]
fn multiple_staged() {
    let mut a: WeakPtr<i32> = WeakPtr::new();
    let data = Arc::new(0i32);
    {
        let factory = WeakPtrFactory::new(&data);
        a = factory.get_weak_ptr();
        {
            let _b = factory.get_weak_ptr();
        }
        assert!(a.get().is_some());
    }
    assert!(a.get().is_none());
}

trait Base: Send + Sync {
    fn member(&self) -> f64;
}

struct BaseData {
    member: f64,
}

impl Base for BaseData {
    fn member(&self) -> f64 {
        self.member
    }
}

struct Derived {
    base: BaseData,
}

impl Base for Derived {
    fn member(&self) -> f64 {
        self.base.member
    }
}

#[test]
fn dereference() {
    let data = Arc::new(BaseData { member: 123456. });
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    assert_eq!(of(&data), addr(ptr.get()));
    assert_eq!(data.member, ptr.get().unwrap().member);
}

fn upcast(p: WeakPtr<Derived>) -> WeakPtr<dyn Base> {
    p.upcast(|w| w as Weak<dyn Base>)
}

#[test]
fn upcast_copy_construction() {
    let data = Arc::new(Derived { base: BaseData { member: 0. } });
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let ptr2 = upcast(ptr.clone());
    assert_eq!(of(&data), addr(ptr.get()));
    assert_eq!(of(&data), addr(ptr2.get()));
    assert_eq!(0., ptr2.get().unwrap().member());
}

#[test]
fn upcast_move_assignment() {
    let data = Arc::new(Derived { base: BaseData { member: 0. } });
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let mut ptr2: WeakPtr<dyn Base> = WeakPtr::new();
    assert!(ptr2.get().is_none());
    ptr2 = upcast(ptr);
    assert_eq!(of(&data), addr(ptr2.get()));
}

// Not upstream: the factory as the last member of the object it vends
// pointers to, upstream's usual `weak_factory_(this)`.
#[test]
fn factory_inside_its_object() {
    struct Controller {
        value: i32,
        weak_factory_: WeakPtrFactory<Controller>,
    }
    let controller = Arc::new_cyclic(|weak| Controller {
        value: 7,
        weak_factory_: WeakPtrFactory::from_weak(weak.clone()),
    });
    let ptr = controller.weak_factory_.get_weak_ptr();
    assert_eq!(7, ptr.get().unwrap().value);
    drop(controller);
    assert!(!ptr.as_bool());
    assert!(ptr.get().is_none());
}

// Not upstream: in debug builds, using a WeakPtr off its factory's thread
// fails the thread check.
#[cfg(debug_assertions)]
#[test]
fn use_on_another_thread_fails_the_thread_check() {
    let data = Arc::new(0i32);
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let result = std::thread::spawn(move || ptr.as_bool()).join();
    assert!(result.is_err());
}
