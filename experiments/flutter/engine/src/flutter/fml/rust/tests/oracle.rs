// Not an upstream file: the differential test of the Rust port of flutter/fml
// against the upstream C++, which stays in this checkout as the oracle.
//
// Builds oracle/fml_dump.cc against the upstream fml sources with the system
// C++ compiler (clang++ with libc++ by default, as the engine is built), runs
// it and the port's fml_dump binary over the same seeds, and fails unless the
// outputs are byte-identical.
//
//   FML_ORACLE_CXX        compiler (default clang++)
//   FML_ORACLE_STDLIB     libc++ (default) or libstdc++
//   FML_ORACLE_SEED_BASE  first seed (default 1)
//   FML_ORACLE_SEEDS      seeds per suite (default 16)
//   FML_ORACLE_CASES      cases per seed (default 250)
//   FML_ORACLE_SUITES     comma-separated subset of the suites (default all)
//   FML_ORACLE_WORK       scratch directory (default <target>/fml_oracle)

use std::path::{Path, PathBuf};
use std::process::Command;

/// Upstream sources the oracle links, relative to engine/src.
const UPSTREAM_SOURCES: &[&str] = &[
    "flutter/fml/ascii_trie.cc",
    "flutter/fml/base32.cc",
    "flutter/fml/hex_codec.cc",
    "flutter/fml/string_conversion.cc",
    "flutter/fml/delayed_task.cc",
    "flutter/fml/task_source.cc",
    "flutter/fml/message_loop_task_queues.cc",
    "flutter/fml/logging.cc",
    "flutter/fml/log_settings.cc",
    "flutter/fml/log_settings_state.cc",
    "flutter/fml/time/time_point.cc",
    "flutter/fml/synchronization/count_down_latch.cc",
    "flutter/fml/synchronization/waitable_event.cc",
];

const SUITES: &[&str] = &["time", "strings", "codec", "hash", "endian", "trie", "queues"];

fn engine_src() -> PathBuf {
    // CARGO_MANIFEST_DIR is engine/src/flutter/fml/rust.
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

fn env_or(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

fn work_dir() -> PathBuf {
    let dir = match std::env::var("FML_ORACLE_WORK") {
        Ok(d) => PathBuf::from(d),
        Err(_) => {
            // The test binary lives in <target>/<profile>/deps.
            let exe = std::env::current_exe().unwrap();
            exe.parent().unwrap().parent().unwrap().parent().unwrap().join("fml_oracle")
        }
    };
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Builds the C++ oracle unless an up-to-date binary is already there.
pub fn build_oracle() -> PathBuf {
    let src = engine_src();
    let stdlib = env_or("FML_ORACLE_STDLIB", "libc++");
    let cxx = env_or("FML_ORACLE_CXX", if stdlib == "libc++" { "clang++" } else { "g++" });
    let out = work_dir().join(format!("fml_dump_{stdlib}"));
    let driver = src.join("flutter/fml/rust/oracle/fml_dump.cc");
    let mut inputs: Vec<PathBuf> = vec![driver.clone()];
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
    let mut cmd = Command::new(&cxx);
    cmd.arg("-std=c++20").arg("-O2").arg("-DNDEBUG").arg("-fwrapv").arg("-w");
    if stdlib == "libc++" {
        cmd.arg("-stdlib=libc++");
    }
    cmd.arg("-I").arg(&src).arg("-o").arg(&out);
    cmd.args(&inputs).arg("-lpthread");
    let status = cmd.status().unwrap_or_else(|e| panic!("cannot run {cxx}: {e}"));
    assert!(status.success(), "building the C++ oracle with {cxx} failed");
    out
}

fn run(bin: &Path, args: &[&str]) -> Vec<u8> {
    let out = Command::new(bin).args(args).output().unwrap();
    assert!(
        out.status.success(),
        "{} {:?} failed: {}",
        bin.display(),
        args,
        String::from_utf8_lossy(&out.stderr)
    );
    out.stdout
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
    let oracle = build_oracle();
    let port = PathBuf::from(env!("CARGO_BIN_EXE_fml_dump"));
    let base: u64 = env_or("FML_ORACLE_SEED_BASE", "1").parse().unwrap();
    let seeds: u64 = env_or("FML_ORACLE_SEEDS", "16").parse().unwrap();
    let cases = env_or("FML_ORACLE_CASES", "250");
    let mut failures = Vec::new();
    let mut compared = 0usize;
    let only = env_or("FML_ORACLE_SUITES", "");
    let suites: Vec<&str> = SUITES
        .iter()
        .copied()
        .filter(|s| only.is_empty() || only.split(',').any(|o| o == *s))
        .collect();
    for suite in &suites {
        for seed in base..base + seeds {
            let seed = seed.to_string();
            let args = [*suite, seed.as_str(), cases.as_str()];
            let expected = run(&oracle, &args);
            let actual = run(&port, &args);
            compared += expected.len();
            if expected != actual {
                failures.push(format!(
                    "{suite} seed {seed}: {}",
                    first_difference(&expected, &actual)
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
    eprintln!("oracle: {} suites x {seeds} seeds x {cases} cases, {compared} bytes identical", suites.len());
}
