// The helper program the dartvel CLI runs for its syntax check (not a
// ported file).
//
// Reads file paths from standard input, one per line, and answers each in
// order on standard output (see `result_lines` in lib.rs), flushing after
// every file so that the CLI knows how far the helper got if it dies.
// `--diagnostics` also lists each flagged file's diagnostics.
#![forbid(unsafe_code)]

use std::io::{self, BufRead, Write};
use std::path::Path;
use std::process::ExitCode;
use std::thread;

use dartvel_syntax::{check_file, greeting, result_lines};

/// The parser is recursive descent, so nesting in the source is depth on
/// the stack. The pages of this stack are only mapped when touched; the
/// size costs address space, not memory.
const PARSER_STACK_BYTES: usize = 512 * 1024 * 1024;

/// Used when the system refuses the large stack.
const SMALLER_PARSER_STACK_BYTES: usize = 64 * 1024 * 1024;

fn main() -> ExitCode {
    let mut with_diagnostics = false;
    for argument in std::env::args().skip(1) {
        match argument.as_str() {
            "--diagnostics" => with_diagnostics = true,
            "--version" => {
                println!("{}", greeting());
                return ExitCode::SUCCESS;
            }
            unknown => {
                eprintln!("dartvel_syntax: unknown argument {unknown}");
                return ExitCode::from(64);
            }
        }
    }

    // A panic is caught per file and answered as `deferred`; the default
    // hook would also print it, to a stream nobody reads.
    std::panic::set_hook(Box::new(|_| {}));

    for stack_bytes in [PARSER_STACK_BYTES, SMALLER_PARSER_STACK_BYTES] {
        let spawned = thread::Builder::new()
            .name("parser".to_string())
            .stack_size(stack_bytes)
            .spawn(move || answer_every_path(with_diagnostics));
        if let Ok(parser_thread) = spawned {
            return match parser_thread.join() {
                Ok(Ok(())) => ExitCode::SUCCESS,
                Ok(Err(_)) | Err(_) => ExitCode::FAILURE,
            };
        }
    }
    match answer_every_path(with_diagnostics) {
        Ok(()) => ExitCode::SUCCESS,
        Err(_) => ExitCode::FAILURE,
    }
}

/// Answers each path on standard input until it ends. An error is the
/// output pipe closing: the CLI has gone, and there is nobody to answer.
fn answer_every_path(with_diagnostics: bool) -> io::Result<()> {
    let standard_output = io::stdout();
    let mut output = standard_output.lock();
    writeln!(output, "{}", greeting())?;
    output.flush()?;
    for (index, line) in io::stdin().lock().lines().enumerate() {
        let path = line?;
        let outcome = check_file(Path::new(&path));
        for result_line in result_lines(index, &outcome, with_diagnostics) {
            writeln!(output, "{result_line}")?;
        }
        output.flush()?;
    }
    Ok(())
}
