// Differential test of damaged input against upstream (not a mirrored file;
// see ../README.md).
//
// Each base file is damaged many ways (cut short at a length, or one byte
// flipped with a mask), and each damaged file is read and written by
// upstream (oracle/damage.dart) and by the port (src/bin/kernel_damage.rs).
// For every mutation both must do the same: write the same bytes, or throw
// the same thing (upstream's exception, as its toString() prints it).
//
// Environment:
//   DART          the Dart executable (default: `dart` on PATH).
//   DAMAGE_INPUTS base files, separated by `:` (default: the fixtures and
//                 the corpus's hello-aot.dill). A file of up to 4 KiB is
//                 damaged at every offset; a larger one at its first and last
//                 256 bytes and DAMAGE_SAMPLES more offsets (default 60;
//                 upstream takes about 0.4 s per mutation of hello-aot.dill),
//                 the same ones on every run.
//   KERNEL_WORK   scratch directory (default: target/kernel_oracle/damage).
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

fn under_root(path: &str) -> PathBuf {
    let path = PathBuf::from(path);
    if path.is_absolute() { path } else { sdk_root().join(path) }
}

const MASKS: [u8; 4] = [0x01, 0x40, 0x80, 0xFF];

/// The mutations of a file of [length] bytes.
fn mutations(length: usize, samples: usize) -> Vec<String> {
    let offsets: Vec<usize> = if length <= 4096 {
        (0..length).collect()
    } else {
        // The first and last 256 bytes (header, index), then offsets spread
        // over the file by a fixed linear congruential sequence.
        let mut offsets: Vec<usize> = (0..256).chain(length - 256..length).collect();
        let mut state: u64 = 0x2545F4914F6CDD1D;
        for _ in 0..samples {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            offsets.push((state >> 33) as usize % length);
        }
        offsets.sort_unstable();
        offsets.dedup();
        offsets
    };
    let mut lines = Vec::new();
    for &offset in &offsets {
        lines.push(format!("T {offset}"));
        for mask in MASKS {
            lines.push(format!("F {offset} {mask}"));
        }
    }
    lines
}

/// [line] with every `:<digits>)` as `:0)`. Upstream's `already bound`
/// and orphan messages print nodes as `(Type:hashCode)`, and a node's
/// `hashCode` is its identity hash, which the VM picks at random: two
/// upstream runs over the same input print different numbers. The port
/// prints 0; everything around the number must match.
fn without_hash_codes(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut out = String::with_capacity(line.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b':' {
            let digits = bytes[i + 1..].iter().take_while(|b| b.is_ascii_digit()).count();
            if digits > 0 && bytes.get(i + 1 + digits) == Some(&b')') {
                out.push_str(":0)");
                i += digits + 2;
                continue;
            }
        }
        let width = line[i..].chars().next().unwrap().len_utf8();
        out.push_str(&line[i..i + width]);
        i += width;
    }
    out
}

fn run(command: &mut Command) -> String {
    let output = command.output().unwrap_or_else(|e| panic!("cannot run {command:?}: {e}"));
    assert!(output.status.success(), "{command:?} failed: {}", String::from_utf8_lossy(&output.stderr));
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn damaged_input_does_what_upstream_does() {
    let work = under_root(&std::env::var("KERNEL_WORK").unwrap_or_else(|_| "target/kernel_oracle/damage".into()));
    fs::create_dir_all(&work).unwrap();
    let packages = work.join("package_config.json");
    let entries: Vec<String> = ["kernel", "_fe_analyzer_shared", "meta"]
        .iter()
        .map(|name| format!("{{\"name\": \"{name}\", \"rootUri\": \"file://{}/\", \"packageUri\": \"lib/\"}}",
            sdk_root().join("pkg").join(name).display()))
        .collect();
    fs::write(&packages, format!("{{\"configVersion\": 2, \"packages\": [{}]}}\n", entries.join(", "))).unwrap();
    let crate_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let inputs: Vec<PathBuf> = match std::env::var("DAMAGE_INPUTS") {
        Ok(list) => list.split(':').filter(|s| !s.is_empty()).map(under_root).collect(),
        Err(_) => vec![
            crate_dir.join("tests/fixtures/empty.dill"),
            crate_dir.join("tests/fixtures/hello-unlinked.dill"),
            crate_dir.join("tests/fixtures/json_roundtrip-unlinked.dill"),
            under_root("target/kernel_oracle/corpus/hello-aot.dill"),
        ],
    };
    let samples: usize = std::env::var("DAMAGE_SAMPLES").ok().and_then(|s| s.parse().ok()).unwrap_or(60);
    let dart = std::env::var("DART").unwrap_or_else(|_| "dart".into());
    let mut report = Vec::new();
    let mut total = 0;
    let mut different = 0;
    for input in &inputs {
        let length = fs::metadata(input).unwrap_or_else(|e| panic!("{}: {e}", input.display())).len() as usize;
        let lines = mutations(length, samples);
        let list = work.join(format!("{}.mutations", input.file_name().unwrap().to_string_lossy()));
        fs::write(&list, lines.join("\n") + "\n").unwrap();
        // A bounded heap: damaged lengths can make upstream allocate without
        // limit, and it then throws OutOfMemoryError ("Out of Memory") when
        // this heap is full (where exactly depends on the limit).
        let upstream = run(Command::new(&dart)
            .arg("--old_gen_heap_size=256")
            .arg(format!("--packages={}", packages.display()))
            .arg(sdk_root().join("pkg/kernel/rust/oracle/damage.dart"))
            .arg(input)
            .arg(&list));
        let port = run(Command::new(env!("CARGO_BIN_EXE_kernel_damage")).arg(input).arg(&list));
        let upstream: Vec<&str> = upstream.lines().collect();
        let port: Vec<&str> = port.lines().collect();
        assert_eq!(upstream.len(), lines.len());
        assert_eq!(port.len(), lines.len());
        let mut here = 0;
        for ((mutation, expected), actual) in lines.iter().zip(&upstream).zip(&port) {
            total += 1;
            if without_hash_codes(expected) != without_hash_codes(actual) {
                here += 1;
                if report.len() < 60 {
                    report.push(format!("{} [{mutation}]\n  upstream: {expected}\n  port:     {actual}",
                        input.file_name().unwrap().to_string_lossy()));
                }
            }
        }
        different += here;
        eprintln!("{}: {} of {} mutations differ", input.display(), here, lines.len());
    }
    assert!(different == 0, "{different} of {total} damaged inputs differ from upstream:\n{}", report.join("\n"));
}
