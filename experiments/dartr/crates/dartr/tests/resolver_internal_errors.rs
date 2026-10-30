//! A resolver that panics must not make diagnostics disappear without a
//! sign. dartr catches a panic in one step of a unit's analysis, or in the
//! analysis of a whole library, and goes on with the other libraries;
//! `dartr analyze` reports the panic on stderr, naming the file, and exits
//! with 4, dartdev's `_Result.crash`, as it does for an exception the
//! analysis server reports.
//!
//! `DARTR_RESOLVER_PANIC_FOR_TESTING=<step>` makes that step panic: the name
//! of a unit step of the library analyzer (`_computeWarnings`), or
//! `analyze_library` for the analysis of the whole library.
//!
//! Needs a Dart SDK for `dart:core` (found like `dartr analyze` finds it, from
//! `dart` on PATH); skipped with a message when there is none.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const SOURCE: &str = "\
void main() {
  var unused = 1;
  print('a');
}
";

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn project(name: &str) -> PathBuf {
    let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
        .join("resolver_internal_errors")
        .join(name);
    if root.exists() {
        fs::remove_dir_all(&root).unwrap();
    }
    fs::create_dir_all(root.join("lib")).unwrap();
    fs::write(
        root.join("pubspec.yaml"),
        "name: resolver_panic\nenvironment:\n  sdk: ^3.9.0\n",
    )
    .unwrap();
    fs::write(
        root.join("analysis_options.yaml"),
        "linter:\n  rules:\n    - avoid_print\n",
    )
    .unwrap();
    fs::write(root.join("lib/a.dart"), SOURCE).unwrap();
    root.canonicalize().unwrap()
}

fn analyze(root: &Path, panicking_step: Option<&str>) -> Run {
    let mut command = Command::new(env!("CARGO_BIN_EXE_dartr"));
    command
        .arg("analyze")
        .arg(root)
        .current_dir(root)
        .env_remove("COLUMNS")
        .env_remove("DARTR_RESOLVER_PANIC_FOR_TESTING")
        .env("RUST_BACKTRACE", "0");
    if let Some(step) = panicking_step {
        command.env("DARTR_RESOLVER_PANIC_FOR_TESTING", step);
    }
    let out = command.output().expect("run dartr analyze");
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

fn sdk_available() -> bool {
    let ok = Command::new("dart")
        .arg("--version")
        .output()
        .is_ok_and(|o| o.status.success());
    if !ok {
        eprintln!("skipped: no `dart` on PATH, so `dartr analyze` has no SDK for dart:core");
    }
    ok
}

/// Without a panic: the warning and the lint, nothing on stderr, exit 2 (a
/// warning).
#[test]
fn diagnostics_without_a_panic() {
    if !sdk_available() {
        return;
    }
    let root = project("control");
    let run = analyze(&root, None);
    for code in ["unused_local_variable", "avoid_print"] {
        assert!(run.stdout.contains(code), "{code} missing:\n{}", run.stdout);
    }
    assert!(!run.stderr.contains("internal error"), "{}", run.stderr);
    assert_eq!(run.code, 2, "{}\n{}", run.stdout, run.stderr);
}

fn assert_loud(step: &str) {
    let root = project(step);
    let run = analyze(&root, Some(step));
    let file = root.join("lib/a.dart");
    let line = run
        .stderr
        .lines()
        .find(|l| l.contains("internal error") && l.contains(&*file.to_string_lossy()))
        .unwrap_or_else(|| {
            panic!(
                "no internal error naming {} on stderr:\n{}\n{}",
                file.display(),
                run.stdout,
                run.stderr
            )
        });
    assert!(line.contains(step), "the internal error does not name {step}: {line}");
    // dartdev `_Result.crash`.
    assert_eq!(run.code, 4, "{}\n{}", run.stdout, run.stderr);
}

/// A panic in one step of a unit (Dart: an exception aborts the analysis
/// of the library).
#[test]
fn a_panicking_unit_step_is_reported() {
    if !sdk_available() {
        return;
    }
    assert_loud("_computeWarnings");
}

/// A panic in the analysis of a whole library: the file falls back to the
/// parse-only pipeline.
#[test]
fn a_panicking_library_analysis_is_reported() {
    if !sdk_available() {
        return;
    }
    assert_loud("analyze_library");
}
