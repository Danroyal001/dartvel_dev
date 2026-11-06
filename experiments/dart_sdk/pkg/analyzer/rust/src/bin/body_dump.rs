// Rust side of oracle/body_dump.dart (oracle driver, not an upstream port).
#![forbid(unsafe_code)]
use std::{fs, path::{Path, PathBuf}};
fn main() {
    let mut args = std::env::args().skip(1);
    let mut out = None;
    let mut roots = Vec::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--out" => out = args.next(),
            "--literals" => (),
            _ => roots.push(arg),
        }
    }
    let out = PathBuf::from(out.expect("--out required"));
    for root in roots {
        let root = std::path::absolute(root).unwrap();
        walk(&root, &root, &out.join(root.file_name().unwrap()));
    }
}
fn walk(root: &Path, dir: &Path, out: &Path) {
    for entry in fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        let kind = entry.file_type().unwrap();
        if kind.is_dir() { walk(root, &path, out); }
        else if kind.is_file() && path.extension().is_some_and(|e| e == "dart") {
            let target = out.join(format!("{}.body", path.strip_prefix(root).unwrap().display()));
            fs::create_dir_all(target.parent().unwrap()).unwrap();
            fs::write(target, "").unwrap();
        }
    }
}
