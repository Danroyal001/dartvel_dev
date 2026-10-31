// Not an upstream file: checks that every `unsafe` in the port says why it is
// sound.
//
// Each unsafe block, unsafe fn, unsafe impl, unsafe trait and extern block
// under src/ must have a `SAFETY:` comment (or, for an unsafe fn or trait, a
// `# Safety` doc section) within the 14 lines above it, which covers a
// comment placed above the statement an unsafe block sits in. The README's
// "Unsafe code" table lists the sites; this keeps a new one from arriving
// without its reason.

use std::path::{Path, PathBuf};

const WINDOW: usize = 14;

/// The 1-based lines of `text` that use `unsafe` with no reason above them.
fn unexplained(text: &str) -> Vec<usize> {
    let lines: Vec<&str> = text.lines().collect();
    let mut missing = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        let code = line.split("//").next().unwrap_or("");
        if !code.split(|c: char| !c.is_alphanumeric() && c != '_').any(|word| word == "unsafe") {
            continue;
        }
        // A function-pointer type (`type F = unsafe extern "C" fn(..)`) is
        // not unsafe code.
        if code.trim_start().starts_with("type ") {
            continue;
        }
        let from = i.saturating_sub(WINDOW);
        let explained = lines[from..=i].iter().any(|l| l.contains("SAFETY") || l.contains("# Safety"));
        if !explained {
            missing.push(i + 1);
        }
    }
    missing
}

fn rust_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            rust_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "rs") {
            out.push(path);
        }
    }
}

#[test]
fn the_checker_finds_an_unexplained_block() {
    assert_eq!(unexplained("fn f() {\n    let p = unsafe { g() };\n}\n"), vec![2]);
    assert_eq!(unexplained("unsafe extern \"C\" {\n    fn g();\n}\n"), vec![1]);
    assert_eq!(unexplained("// SAFETY: g has no preconditions.\nlet p = unsafe { g() };\n"), Vec::<usize>::new());
    assert_eq!(unexplained("// not unsafe code: unsafe { }\ntype F = unsafe extern \"C\" fn();\n"), Vec::<usize>::new());
}

#[test]
fn every_unsafe_in_the_port_says_why() {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    rust_files(&src, &mut files);
    files.sort();
    let mut failures = Vec::new();
    let mut sites = 0;
    for file in &files {
        let text = std::fs::read_to_string(file).unwrap();
        sites += text
            .lines()
            .filter(|l| l.split("//").next().unwrap_or("").contains("unsafe"))
            .count();
        for line in unexplained(&text) {
            failures.push(format!("{}:{line}", file.strip_prefix(&src).unwrap().display()));
        }
    }
    assert!(failures.is_empty(), "unsafe without a SAFETY comment:\n{}", failures.join("\n"));
    eprintln!("unsafe audit: {sites} lines with unsafe in {} files, all explained", files.len());
}
