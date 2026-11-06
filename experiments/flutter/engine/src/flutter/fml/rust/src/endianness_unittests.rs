// Port of flutter/fml/endianness_unittests.cc.

use super::endianness::*;

#[test]
fn byte_swap_test() {
    assert_eq!(byte_swap::<i16>(0x1122), 0x2211);
    assert_eq!(byte_swap::<i32>(0x11223344), 0x44332211);
    assert_eq!(byte_swap::<u64>(0x1122334455667788), 0x8877665544332211);
}

#[test]
fn big_endian_to_arch_test() {
    let expected: u32 = if cfg!(target_endian = "little") { 0x44332211 } else { 0x11223344 };
    assert_eq!(big_endian_to_arch(0x11223344u32), expected);
}

#[test]
fn little_endian_to_arch_test() {
    let expected: u32 = if cfg!(target_endian = "little") { 0x11223344 } else { 0x44332211 };
    assert_eq!(little_endian_to_arch(0x11223344u32), expected);
}
