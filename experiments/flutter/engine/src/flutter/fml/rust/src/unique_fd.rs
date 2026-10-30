// Port of flutter/fml/unique_fd.h and flutter/fml/unique_fd.cc (the POSIX
// branch). `UniqueDir` (`DIR*`, freed with closedir) waits for the port of
// `file`, its only user; the Windows branch (HANDLEs and the directory cache)
// is not ported.

use crate::unique_object::{UniqueObject, UniqueObjectTraits};

pub mod internal {
    pub mod os_unix {
        use super::super::*;

        unsafe extern "C" {
            fn close(fd: i32) -> i32;
        }

        #[derive(Clone, Copy, Debug, Default)]
        pub struct UniqueFDTraits;

        impl UniqueObjectTraits for UniqueFDTraits {
            type T = i32;

            fn invalid_value() -> i32 {
                -1
            }

            fn is_valid(value: i32) -> bool {
                value >= 0
            }

            fn free(&mut self, fd: i32) {
                // SAFETY: close takes the descriptor by value and touches no
                // memory of ours. The UniqueFD owns `fd` (it is never freed
                // twice: the owner resets to the invalid value after freeing),
                // so no other owner's descriptor is closed.
                unsafe {
                    close(fd);
                }
            }
        }
    }
}

pub type UniqueFD = UniqueObject<internal::os_unix::UniqueFDTraits>;
