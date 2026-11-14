// Port of pkg/_fe_analyzer_shared/test/keyword_state_test.dart.
//
// Upstream compares the table against the older KeywordState
// implementation the test file carries. That implementation's answer for
// every state is "the keyword whose lexeme is the characters read so far,
// and null once no keyword starts with them", so this compares the table
// against that rule directly, for every keyword prefix and every next
// character in $A..$z, as upstream does.

use fe_analyzer_shared::scanner::characters::{C_A, C_z};
use fe_analyzer_shared::scanner::keyword_state::KeywordStateHelper;
use fe_analyzer_shared::scanner::token::Keyword;

fn expected(prefix: &str) -> (bool, Option<&'static str>) {
    let is_null = !Keyword::values
        .iter()
        .any(|k| k.lexeme().starts_with(prefix));
    let keyword = Keyword::values
        .iter()
        .find(|k| k.lexeme() == prefix)
        .map(|k| k.lexeme());
    (is_null, keyword)
}

#[test]
fn keyword_state_matches_keyword_prefixes() {
    for keyword in Keyword::values {
        let lexeme = keyword.lexeme();
        let mut state = KeywordStateHelper::table();
        for j in 0..lexeme.len() {
            let c = lexeme.as_bytes()[j] as i32;
            state = state.next(c);
            let prefix = &lexeme[..=j];
            assert_eq!(
                state.keyword().map(|k| k.lexeme()),
                expected(prefix).1,
                "{prefix}"
            );

            // What if we were to take any (other) character?
            for k in C_A..C_z {
                let state_prime = state.next(k);
                let prefix_prime = format!("{prefix}{}", k as u8 as char);
                let (is_null, keyword) = expected(&prefix_prime);
                assert_eq!(state_prime.is_null(), is_null, "{prefix_prime}");
                if !is_null {
                    assert_eq!(
                        state_prime.keyword().map(|k| k.lexeme()),
                        keyword,
                        "{prefix_prime}"
                    );
                }
            }
        }
        assert_eq!(state.keyword().map(|k| k.lexeme()), Some(lexeme));
    }
}
