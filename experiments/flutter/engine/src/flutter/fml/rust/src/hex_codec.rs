// Port of flutter/fml/hex_codec.h and flutter/fml/hex_codec.cc.

const K_ENCODING: &[u8; 16] = b"0123456789abcdef";

pub fn hex_encode(input: impl AsRef<[u8]>) -> String {
    let input = input.as_ref();
    let mut result = String::with_capacity(input.len() * 2);
    for &b in input {
        result.push(K_ENCODING[(b >> 4) as usize] as char);
        result.push(K_ENCODING[(b & 0xF) as usize] as char);
    }
    result
}
