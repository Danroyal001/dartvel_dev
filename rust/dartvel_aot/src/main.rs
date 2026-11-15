// Ours (not a ported file): the dartvel_aot command line.
#![forbid(unsafe_code)]
//
//   dartvel_aot build <file.dart> -o <exe> [--tree-shake=none|calls|types]
//                                          [--emit-c <file.c>] [--report]
//   dartvel_aot dump <file.dart>
use std::path::PathBuf;
use std::process::exit;

use dartvel_aot::Mode;

fn usage() -> ! {
    eprintln!("usage: dartvel_aot build <file.dart> -o <exe> [--tree-shake=none|calls|types] [--emit-c <file.c>] [--report]\n       dartvel_aot dump <file.dart>");
    exit(64);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("dump") if args.len() == 2 => {
            let source = std::fs::read_to_string(&args[1]).unwrap_or_else(|e| {
                eprintln!("cannot read {}: {e}", args[1]);
                exit(66)
            });
            match dartvel_aot::syntax::parse(&source, &args[1]) {
                Ok(unit) => {
                    let mut out = String::new();
                    unit.dump(0, &mut out);
                    print!("{out}");
                }
                Err(errors) => {
                    for e in errors {
                        eprintln!("{}:{}: {}", args[1], e.offset, e.message);
                    }
                    exit(65);
                }
            }
        }
        Some("build") => {
            let mut input = None;
            let mut output = None;
            let mut emit_c = None;
            let mut report = false;
            let mut mode = Mode::Types;
            let mut i = 1;
            while i < args.len() {
                let a = &args[i];
                if a == "-o" && i + 1 < args.len() {
                    output = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                } else if a == "--emit-c" && i + 1 < args.len() {
                    emit_c = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                } else if a == "--report" {
                    report = true;
                } else if let Some(m) = a.strip_prefix("--tree-shake=") {
                    mode = Mode::parse(m).unwrap_or_else(|| usage());
                } else if input.is_none() && !a.starts_with('-') {
                    input = Some(a.clone());
                } else {
                    usage();
                }
                i += 1;
            }
            let (Some(input), Some(output)) = (input, output) else { usage() };
            let source = std::fs::read_to_string(&input).unwrap_or_else(|e| {
                eprintln!("cannot read {input}: {e}");
                exit(66)
            });
            let compiled = match dartvel_aot::compile(&source, &input, mode) {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("error: {e}");
                    exit(65);
                }
            };
            if let Some(path) = emit_c {
                std::fs::write(&path, &compiled.c_source).unwrap_or_else(|e| {
                    eprintln!("cannot write {}: {e}", path.display());
                    exit(73)
                });
            }
            if report {
                print!("{}", compiled.report());
            }
            if let Err(e) = dartvel_aot::build_executable(&compiled.c_source, &output) {
                eprintln!("error: {e}");
                exit(70);
            }
        }
        _ => usage(),
    }
}
