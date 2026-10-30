// Port of rust/oracle/parser_dump.dart: the Rust side of the parser oracle.
//
// Writes, for every `.dart` file under the corpus roots, the listener event
// trace the Rust parser produces, in exactly the format the Dart oracle
// writes for the upstream parser, so the two outputs can be compared byte
// for byte.
//
// Usage: parser_dump [--bench=N] --out <dir> <root>...

use std::fs;
use std::path::{Path, PathBuf};

fn main() {
    let mut out: Option<String> = None;
    let mut bench = 0usize;
    let mut roots: Vec<String> = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if let Some(n) = arg.strip_prefix("--bench=") {
            bench = n.parse().expect("--bench=N");
        } else if arg == "--out" {
            out = args.next();
        } else {
            roots.push(arg);
        }
    }
    if roots.is_empty() || (out.is_none() && bench == 0) {
        eprintln!("usage: parser_dump [--bench=N] --out <dir> <root>...");
        std::process::exit(64);
    }

    let inputs = corpus_files(&roots);

    let out = out.unwrap();
    for (path, relative) in &inputs {
        let bytes = fs::read(path).expect("read corpus file");
        let dump = dump_file(&bytes);
        let target = PathBuf::from(format!("{out}/{relative}.trace"));
        fs::create_dir_all(target.parent().unwrap()).expect("create output directory");
        fs::write(&target, dump).expect("write dump");
    }
}

/// Every `.dart` file under [roots] as (path, label/relative path), sorted by
/// relative path within each root, as the Dart oracle lists them.
fn corpus_files(roots: &[String]) -> Vec<(PathBuf, String)> {
    let mut seen: std::collections::HashMap<String, usize> = Default::default();
    let mut result = Vec::new();
    for root in roots {
        let dir = std::path::absolute(root).expect("absolute corpus root");
        let base = dir.file_name().unwrap().to_string_lossy().to_string();
        let count = seen.entry(base.clone()).or_insert(0);
        *count += 1;
        let label = if *count == 1 {
            base
        } else {
            format!("{base}~{count}")
        };
        let mut files = Vec::new();
        walk(&dir, &dir, &label, &mut files);
        files.sort_by(|a: &(PathBuf, String), b| a.1.as_bytes().cmp(b.1.as_bytes()));
        result.extend(files);
    }
    result
}

fn walk(root: &Path, dir: &Path, label: &str, files: &mut Vec<(PathBuf, String)>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if meta.is_dir() {
            walk(root, &path, label, files);
        } else if meta.is_file() && path.to_string_lossy().ends_with(".dart") {
            let relative = path
                .strip_prefix(root)
                .unwrap()
                .to_string_lossy()
                .to_string();
            files.push((path.clone(), format!("{label}/{relative}")));
        }
    }
}

/// The parser is not ported yet: every trace is empty.
fn dump_file(_bytes: &[u8]) -> String {
    String::new()
}
