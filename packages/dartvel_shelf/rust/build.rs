use std::path::{Path, PathBuf};

fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    record_source_revision(Path::new(&crate_dir));

    // The header describes the C ABI, which is the same for every target, and
    // is committed. A cross build skips regenerating it: cbindgen runs `cargo
    // metadata`, which inherits the target's rustflags (cargo-xwin's
    // lld-link, for one) and fails when it applies them to the host.
    if std::env::var("TARGET").ok() != std::env::var("HOST").ok() {
        return;
    }
    let config_path = format!("{crate_dir}/cbindgen.toml");
    let config = cbindgen::Config::from_file(&config_path).expect("load cbindgen config");

    cbindgen::Builder::new()
        .with_crate(crate_dir.clone())
        .with_config(config)
        .generate()
        .expect("cbindgen")
        .write_to_file(format!("{crate_dir}/include/dartvel_shelf.h"));
}

/// The files a library is built from, relative to the crate, in the order
/// they are hashed: Cargo.toml, Cargo.lock, build.rs, then every file under
/// src/ sorted by path. `test/prebuilt_source_revision_test.dart` hashes the
/// same list the same way, so change both or neither.
fn source_files(crate_dir: &Path) -> Vec<String> {
    let mut files = vec![
        "Cargo.toml".to_string(),
        "Cargo.lock".to_string(),
        "build.rs".to_string(),
    ];
    let mut sources = Vec::new();
    collect(crate_dir, &crate_dir.join("src"), &mut sources);
    sources.sort();
    files.extend(sources);
    files
}

fn collect(crate_dir: &Path, dir: &Path, out: &mut Vec<String>) {
    for entry in std::fs::read_dir(dir).expect("read src/") {
        let path: PathBuf = entry.expect("read src/ entry").path();
        if path.is_dir() {
            collect(crate_dir, &path, out);
        } else {
            let relative = path.strip_prefix(crate_dir).unwrap();
            let parts: Vec<String> = relative
                .components()
                .map(|part| part.as_os_str().to_string_lossy().into_owned())
                .collect();
            out.push(parts.join("/"));
        }
    }
}

/// Stamps the library with a hash of the source it was compiled from, so the
/// prebuilt copies in lib/native/ can be compared with each other and with
/// the source without running them: six platforms are built on different
/// machines, and in November 2026 three of them were rebuilt after a fix and
/// three were not, with nothing to show the difference.
///
/// FNV-1a 64 over each file's path, a NUL, its bytes with CRLF read as LF (a
/// Windows checkout must give the same answer), and a NUL. It identifies a
/// revision; it is not a defence against anyone.
fn record_source_revision(crate_dir: &Path) {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    let mut feed = |bytes: &[u8]| {
        for &byte in bytes {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    };
    for relative in source_files(crate_dir) {
        let path = crate_dir.join(&relative);
        println!("cargo:rerun-if-changed={}", path.display());
        let bytes = std::fs::read(&path).unwrap_or_else(|_| panic!("read {relative}"));
        let mut normalised = Vec::with_capacity(bytes.len());
        let mut index = 0;
        while index < bytes.len() {
            if bytes[index] == b'\r' && bytes.get(index + 1) == Some(&b'\n') {
                index += 1;
                continue;
            }
            normalised.push(bytes[index]);
            index += 1;
        }
        feed(relative.as_bytes());
        feed(&[0]);
        feed(&normalised);
        feed(&[0]);
    }
    println!("cargo:rerun-if-changed={}", crate_dir.join("src").display());
    println!("cargo:rustc-env=DARTVEL_SHELF_SOURCE_REVISION={hash:016x}");
}
