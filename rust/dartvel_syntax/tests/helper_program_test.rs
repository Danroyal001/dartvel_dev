// The helper program, run as the CLI runs it (not a ported file).

use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

fn scratch_directory(name: &str) -> PathBuf {
    let directory =
        std::env::temp_dir().join(format!("dartvel_syntax_{name}_{}", std::process::id()));
    let _ = fs::remove_dir_all(&directory);
    fs::create_dir_all(&directory).expect("create scratch directory");
    directory
}

fn run_helper(arguments: &[&str], paths: &[String]) -> Output {
    let mut helper = Command::new(env!("CARGO_BIN_EXE_dartvel_syntax"))
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("start the helper");
    let mut input = helper.stdin.take().expect("helper stdin");
    for path in paths {
        writeln!(input, "{path}").expect("write a path");
    }
    drop(input);
    helper.wait_with_output().expect("helper output")
}

fn output_lines(output: &Output) -> Vec<String> {
    String::from_utf8(output.stdout.clone())
        .expect("helper output is UTF-8")
        .lines()
        .map(str::to_string)
        .collect()
}

#[test]
fn answers_every_path_in_order() {
    let directory = scratch_directory("order");
    let clean = directory.join("clean.dart");
    let broken = directory.join("broken file.dart");
    let missing = directory.join("missing.dart");
    fs::write(&clean, "void main() {}\n").unwrap();
    fs::write(&broken, "void main() {\n").unwrap();
    let paths: Vec<String> = [&clean, &broken, &missing]
        .iter()
        .map(|path| path.to_string_lossy().into_owned())
        .collect();

    let output = run_helper(&[], &paths);
    assert!(output.status.success());
    assert_eq!(
        output_lines(&output),
        vec![
            "dartvel_syntax\t1",
            "clean\t0",
            "flagged\t1\t1",
            "deferred\t2\tunreadable"
        ]
    );
    assert!(output.stderr.is_empty());

    let detailed = run_helper(&["--diagnostics"], &paths);
    assert_eq!(
        output_lines(&detailed),
        vec![
            "dartvel_syntax\t1",
            "clean\t0",
            "flagged\t1\t1",
            "diagnostic\t1\texpected_token\t14\t1\tExpected to find '}'.",
            "deferred\t2\tunreadable",
        ]
    );
    fs::remove_dir_all(&directory).unwrap();
}

#[test]
fn no_paths_is_a_greeting_and_success() {
    let output = run_helper(&[], &[]);
    assert!(output.status.success());
    assert_eq!(output_lines(&output), vec!["dartvel_syntax\t1"]);
}

#[test]
fn an_unknown_argument_is_refused() {
    let output = run_helper(&["--frobnicate"], &[]);
    assert_eq!(output.status.code(), Some(64));
    assert!(output.stdout.is_empty());
}

/// Nesting far past anything a person writes, in each shape the parser
/// recurses on. The helper answers all of them rather than dying on its
/// stack; what it answers is the analyzer's business.
#[test]
fn deep_nesting_is_answered() {
    const DEPTH: usize = 20_000;
    let directory = scratch_directory("nesting");
    let shapes: Vec<(&str, String)> = vec![
        (
            "parentheses",
            format!("var x = {}1{};", "(".repeat(DEPTH), ")".repeat(DEPTH)),
        ),
        (
            "unclosed_parentheses",
            format!("var x = {}", "(".repeat(DEPTH)),
        ),
        (
            "lists",
            format!("var x = {}{};", "[".repeat(DEPTH), "]".repeat(DEPTH)),
        ),
        (
            "blocks",
            format!("void f() {}{}", "{".repeat(DEPTH), "}".repeat(DEPTH)),
        ),
        (
            "type_arguments",
            format!("{}int{} x;", "List<".repeat(DEPTH), ">".repeat(DEPTH)),
        ),
        ("negations", format!("var x = {}true;", "!".repeat(DEPTH))),
        (
            "awaits",
            format!("f() async {{ {}x; }}", "await ".repeat(DEPTH)),
        ),
        (
            "conditionals",
            format!("var x = {}c;", "a ? b : ".repeat(DEPTH)),
        ),
        (
            "assignments",
            format!("f() {{ {}1; }}", "a = ".repeat(DEPTH)),
        ),
        (
            "if_statements",
            format!("f() {{ {}; }}", "if (a) ".repeat(DEPTH)),
        ),
        ("closures", format!("var x = {}1;", "() => ".repeat(DEPTH))),
        (
            "interpolations",
            format!("var x = {}1{};", "'${".repeat(DEPTH), "}'".repeat(DEPTH)),
        ),
        (
            "function_types",
            format!(
                "{}int{} x;",
                "void Function(".repeat(DEPTH),
                ")".repeat(DEPTH)
            ),
        ),
        (
            "patterns",
            format!(
                "f() {{ var {}a{} = x; }}",
                "[".repeat(DEPTH),
                "]".repeat(DEPTH)
            ),
        ),
    ];
    let mut paths = Vec::new();
    for (name, source) in &shapes {
        let path = directory.join(format!("{name}.dart"));
        fs::write(&path, source).unwrap();
        paths.push(path.to_string_lossy().into_owned());
    }
    let output = run_helper(&[], &paths);
    let lines = output_lines(&output);
    println!("{}", lines.join("\n"));
    assert!(
        output.status.success(),
        "the helper died: {:?}",
        output.status
    );
    assert_eq!(lines.len(), shapes.len() + 1);
    fs::remove_dir_all(&directory).unwrap();
}

