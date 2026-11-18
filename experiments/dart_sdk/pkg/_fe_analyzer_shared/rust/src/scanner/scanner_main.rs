// Port of lib/src/scanner/scanner_main.dart.
//
// `const bool.fromEnvironment(...)` defaults become the environment
// variables of the same names, set to `true`.

use std::path::PathBuf;
use std::rc::Rc;
use std::time::Instant;

use super::io::read_bytes_from_file_sync;
use super::scanner::scan;
use super::token::{TokenId, TokenStore};

pub fn scan_all(files: &[(PathBuf, Rc<[u8]>)], verbose: bool, verify: bool) {
    let sw = Instant::now();
    let mut byte_count: i64 = 0;
    for (uri, bytes) in files {
        let result = scan(bytes.clone(), None, false, || None, true);
        if verbose {
            print_tokens(&result.store, result.tokens);
        }
        if verify {
            verify_error_tokens(&result.store, result.tokens, uri);
        }
        byte_count += bytes.len() as i64 - 1;
    }
    let elapsed = sw.elapsed();
    println!("Scanning files took: {elapsed:?}");
    println!(
        "Bytes/ms: {}",
        byte_count as f64 / elapsed.as_millis() as f64
    );
}

pub fn print_tokens(store: &TokenStore, mut token: TokenId) {
    while !store.is_eof(token) {
        println!(
            "{}: {}",
            store.char_offset(token),
            token_to_string(store, token)
        );
        token = store.next(token);
    }
}

/// `Token.toString()`: the lexeme, or for an error token its class's
/// `toString`.
fn token_to_string(store: &TokenStore, token: TokenId) -> String {
    use super::token::TokenRuntimeType::*;
    let runtime_type = store.runtime_type(token);
    match runtime_type {
        EncodingErrorToken => "EncodingErrorToken()".to_string(),
        NonAsciiIdentifierToken | NonAsciiWhitespaceToken | AsciiControlCharacterToken => {
            format!(
                "{}({})",
                runtime_type.name(),
                store.character(token).unwrap()
            )
        }
        UnsupportedOperator => {
            format!(
                "UnsupportedOperator({})",
                store.lexeme_string(store.unsupported_operator_token(token))
            )
        }
        UnterminatedString => {
            format!(
                "UnterminatedString({})",
                String::from_utf16_lossy(store.start(token).unwrap())
            )
        }
        UnterminatedToken => format!("UnterminatedToken({})", store.error_code(token)),
        UnmatchedToken => format!(
            "UnmatchedToken({})",
            store.lexeme_string(store.begin(token))
        ),
        _ => store.lexeme_string(token),
    }
}

/// Check that all error tokens come at the start of the stream.
pub fn verify_error_tokens(store: &TokenStore, first_token: TokenId, uri: &std::path::Path) {
    let mut token = first_token;
    // Skip over all error tokens.
    while store.runtime_type(token).is_error_token() {
        token = store.next(token);
    }

    // Assert no error tokens in the remaining tokens.
    while !store.is_eof(token) {
        if store.runtime_type(token).is_error_token() {
            println!(
                "Found out-of-order ErrorTokens when scanning:\n  {}",
                uri.display()
            );

            // Rescan to find token before error token.
            let error_token = token;
            let mut start = first_token;
            let mut count = 0;
            token = first_token;
            while token != error_token {
                token = store.next(token);
                if count < 10 {
                    count += 1;
                } else {
                    start = store.next(start);
                }
            }

            // Print tokens before and after the error token.
            count = 0;
            token = start;
            while count < 20 && !store.is_eof(token) {
                println!(
                    "{}: {}",
                    store.char_offset(token),
                    token_to_string(store, token)
                );
                token = store.next(token);
                count += 1;
            }
            panic!(
                "Out of order ErrorToken: {}",
                token_to_string(store, error_token)
            );
        }
        token = store.next(token);
    }
}

pub fn main_entry_point(arguments: &[String]) {
    let mut files: Vec<(PathBuf, Rc<[u8]>)> = Vec::new();
    let sw = Instant::now();
    let mut verbose = std::env::var("printTokens").as_deref() == Ok("true");
    let mut verify = std::env::var("verifyErrorTokens").as_deref() == Ok("true");
    for arg in arguments {
        if arg.starts_with("--") {
            if arg == "--print-tokens" {
                verbose = true;
            } else if arg == "--verify-error-tokens" {
                verify = true;
            } else {
                println!("Unrecognized option: {arg}");
            }
            continue;
        }
        let uri = std::path::absolute(arg).expect("absolute path");
        let bytes = read_bytes_from_file_sync(&uri).expect("read file");
        files.push((uri, Rc::from(bytes)));
    }
    println!("Reading files took: {:?}", sw.elapsed());
    scan_all(&files, verbose, verify);
}
