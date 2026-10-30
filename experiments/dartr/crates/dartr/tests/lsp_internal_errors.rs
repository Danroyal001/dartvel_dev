//! A panic in the analysis must not go unseen in the language server
//! either: the server writes each one to stderr, the log a client shows,
//! naming the file whose diagnostics are incomplete (`dartr analyze` exits
//! 4 for the same panics, see `resolver_internal_errors.rs`). The protocol
//! output stays as Dart's.
//!
//! `DARTR_RESOLVER_PANIC_FOR_TESTING=_computeWarnings` makes that step of
//! the library analyzer panic. Needs a Dart SDK (the first `dart` on PATH);
//! skipped without one.

mod lsp_support;

use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use lsp_support::{LspClient, dart_available, dart_code_initialize_params, file_uri};
use serde_json::json;

fn project() -> PathBuf {
    let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("lsp_internal_errors");
    if root.exists() {
        fs::remove_dir_all(&root).unwrap();
    }
    fs::create_dir_all(root.join("lib")).unwrap();
    fs::write(
        root.join("pubspec.yaml"),
        "name: lsp_panic\nenvironment:\n  sdk: ^3.9.0\n",
    )
    .unwrap();
    fs::write(
        root.join("lib/a.dart"),
        "void main() {\n  var unused = 1;\n}\n",
    )
    .unwrap();
    root.canonicalize().unwrap()
}

#[test]
fn a_panic_in_the_analysis_is_written_to_stderr() {
    if !dart_available() {
        eprintln!("skipped: no `dart` on PATH");
        return;
    }
    let root = project();
    let file = root.join("lib/a.dart");
    let mut c = LspClient::spawn(
        env!("CARGO_BIN_EXE_dartr"),
        &["language-server", "--protocol=lsp", "--client-id=VS-Code"],
        &[
            ("DARTR_RESOLVER_PANIC_FOR_TESTING", "_computeWarnings"),
            ("RUST_BACKTRACE", "0"),
        ],
    );
    let init = c.request("initialize", dart_code_initialize_params(&root));
    assert!(init["result"]["capabilities"].is_object(), "{init}");
    c.notify("initialized", json!({}));
    c.notify(
        "textDocument/didOpen",
        json!({"textDocument": {
            "uri": file_uri(&file),
            "languageId": "dart",
            "version": 1,
            "text": fs::read_to_string(&file).unwrap(),
        }}),
    );
    c.settle(true);
    let path = file.to_string_lossy().to_string();
    let deadline = Instant::now() + Duration::from_secs(30);
    let line = loop {
        let stderr = c.stderr();
        if let Some(line) = stderr
            .lines()
            .find(|l| l.contains("internal error") && l.contains(&path))
        {
            break line.to_string();
        }
        assert!(
            Instant::now() < deadline,
            "no internal error naming {path} on stderr:\n{stderr}"
        );
        std::thread::sleep(Duration::from_millis(100));
    };
    assert!(line.contains("_computeWarnings"), "{line}");
    let (_, code) = c.shutdown_and_exit();
    assert_eq!(code, 0);
}
