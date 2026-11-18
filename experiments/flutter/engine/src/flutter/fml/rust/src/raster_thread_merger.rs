// Port of flutter/fml/raster_thread_merger.h and
// flutter/fml/raster_thread_merger.cc.
//
// `merge_unmerge_callback_` is set without the lock upstream (a race with a
// merge on another thread); it has its own lock here. It is still invoked
// with `mutex_` held, as upstream does, so a callback must not call back
// into the same merger.

use std::sync::{Condvar, Mutex, MutexGuard};

use crate::closure::closure;
use crate::memory::ref_counted::RefCountedThreadSafe;
use crate::memory::ref_ptr::{RefPtr, make_ref_counted};
use crate::message_loop::MessageLoop;
use crate::shared_thread_merger::{RasterThreadMergerId, SharedThreadMerger};
use crate::task_queue_id::TaskQueueId;
use crate::{fml_check_at, fml_dcheck_at};

const FILE: &str = "flutter/fml/raster_thread_merger.cc";

#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub enum RasterThreadStatus {
    kRemainsMerged,
    kRemainsUnmerged,
    kUnmergedNow,
}

/// RasterThreadMerger instances are owned by the shell and the raster
/// cache. Merges the raster thread into the platform thread for a number of
/// frames (a lease), and un-merges it when the lease runs out.
pub struct RasterThreadMerger {
    platform_queue_id_: TaskQueueId,
    gpu_queue_id_: TaskQueueId,
    shared_merger_: RefPtr<SharedThreadMerger>,
    merged_condition_: Condvar,
    mutex_: Mutex<()>,
    merge_unmerge_callback_: Mutex<Option<closure>>,
}

impl RefCountedThreadSafe for RasterThreadMerger {}

impl RasterThreadMerger {
    /// Upstream's private constructor, reached through MakeRefCounted.
    pub fn new(platform_queue_id: TaskQueueId, gpu_queue_id: TaskQueueId) -> RefPtr<Self> {
        Self::with_shared(
            make_ref_counted(SharedThreadMerger::new(platform_queue_id, gpu_queue_id)),
            platform_queue_id,
            gpu_queue_id,
        )
    }

    fn with_shared(
        shared_merger: RefPtr<SharedThreadMerger>,
        platform_queue_id: TaskQueueId,
        gpu_queue_id: TaskQueueId,
    ) -> RefPtr<Self> {
        make_ref_counted(RasterThreadMerger {
            platform_queue_id_: platform_queue_id,
            gpu_queue_id_: gpu_queue_id,
            shared_merger_: shared_merger,
            merged_condition_: Condvar::new(),
            mutex_: Mutex::new(()),
            merge_unmerge_callback_: Mutex::new(None),
        })
    }

    fn lock(&self) -> MutexGuard<'_, ()> {
        self.mutex_.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn id(&self) -> RasterThreadMergerId {
        self as *const RasterThreadMerger as usize
    }

    fn run_callback(&self) {
        let callback = self.merge_unmerge_callback_.lock().unwrap_or_else(|e| e.into_inner()).clone();
        if let Some(callback) = callback {
            callback.call();
        }
    }

    /// Merges the raster thread into platform thread for the duration of the
    /// lease term. Lease is managed by the caller by either calling
    /// `extend_lease_to` or `decrement_lease`.
    pub fn merge_with_lease(&self, lease_term: usize) {
        let _lock = self.lock();
        if self.task_queues_are_same() {
            return;
        }
        if !self.is_enabled_unsafe() {
            return;
        }
        fml_dcheck_at!(FILE, 62, "lease_term > 0", lease_term > 0, "lease_term should be positive.");

        if self.is_merged_unsafe() {
            self.merged_condition_.notify_one();
            return;
        }

        let success = self.shared_merger_.merge_with_lease(self.id(), lease_term);
        if success {
            self.run_callback();
        }

        self.merged_condition_.notify_one();
    }

    pub fn get_shared_raster_thread_merger(&self) -> &RefPtr<SharedThreadMerger> {
        &self.shared_merger_
    }

    /// Creates a new merger, sharing `parent_merger`'s inner merger when it
    /// merges the same pair of queues.
    pub fn create_or_share_thread_merger(
        parent_merger: &RefPtr<RasterThreadMerger>,
        platform_id: TaskQueueId,
        raster_id: TaskQueueId,
    ) -> RefPtr<RasterThreadMerger> {
        if parent_merger.as_bool()
            && parent_merger.platform_queue_id_ == platform_id
            && parent_merger.gpu_queue_id_ == raster_id
        {
            let shared_merger = parent_merger.get_shared_raster_thread_merger().clone();
            Self::with_shared(shared_merger, platform_id, raster_id)
        } else {
            Self::new(platform_id, raster_id)
        }
    }

