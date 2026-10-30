// Not an upstream file: the differential test of the Rust port of
// flutter/impeller/geometry against the upstream C++, which stays in this
// checkout as the oracle.
//
// Builds oracle/geometry_dump.cc against the upstream geometry sources with
// clang++ and libc++ (as the engine is built), runs it and the port's
// geometry_dump binary over the same seeds, and fails unless the outputs,
// stdout and stderr, are byte-identical. Floats are printed as bit patterns.
//
//   GEOMETRY_ORACLE_CXX        compiler (default clang++)
//   GEOMETRY_ORACLE_STDLIB     libc++ (default) or libstdc++
//   GEOMETRY_ORACLE_SEED_BASE  first seed (default 1)
//   GEOMETRY_ORACLE_SEEDS      seeds per suite (default 16)
//   GEOMETRY_ORACLE_CASES      cases per seed (default 2000)
//   GEOMETRY_ORACLE_SUITES     comma-separated subset of the suites
//   GEOMETRY_ORACLE_WORK       scratch directory (default <target>/geometry_oracle)
//
// The comparison is made in release builds (`cargo test --release`), against
// a C++ build with -DNDEBUG: the drivers feed inputs that upstream's
// FML_DCHECKs reject (NaN scales, inverted rects), which a debug build of
// either side aborts on. In a debug test run the test only reports that.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Upstream sources the oracle links, relative to engine/src.
const UPSTREAM_SOURCES: &[&str] = &[
    "flutter/fml/logging.cc",
    "flutter/fml/log_settings.cc",
    "flutter/fml/log_settings_state.cc",
    "flutter/impeller/geometry/constants.cc",
];

const SUITES: &[&str] = &["scalar", "point", "size"];

/// The compiler flags that decide floating-point results, as the engine's
/// //build/config/compiler sets them for linux-x64: -march=x86-64 (SSE2, no
/// FMA, so clang's default -ffp-contract=on has nothing to fuse), no
/// -ffast-math, and -O2 (the engine's optimize config). -fwrapv defines the
/// signed overflow upstream leaves undefined, as the port wraps.
const FP_FLAGS: &[&str] = &["-std=c++20", "-O2", "-march=x86-64", "-ffp-contract=on", "-fwrapv"];

fn engine_src() -> PathBuf {
    // CARGO_MANIFEST_DIR is engine/src/flutter/impeller/geometry/rust.
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..").canonicalize().unwrap()
}

