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
fn upcast_move_construction() {
    let data = Arc::new(Derived { base: BaseData { member: 0. } });
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let ptr2 = upcast(ptr);
    assert_eq!(of(&data), addr(ptr2.get()));
}

#[test]
fn upcast_copy_assignment() {
    let data = Arc::new(Derived { base: BaseData { member: 0. } });
    let factory = WeakPtrFactory::new(&data);
    let ptr = factory.get_weak_ptr();
    let mut ptr2: WeakPtr<dyn Base> = WeakPtr::new();
    assert!(ptr2.get().is_none());
    ptr2 = upcast(ptr.clone());
    assert_eq!(of(&data), addr(ptr.get()));
    assert_eq!(of(&data), addr(ptr2.get()));
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

mod task_runner_affine_weak_ptr_test {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    use crate::memory::weak_ptr::TaskRunnerAffineWeakPtrFactory;
    use crate::message_loop::MessageLoop;
    use crate::raster_thread_merger::RasterThreadMerger;
    use crate::raster_thread_merger_unittests::TaskQueueWrapper;
    use crate::synchronization::waitable_event::AutoResetWaitableEvent;

    #[test]
    fn should_not_crash_if_running_on_the_same_task_runner() {
        let queue1 = TaskQueueWrapper::new();

        let slot: Arc<std::sync::Mutex<Option<MessageLoop>>> = Arc::default();
        let latch2 = Arc::new(AutoResetWaitableEvent::new());
        let term2 = Arc::new(AutoResetWaitableEvent::new());
        let loop2_task_finish_latch = Arc::new(AutoResetWaitableEvent::new());
        let loop2_task_start_latch = Arc::new(AutoResetWaitableEvent::new());
        let matched = Arc::new(AtomicBool::new(false));
        let thread2 = {
            let (slot, latch2, term2, finish, start, matched) = (
                slot.clone(),
                latch2.clone(),
                term2.clone(),
                loop2_task_finish_latch.clone(),
                loop2_task_start_latch.clone(),
                matched.clone(),
            );
            std::thread::spawn(move || {
                MessageLoop::ensure_initialized_for_current_thread();
                let data = Arc::new(0i32);
                let factory = Arc::new(TaskRunnerAffineWeakPtrFactory::new(&data));
                let loop2 = MessageLoop::get_current();
                *slot.lock().unwrap() = Some(loop2.clone());

                let f = factory.clone();
                let d = data.clone();
                loop2.get_task_runner().post_task(crate::closure::closure::new(move || {
                    latch2.signal();
                    start.wait();
                    let ptr = f.get_weak_ptr();
                    matched.store(ptr.get().is_some_and(|p| *p == *d), Ordering::SeqCst);
                    finish.signal();
                }));
                loop2.run();
                term2.wait();
                drop(factory);
            })
        };

        latch2.wait();
        let loop2 = slot.lock().unwrap().take().unwrap();
        let qid1 = queue1.get_task_queue_id();
        let qid2 = loop2.get_task_runner().get_task_queue_id();
        let raster_thread_merger = RasterThreadMerger::new(qid1, qid2);
        const K_NUM_FRAMES_MERGED: usize = 5;

        raster_thread_merger.merge_with_lease(K_NUM_FRAMES_MERGED);

        loop2_task_start_latch.signal();
        loop2_task_finish_latch.wait();

        for _ in 0..K_NUM_FRAMES_MERGED {
            assert!(raster_thread_merger.is_merged());
            raster_thread_merger.decrement_lease();
        }

        assert!(!raster_thread_merger.is_merged());
        loop2.terminate();

        term2.signal();
        thread2.join().unwrap();
        assert!(matched.load(Ordering::SeqCst));
    }
}
