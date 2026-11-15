// Ours (not a ported file): helpers the integration tests share.
#![allow(dead_code)]

use std::path::{Path, PathBuf};
use std::process::Command;

use dartvel_aot::Mode;

pub fn programs_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/programs")
}

/// Every benchmark program, by name (without `.dart`).
pub fn programs() -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(programs_dir())
        .unwrap()
        .filter_map(|e| {
            let name = e.unwrap().file_name().into_string().unwrap();
            name.strip_suffix(".dart").map(str::to_string)
        })
        .collect();
    names.sort();
    names
}

pub fn scratch(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("dartvel_aot-{test}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Compiles programs/<name>.dart in [mode] to an executable in [dir].
pub fn build(name: &str, mode: Mode, dir: &Path) -> (PathBuf, dartvel_aot::Compiled) {
    let path = programs_dir().join(format!("{name}.dart"));
    let source = std::fs::read_to_string(&path).unwrap();
    let compiled = dartvel_aot::compile(&source, path.to_str().unwrap(), mode)
        .unwrap_or_else(|e| panic!("{name} ({}) did not compile: {e}", mode.name()));
    let exe = dir.join(format!("{name}-{}", mode.name()));
    dartvel_aot::build_executable(&compiled.c_source, &exe)
        .unwrap_or_else(|e| panic!("{name} ({}) did not build: {e}", mode.name()));
    (exe, compiled)
}

pub fn run(exe: &Path) -> (Vec<u8>, i32) {
    let out = Command::new(exe).output().unwrap();
    (out.stdout, out.status.code().unwrap_or(-1))
}

/// The stock Dart SDK, when one is on PATH (or in $DART).
pub fn dart() -> Option<String> {
    let dart = std::env::var("DART").unwrap_or_else(|_| "dart".into());
    Command::new(&dart)
        .arg("--version")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|_| dart)
}
