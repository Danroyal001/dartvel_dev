// Not an upstream file: keeps the driver's start-up as small as the C++
// driver's, which the README's cold-start row measures.
//
// std's `fn main` runs its runtime set-up first: it reads /proc/self/maps to
// find the main thread's stack guard, installs SIGSEGV and SIGBUS handlers on
// an alternate signal stack, ignores SIGPIPE and polls fds 0-2. None of it
// does anything for a driver that prints and exits, and on this host it cost
// a fifth of a cold start. The driver enters through a C `main` instead, and
// this test fails if the runtime set-up comes back.

use std::process::Command;

#[test]
fn the_driver_starts_without_std_runtime_setup() {
    let Ok(probe) = Command::new("strace").arg("-V").output() else {
        eprintln!("strace not installed: start-up system calls not checked");
        return;
    };
    assert!(probe.status.success(), "strace -V failed");
    let log = std::env::temp_dir().join(format!("geometry_cold_start_{}.txt", std::process::id()));
    let status = Command::new("strace")
        .args(["-f", "-e", "trace=openat,sigaltstack,poll,brk", "-o"])
        .arg(&log)
        .arg(env!("CARGO_BIN_EXE_geometry_dump"))
        .output()
        .unwrap()
        .status;
    // No arguments: the driver prints its usage and exits with 2.
    assert_eq!(status.code(), Some(2));
    let trace = std::fs::read_to_string(&log).unwrap();
    let _ = std::fs::remove_file(&log);
    for call in ["/proc/self/maps", "sigaltstack(", "poll("] {
        assert!(!trace.contains(call), "the driver's start-up made `{call}`:\n{trace}");
    }
    // The loader asks for the break once (`brk(NULL)`); a second `brk` is the
    // heap being set up, which printing the usage error does not need.
    let breaks = trace.matches("brk(").count();
    assert!(breaks <= 1, "the driver set up a heap before printing its usage ({breaks} brk calls):\n{trace}");
}

#[test]
fn the_driver_still_reads_its_arguments_and_flushes_its_output() {
    let out = Command::new(env!("CARGO_BIN_EXE_geometry_dump")).args(["scalar", "1", "3"]).output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert!(!out.stdout.is_empty(), "no output for three scalar cases");
    let unknown = Command::new(env!("CARGO_BIN_EXE_geometry_dump")).args(["nope", "1", "1"]).output().unwrap();
    assert_eq!(unknown.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&unknown.stderr).contains("unknown suite nope"));
}
