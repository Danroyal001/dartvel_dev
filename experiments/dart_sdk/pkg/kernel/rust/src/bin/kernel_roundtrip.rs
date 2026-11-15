// The Rust side of the round-trip oracle (not a mirrored file): reads a
// kernel component and writes it again, as oracle/roundtrip.dart does with
// upstream's BinaryBuilder and BinaryPrinter.
//
// Usage: kernel_roundtrip <input.dill> <output.dill> [<input> <output>]...
//        kernel_roundtrip --bench <runs> <input.dill> <output.dill>
//
// With --bench, the read and write of one component is repeated <runs>
// times in the process and the fastest and median times are printed as
// `min_us=... median_us=...`, as the Dart oracle does.
#![forbid(unsafe_code)]

use std::process::ExitCode;
use std::time::Instant;

use kernel::binary::ast_from_binary::loadComponentFromBytes;
use kernel::binary::ast_to_binary::writeComponentToBytes;

fn round_trip(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let component = loadComponentFromBytes(bytes).map_err(|e| e.to_string())?;
    writeComponentToBytes(&component).map_err(|e| e.to_string())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() == 4 && args[0] == "--bench" {
        let runs: usize = match args[1].parse() {
            Ok(runs) if runs > 0 => runs,
            _ => {
                eprintln!("--bench needs a positive number of runs");
                return ExitCode::from(64);
            }
        };
        let bytes = match std::fs::read(&args[2]) {
            Ok(bytes) => bytes,
            Err(e) => {
                eprintln!("{}: {e}", args[2]);
                return ExitCode::from(66);
            }
        };
        let mut times = Vec::with_capacity(runs);
        let mut out = Vec::new();
        for _ in 0..runs {
            let start = Instant::now();
            out = match round_trip(&bytes) {
                Ok(out) => out,
                Err(e) => {
                    eprintln!("{}: {e}", args[2]);
                    return ExitCode::from(65);
                }
            };
            times.push(start.elapsed().as_micros());
        }
        times.sort_unstable();
        if let Err(e) = std::fs::write(&args[3], out) {
            eprintln!("{}: {e}", args[3]);
            return ExitCode::from(73);
        }
        println!("min_us={} median_us={}", times[0], times[(times.len() - 1) / 2]);
        return ExitCode::SUCCESS;
    }
    if args.is_empty() || args.len() % 2 != 0 {
        eprintln!("usage: kernel_roundtrip <input.dill> <output.dill> [<input> <output>]...");
        return ExitCode::from(64);
    }
    for pair in args.chunks(2) {
        let bytes = match std::fs::read(&pair[0]) {
            Ok(bytes) => bytes,
            Err(e) => {
                eprintln!("{}: {e}", pair[0]);
                return ExitCode::from(66);
            }
        };
        let out = match round_trip(&bytes) {
            Ok(out) => out,
            Err(e) => {
                eprintln!("{}: {e}", pair[0]);
                return ExitCode::from(65);
            }
        };
        if let Err(e) = std::fs::write(&pair[1], out) {
            eprintln!("{}: {e}", pair[1]);
            return ExitCode::from(73);
        }
    }
    ExitCode::SUCCESS
}
