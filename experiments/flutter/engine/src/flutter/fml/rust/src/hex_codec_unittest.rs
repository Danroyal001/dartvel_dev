// Port of flutter/fml/hex_codec_unittest.cc.

use super::hex_codec::hex_encode;

#[test]
fn can_encode() {
    assert_eq!(hex_encode("hello"), "68656c6c6f");
    assert_eq!(hex_encode(""), "");
    assert_eq!(hex_encode("1"), "31");
    assert_eq!(hex_encode(b"\xFF\xFE\x00\x01"), "fffe0001");
}
