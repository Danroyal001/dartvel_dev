// Port of rust/oracle/element_dump.dart: the Rust side of the element
// oracle (see ../../../README.md).
//
// Usage: element_dump --sdk <dir> --packages <package_config.json>
//          [--types] [--bench=N] --out <dir> <root>...
//
// Not ported yet: writes no dumps, so tests/element_oracle.rs fails.

#![forbid(unsafe_code)]

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if !args.iter().any(|a| a == "--out") {
        eprintln!(
            "usage: element_dump --sdk <dir> --packages <file> [--types] [--bench=N] --out <dir> <root>..."
        );
        std::process::exit(64);
    }
}
