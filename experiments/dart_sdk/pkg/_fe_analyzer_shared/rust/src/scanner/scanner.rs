// Port of lib/src/scanner/scanner.dart.
#![allow(non_upper_case_globals)]
//
// `abstract class Scanner` is the interface both scanners implement; here
// both are `AbstractScanner<S>`, so its members are that type's.

use std::rc::Rc;

use super::abstract_scanner::{
    AbstractScanner, LanguageVersionChanged, ScannerConfiguration, ScannerSubclass,
};
use super::string_scanner::StringScanner;
use super::token::{TokenId, TokenStore};
use super::utf8_bytes_scanner::Utf8BytesScanner;

pub const unicodeReplacementCharacter: i32 = 0xFFFD;

/// The result of a scan: the first token, line starts and errors. The tokens
/// live in [ScannerResult::store].
pub struct ScannerResult {
    pub tokens: TokenId,
    pub line_starts: Vec<u32>,
    pub has_errors: bool,
    pub store: TokenStore,
}

impl ScannerResult {
    fn from_scanner<S: ScannerSubclass>(
        tokens: TokenId,
        scanner: AbstractScanner<S>,
    ) -> ScannerResult {
        ScannerResult {
            tokens,
            line_starts: scanner.line_starts.array,
            has_errors: scanner.has_errors,
            store: scanner.store,
        }
    }
}

/// Scan/tokenize the given UTF8 [bytes], stopping after the directives.
pub fn scan_directives(
    bytes: Rc<[u8]>,
    configuration: Option<ScannerConfiguration>,
    language_version_changed: Option<LanguageVersionChanged>,
) -> ScannerResult {
    let mut scanner = Utf8BytesScanner::new(
        bytes,
        configuration,
        /* includeComments = */ false,
        language_version_changed,
        /* allowLazyStrings = */ false,
    );
    let tokens = scanner.tokenize_directives();
    ScannerResult::from_scanner(tokens, scanner)
}

/// Scan/tokenize the given UTF8 [bytes].
///
/// Upstream's `languageVersionChanged` callback is shared by both scans when
/// it rescans for curly-bracket recovery; a boxed `FnMut` cannot be, so the
/// rescan takes a second callback from [language_version_changed_factory].
pub fn scan(
    bytes: Rc<[u8]>,
    configuration: Option<ScannerConfiguration>,
    include_comments: bool,
    mut language_version_changed_factory: impl FnMut() -> Option<LanguageVersionChanged>,
    allow_lazy_strings: bool,
) -> ScannerResult {
    let mut scanner = Utf8BytesScanner::new(
        bytes.clone(),
        configuration,
        include_comments,
        language_version_changed_factory(),
        allow_lazy_strings,
    );
    let mut tokens = scanner.tokenize();
    if scanner.has_errors
        && let Some(offset_for_curly_bracket_recovery_start) =
            scanner.get_offset_for_curly_bracket_recovery_start()
    {
        scanner = Utf8BytesScanner::new(
            bytes,
            configuration,
            include_comments,
            language_version_changed_factory(),
            allow_lazy_strings,
        );
        scanner.offset_for_curly_bracket_recovery_start =
            Some(offset_for_curly_bracket_recovery_start);
        tokens = scanner.tokenize();
    }
    ScannerResult::from_scanner(tokens, scanner)
}

/// Scan/tokenize the given [source], as UTF-16 code units.
pub fn scan_string(
    source: Rc<[u16]>,
    configuration: Option<ScannerConfiguration>,
    include_comments: bool,
    mut language_version_changed_factory: impl FnMut() -> Option<LanguageVersionChanged>,
) -> ScannerResult {
    let mut scanner = StringScanner::new(
        source.clone(),
        configuration,
        include_comments,
        language_version_changed_factory(),
    );
    let mut tokens = scanner.tokenize();
    if scanner.has_errors
        && let Some(offset_for_curly_bracket_recovery_start) =
            scanner.get_offset_for_curly_bracket_recovery_start()
    {
        scanner = StringScanner::new(
            source,
            configuration,
            include_comments,
            language_version_changed_factory(),
        );
        scanner.offset_for_curly_bracket_recovery_start =
            Some(offset_for_curly_bracket_recovery_start);
        tokens = scanner.tokenize();
    }
    ScannerResult::from_scanner(tokens, scanner)
}