/// Files of every kind the helper answers: clean, flagged (one and several
/// diagnostics), unreadable, not UTF-8, with a byte order mark, and names
/// with spaces and tabs.
fn mixed_paths(directory: &std::path::Path, count: usize) -> Vec<String> {
    let mut paths = Vec::new();
    for index in 0..count {
        let path = directory.join(format!("file {index}.dart"));
        match index % 7 {
            0 => fs::write(&path, format!("void main() {{ print({index}); }}\n")).unwrap(),
            1 => fs::write(&path, format!("void main() {{ print({index})\n")).unwrap(),
            2 => fs::write(&path, "class {\nvar x = ;\n").unwrap(),
            3 => {} // never written: unreadable
            4 => fs::write(&path, [0x76, 0x61, 0x72, 0xFF, 0x3B]).unwrap(),
            5 => fs::write(&path, b"\xEF\xBB\xBFvoid main() {}\n").unwrap(),
            _ => fs::write(
                &path,
                format!("{}int{} x{index};", "List<".repeat(40), ">".repeat(40)),
            )
            .unwrap(),
        }
        paths.push(path.to_string_lossy().into_owned());
    }
    paths
}

/// Several files are parsed at once, and what comes out is exactly what one
/// file at a time gives: the same lines in the same order.
#[test]
fn parallel_answers_are_the_serial_answers_in_order() {
    let directory = scratch_directory("parallel");
    let paths = mixed_paths(&directory, 300);
    for flags in [&[][..], &["--diagnostics"][..]] {
        let serial = run_helper(&[flags, &["--jobs", "1"]].concat(), &paths);
        assert!(serial.status.success());
        assert!(output_lines(&serial).len() > paths.len());
        for jobs in ["2", "4", "16"] {
            let parallel = run_helper(&[flags, &["--jobs", jobs]].concat(), &paths);
            assert!(
                parallel.status.success(),
                "--jobs {jobs}: {:?}",
                parallel.status
            );
            assert_eq!(
                output_lines(&parallel),
                output_lines(&serial),
                "--jobs {jobs} {flags:?}"
            );
            assert!(parallel.stderr.is_empty());
        }
        let by_default = run_helper(flags, &paths);
        assert_eq!(
            output_lines(&by_default),
            output_lines(&serial),
            "default {flags:?}"
        );
    }
    fs::remove_dir_all(&directory).unwrap();
}

/// A file that takes long does not hold back the files after it from being
/// parsed, only from being answered: answers stay in the order asked.
#[test]
fn a_slow_file_first_keeps_the_order() {
    let directory = scratch_directory("slow_first");
    let slow = directory.join("slow.dart");
    fs::write(
        &slow,
        format!("{}int{} x;", "List<".repeat(3_000), ">".repeat(3_000)),
    )
    .unwrap();
    let mut paths = vec![slow.to_string_lossy().into_owned()];
    paths.extend(mixed_paths(&directory, 50));
    let serial = run_helper(&["--jobs", "1"], &paths);
    let parallel = run_helper(&["--jobs", "4"], &paths);
    assert!(parallel.status.success());
    assert_eq!(output_lines(&parallel), output_lines(&serial));
    fs::remove_dir_all(&directory).unwrap();
}

#[test]
fn a_job_count_that_is_not_a_positive_number_is_refused() {
    for arguments in [
        &["--jobs"][..],
        &["--jobs", "0"],
        &["--jobs", "many"],
        &["--jobs", "-2"],
    ] {
        let output = run_helper(arguments, &[]);
        assert_eq!(output.status.code(), Some(64), "{arguments:?}");
        assert!(output.stdout.is_empty(), "{arguments:?}");
    }
}
