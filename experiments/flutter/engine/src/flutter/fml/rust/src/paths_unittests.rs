// Port of flutter/fml/paths_unittests.cc.

use super::paths::*;

#[test]
fn sanitize_uri() {
    assert_eq!(sanitize_uri_escaped_characters("hello"), b"hello");
    assert_eq!(sanitize_uri_escaped_characters(""), b"");
    assert_eq!(sanitize_uri_escaped_characters("hello%20world"), b"hello world");
    assert_eq!(
        sanitize_uri_escaped_characters("%5Chello%5cworld%20foo%20bar%21"),
        b"\\hello\\world foo bar!"
    );
}
