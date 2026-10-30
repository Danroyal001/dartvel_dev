// Port of flutter/fml/closure.h.

use std::sync::Arc;

/// `std::function<void()>`: a copyable callable. Upstream's empty
/// std::function is `Option<closure>` where it can occur.
#[allow(non_camel_case_types)]
pub type closure = Arc<dyn Fn() + Send + Sync>;

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
            closure();
        }
    }
}

impl Drop for ScopedCleanupClosure {
    fn drop(&mut self) {
        self.reset();
    }
}
