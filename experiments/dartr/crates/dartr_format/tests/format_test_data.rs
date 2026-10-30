// Dart source: dart_style test/tall_format_test.dart, test/short_format_test.dart
// Dart source: dart_style test/utils.dart (testDirectory, testBenchmarks)

//! Runs the formatting test data of dart_style against the port: every
//! `.unit` and `.stmt` file under `test/tall` and `test/short` (each with the
//! page width, indent, trailing comma and experiment options it declares, at
//! every language version its outputs cover) and the benchmark cases in
//! `benchmark/case` in both styles.
//!
//! The data is read from a dart_style checkout at the revision Dart SDK
//! 3.13.3 pins (`dart_style_rev` in the SDK `DEPS`):
//!
//! - `DART_STYLE_DIR=<path>`: the root of that checkout (the directory with
//!   `test/` and `benchmark/`). Without it, `third_party/dart_style` in the
//!   workspace is used (`tools/fetch_sdk.sh`); if neither exists, the tests
//!   are skipped with a message so that a build without the data passes.
//! - `FORMAT_TEST_FILTER=<substring>`: only files whose path contains it.
//! - `FORMAT_TEST_VERBOSE=1`: print every failure (default: the first 20).
//! - `FORMAT_TEST_ALLOW_FAILURES=1`: print the summary but do not fail.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use dartr_format::testing::test_file::{TestFile, run_test_files};
use dartr_format::{DartFormatter, SourceCode};

/// The root of the dart_style checkout, or `None` (with a message) when the
/// data is not available.
fn package_dir() -> Option<PathBuf> {
    let dir = match std::env::var_os("DART_STYLE_DIR") {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../third_party/dart_style"),
    };
    if dir.join("test").is_dir() {
        Some(dir)
    } else {
        eprintln!(
            "skipped: dart_style test data not found at {} (set DART_STYLE_DIR to a \
             dart_style checkout at the SDK's dart_style_rev, or run tools/fetch_sdk.sh)",
            dir.display()
        );
        None
    }
}

/// The directories under `test/<style>` (sorted), so that a directory added
/// upstream is run without changing this file.
fn style_dirs(test_dir: &Path, style: &str) -> Vec<String> {
    let mut dirs: Vec<String> = std::fs::read_dir(test_dir.join(style))
        .unwrap()
        .flatten()
        .filter(|entry| entry.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .map(|entry| format!("{style}/{}", entry.file_name().to_string_lossy()))
        .collect();
    dirs.sort();
    dirs
}

fn run(style: &str) {
    let Some(package_dir) = package_dir() else {
        return;
    };
    let test_dir = package_dir.join("test");
    let filter = std::env::var("FORMAT_TEST_FILTER").ok();
    let verbose = std::env::var("FORMAT_TEST_VERBOSE").is_ok();
    let allow = std::env::var("FORMAT_TEST_ALLOW_FAILURES").is_ok();

    let mut summary = BTreeMap::new();
    let mut all_failures = Vec::new();
    let mut total = 0;
    for dir in style_dirs(&test_dir, style) {
        let mut files = TestFile::list_directory(&test_dir, &dir).unwrap();
        if let Some(filter) = &filter {
            files.retain(|f| f.path.contains(filter.as_str()));
        }
        if files.is_empty() {
            continue;
        }
        let (count, failures) = run_test_files(&files);
        total += count;
        summary.insert(dir, (count, failures.len()));
        all_failures.extend(failures);
    }

    for (i, failure) in all_failures.iter().enumerate() {
        if verbose || i < 20 {
            eprintln!(
                "FAIL {} {} at {}:\n{}\n",
                failure.file,
                failure.label,
                failure.version.major_minor(),
                failure.message
            );
        }
    }
    for failure in &all_failures {
        eprintln!(
            "failed: {} {} at {}",
            failure.file,
            failure.label,
            failure.version.major_minor()
        );
    }
    for (dir, (count, failed)) in &summary {
        eprintln!("{dir}: {} of {count} passed ({failed} failed)", count - failed);
    }
    eprintln!(
        "{style}: {} of {total} tests passed ({} failed)",
        total - all_failures.len(),
        all_failures.len()
    );
    if !allow {
        assert!(all_failures.is_empty(), "{} failures", all_failures.len());
    }
}

#[test]
fn tall() {
    run("tall");
}

#[test]
fn short() {
    run("short");
}

/// Dart `File.readAsLinesSync()`: splits at `\n`, `\r\n` and `\r`; a final
/// line terminator does not start a new line.
fn read_as_lines(text: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\n' => lines.push(std::mem::take(&mut current)),
            '\r' => {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                lines.push(std::mem::take(&mut current));
            }
            _ => current.push(c),
        }
    }
    if !current.is_empty() {
        lines.push(current);
    }
    lines
}