fn env_or(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

fn work_dir() -> PathBuf {
    let dir = match std::env::var("GEOMETRY_ORACLE_WORK") {
        Ok(d) => PathBuf::from(d),
        Err(_) => {
            // The test binary lives in <target>/<profile>/deps.
            let exe = std::env::current_exe().unwrap();
            exe.parent().unwrap().parent().unwrap().parent().unwrap().join("geometry_oracle")
        }
    };
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Every header of the upstream library: the driver includes them, so a
/// change to any one rebuilds the oracle.
fn upstream_headers(src: &Path) -> Vec<PathBuf> {
    let dir = src.join("flutter/impeller/geometry");
    let mut out = Vec::new();
    for entry in std::fs::read_dir(&dir).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_some_and(|e| e == "h") {
            out.push(path);
        }
    }
    out
}

/// Builds the C++ oracle unless an up-to-date binary is already there.
pub fn build_oracle() -> PathBuf {
    let src = engine_src();
    let stdlib = env_or("GEOMETRY_ORACLE_STDLIB", "libc++");
    let cxx = env_or("GEOMETRY_ORACLE_CXX", if stdlib == "libc++" { "clang++" } else { "g++" });
    let out = work_dir().join(format!("geometry_dump_{stdlib}"));
    let driver = src.join("flutter/impeller/geometry/rust/oracle/geometry_dump.cc");
    let mut inputs: Vec<PathBuf> = vec![driver];
    // This file too: it holds the compiler flags.
    inputs.push(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/oracle.rs"));
    inputs.extend(upstream_headers(&src));
    inputs.extend(UPSTREAM_SOURCES.iter().map(|s| src.join(s)));
    let newest_input = inputs
        .iter()
        .map(|p| std::fs::metadata(p).and_then(|m| m.modified()).unwrap())
        .max()
        .unwrap();
    if let Ok(built) = std::fs::metadata(&out).and_then(|m| m.modified()) {
        if built >= newest_input {
            return out;
        }
    }
    // Compile from engine/src with relative paths, as the engine's build
    // does. Upstream includes both "impeller/geometry/…" and
    // "flutter/impeller/geometry/…" (and "fml/…"), so both roots are on the
    // include path.
    let mut cmd = Command::new(&cxx);
    cmd.current_dir(&src);
    cmd.args(FP_FLAGS).arg("-w").arg("-DNDEBUG");
    if stdlib == "libc++" {
        cmd.arg("-stdlib=libc++");
    }
    cmd.arg("-I").arg(".").arg("-I").arg("flutter").arg("-o").arg(&out);
    cmd.arg("flutter/impeller/geometry/rust/oracle/geometry_dump.cc");
    cmd.args(UPSTREAM_SOURCES).arg("-lm");
    let status = cmd.status().unwrap_or_else(|e| panic!("cannot run {cxx}: {e}"));
    assert!(status.success(), "building the C++ oracle with {cxx} failed");
    out
}

fn run(bin: &Path, args: &[&str]) -> (Vec<u8>, Vec<u8>) {
    let out = Command::new(bin).args(args).output().unwrap();
    assert!(
        out.status.success(),
        "{} {:?} failed ({}): {}",
        bin.display(),
        args,
        out.status,
        String::from_utf8_lossy(&out.stderr)
    );
    (out.stdout, out.stderr)
}

fn first_difference(a: &[u8], b: &[u8]) -> String {
    let a = String::from_utf8_lossy(a);
    let b = String::from_utf8_lossy(b);
    let (mut al, mut bl) = (a.lines(), b.lines());
    let mut n = 1;
    loop {
        match (al.next(), bl.next()) {
            (Some(x), Some(y)) if x == y => n += 1,
            (x, y) => return format!("line {n}:\n  c++:  {x:?}\n  rust: {y:?}"),
        }
    }
}

#[test]
fn oracle_matches_upstream() {
    if cfg!(debug_assertions) {
        eprintln!("oracle: compared in release builds only (cargo test --release)");
        return;
    }
    let oracle = build_oracle();
    let port = PathBuf::from(env!("CARGO_BIN_EXE_geometry_dump"));
    let base: u64 = env_or("GEOMETRY_ORACLE_SEED_BASE", "1").parse().unwrap();
    let seeds: u64 = env_or("GEOMETRY_ORACLE_SEEDS", "16").parse().unwrap();
    let cases = env_or("GEOMETRY_ORACLE_CASES", "2000");
    let only = env_or("GEOMETRY_ORACLE_SUITES", "");
    let suites: Vec<&str> = SUITES
        .iter()
        .copied()
        .filter(|s| only.is_empty() || only.split(',').any(|o| o == *s))
        .collect();
    let mut failures = Vec::new();
    let mut compared = 0usize;
    for suite in &suites {
        for seed in base..base + seeds {
            let seed = seed.to_string();
            let args = [*suite, seed.as_str(), cases.as_str()];
            let (expected, expected_log) = run(&oracle, &args);
            let (actual, actual_log) = run(&port, &args);
            compared += expected.len() + expected_log.len();
            assert!(!expected.is_empty(), "{suite} printed nothing");
            if expected != actual {
                failures.push(format!("{suite} seed {seed}: {}", first_difference(&expected, &actual)));
            }
            if expected_log != actual_log {
                failures.push(format!(
                    "{suite} seed {seed} (stderr): {}",
                    first_difference(&expected_log, &actual_log)
                ));
            }
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} runs differ ({} bytes of oracle output):\n{}",
        failures.len(),
        suites.len() as u64 * seeds,
        compared,
        failures.join("\n")
    );
    eprintln!(
        "oracle: {} suites x {seeds} seeds x {cases} cases, {compared} bytes identical",
        suites.len()
    );
}
