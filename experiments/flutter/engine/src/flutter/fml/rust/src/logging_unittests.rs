// Port of flutter/fml/logging_unittests.cc.
//
// gtest's ASSERT_DEATH runs the statement in a child process; `expect_death`
// re-runs this test binary filtered to the one test, with an environment
// variable telling the test to run its deadly statement, and checks that the
// child died by SIGABRT with stderr matching. The static-initialization
// segfault check has no counterpart (Rust has no static constructors).

use crate::log_level::*;
use crate::logging::testing::LogCapture;
use crate::logging::{LogMessage, kill_process};

const _: () = assert!(kLogFatal == kLogNumSeverities - 1);
const _: () = assert!(kLogImportant < kLogFatal);
const _: () = assert!(kLogImportant > kLogError);

const DEATH_TEST_ENV: &str = "FML_DEATH_TEST";

/// Runs `statement` in a child process (this binary, filtered to `test`) and
/// asserts that the child aborts with `expected` in its stderr.
pub(crate) fn expect_death(test: &str, expected: &str, statement: impl FnOnce()) {
    if std::env::var(DEATH_TEST_ENV).as_deref() == Ok(test) {
        statement();
        // Surviving is the failure the parent reports.
        std::process::exit(0);
    }
    use std::os::unix::process::ExitStatusExt;
    let out = std::process::Command::new(std::env::current_exe().unwrap())
        .args([test, "--exact", "--nocapture", "--test-threads=1"])
        .env(DEATH_TEST_ENV, test)
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert_eq!(out.status.signal(), Some(6), "{test} did not abort; stderr: {stderr}");
    assert!(stderr.contains(expected), "{test}: {expected:?} not in stderr: {stderr}");
}

#[allow(dead_code, unreachable_code)]
fn unreachable_scope_without_return_does_not_make_compiler_mad() -> i32 {
    kill_process();
    // return 0; <--- Missing but compiler is fine.
}

#[allow(dead_code, unreachable_code)]
fn unreachable_scope_with_macro_without_return_does_not_make_compiler_mad() -> i32 {
    crate::fml_unreachable_at!("flutter/fml/logging_unittests.cc", 63);
    // return 0; <--- Missing but compiler is fine.
}

#[test]
fn unreachable_kill_process() {
    expect_death("logging_unittests::unreachable_kill_process", "", || kill_process());
}

#[test]
fn unreachable_kill_process_with_macro() {
    expect_death(
        "logging_unittests::unreachable_kill_process_with_macro",
        "[ERROR:flutter/fml/logging_unittests.cc(72)] Reached unreachable code.\n",
        || {
            crate::fml_unreachable_at!("flutter/fml/logging_unittests.cc", 72);
        },
    );
}

#[test]
fn sanity_tests() {
    let severities = ["INFO", "WARNING", "ERROR", "IMPORTANT"];

    for (i, severity) in severities.iter().enumerate() {
        let capture = LogCapture::new();
        {
            let mut log = LogMessage::new(i as LogSeverity, "path/to/file.cc", 4, None);
            log.stream().push_str("Hello!");
        }
        assert_eq!(capture.str(), format!("[{severity}:path/to/file.cc(4)] Hello!\n"));
    }

    expect_death("logging_unittests::sanity_tests", "[FATAL:path/to/file.cc(5)] Goodbye", || {
        let mut log = LogMessage::new(kLogFatal, "path/to/file.cc", 5, None);
        log.stream().push_str("Goodbye");
    });
}