// Dart source: dart_style lib/src/testing/benchmark.dart (Benchmark.read),
// test/utils.dart (testBenchmarks)

/// Formats the benchmark cases of dart_style (`benchmark/case/*.unit` and
/// `*.stmt`) in one style and compares with the `.expect` (tall) or
/// `.expect_short` (short) files.
fn run_benchmarks(use_tall_style: bool) {
    let Some(package_dir) = package_dir() else {
        return;
    };
    let dir = package_dir.join("benchmark/case");
    let filter = std::env::var("FORMAT_TEST_FILTER").ok();
    let mut paths: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| {
            matches!(
                path.extension().and_then(|e| e.to_str()),
                Some("unit" | "stmt")
            )
        })
        .collect();
    paths.sort();
    let mut failures = Vec::new();
    let mut count = 0;
    for path in &paths {
        let name = path.file_stem().unwrap().to_str().unwrap().to_string();
        if let Some(filter) = &filter {
            if !name.contains(filter.as_str()) {
                continue;
            }
        }
        count += 1;
        let mut lines = read_as_lines(&std::fs::read_to_string(path).unwrap());
        // The first line may have a "|" to indicate the page width.
        let mut page_width = 80;
        if lines[0].ends_with('|') {
            page_width = lines[0].find('|').unwrap();
            lines.remove(0);
        }
        let input = lines.join("\n");
        let is_compilation_unit = path.extension().unwrap() == "unit";
        let expected = std::fs::read_to_string(path.with_extension(if use_tall_style {
            "expect"
        } else {
            "expect_short"
        }))
        .unwrap();
        let mut formatter = DartFormatter::new(if use_tall_style {
            DartFormatter::LATEST_LANGUAGE_VERSION
        } else {
            DartFormatter::LATEST_SHORT_STYLE_LANGUAGE_VERSION
        });
        formatter.page_width = page_width;
        // Dart `SourceCode(benchmark.input)`: `isCompilationUnit` defaults to
        // true, also for the `.stmt` cases.
        let source = SourceCode::new(input, None, true, None, None).unwrap();
        match formatter.format_source(&source) {
            Ok(result) => {
                // The test files always put a newline at the end of the
                // expectation. Statements from the formatter (correctly) don't
                // have that, so add one to line up with the expected result.
                let mut actual = result.text;
                if !is_compilation_unit {
                    actual.push('\n');
                }
                if actual != expected {
                    failures.push(format!(
                        "{name}: output differs\n--- expected\n{expected}\n--- actual\n{actual}"
                    ));
                }
            }
            Err(error) => failures.push(format!("{name}: error: {error}")),
        }
    }
    for failure in &failures {
        eprintln!("FAIL {failure}\n");
    }
    eprintln!(
        "{} benchmarks: {} of {} passed ({} failed)",
        if use_tall_style { "tall" } else { "short" },
        count - failures.len(),
        count,
        failures.len()
    );
    if std::env::var("FORMAT_TEST_ALLOW_FAILURES").is_err() {
        assert!(failures.is_empty(), "{} failures", failures.len());
    }
}

#[test]
fn tall_benchmarks() {
    run_benchmarks(true);
}

#[test]
fn short_benchmarks() {
    run_benchmarks(false);
}
