// Port of lib/src/scanner/keyword_state.dart.
#![allow(non_upper_case_globals)]

use std::sync::OnceLock;

use super::characters::C_A;
use super::token::Keyword;

/// `extension type KeywordState._(int _offset)`: an offset into the table.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct KeywordState(u32);

impl KeywordState {
    pub const block_size: u32 = 59;

    #[inline(always)]
    pub fn is_null(self) -> bool {
        self.0 == 0
    }

    #[inline(always)]
    pub fn keyword(self) -> Option<&'static Keyword> {
        let keyword_index_plus_one = KeywordStateHelper::table_data()[self.0 as usize];
        if keyword_index_plus_one == 0 {
            return None;
        }
        Some(Keyword::values[keyword_index_plus_one as usize - 1])
    }

    /// [next] is a character in `$A..=$z`, as the scanner guarantees.
    #[inline(always)]
    pub fn next(self, next: i32) -> KeywordState {
        KeywordState(
            KeywordStateHelper::table_data()[(self.0 as i32 + next - C_A + 1) as usize] as u32,
        )
    }
}

pub struct KeywordStateHelper;

static TABLE: OnceLock<Box<[u16]>> = OnceLock::new();

impl KeywordStateHelper {
    #[inline(always)]
    fn table_data() -> &'static [u16] {
        TABLE.get_or_init(KeywordStateHelper::create_table)
    }

    /// `KeywordStateHelper.table`: the start state.
    #[inline(always)]
    pub fn table() -> KeywordState {
        KeywordStateHelper::table_data();
        KeywordState(KeywordState::block_size)
    }

    fn create_table() -> Box<[u16]> {
        let block_size = KeywordState::block_size as usize;
        let mut table = vec![0u16; 297 * block_size];
        let mut next_empty = 2 * block_size;
        for (i, keyword) in Keyword::values.iter().enumerate() {
            let lexeme = keyword.lexeme();
            let mut offset = block_size;
            for c in lexeme.bytes() {
                let char_offset = c as usize - C_A as usize;
                let link = table[offset + 1 + char_offset] as usize;
                if link == 0 {
                    table[offset + 1 + char_offset] = next_empty as u16;
                    offset = next_empty;
                    next_empty += block_size;
                } else {
                    offset = link;
                }
            }
            table[offset] = (i + 1) as u16;
        }
        assert_eq!(next_empty, table.len());
        table.into_boxed_slice()
    }
}
