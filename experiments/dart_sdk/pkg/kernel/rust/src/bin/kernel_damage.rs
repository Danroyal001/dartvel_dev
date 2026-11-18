// The Rust side of the damage oracle (not a mirrored file): applies each
// mutation in a list to a kernel file, reads and writes the result, and
// prints one line per mutation, as oracle/damage.dart does with upstream's
// BinaryBuilder and BinaryPrinter: `ok <length> <fnv-1a 64>` or
// `error <message>`, newlines as `\n`.
//
// Usage: kernel_damage <input.dill> <mutations>
#![forbid(unsafe_code)]

use std::fmt::Write as _;
use std::process::ExitCode;

use kernel::binary::ast_from_binary::loadComponentFromBytes;
use kernel::binary::ast_to_binary::writeComponentToBytes;

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &byte in bytes {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 2 {
        eprintln!("usage: kernel_damage <input.dill> <mutations>");
        return ExitCode::from(64);
    }
    let (base, mutations) = match (std::fs::read(&args[0]), std::fs::read_to_string(&args[1])) {
        (Ok(base), Ok(mutations)) => (base, mutations),
        (Err(e), _) => {
            eprintln!("{}: {e}", args[0]);
            return ExitCode::from(66);
        }
        (_, Err(e)) => {
            eprintln!("{}: {e}", args[1]);
            return ExitCode::from(66);
        }
    };
    let mut out = String::new();
    for line in mutations.lines().filter(|l| !l.is_empty()) {
        let parts: Vec<&str> = line.split(' ').collect();
        let input = match parts.as_slice() {
            ["T", length] => match length.parse::<usize>() {
                Ok(length) if length <= base.len() => base[..length].to_vec(),
                _ => {
                    eprintln!("bad mutation: {line}");
                    return ExitCode::from(65);
                }
            },
            ["F", offset, mask] => match (offset.parse::<usize>(), mask.parse::<u8>()) {
                (Ok(offset), Ok(mask)) if offset < base.len() => {
                    let mut input = base.clone();
                    input[offset] ^= mask;
                    input
                }
                _ => {
                    eprintln!("bad mutation: {line}");
                    return ExitCode::from(65);
                }
            },
            _ => {
                eprintln!("bad mutation: {line}");
                return ExitCode::from(65);
            }
        };
        let result = loadComponentFromBytes(&input)
            .map_err(|e| e.to_string())
            .and_then(|component| writeComponentToBytes(&component).map_err(|e| e.to_string()));
        match result {
            Ok(output) => {
                let _ = writeln!(out, "ok {} {:016x}", output.len(), fnv1a64(&output));
            }
            Err(message) => {
                let _ = writeln!(out, "error {}", message.replace('\n', "\\n"));
            }
        }
    }
    print!("{out}");
    ExitCode::SUCCESS
}