    /// Un-merges the threads now if current caller is the last merged caller,
    /// and it resets the lease term to 0.
    pub fn un_merge_now_if_last_one(&self) {
        let _lock = self.lock();
        if self.task_queues_are_same() {
            return;
        }
        if !self.is_enabled_unsafe() {
            return;
        }
        let success = self.shared_merger_.un_merge_now_if_last_one(self.id());
        if success {
            self.run_callback();
        }
    }

    pub fn extend_lease_to(&self, lease_term: usize) {
        fml_dcheck_at!(FILE, 107, "lease_term > 0", lease_term > 0, "lease_term should be positive.");
        if self.task_queues_are_same() {
            return;
        }
        let _lock = self.lock();
        if !self.is_enabled_unsafe() {
            return;
        }
        self.shared_merger_.extend_lease_to(self.id(), lease_term);
    }

    /// Returns `kUnmergedNow` if the lease term has decremented to 0.
    pub fn decrement_lease(&self) -> RasterThreadStatus {
        if self.task_queues_are_same() {
            return RasterThreadStatus::kRemainsMerged;
        }
        let _lock = self.lock();
        if !self.is_merged_unsafe() {
            return RasterThreadStatus::kRemainsUnmerged;
        }
        if !self.is_enabled_unsafe() {
            return RasterThreadStatus::kRemainsMerged;
        }
        let unmerged_after_decrement = self.shared_merger_.decrement_lease(self.id());
        if unmerged_after_decrement {
            self.run_callback();
            return RasterThreadStatus::kUnmergedNow;
        }

        RasterThreadStatus::kRemainsMerged
    }

    pub fn is_merged(&self) -> bool {
        let _lock = self.lock();
        self.is_merged_unsafe()
    }

    /// Waits until the threads are merged.
    ///
    /// Must run on the platform task runner.
    pub fn wait_until_merged(&self) {
        if self.task_queues_are_same() {
            return;
        }
        fml_check_at!(FILE, 154, "IsOnPlatformThread()", self.is_on_platform_thread());
        let lock = self.lock();
        let _lock = self
            .merged_condition_
            .wait_while(lock, |_| !self.is_merged_unsafe())
            .unwrap_or_else(|e| e.into_inner());
    }

    /// Returns true if the current thread owns rasterizing.
    /// When the threads are merged, platform thread owns rasterizing.
    /// When un-merged, raster thread owns rasterizing.
    pub fn is_on_rasterizing_thread(&self) -> bool {
        let _lock = self.lock();
        if self.is_merged_unsafe() {
            self.is_on_platform_thread()
        } else {
            !self.is_on_platform_thread()
        }
    }

    /// Returns true if the current thread is the platform thread.
    pub fn is_on_platform_thread(&self) -> bool {
        MessageLoop::get_current_task_queue_id() == self.platform_queue_id_
    }

    /// Enables the thread merger.
    pub fn enable(&self) {
        let _lock = self.lock();
        self.shared_merger_.set_enabled_unsafe(true);
    }

    /// Disables the thread merger. Once disabled, any call to
    /// `merge_with_lease` or `un_merge_now_if_last_one` results in a noop.
    pub fn disable(&self) {
        let _lock = self.lock();
        self.shared_merger_.set_enabled_unsafe(false);
    }

    /// Whether the thread merger is enabled. By default, the thread merger is
    /// enabled. If false, calls to `merge_with_lease` or
    /// `un_merge_now_if_last_one` or `extend_lease_to` or `decrement_lease`
    /// results in a noop.
    pub fn is_enabled(&self) -> bool {
        let _lock = self.lock();
        self.is_enabled_unsafe()
    }

    /// Registers a callback that can be used to clean up global state right
    /// after the thread configuration has changed.
    ///
    /// For example, it can be used to clear the GL context so it can be used
    /// in the next task from a different thread.
    pub fn set_merge_unmerge_callback(&self, callback: closure) {
        *self.merge_unmerge_callback_.lock().unwrap_or_else(|e| e.into_inner()) = Some(callback);
    }

    fn is_merged_unsafe(&self) -> bool {
        self.task_queues_are_same() || self.shared_merger_.is_merged_unsafe()
    }

    fn is_enabled_unsafe(&self) -> bool {
        self.shared_merger_.is_enabled_unsafe()
    }

    fn task_queues_are_same(&self) -> bool {
        self.platform_queue_id_ == self.gpu_queue_id_
    }
}
