// What the syntax check answers for single sources (not a ported file).

use dartvel_syntax::{
    DEEPEST_NESTING, DeferReason, LARGEST_SOURCE_BYTES, SyntaxDiagnostic, SyntaxOutcome,
    check_source_bytes, deepest_nesting, escape_field, result_lines,
};

#[test]
fn a_source_that_parses_is_clean() {
    let source = "import 'dart:io';\n\nvoid main() {\n  stdout.writeln('hello');\n}\n";
    assert_eq!(check_source_bytes(source.as_bytes()), SyntaxOutcome::Clean);
}

#[test]
fn an_empty_source_is_clean() {
    assert_eq!(check_source_bytes(b""), SyntaxOutcome::Clean);
}

#[test]
fn a_missing_semicolon_is_flagged_where_the_analyzer_places_it() {
    let source = "void main() {\n  var count = 1\n}\n";
    let SyntaxOutcome::Flagged(diagnostics) = check_source_bytes(source.as_bytes()) else {
        panic!("a missing semicolon was not flagged");
    };
    assert_eq!(
        diagnostics,
        vec![SyntaxDiagnostic {
            unique_name: "expected_token".to_string(),
            offset: 28,
            length: 1,
            message: "Expected to find ';'.".to_string(),
        }]
    );
}

#[test]
fn offsets_count_utf16_code_units_as_dart_does() {
    // The emoji is two code units in Dart and four bytes in the file.
    let source = "var face = '\u{1F600}'\n";
    let SyntaxOutcome::Flagged(diagnostics) = check_source_bytes(source.as_bytes()) else {
        panic!("a missing semicolon was not flagged");
    };
    assert_eq!(diagnostics[0].offset, 11);
    assert_eq!(diagnostics[0].length, 4);
}

#[test]
fn bytes_that_are_not_utf8_are_left_to_dart() {
    assert_eq!(
        check_source_bytes(b"var name = '\xff\xfe';\n"),
        SyntaxOutcome::Deferred(DeferReason::NotUtf8)
    );
}

#[test]
fn a_byte_order_mark_is_left_to_dart() {
    assert_eq!(
        check_source_bytes(b"\xEF\xBB\xBFvoid main() {}\n"),
        SyntaxOutcome::Deferred(DeferReason::ByteOrderMark)
    );
}

#[test]
fn a_source_over_the_size_limit_is_left_to_dart() {
    let oversized = vec![b' '; LARGEST_SOURCE_BYTES + 1];
    assert_eq!(
        check_source_bytes(&oversized),
        SyntaxOutcome::Deferred(DeferReason::TooLarge)
    );
}

#[test]
fn result_lines_carry_the_file_number_and_nothing_that_breaks_a_line() {
    assert_eq!(
        result_lines(3, &SyntaxOutcome::Clean, true),
        vec!["clean\t3"]
    );
    assert_eq!(
        result_lines(4, &SyntaxOutcome::Deferred(DeferReason::ParserPanic), true),
        vec!["deferred\t4\tparser-panic"]
    );
    let flagged = SyntaxOutcome::Flagged(vec![SyntaxDiagnostic {
        unique_name: "expected_token".to_string(),
        offset: 7,
        length: 2,
        message: "a\tb\nc\\d".to_string(),
    }]);
    assert_eq!(result_lines(5, &flagged, false), vec!["flagged\t5\t1"]);
    assert_eq!(
        result_lines(5, &flagged, true),
        vec![
            "flagged\t5\t1",
            "diagnostic\t5\texpected_token\t7\t2\ta\\tb\\nc\\\\d",
        ]
    );
    assert_eq!(escape_field("plain"), "plain");
}

#[test]
fn the_deepest_nesting_is_the_longest_chain_of_parents() {
    const NO_PARENT: u32 = u32::MAX;
    assert_eq!(deepest_nesting(&[]), 0);
    assert_eq!(deepest_nesting(&[NO_PARENT]), 1);
    // Children before parents, as the builder makes them: 0 and 1 under 2,
    // 2 under 4, 3 on its own.
    assert_eq!(deepest_nesting(&[2, 2, 4, NO_PARENT, NO_PARENT]), 3);
    // Parents before children.
    assert_eq!(deepest_nesting(&[NO_PARENT, 0, 1, 2, 3]), 5);
    // Not a tree: it must still end.
    assert!(deepest_nesting(&[1, 0]) >= 1);
}

#[test]
fn ordinary_nesting_is_answered_and_extreme_nesting_is_left_to_dart() {
    let nested = |depth: usize| format!("var x = {}1{};\n", "(".repeat(depth), ")".repeat(depth));
    assert_eq!(
        check_source_bytes(nested(100).as_bytes()),
        SyntaxOutcome::Clean
    );
    assert_eq!(
        check_source_bytes(nested(DEEPEST_NESTING + 1).as_bytes()),
        SyntaxOutcome::Deferred(DeferReason::DeeplyNested)
    );
}
