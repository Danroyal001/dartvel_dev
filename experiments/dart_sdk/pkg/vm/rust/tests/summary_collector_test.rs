// Port of test/transformations/type_flow/summary_collector_test.dart, as an
// oracle against upstream (see ../README.md).
//
// Upstream's test compiles each program under
// testcases/transformations/type_flow/summary_collector, prints the summary
// of every member of its main library (and of every local function in it)
// with `PrintSummaries`, and compares the text with the program's `.expect`
// file. Here the program's kernel comes from oracle/build_inputs.dart, which
// compiles it the same way, writes it to a `.dill` and checks that
// upstream's own `PrintSummaries` reproduces the `.expect` file both from
// the component in memory and from the `.dill` read back. The Rust port
// reads that `.dill` and must print the `.expect` file byte for byte; the
// `.expect` files are upstream's, unchanged.
//
// Environment:
//   DART       the Dart executable that runs oracle/build_inputs.dart when
//              the inputs are missing (default: `dart` on PATH).
//   TFA_ORACLE the inputs' directory (default: target/tfa_oracle under the
//              SDK root).
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use kernel::ast::Component;
use kernel::binary::ast_from_binary::loadComponentFromBytes;

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap()
}

fn testcases_dir() -> PathBuf {
    sdk_root().join("pkg/vm/testcases/transformations/type_flow/summary_collector")
}

fn oracle_dir() -> PathBuf {
    match std::env::var("TFA_ORACLE") {
        Ok(dir) => {
            let dir = PathBuf::from(dir);
            if dir.is_absolute() { dir } else { sdk_root().join(dir) }
        }
        Err(_) => sdk_root().join("target/tfa_oracle"),
    }
}

/// The testcases, as the test finds them: every `.dart` file in the
/// directory, by path.
fn testcases() -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(testcases_dir())
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.ends_with(".dart"))
        .map(|n| n.trim_end_matches(".dart").to_string())
        .collect();
    names.sort();
    names
}

fn ensure_inputs() {
    let out = oracle_dir().join("summary_collector");
    if testcases().iter().all(|n| out.join(format!("{n}.dill")).exists()) {
        return;
    }
    let dart = std::env::var("DART").unwrap_or_else(|_| "dart".into());
    let status = Command::new(dart)
        .arg(sdk_root().join("pkg/vm/rust/oracle/build_inputs.dart"))
        .arg(sdk_root())
        .arg(oracle_dir())
        .status()
        .expect("run oracle/build_inputs.dart");
    assert!(status.success(), "oracle/build_inputs.dart failed");
}

/// `PrintSummaries.print`: the summaries of the main library's members.
fn print_summaries(component: &Component) -> String {
    vm::transformations::type_flow::print_summaries_for_testing(component)
}

/// `findFirstDifference` of test/common_test_utils.dart.
fn first_difference(actual: &str, expected: &str) -> String {
    let a: Vec<&str> = actual.split('\n').collect();
    let e: Vec<&str> = expected.split('\n').collect();
    let mut i = 0;
    while i < a.len() && i < e.len() {
        if a[i] != e[i] {
            return format!("line {}:\n  actual:   {}\n  expected: {}", i + 1, a[i], e[i]);
        }
        i += 1;
    }
    format!(
        "line {}:\n  actual:   {}\n  expected: {}",
        i + 1,
        a.get(i).copied().unwrap_or("<END>"),
        e.get(i).copied().unwrap_or("<END>")
    )
}

#[test]
fn collect_summary() {
    ensure_inputs();
    let out = oracle_dir().join("summary_collector");
    let names = testcases();
    let mut passed = Vec::new();
    let mut failed = Vec::new();
    for name in &names {
        let expect_path = testcases_dir().join(format!("{name}.dart.expect"));
        let expected = fs::read_to_string(&expect_path).unwrap_or_default();
        // The harness: upstream printed exactly the .expect file from this
        // .dill (oracle/build_inputs.dart checks it; this re-checks the
        // copy it left).
        let upstream = fs::read_to_string(out.join(format!("{name}.upstream.txt"))).unwrap();
        assert_eq!(upstream, expected, "{name}: upstream's output from the .dill is not the .expect file");

        let bytes = fs::read(out.join(format!("{name}.dill"))).unwrap();
        let component = loadComponentFromBytes(&bytes).unwrap();
        let actual = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| print_summaries(&component)));
        match actual {
            Ok(actual) if actual == expected => passed.push(name.clone()),
            Ok(actual) => {
                let _ = fs::write(out.join(format!("{name}.rust.txt")), &actual);
                failed.push(format!("{name}: first difference at {}", first_difference(&actual, &expected)));
            }
            Err(panic) => {
                let message = panic
                    .downcast_ref::<String>()
                    .cloned()
                    .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                    .unwrap_or_default();
                failed.push(format!("{name}: panicked: {message}"));
            }
        }
    }
    eprintln!("summary_collector: {} of {} testcases identical to their .expect", passed.len(), names.len());
    for f in &failed {
        eprintln!("FAIL {f}");
    }
    assert!(failed.is_empty(), "{} of {} testcases differ", failed.len(), names.len());
}
