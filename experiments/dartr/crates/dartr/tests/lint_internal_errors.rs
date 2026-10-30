//! A lint rule that panics must not make diagnostics disappear without a
//! sign. Dart's `AnalysisRuleVisitor._runSubscriptions` catches an exception
//! of one rule on one node and goes on with the other rules and the other
//! nodes; dartr does the same, and `dartr analyze` also reports the panic on
//! stderr (naming the rule and the file) and exits with 4, dartdev's
//! `_Result.crash`.
//!
//! `DARTR_LINT_PANIC_FOR_TESTING=<rule>` makes that rule panic on every call.
//!
//! Needs a Dart SDK for `dart:core` (found like `dartr analyze` finds it, from
//! `dart` on PATH); skipped with a message when there is none.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const SOURCE: &str = "\
void main() {
  var x = 1;
  print(x);
  ;
  if (x == 1) {
  } else ;
}
";

const OPTIONS: &str = "\
linter:
  rules:
    - avoid_print
    - prefer_final_locals
    - empty_statements
    - avoid_empty_else
";

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn project(name: &str) -> PathBuf {
    let root = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
        .join("lint_internal_errors")
        .join(name);
    if root.exists() {
        fs::remove_dir_all(&root).unwrap();
    }
    fs::create_dir_all(root.join("lib")).unwrap();
    fs::write(
        root.join("pubspec.yaml"),
        "name: lint_panic\nenvironment:\n  sdk: ^3.9.0\n",
    )
    .unwrap();
    fs::write(root.join("analysis_options.yaml"), OPTIONS).unwrap();
    fs::write(root.join("lib/a.dart"), SOURCE).unwrap();
    root.canonicalize().unwrap()
}

fn analyze(root: &Path, panicking_rule: Option<&str>) -> Run {
    let mut command = Command::new(env!("CARGO_BIN_EXE_dartr"));
    command
        .arg("analyze")
        .arg(root)
        .current_dir(root)
        .env_remove("COLUMNS")
        .env_remove("DARTR_LINT_PANIC_FOR_TESTING")
        .env("RUST_BACKTRACE", "0");
    if let Some(rule) = panicking_rule {
        command.env("DARTR_LINT_PANIC_FOR_TESTING", rule);
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

/// Without a panic: every rule reports, nothing on stderr, exit 0 (all four
/// lints are infos, and infos are not fatal by default).
#[test]
fn all_rules_report_without_a_panic() {
    if !sdk_available() {
        return;
    }
    let root = project("control");
    let run = analyze(&root, None);
    for rule in [
        "avoid_print",
        "prefer_final_locals",
        "empty_statements",
        "avoid_empty_else",
    ] {
        assert!(run.stdout.contains(rule), "{rule} missing:\n{}", run.stdout);
    }
    assert!(!run.stderr.contains("internal error"), "{}", run.stderr);
    assert_eq!(run.code, 0, "{}\n{}", run.stdout, run.stderr);
}

fn assert_loud_and_others_kept(panicking: &str, others: &[&str]) {
    let root = project(panicking);
    let run = analyze(&root, Some(panicking));
    // The other rules' lints of the same library are still reported.
    for rule in others {
        assert!(
            run.stdout.contains(rule),
            "the lints of {rule} were dropped with {panicking}'s:\n{}\n{}",
            run.stdout,
            run.stderr
        );
    }
    assert!(
        !run.stdout.contains(&format!(" {panicking}\n"))
            && !run.stdout.contains(&format!("- {panicking}")),
        "the panicking rule cannot have reported:\n{}",
        run.stdout
    );
    // The panic is reported, naming the rule and the file.
    let file = root.join("lib/a.dart");
    let line = run
        .stderr
        .lines()
        .find(|l| l.contains("internal error") && l.contains(panicking))
        .unwrap_or_else(|| {
            panic!(
                "no internal error naming {panicking} on stderr:\n{}",
                run.stderr
            )
        });
    assert!(
        line.contains(&*file.to_string_lossy()),
        "the internal error does not name {}: {line}",
        file.display()
    );
    // dartdev `_Result.crash`.
    assert_eq!(run.code, 4, "{}\n{}", run.stdout, run.stderr);
}

/// A rule that runs on the resolved units (Dart `_computeLints`).
#[test]
fn a_panicking_resolved_rule_is_reported_and_other_lints_are_kept() {
    if !sdk_available() {
        return;
    }
    assert_loud_and_others_kept(
        "avoid_print",
        &[
            "prefer_final_locals",
            "empty_statements",
            "avoid_empty_else",
        ],
    );
}

/// A rule that runs on the parsed units.
#[test]
fn a_panicking_parsed_rule_is_reported_and_other_lints_are_kept() {
    if !sdk_available() {
        return;
    }
    assert_loud_and_others_kept(
        "empty_statements",
        &["avoid_print", "prefer_final_locals", "avoid_empty_else"],
    );
}
