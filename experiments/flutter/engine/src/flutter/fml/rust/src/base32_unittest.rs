// Port of flutter/fml/base32_unittest.cc.

use super::base32::{base32_decode, base32_encode};

#[test]
fn can_encode() {
    for (input, expected) in [
        (&b"hello"[..], "NBSWY3DP"),
        (b"helLo", "NBSWYTDP"),
        (b"", ""),
        (b"1", "GE"),
        (b"helLo", "NBSWYTDP"),
        (b"\xff\xfe\x7f\x80\x81", "777H7AEB"),
    ] {
        let result = base32_encode(input);
        assert!(result.0);
        assert_eq!(result.1, expected);
    }
}

#[test]
fn can_encode_decode_strings() {
    // Upstream's "\0" literal makes a std::string of length zero.
    let strings: [&[u8]; 5] = [b"hello", b"helLo", b"", b"1", b""];
    for s in strings {
        let encode_result = base32_encode(s);
        assert!(encode_result.0);
        let decode_result = base32_decode(encode_result.1);
        assert!(decode_result.0);
        assert_eq!(s, &decode_result.1[..]);
    }
}

#[test]
fn decode_returns_false_for_invalide_input() {
    // "B" is invalid because it has a non-zero padding.
    for input in ["a", "1", "9", "B"] {
        let decode_result = base32_decode(input);
        assert!(!decode_result.0, "Base32Decode should return false on {input}");
    }
}

#[test]
fn can_decode_sksl_keys() {
    let inputs = [
        "CAZAAAACAAAAADQAAAABKAAAAAJQAAIA7777777777776EYAAEAP777777777777AAAAAABA\
         ABTAAAAAAAAAAAAAAABAAAAAGQAGGAA",
        "CAZAAAICAAAAAAAAAAADOAAAAAJQAAIA777777Y4AAKAAEYAAEAP777777777777EAAGMAAA\
         AAAAAAAAAAACQACNAAAAAAAAAAAAAAACAAAAAPAAMMAA",
        "CAZACAACAAAABAYACAAAAAAAAAJQAAIADQABIAH777777777777RQAAOAAAAAAAAAAAAAABE\
         AANQAAAAAAAAAAAAAAYAAJYAAAAAAAANAAAQAAAAAAAEAAAHAAAAAAAAAAAAAAANAAAQAAAA\
         AAAFIADKAAAAAAAAAAAAAAACAAAAAZAAMMAA",
    ];
    for input in inputs {
        let decode_result = base32_decode(input);
        assert!(decode_result.0, "Base32Decode should return true on {input}");
        let encode_result = base32_encode(&decode_result.1);
        assert!(encode_result.0);
        assert_eq!(encode_result.1, input);
    }
}
