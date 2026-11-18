// Differential tests for linked elements and declared types (not a port).
#[path = "support/oracle.rs"]
mod oracle;
use oracle::*;
use std::{fs, process::Command};
/// Runs both dumpers over the corpus with [flags] and fails unless every
/// dump is identical.
fn check(name: &str, flags: &[&str]) {
    let work = work_dir().join(name);
    fs::create_dir_all(&work).unwrap();
    let package_config = write_package_config(&work);
    let sdk = write_sdk(&work);
    let roots = corpus();
    let dart_out = work.join("dart");
    let rust_out = work.join("rust");
    let _ = fs::remove_dir_all(&dart_out);
    let _ = fs::remove_dir_all(&rust_out);
    run(Command::new(dart())
        .current_dir(sdk_root())
        .arg(format!("--packages={}", package_config.display()))
        .arg("pkg/analyzer/rust/oracle/element_dump.dart")
        .arg("--sdk")
        .arg(&sdk)
        .args(flags)
        .arg("--out")
        .arg(&dart_out)
        .args(&roots));
    run(Command::new(env!("CARGO_BIN_EXE_element_dump"))
        .arg("--sdk")
        .arg(&sdk)
        .arg("--packages")
        .arg(&package_config)
        .args(flags)
        .arg("--out")
        .arg(&rust_out)
        .args(&roots));
    let (files, differences, report) = compare(&dart_out, &rust_out);
    eprintln!("{name}: {files} files, {differences} differences");
    if differences == 0 {
        let _ = fs::remove_dir_all(&dart_out);
        let _ = fs::remove_dir_all(&rust_out);
    }
    assert!(files > 0, "the oracle wrote no dumps");
    assert!(
        differences == 0,
        "{differences} of {files} files differ\n{report}"
    );
}

/// The elements built from the declarations: every element's kind, name,
/// fragments (offsets and flags) and children, the directives, and the
/// import and export namespaces.
#[test]
fn elements_are_identical_to_upstream() {
    check("elements", &[]);
}

/// The declared types, as `getDisplayString` writes them.
#[test]
fn declared_types_are_identical_to_upstream() {
    check("types", &["--types"]);
}
