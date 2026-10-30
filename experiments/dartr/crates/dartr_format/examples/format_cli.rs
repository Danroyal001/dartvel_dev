//! `dartr format` without the rest of dartr: the same call that
//! `crates/dartr/src/main.rs` makes for the `format` command, so that the
//! formatter can be compared with `dart format` on corpora without building
//! the analyzer and the servers.
//!
//! `cargo run --release -p dartr_format --example format_cli -- <dart format arguments>`

use std::io::{IsTerminal, Write};

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let stderr = std::io::stderr();
    let code = {
        let mut stdout = std::io::BufWriter::new(stdout.lock());
        let mut stderr = stderr.lock();
        let code = dartr_format::cli::run(
            &argv,
            dartr_format::cli::CommandIo {
                stdin_has_terminal: stdin.is_terminal(),
                stdin: &mut stdin.lock(),
                stderr_is_terminal: std::io::stderr().is_terminal(),
                stdout: &mut stdout,
                stderr: &mut stderr,
            },
        );
        let _ = stdout.flush();
        code
    };
    std::process::exit(code);
}
