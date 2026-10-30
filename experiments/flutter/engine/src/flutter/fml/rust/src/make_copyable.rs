// Port of flutter/fml/make_copyable.h.
//
// Upstream wraps a move-only lambda in a ref-counted holder so that it can be
// stored in a `std::function`, which must be copyable. A `closure` copies
// its captures as `std::function` does, so a capture that cannot be cloned
// is shared instead: `closure::shared` does that for a `closure`, and
// `CopyableLambda` for any other `Fn` that has to be cloned, sharing one
// instance of the lambda as upstream's copies share one `Impl`.

use std::sync::Arc;

pub mod internal {
    use super::*;

    pub struct CopyableLambda<T> {
        impl_: Arc<T>,
    }

    impl<T> Clone for CopyableLambda<T> {
        fn clone(&self) -> Self {
            CopyableLambda { impl_: self.impl_.clone() }
        }
    }

    impl<T> CopyableLambda<T> {
        pub fn new(func: T) -> Self {
            CopyableLambda { impl_: Arc::new(func) }
        }

        /// `operator()`: calls the shared lambda with `args` (pass a tuple, or
        /// `()`, for several or none).
        pub fn call<A, R>(&self, args: A) -> R
        where
            T: Fn(A) -> R,
        {
            (self.impl_)(args)
        }

        /// The shared lambda, for calling with any arity.
        pub fn func(&self) -> &T {
            &self.impl_
        }
    }
}

/// Makes a lambda copyable by sharing it.
pub fn make_copyable<T>(lambda: T) -> internal::CopyableLambda<T> {
    internal::CopyableLambda::new(lambda)
}
