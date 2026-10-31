// Not an upstream file: the module root for flutter/fml/memory.
//
// The C++ to Rust mapping (Track E): an `fml::RefCountedThreadSafe<T>` object
// lives in an `Arc<T>`, `fml::RefPtr<T>` is a nullable `Arc` (ref_ptr.rs),
// and `fml::WeakPtr<T>` is a `Weak` plus upstream's invalidation flag and
// thread check (weak_ptr.rs). Arc's count is RefCountedThreadSafeBase's,
// with the same orderings (relaxed increment, release decrement, acquire
// fence before destruction).

pub mod ref_counted;
pub mod ref_ptr;
pub mod task_runner_checker;
pub mod thread_checker;
pub mod weak_ptr;
pub mod weak_ptr_internal;

#[cfg(test)]
mod ref_counted_unittest;
#[cfg(test)]
mod task_runner_checker_unittest;
#[cfg(test)]
mod weak_ptr_unittest;
