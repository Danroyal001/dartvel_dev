// Port of lib/src/scanner/internal_utils.dart.

use super::characters::*;

#[inline(always)]
pub fn is_identifier_char(next: i32, allow_dollar: bool) -> bool {
    (C_a <= next && next <= C_z)
        || (C_A <= next && next <= C_Z)
        || (C_0 <= next && next <= C_9)
        || next == C_UNDERSCORE
        || (next == C_DOLLAR && allow_dollar)
}

/// Upstream spells this table out as 256 literals; it is the same predicate
/// as [is_identifier_char] with `allow_dollar` for every byte, built at
/// compile time.
const IDENTIFIER_CHAR_ALLOW_DOLLAR_TABLE: [bool; 256] = {
    let mut table = [false; 256];
    let mut i = 0;
    while i < 256 {
        let c = i as i32;
        table[i] = (C_a <= c && c <= C_z)
            || (C_A <= c && c <= C_Z)
            || (C_0 <= c && c <= C_9)
            || c == C_UNDERSCORE
            || c == C_DOLLAR;
        i += 1;
    }
    table
};

/// [next] must be a byte (0..=255), as it is in the Utf8BytesScanner.
#[inline(always)]
pub fn is_identifier_char_allow_dollar_table_lookup(next: i32) -> bool {
    IDENTIFIER_CHAR_ALLOW_DOLLAR_TABLE[next as usize]
}
