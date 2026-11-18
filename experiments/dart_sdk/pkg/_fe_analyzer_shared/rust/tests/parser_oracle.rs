// Differential test of the parser port against upstream (not a mirrored
// file; see ../README.md).
//
// Runs the Dart oracle (rust/oracle/parser_dump.dart, on the upstream
// parser) and the Rust `parser_dump` binary over the same corpus, and fails
// unless every listener event trace is byte for byte identical.
//
// Environment:
//   DART           the Dart executable (default: `dart` on PATH); its SDK
//                  must be at least the version pkg/_fe_analyzer_shared
//                  requires.
//   PARSER_CORPUS  corpus roots separated by `:` (default:
//                  pkg/_fe_analyzer_shared/lib, pkg/analyzer/lib and
//                  tests/language). A relative root is resolved against the
//                  SDK root.
//   PARSER_WORK    scratch directory (default: target/parser_oracle),
//                  relative to the SDK root.
//
// Every child process runs under a time limit.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

const TIME_LIMIT: Duration = Duration::from_secs(1800);

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
    match std::env::var("PARSER_WORK") {
        Ok(dir) => sdk_root().join(dir),
        Err(_) => sdk_root().join("target/parser_oracle"),
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

fn corpus() -> Vec<String> {
    let roots = std::env::var("PARSER_CORPUS").unwrap_or_else(|_| {
        "pkg/_fe_analyzer_shared/lib:pkg/analyzer/lib:tests/language".to_string()
    });
    roots
        .split(':')
        .filter(|r| !r.is_empty())
        // The oracle runs in the SDK root and the Rust binary in this
        // crate, so a relative root would name two directories.
        .map(|r| sdk_root().join(r).to_string_lossy().to_string())
        .collect()
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

/// Compares two trace trees, deletes the traces that match and returns a
/// report of every difference.
fn compare(expected: &Path, actual: &Path) -> (usize, usize, String) {
    let expected_files = files_under(expected);
    let actual_files = files_under(actual);
    let mut report = String::new();
    let mut differences = 0;
    for file in &expected_files {
        let want = fs::read(expected.join(file)).unwrap();
        let got = fs::read(actual.join(file)).unwrap_or_default();
        if want == got {
            let _ = fs::remove_file(expected.join(file));
            let _ = fs::remove_file(actual.join(file));
            continue;
        }
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
    for file in &actual_files {
        if !expected_files.contains(file) {
            differences += 1;
            report.push_str(&format!("{}: only in the Rust output\n", file.display()));
        }
    }
    (expected_files.len(), differences, report)
}

#[test]
fn parser_events_are_identical_to_upstream() {
    let work = work_dir();
    fs::create_dir_all(&work).unwrap();
    let roots = corpus();
    let dart_out = work.join("dart");
    let rust_out = work.join("rust");
    let _ = fs::remove_dir_all(&dart_out);
    let _ = fs::remove_dir_all(&rust_out);
    run(Command::new(dart())
        .current_dir(sdk_root())
        .arg("--packages=pkg/_fe_analyzer_shared/rust/oracle/package_config.json")
        .arg("pkg/_fe_analyzer_shared/rust/oracle/parser_dump.dart")
        .arg("--out")
        .arg(&dart_out)
        .args(&roots));
    run(Command::new(env!("CARGO_BIN_EXE_parser_dump"))
        .arg("--out")
        .arg(&rust_out)
        .args(&roots));
    let (files, differences, report) = compare(&dart_out, &rust_out);
    eprintln!("parser: {files} files, {differences} differences");
    if differences == 0 {
        let _ = fs::remove_dir_all(&dart_out);
        let _ = fs::remove_dir_all(&rust_out);
    }
    assert!(
        differences == 0,
        "{differences} of {files} files differ\n{report}"
    );
}
