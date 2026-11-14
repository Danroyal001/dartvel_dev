// Port of flutter/fml/unique_fd.h and flutter/fml/unique_fd.cc (the POSIX
// branch), with `UniqueDir` (a `DIR*`, freed with closedir). The Windows
// branch (HANDLEs and the directory cache) is not ported.

use crate::unique_object::{UniqueObject, UniqueObjectTraits};

pub mod internal {
    pub mod os_unix {
        use super::super::*;
        use crate::platform::posix::libc::{DIR, closedir};

        // SAFETY: declarations only, each matching its prototype in <unistd.h>
        // for the LP64 Linux/Apple targets this crate builds for; every call
        // below is in its own unsafe block that says why it is sound.
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

        #[derive(Clone, Copy, Debug, Default)]
        pub struct UniqueDirTraits;

        impl UniqueObjectTraits for UniqueDirTraits {
            type T = *mut DIR;

            fn invalid_value() -> *mut DIR {
                std::ptr::null_mut()
            }

            fn is_valid(value: *mut DIR) -> bool {
                !value.is_null()
            }

            fn free(&mut self, dir: *mut DIR) {
                // SAFETY: `dir` came from opendir or fdopendir (the only way a
                // UniqueDir is filled) and is owned by this UniqueDir, which
                // never frees it twice; closedir also closes its descriptor.
                unsafe {
                    closedir(dir);
                }
            }
        }
    }
}

pub type UniqueFD = UniqueObject<internal::os_unix::UniqueFDTraits>;
pub type UniqueDir = UniqueObject<internal::os_unix::UniqueDirTraits>;
