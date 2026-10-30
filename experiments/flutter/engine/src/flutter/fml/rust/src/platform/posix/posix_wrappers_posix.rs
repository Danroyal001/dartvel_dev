// Port of flutter/fml/platform/posix/posix_wrappers_posix.cc.
//
// Upstream returns a malloc'd copy the caller frees; the copy here is a
// CString, freed when dropped.

use std::ffi::{CStr, CString};

pub fn strdup(str1: &CStr) -> CString {
    str1.to_owned()
}
