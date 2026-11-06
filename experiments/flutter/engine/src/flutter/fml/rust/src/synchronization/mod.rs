// Not an upstream file: the module root for flutter/fml/synchronization.

pub mod atomic_object;
pub mod count_down_latch;
pub mod semaphore;
pub mod sync_switch;
pub mod waitable_event;

#[cfg(test)]
mod count_down_latch_unittests;
#[cfg(test)]
mod semaphore_unittest;
#[cfg(test)]
mod sync_switch_unittest;
#[cfg(test)]
mod waitable_event_unittest;
