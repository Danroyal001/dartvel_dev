// Differential resolved-body oracle (test harness, not an upstream port).
#[path = "support/oracle.rs"]
#[allow(dead_code)]
mod oracle;

use std::{fs, path::Path, process::Command};

#[test]
fn context_independent_literals_match_upstream() {
    compare_selection("literals");
}

#[test]
fn operator_typed_expressions_match_upstream() {
    compare_selection("operators");
}

#[test]
fn declared_context_integers_match_upstream() {
    compare_selection("integers");
}

/// Runs `oracle/body_dump.dart` and `body_dump` with `--<selection>` on the
/// corpus and fails unless they wrote nonempty, byte-identical dumps.
fn compare_selection(selection: &str) {
    let work = oracle::work_dir().join(format!("body-{selection}"));
    fs::create_dir_all(&work).unwrap();
    let packages = oracle::write_package_config(&work);
    let sdk = oracle::write_sdk(&work);
    let roots = oracle::corpus();
    let expected = work.join("dart");
    let actual = work.join("rust");
    for dir in [&expected, &actual] {
        if dir.exists() {
            fs::remove_dir_all(dir).unwrap();
        }
    }
    let flag = format!("--{selection}");
    oracle::run(
        Command::new(oracle::dart())
            .current_dir(oracle::sdk_root())
            .arg(format!("--packages={}", packages.display()))
            .arg("pkg/analyzer/rust/oracle/body_dump.dart")
            .arg("--sdk")
            .arg(&sdk)
            .arg(&flag)
            .arg("--out")
            .arg(&expected)
            .args(&roots),
    );
    oracle::run(
        Command::new(env!("CARGO_BIN_EXE_body_dump"))
            .arg("--sdk")
            .arg(&sdk)
            .arg("--packages")
            .arg(&packages)
            .arg(&flag)
            .arg("--out")
            .arg(&actual)
            .args(&roots),
    );

    fn count_rows(path: &Path) -> usize {
        fs::read_dir(path)
            .unwrap()
            .map(|e| {
                let path = e.unwrap().path();
                if path.is_dir() {
                    count_rows(&path)
                } else {
                    fs::read_to_string(path).unwrap().lines().count()
                }
            })
            .sum()
    }
    let rows = count_rows(&expected);
    assert!(rows > 0, "oracle emitted no expression rows");
    eprintln!("body-{selection}: {rows} expression rows");
    let (files, differences, report) = oracle::compare(&expected, &actual);
    eprintln!("body-{selection}: {files} files, {differences} differences");
    assert!(files > 0, "oracle wrote no files");
    assert_eq!(differences, 0, "{report}");
}
