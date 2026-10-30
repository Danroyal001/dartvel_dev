// Port of flutter/fml/closure.h (the `closure` alias; ScopedCleanupClosure is
// not ported yet).

use std::sync::Arc;

/// `std::function<void()>`: a copyable callable. Upstream's empty
/// std::function is `Option<closure>` where it can occur.
#[allow(non_camel_case_types)]
pub type closure = Arc<dyn Fn() + Send + Sync>;
