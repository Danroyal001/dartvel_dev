// Port of flutter/fml/shared_thread_merger.h and
// flutter/fml/shared_thread_merger.cc.
//
// Upstream's "UnSafe" methods are called with the calling
// RasterThreadMerger's mutex held, not this object's, so two mergers that
// share this object read `lease_term_by_caller_` and `enabled_` concurrently
// with its writers (a data race). Here the map is read under this object's
// own mutex and `enabled_` is an atomic.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, MutexGuard};

use crate::memory::ref_counted::RefCountedThreadSafe;
use crate::message_loop_task_queues::MessageLoopTaskQueues;
use crate::task_queue_id::TaskQueueId;
use crate::{fml_check_at, fml_dcheck_at, fml_log_at};

const FILE: &str = "flutter/fml/shared_thread_merger.cc";

/// The address of the RasterThreadMerger calling in (`void*` upstream).
pub type RasterThreadMergerId = usize;

type Leases = BTreeMap<RasterThreadMergerId, usize>;

/// Instances of this class are shared between multiple RasterThreadMerger
/// instances, Most of the callings from RasterThreadMerger will be redirected
/// to this class with one more caller parameter.
pub struct SharedThreadMerger {
    owner_: TaskQueueId,
    subsumed_: TaskQueueId,
    task_queues_: &'static MessageLoopTaskQueues,
    mutex_: Mutex<Leases>,
    enabled_: AtomicBool,
}

impl RefCountedThreadSafe for SharedThreadMerger {}

impl SharedThreadMerger {
    pub fn new(owner: TaskQueueId, subsumed: TaskQueueId) -> Self {
        SharedThreadMerger {
            owner_: owner,
            subsumed_: subsumed,
            task_queues_: MessageLoopTaskQueues::get_instance(),
            mutex_: Mutex::new(Leases::new()),
            enabled_: AtomicBool::new(true),
        }
    }

    fn lock(&self) -> MutexGuard<'_, Leases> {
        self.mutex_.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// It's called by `RasterThreadMerger::merge_with_lease`.
    pub fn merge_with_lease(&self, caller: RasterThreadMergerId, lease_term: usize) -> bool {
        fml_dcheck_at!(FILE, 23, "lease_term > 0", lease_term > 0, "lease_term should be positive.");
        let mut lease_term_by_caller_ = self.lock();
        if Self::is_merged_locked(&lease_term_by_caller_) {
            return true;
        }
        let success = self.task_queues_.merge(self.owner_, self.subsumed_);
        fml_check_at!(
            FILE,
            29,
            "success",
            success,
            "Unable to merge the raster and platform threads."
        );
        // Save the lease term
        lease_term_by_caller_.insert(caller, lease_term);
        success
    }

    fn un_merge_now_locked(&self, lease_term_by_caller_: &Leases) -> bool {
        fml_check_at!(
            FILE,
            36,
            "IsAllLeaseTermsZeroUnSafe()",
            Self::is_all_lease_terms_zero_locked(lease_term_by_caller_),
            "all lease term records must be zero before calling UnMergeNowUnSafe()"
        );
        let success = self.task_queues_.unmerge(self.owner_, self.subsumed_);
        fml_check_at!(
            FILE,
            40,
            "success",
            success,
            "Unable to un-merge the raster and platform threads."
        );
        success
    }

    /// It's called by `RasterThreadMerger::un_merge_now_if_last_one`.
    pub fn un_merge_now_if_last_one(&self, caller: RasterThreadMergerId) -> bool {
        let mut lease_term_by_caller_ = self.lock();
        lease_term_by_caller_.remove(&caller);
        if lease_term_by_caller_.is_empty()
            || Self::is_all_lease_terms_zero_locked(&lease_term_by_caller_)
        {
            return self.un_merge_now_locked(&lease_term_by_caller_);
        }
        true
    }

    /// It's called by `RasterThreadMerger::decrement_lease`; returns whether
    /// the threads were un-merged.
    pub fn decrement_lease(&self, caller: RasterThreadMergerId) -> bool {
        let mut lease_term_by_caller_ = self.lock();
        match lease_term_by_caller_.get_mut(&caller) {
            Some(lease_term_ref) => {
                fml_check_at!(
                    FILE,
                    59,
                    "lease_term_ref > 0",
                    *lease_term_ref > 0,
                    "lease_term should always be positive when merged, lease_term={}",
                    *lease_term_ref
                );
                *lease_term_ref -= 1;
            }
            None => {
                fml_log_at!(
                    kLogWarning,
                    FILE,
                    64,
                    "The caller does not exist when calling DecrementLease(), ignored. This may happens after caller is erased in UnMergeNowIfLastOne(). caller={:#x}",
                    caller
                );
            }
        }
        if Self::is_all_lease_terms_zero_locked(&lease_term_by_caller_) {
            // Unmerge now because lease_term_ decreased to zero.
            self.un_merge_now_locked(&lease_term_by_caller_);
            return true;
        }
        false
    }

    /// It's called by `RasterThreadMerger::extend_lease_to`.
    pub fn extend_lease_to(&self, caller: RasterThreadMergerId, lease_term: usize) {
        fml_dcheck_at!(FILE, 79, "lease_term > 0", lease_term > 0, "lease_term should be positive.");
        let mut lease_term_by_caller_ = self.lock();
        fml_dcheck_at!(
            FILE,
            81,
            "IsMergedUnSafe()",
            Self::is_merged_locked(&lease_term_by_caller_),
            "should be merged state when calling this method"
        );
        lease_term_by_caller_.insert(caller, lease_term);
    }

    /// It's called by `RasterThreadMerger::is_merged_unsafe`.
    pub fn is_merged_unsafe(&self) -> bool {
        Self::is_merged_locked(&self.lock())
    }

    /// It's called by `RasterThreadMerger::is_enabled_unsafe`.
    pub fn is_enabled_unsafe(&self) -> bool {
        self.enabled_.load(Ordering::SeqCst)
    }

    /// It's called by `RasterThreadMerger::enable` or
    /// `RasterThreadMerger::disable`.
    pub fn set_enabled_unsafe(&self, enabled: bool) {
        self.enabled_.store(enabled, Ordering::SeqCst);
    }

    fn is_merged_locked(lease_term_by_caller_: &Leases) -> bool {
        !Self::is_all_lease_terms_zero_locked(lease_term_by_caller_)
    }

    fn is_all_lease_terms_zero_locked(lease_term_by_caller_: &Leases) -> bool {
        lease_term_by_caller_.values().all(|&lease| lease == 0)
    }
}
