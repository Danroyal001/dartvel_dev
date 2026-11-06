// Differential resolved-body oracle (test harness, not an upstream port).
#[path = "support/oracle.rs"]
#[allow(dead_code)]
mod oracle;

use std::{fs, process::Command};

#[test]
fn context_independent_literals_match_upstream() {
    let work = oracle::work_dir().join("body-literals");
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
    oracle::run(
        Command::new(oracle::dart())
            .current_dir(oracle::sdk_root())
            .arg(format!("--packages={}", packages.display()))
            .arg("pkg/analyzer/rust/oracle/body_dump.dart")
            .arg("--sdk")
            .arg(&sdk)
            .arg("--literals")
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
            .arg("--literals")
            .arg("--out")
            .arg(&actual)
            .args(&roots),
    );

    fn count_rows(path: &std::path::Path) -> usize {
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
    eprintln!("body-literals: {rows} expression rows");
    let (files, differences, report) = oracle::compare(&expected, &actual);
    eprintln!("body-literals: {files} files, {differences} differences");
    assert!(files > 0, "oracle wrote no files");
    assert_eq!(differences, 0, "{report}");
}
