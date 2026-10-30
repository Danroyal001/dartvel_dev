// Not an upstream file: the differential test of the Rust port of flutter/fml
// against the upstream C++, which stays in this checkout as the oracle.
//
// Builds oracle/fml_dump.cc against the upstream fml sources with the system
// C++ compiler (clang++ with libc++ by default, as the engine is built), runs
// it and the port's fml_dump binary over the same seeds, and fails unless the
// outputs, stdout and stderr, are byte-identical.
//
//   FML_ORACLE_CXX        compiler (default clang++)
//   FML_ORACLE_STDLIB     libc++ (default) or libstdc++
//   FML_ORACLE_SEED_BASE  first seed (default 1)
//   FML_ORACLE_SEEDS      seeds per suite (default 16)
//   FML_ORACLE_CASES      cases per seed (default 250)
//   FML_ORACLE_SUITES     comma-separated subset of the suites (default all)
//   FML_ORACLE_WORK       scratch directory (default <target>/fml_oracle)
//   FML_ORACLE_TIMEOUT    seconds one driver run may take (default 300)
//
// The C++ is built with -DNDEBUG in release test runs and without it in debug
// ones, matching the port's debug_assertions.

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
    "flutter/fml/message_loop.cc",
    "flutter/fml/message_loop_impl.cc",
    "flutter/fml/platform/linux/message_loop_linux.cc",
    "flutter/fml/platform/linux/timerfd.cc",
    "flutter/fml/task_runner.cc",
    "flutter/fml/task_runner_util.cc",
    "flutter/fml/thread.cc",
    "flutter/fml/concurrent_message_loop.cc",
    "flutter/fml/concurrent_message_loop_factory.cc",
    "flutter/fml/raster_thread_merger.cc",
    "flutter/fml/shared_thread_merger.cc",
    "flutter/fml/memory/task_runner_checker.cc",
    "flutter/fml/unique_fd.cc",
];

/// Headers that stand in for upstream ones the oracle cannot build against,
/// searched before engine/src (see the files for why).
const SHIM_DIR: &str = "flutter/fml/rust/oracle/shim";

const SUITES: &[&str] = &[
    "time", "strings", "codec", "hash", "endian", "trie", "queues", "loop", "merger", "thread",
    "logging",
];

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
    // The oracle is built with NDEBUG exactly when the port is built without
    // debug assertions, so that FML_DLOG and FML_DCHECK are compiled in or
    // out on both sides alike.
    let debug = cfg!(debug_assertions);
    let out = work_dir().join(format!("fml_dump_{stdlib}{}", if debug { "_debug" } else { "" }));
    let driver = src.join("flutter/fml/rust/oracle/fml_dump.cc");
    let mut inputs: Vec<PathBuf> = vec![driver.clone(), src.join(SHIM_DIR).join("flutter/fml/trace_event.h")];
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
    // Compile from engine/src with relative paths, as the engine's build does,
    // so __FILE__ (and so FML_LOG's file name) reads "flutter/fml/...".
    let mut cmd = Command::new(&cxx);
    cmd.current_dir(&src);
    cmd.arg("-std=c++20").arg("-O2").arg("-fwrapv").arg("-w");
    if !debug {
        cmd.arg("-DNDEBUG");
    }
    if stdlib == "libc++" {
        cmd.arg("-stdlib=libc++");
    }
    cmd.arg("-I").arg(SHIM_DIR).arg("-I").arg(".").arg("-o").arg(&out);
    cmd.arg("flutter/fml/rust/oracle/fml_dump.cc");
    cmd.args(UPSTREAM_SOURCES).arg("-lpthread");
    let status = cmd.status().unwrap_or_else(|e| panic!("cannot run {cxx}: {e}"));
    assert!(status.success(), "building the C++ oracle with {cxx} failed");
    out
}

/// Runs one driver, killing it after FML_ORACLE_TIMEOUT seconds (default
/// 300): a port that loses a task makes the loop and thread suites wait for
/// it forever, and a hang must fail the test, not stall it.
fn run(bin: &Path, args: &[&str]) -> (Vec<u8>, Vec<u8>) {
    use std::io::Read;
    use std::process::Stdio;
    let timeout: u64 = env_or("FML_ORACLE_TIMEOUT", "300").parse().unwrap();
    let mut child =
        Command::new(bin).args(args).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
    // Drain both pipes on threads so that a chatty child cannot block.
    let mut stdout = child.stdout.take().unwrap();
    let mut stderr = child.stderr.take().unwrap();
    let out_reader = std::thread::spawn(move || {
        let mut v = Vec::new();
        stdout.read_to_end(&mut v).unwrap();
        v
    });
    let err_reader = std::thread::spawn(move || {
        let mut v = Vec::new();
        stderr.read_to_end(&mut v).unwrap();
        v
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(timeout);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if std::time::Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!("{} {:?} did not finish within {timeout} s", bin.display(), args);
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    };
    struct Output {
        status: std::process::ExitStatus,
        stdout: Vec<u8>,
        stderr: Vec<u8>,
    }
    let out = Output { status, stdout: out_reader.join().unwrap(), stderr: err_reader.join().unwrap() };
    assert!(
        out.status.success(),
        "{} {:?} failed: {}",
        bin.display(),
        args,
        String::from_utf8_lossy(&out.stderr)
    );
    (out.stdout, out.stderr)
}

/// Replaces the pointer in SharedThreadMerger::DecrementLease's warning
/// ("... caller=0x55d0c0ffee00"), the one address upstream logs, with
/// `<ptr>`: where the allocator puts a merger is not behaviour.
fn normalize_log(log: &[u8]) -> Vec<u8> {
    const KEY: &[u8] = b"caller=0x";
    let mut out = Vec::with_capacity(log.len());
    let mut i = 0;
    while i < log.len() {
        if log[i..].starts_with(KEY) {
            out.extend_from_slice(b"caller=<ptr>");
            i += KEY.len();
            while i < log.len() && log[i].is_ascii_hexdigit() {
                i += 1;
            }
        } else {
            out.push(log[i]);
            i += 1;
        }
    }
    out
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
            let (expected, expected_log) = run(&oracle, &args);
            let (actual, actual_log) = run(&port, &args);
            let (expected_log, actual_log) = (normalize_log(&expected_log), normalize_log(&actual_log));
            compared += expected.len() + expected_log.len();
            if expected != actual {
                failures.push(format!(
                    "{suite} seed {seed}: {}",
                    first_difference(&expected, &actual)
                ));
            }
            // Logs (FML_LOG) go to stderr and must match too.
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
    eprintln!("oracle: {} suites x {seeds} seeds x {cases} cases, {compared} bytes identical", suites.len());
}
