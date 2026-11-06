// Port of lib/src/scanner/string_canonicalizer.dart.
//
// Upstream keeps a cache so that equal lexemes share one `String` instance.
// That is an identity optimization with no observable effect on values. In
// this port a token's lexeme is a range into the source (see
// token.rs, `Lexeme`), so equal lexemes already share storage and the cache
// (`_StringCanonicalizer`, `clearStringCanonicalizationCache`,
// `pruneStringCanonicalizationCache`) has nothing to do. What carries over
// is the decoding, which decides the text of every lexeme.

/// `decodeString`: the UTF-16 text of `bytes[start..end]`.
///
/// When `is_ascii` is true, upstream uses `String.fromCharCodes`, which maps
/// each byte to the code unit of the same value (Latin-1), whether or not the
/// bytes really are ASCII. Otherwise it uses `Utf8Decoder(allowMalformed:
/// true)`; see [decode_utf8_allow_malformed].
pub fn decode_string(bytes: &[u8], start: usize, end: usize, is_ascii: bool) -> Vec<u16> {
    if is_ascii {
        bytes[start..end].iter().map(|&b| b as u16).collect()
    } else {
        decode_utf8_allow_malformed(&bytes[start..end])
    }
}

/// `const Utf8Decoder(allowMalformed: true).convert(bytes)` as UTF-16.
///
/// Dart's decoder skips a byte order mark at the start of the converted
/// range, and replaces each maximal ill-formed subsequence with U+FFFD, which
/// is what `String::from_utf8_lossy` does too.
pub fn decode_utf8_allow_malformed(bytes: &[u8]) -> Vec<u16> {
    let bytes = strip_bom(bytes);
    match std::str::from_utf8(bytes) {
        Ok(s) => s.encode_utf16().collect(),
        Err(_) => String::from_utf8_lossy(bytes).encode_utf16().collect(),
    }
}

/// The UTF-16 length of [decode_utf8_allow_malformed]`(bytes)`, without
/// building the string.
pub fn utf16_length_of_utf8_allow_malformed(bytes: &[u8]) -> usize {
    let bytes = strip_bom(bytes);
    match std::str::from_utf8(bytes) {
        Ok(s) => utf16_length(s),
        Err(_) => utf16_length(&String::from_utf8_lossy(bytes)),
    }
}

fn utf16_length(s: &str) -> usize {
    // Every scalar takes one code unit, plus one more above U+FFFF, which is
    // exactly the scalars whose UTF-8 form starts with 0xF0..=0xF4.
    s.chars().count() + s.bytes().filter(|&b| b >= 0xF0).count()
}

fn strip_bom(bytes: &[u8]) -> &[u8] {
    if bytes.len() >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
        &bytes[3..]
    } else {
        bytes
    }
}
