// Port of lib/src/scanner/characters.dart.
//
// Dart names these constants `$X`; Rust has no `$` in identifiers, so `$X`
// is `C_X` here, `$$` is `C_DOLLAR` and `$_` is `C_UNDERSCORE`.
#![allow(non_upper_case_globals)]

pub const C_EOF: i32 = -1;
pub const C_STX: i32 = 2;
pub const C_BS: i32 = 8;
pub const C_TAB: i32 = 9;
pub const C_LF: i32 = 10;
pub const C_VTAB: i32 = 11;
pub const C_FF: i32 = 12;
pub const C_CR: i32 = 13;
pub const C_SPACE: i32 = 32;
pub const C_BANG: i32 = 33;
pub const C_DQ: i32 = 34;
pub const C_HASH: i32 = 35;
pub const C_DOLLAR: i32 = 36;
pub const C_PERCENT: i32 = 37;
pub const C_AMPERSAND: i32 = 38;
pub const C_SQ: i32 = 39;
pub const C_OPEN_PAREN: i32 = 40;
pub const C_CLOSE_PAREN: i32 = 41;
pub const C_STAR: i32 = 42;
pub const C_PLUS: i32 = 43;
pub const C_COMMA: i32 = 44;
pub const C_MINUS: i32 = 45;
pub const C_PERIOD: i32 = 46;
pub const C_SLASH: i32 = 47;
pub const C_0: i32 = 48;
pub const C_1: i32 = 49;
pub const C_2: i32 = 50;
pub const C_3: i32 = 51;
pub const C_4: i32 = 52;
pub const C_5: i32 = 53;
pub const C_6: i32 = 54;
pub const C_7: i32 = 55;
pub const C_8: i32 = 56;
pub const C_9: i32 = 57;
pub const C_COLON: i32 = 58;
pub const C_SEMICOLON: i32 = 59;
pub const C_LT: i32 = 60;
pub const C_EQ: i32 = 61;
pub const C_GT: i32 = 62;
pub const C_QUESTION: i32 = 63;
pub const C_AT: i32 = 64;
pub const C_A: i32 = 65;
pub const C_B: i32 = 66;
pub const C_C: i32 = 67;
pub const C_D: i32 = 68;
pub const C_E: i32 = 69;
pub const C_F: i32 = 70;
pub const C_G: i32 = 71;
pub const C_H: i32 = 72;
pub const C_I: i32 = 73;
pub const C_J: i32 = 74;
pub const C_K: i32 = 75;
pub const C_L: i32 = 76;
pub const C_M: i32 = 77;
pub const C_N: i32 = 78;
pub const C_O: i32 = 79;
pub const C_P: i32 = 80;
pub const C_Q: i32 = 81;
pub const C_R: i32 = 82;
pub const C_S: i32 = 83;
pub const C_T: i32 = 84;
pub const C_U: i32 = 85;
pub const C_V: i32 = 86;
pub const C_W: i32 = 87;
pub const C_X: i32 = 88;
pub const C_Y: i32 = 89;
pub const C_Z: i32 = 90;
pub const C_OPEN_SQUARE_BRACKET: i32 = 91;
pub const C_BACKSLASH: i32 = 92;
pub const C_CLOSE_SQUARE_BRACKET: i32 = 93;
pub const C_CARET: i32 = 94;
pub const C_UNDERSCORE: i32 = 95;
pub const C_BACKPING: i32 = 96;
pub const C_a: i32 = 97;
pub const C_b: i32 = 98;
pub const C_c: i32 = 99;
pub const C_d: i32 = 100;
pub const C_e: i32 = 101;
pub const C_f: i32 = 102;
pub const C_g: i32 = 103;
pub const C_h: i32 = 104;
pub const C_i: i32 = 105;
pub const C_j: i32 = 106;
pub const C_k: i32 = 107;
pub const C_l: i32 = 108;
pub const C_m: i32 = 109;
pub const C_n: i32 = 110;
pub const C_o: i32 = 111;
pub const C_p: i32 = 112;
pub const C_q: i32 = 113;
pub const C_r: i32 = 114;
pub const C_s: i32 = 115;
pub const C_t: i32 = 116;
pub const C_u: i32 = 117;
pub const C_v: i32 = 118;
pub const C_w: i32 = 119;
pub const C_x: i32 = 120;
pub const C_y: i32 = 121;
pub const C_z: i32 = 122;
pub const C_OPEN_CURLY_BRACKET: i32 = 123;
pub const C_BAR: i32 = 124;
pub const C_CLOSE_CURLY_BRACKET: i32 = 125;
pub const C_TILDE: i32 = 126;
pub const C_DEL: i32 = 127;
pub const C_NBSP: i32 = 160;
pub const C_LS: i32 = 0x2028;
pub const C_PS: i32 = 0x2029;
pub const C_FIRST_SURROGATE: i32 = 0xd800;
pub const C_LAST_SURROGATE: i32 = 0xdfff;
pub const C_LAST_CODE_POINT: i32 = 0x10ffff;

pub fn is_digit(character_code: i32) -> bool {
    C_0 <= character_code && character_code <= C_9
}

pub fn is_hex_digit(mut character_code: i32) -> bool {
    if character_code <= C_9 {
        return C_0 <= character_code;
    }
    character_code |= C_a ^ C_A;
    C_a <= character_code && character_code <= C_f
}

pub fn hex_digit_value(hex_digit: i32) -> i32 {
    debug_assert!(is_hex_digit(hex_digit));
    if hex_digit <= C_9 {
        return hex_digit - C_0;
    }
    (hex_digit | (C_a ^ C_A)) - (C_a - 10)
}
