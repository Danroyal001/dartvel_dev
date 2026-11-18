// Port of flutter/fml/mapping_unittests.cc.

use super::mapping::*;

fn malloc(length: usize) -> Box<[u8]> {
    vec![0u8; length].into_boxed_slice()
}

#[test]
fn empty_contructor() {
    let mapping = MallocMapping::new();
    assert!(mapping.get_mapping().is_null());
    assert_eq!(0, mapping.get_size());
}

#[test]
fn not_empty_contructor() {
    let length = 10;
    let mapping = MallocMapping::from_box(malloc(length));
    assert!(!mapping.get_mapping().is_null());
    assert_eq!(length, mapping.get_size());
}

#[test]
fn move_constructor() {
    let length = 10;
    let mut mapping = MallocMapping::from_box(malloc(length));
    let moved = MallocMapping::take(&mut mapping);

    assert!(mapping.get_mapping().is_null());
    assert_eq!(0, mapping.get_size());
    assert!(!moved.get_mapping().is_null());
    assert_eq!(length, moved.get_size());
}

#[test]
fn copy() {
    let length = 10;
    let mut data = malloc(length);
    data.fill(0xac);
    let mapping = MallocMapping::from_box(data);
    // SAFETY: the mapping owns get_size() initialized bytes.
    let bytes = unsafe { std::slice::from_raw_parts(mapping.get_mapping(), mapping.get_size()) };
    let copied = MallocMapping::copy(bytes);

    assert_ne!(mapping.get_mapping(), copied.get_mapping());
    assert_eq!(mapping.get_size(), copied.get_size());
    // SAFETY: as above, for the copy.
    let copied_bytes = unsafe { std::slice::from_raw_parts(copied.get_mapping(), copied.get_size()) };
    assert_eq!(bytes, copied_bytes);
}

#[test]
fn release() {
    let length = 10;
    let mut mapping = MallocMapping::from_box(malloc(length));
    drop(mapping.release());
    assert!(mapping.get_mapping().is_null());
    assert_eq!(0, mapping.get_size());
}

#[test]
fn is_dont_need_safe() {
    let length = 10;
    let mapping = MallocMapping::from_box(malloc(length));
    assert!(!mapping.get_mapping().is_null());
    assert!(!mapping.is_dont_need_safe());
}

#[test]
fn copy_size_zero() {
    let ch = [b'a'];
    let mapping = MallocMapping::copy(&ch[..0]);
    assert_eq!(0, mapping.get_size());
}

// Not upstream's: an empty DataMapping has a null mapping (libc++'s empty
// vector has no buffer), which WriteAtomically refuses.
#[test]
fn empty_data_mapping_is_null() {
    assert!(DataMapping::new(Vec::new()).get_mapping().is_null());
    assert!(DataMapping::from_string("").get_mapping().is_null());
    assert!(!DataMapping::from_string("x").get_mapping().is_null());
}
