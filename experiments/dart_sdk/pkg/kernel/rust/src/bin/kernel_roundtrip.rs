// The Rust side of the round-trip oracle (not a mirrored file). The reader
// and writer are not ported yet: every input fails.
#![forbid(unsafe_code)]

use std::process::ExitCode;

fn main() -> ExitCode {
    eprintln!("kernel_roundtrip: the binary reader and writer are not ported yet");
    ExitCode::from(70)
}
