// Differential test of the scanner port against upstream (not a mirrored
// file; see ../README.md).
//
// Runs the Dart oracle (rust/oracle/scanner_dump.dart, on the upstream
// scanner) and the Rust `scanner_dump` binary over the same corpus, for both
// the UTF-8 and the string scanner, and fails unless every dump is byte for
// byte identical.
//
// Environment:
//   DART            the Dart executable (default: `dart` on PATH); its SDK
//                   must be at least the version pkg/_fe_analyzer_shared
//                   requires.
//   SCANNER_CORPUS  corpus roots separated by `:` (default: the scanner
//                   tests' inputs, pkg/_fe_analyzer_shared/lib and
//                   pkg/analyzer/lib). A relative root is resolved
//                   against the SDK root.
//   SCANNER_WORK   scratch directory (default: target/scanner_oracle).
//
// Every child process runs under a time limit.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

const TIME_LIMIT: Duration = Duration::from_secs(900);

/// The scanner tests whose inputs make up the first corpus.
const SCANNER_TESTS: &[&str] = &[
    "pkg/front_end/test/scanner_test.dart",
    "pkg/front_end/test/scanner_cfe_test.dart",
    "pkg/front_end/test/scanner_replacement_test.dart",
    "pkg/front_end/test/token_test.dart",
    "pkg/_fe_analyzer_shared/test/scanner/string_canonicalizer_test.dart",
    "pkg/_fe_analyzer_shared/test/scanner/utf8_bytes_scanner_test.dart",
    "pkg/_fe_analyzer_shared/test/keyword_state_test.dart",
    "pkg/analyzer/test/src/fasta/token_utils_test.dart",
];

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap()
}

fn dart() -> String {
    std::env::var("DART").unwrap_or_else(|_| "dart".to_string())
}

fn work_dir() -> PathBuf {
    match std::env::var("SCANNER_WORK") {
        // Relative to the SDK root, like the corpus roots.
        Ok(dir) => sdk_root().join(dir),
        Err(_) => sdk_root().join("target/scanner_oracle"),
    }
}

fn run(command: &mut Command) {
    let description = format!("{command:?}");
    let mut child = command
        .spawn()
        .unwrap_or_else(|e| panic!("cannot run {description}: {e}"));
    let deadline = Instant::now() + TIME_LIMIT;
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success(), "{description} failed: {status}");
            return;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            panic!("{description} exceeded {TIME_LIMIT:?}");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn oracle_command(program: &str) -> Command {
    let root = sdk_root();
    let mut command = Command::new(dart());
    command
        .current_dir(&root)
        .arg("--packages=pkg/_fe_analyzer_shared/rust/oracle/package_config.json")
        .arg(format!("pkg/_fe_analyzer_shared/rust/oracle/{program}"));
    command
}

fn corpus(work: &Path) -> Vec<String> {
    if let Ok(roots) = std::env::var("SCANNER_CORPUS") {
        return roots
            .split(':')
            .filter(|r| !r.is_empty())
            // The oracle runs in the SDK root and the Rust binary in this
            // crate, so a relative root would name two directories. Resolve
            // it against the SDK root for both.
            .map(|r| sdk_root().join(r).to_string_lossy().to_string())
            .collect();
    }
    let root = sdk_root();
    let tests = work.join("scanner_test_inputs");
    let _ = fs::remove_dir_all(&tests);
    run(oracle_command("extract_test_inputs.dart")
        .arg("--out")
        .arg(&tests)
        .args(SCANNER_TESTS));
    vec![
        tests.to_string_lossy().to_string(),
        root.join("pkg/_fe_analyzer_shared/lib")
            .to_string_lossy()
            .to_string(),
        root.join("pkg/analyzer/lib").to_string_lossy().to_string(),
    ]
}

fn files_under(dir: &Path) -> Vec<PathBuf> {
    let mut result = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(entries) = fs::read_dir(&d) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else {
                result.push(path.strip_prefix(dir).unwrap().to_path_buf());
            }
        }
    }
    result.sort();
    result
}

/// Compares two dump trees and returns a report of every difference.
fn compare(expected: &Path, actual: &Path) -> (usize, usize, String) {
    let expected_files = files_under(expected);
    let actual_files = files_under(actual);
    let mut report = String::new();
    let mut differences = 0;
    for file in &expected_files {
        let want = fs::read(expected.join(file)).unwrap();
        let got = fs::read(actual.join(file)).unwrap_or_default();
        if want != got {
            differences += 1;
            if differences <= 20 {
                let want = String::from_utf8_lossy(&want);
                let got = String::from_utf8_lossy(&got);
                let (line, w, g) = want
                    .lines()
                    .zip(got.lines().chain(std::iter::repeat("<missing>")))
                    .enumerate()
                    .find(|(_, (w, g))| w != g)
                    .map(|(i, (w, g))| (i + 1, w.to_string(), g.to_string()))
                    .unwrap_or((0, "<length differs>".into(), String::new()));
                report.push_str(&format!(
                    "{}: first difference at line {line}\n  dart: {w}\n  rust: {g}\n",
                    file.display()
                ));
            }
        }
    }
    for file in &actual_files {
        if !expected_files.contains(file) {
            differences += 1;
            report.push_str(&format!("{}: only in the Rust output\n", file.display()));
        }
    }
    (expected_files.len(), differences, report)
}

#[test]
fn scanner_output_is_identical_to_upstream() {
    let work = work_dir();
    fs::create_dir_all(&work).unwrap();
    let roots = corpus(&work);
    let mut failures = String::new();
    for kind in ["utf8", "string"] {
        let dart_out = work.join(format!("dart-{kind}"));
        let rust_out = work.join(format!("rust-{kind}"));
        let _ = fs::remove_dir_all(&dart_out);
        let _ = fs::remove_dir_all(&rust_out);
        run(oracle_command("scanner_dump.dart")
            .arg(format!("--scanner={kind}"))
            .arg("--out")
            .arg(&dart_out)
            .args(&roots));
        run(Command::new(env!("CARGO_BIN_EXE_scanner_dump"))
            .arg(format!("--scanner={kind}"))
            .arg("--out")
            .arg(&rust_out)
            .args(&roots));
        let (files, differences, report) = compare(&dart_out, &rust_out);
        eprintln!("scanner={kind}: {files} files, {differences} differences");
        if differences > 0 {
            failures.push_str(&format!(
                "scanner={kind}: {differences} of {files} files differ\n{report}"
            ));
        } else {
            // Identical: the dumps are not needed any more.
            let _ = fs::remove_dir_all(&dart_out);
            let _ = fs::remove_dir_all(&rust_out);
        }
    }
    assert!(failures.is_empty(), "{failures}");
}
