// Differential test of the kernel binary reader and writer against upstream
// (not a mirrored file; see ../README.md).
//
// For every component in the corpus, upstream's BinaryBuilder reads it and
// its BinaryPrinter writes it (oracle/roundtrip.dart, on this checkout's
// pkg/kernel), the Rust port does the same (src/bin/kernel_roundtrip.rs),
// and the two outputs must be byte for byte identical.
//
// Environment:
//   DART          the Dart executable (default: `dart` on PATH).
//   KERNEL_CORPUS `.dill` files and directories of them, separated by `:`
//                 (default: target/kernel_oracle/corpus under the SDK root,
//                 which README.md says how to fill). A relative path is
//                 resolved against the SDK root.
//   KERNEL_WORK   scratch directory (default: target/kernel_oracle/work),
//                 relative to the SDK root.
//
// Every child process runs under a time limit.
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

const TIME_LIMIT: Duration = Duration::from_secs(1800);

/// The packages of this checkout the oracle needs.
const SDK_PACKAGES: &[&str] = &["kernel", "_fe_analyzer_shared", "meta"];

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap()
}

fn dart() -> String {
    std::env::var("DART").unwrap_or_else(|_| "dart".to_string())
}

fn under_root(path: &str) -> PathBuf {
    let path = PathBuf::from(path);
    if path.is_absolute() {
        path
    } else {
        sdk_root().join(path)
    }
}

fn work_dir() -> PathBuf {
    under_root(&std::env::var("KERNEL_WORK").unwrap_or_else(|_| "target/kernel_oracle/work".into()))
}

fn write_package_config(work: &Path) -> PathBuf {
    let packages: Vec<String> = SDK_PACKAGES
        .iter()
        .map(|name| {
            format!(
                "    {{\"name\": \"{name}\", \"rootUri\": \"file://{}/\", \"packageUri\": \"lib/\"}}",
                sdk_root().join("pkg").join(name).display()
            )
        })
        .collect();
    let config = format!(
        "{{\n  \"configVersion\": 2,\n  \"packages\": [\n{}\n  ]\n}}\n",
        packages.join(",\n")
    );
    let path = work.join("package_config.json");
    fs::write(&path, config).unwrap();
    path
}

fn run(command: &mut Command) {
    let description = format!("{command:?}");
    let mut child = command
        .spawn()
        .unwrap_or_else(|e| panic!("cannot run {description}: {e}"));
    let deadline = Instant::now() + TIME_LIMIT;
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success(), "{description} failed: {status}");
            return;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            panic!("{description} exceeded {TIME_LIMIT:?}");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn corpus() -> Vec<PathBuf> {
    let roots =
        std::env::var("KERNEL_CORPUS").unwrap_or_else(|_| "target/kernel_oracle/corpus".into());
    let mut files = Vec::new();
    for root in roots.split(':').filter(|r| !r.is_empty()) {
        let root = under_root(root);
        if root.is_dir() {
            let mut found: Vec<PathBuf> = fs::read_dir(&root)
                .unwrap()
                .flatten()
                .map(|e| e.path())
                .filter(|p| p.extension().is_some_and(|e| e == "dill"))
                .collect();
            found.sort();
            files.extend(found);
        } else {
            files.push(root);
        }
    }
    assert!(!files.is_empty(), "the kernel corpus is empty (see README.md)");
    files
}

#[test]
fn round_trips_are_identical_to_upstream() {
    let work = work_dir();
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(work.join("dart")).unwrap();
    fs::create_dir_all(work.join("rust")).unwrap();
    let package_config = write_package_config(&work);
    let files = corpus();
    let mut dart_args = Vec::new();
    let mut rust_args = Vec::new();
    for (i, file) in files.iter().enumerate() {
        let name = format!("{i:04}-{}", file.file_name().unwrap().to_string_lossy());
        dart_args.push(file.clone());
        dart_args.push(work.join("dart").join(&name));
        rust_args.push(file.clone());
        rust_args.push(work.join("rust").join(&name));
    }
    run(Command::new(dart())
        .arg(format!("--packages={}", package_config.display()))
        .arg(sdk_root().join("pkg/kernel/rust/oracle/roundtrip.dart"))
        .args(&dart_args));
    run(Command::new(env!("CARGO_BIN_EXE_kernel_roundtrip")).args(&rust_args));
    let mut differences = Vec::new();
    for pair in dart_args.chunks(2) {
        let expected = fs::read(&pair[1]).unwrap();
        let rust_out = work.join("rust").join(pair[1].file_name().unwrap());
        let actual = fs::read(&rust_out).unwrap();
        if expected != actual {
            let first = expected
                .iter()
                .zip(&actual)
                .position(|(a, b)| a != b)
                .unwrap_or(expected.len().min(actual.len()));
            differences.push(format!(
                "{}: {} bytes upstream, {} in Rust, first difference at byte {first}",
                pair[0].display(),
                expected.len(),
                actual.len()
            ));
        } else {
            fs::remove_file(&pair[1]).unwrap();
            fs::remove_file(&rust_out).unwrap();
        }
    }
    assert!(
        differences.is_empty(),
        "{} of {} components differ:\n{}",
        differences.len(),
        files.len(),
        differences.join("\n")
    );
}
