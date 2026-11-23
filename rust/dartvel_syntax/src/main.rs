// The helper program the dartvel CLI runs for its syntax check (not a
// ported file).
//
// Reads file paths from standard input, one per line, and answers each in
// order on standard output (see `result_lines` in lib.rs), flushing after
// every file so that the CLI knows how far the helper got if it dies.
// `--diagnostics` also lists each flagged file's diagnostics.
//
// Files are parsed on several threads at once (`--jobs N`, by default one
// per processor, at most `MOST_JOBS`). Each file is parsed on its own, so
// the answers are the ones a single thread gives; they are written in the
// order the paths came, whatever order the parses finish in.
#![forbid(unsafe_code)]

use std::collections::BTreeMap;
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::process::ExitCode;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;

use dartvel_syntax::{SyntaxOutcome, check_file, greeting, result_lines};

/// The parser is recursive descent, so nesting in the source is depth on
/// the stack. The pages of this stack are only mapped when touched; the
/// size costs address space, not memory.
const PARSER_STACK_BYTES: usize = 512 * 1024 * 1024;

/// Used when the system refuses the large stack.
const SMALLER_PARSER_STACK_BYTES: usize = 64 * 1024 * 1024;

/// The most threads the helper parses on by default. A project's files are
/// small and many; past this the threads mostly wait for each other on the
/// file system and the allocator.
const MOST_JOBS: usize = 8;

fn main() -> ExitCode {
    let mut with_diagnostics = false;
    let mut jobs: Option<usize> = None;
    let mut arguments = std::env::args().skip(1);
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--diagnostics" => with_diagnostics = true,
            "--version" => {
                println!("{}", greeting());
                return ExitCode::SUCCESS;
            }
            "--jobs" => match arguments.next().and_then(|count| count.parse::<usize>().ok()) {
                Some(count) if count > 0 => jobs = Some(count),
                _ => {
                    eprintln!("dartvel_syntax: --jobs takes a number of threads, 1 or more");
                    return ExitCode::from(64);
                }
            },
            unknown => {
                eprintln!("dartvel_syntax: unknown argument {unknown}");
                return ExitCode::from(64);
            }
        }
    }
    let jobs = jobs.unwrap_or_else(|| {
        thread::available_parallelism()
            .map(|count| count.get())
            .unwrap_or(1)
            .min(MOST_JOBS)
    });

    // A panic is caught per file and answered as `deferred`; the default
    // hook would also print it, to a stream nobody reads.
    std::panic::set_hook(Box::new(|_| {}));

    let answered = if jobs == 1 {
        on_a_parser_stack(move || answer_every_path(with_diagnostics))
    } else {
        answer_every_path_in_parallel(with_diagnostics, jobs)
    };
    match answered {
        Ok(()) => ExitCode::SUCCESS,
        Err(_) => ExitCode::FAILURE,
    }
}

/// Runs [work] on a thread with the parser's stack, or on this thread when
/// the system gives no such thread.
fn on_a_parser_stack(work: impl FnOnce() -> io::Result<()> + Send + Clone + 'static) -> io::Result<()> {
    for stack_bytes in [PARSER_STACK_BYTES, SMALLER_PARSER_STACK_BYTES] {
        let spawned = thread::Builder::new()
            .name("parser".to_string())
            .stack_size(stack_bytes)
            .spawn(work.clone());
        if let Ok(parser_thread) = spawned {
            return parser_thread
                .join()
                .unwrap_or_else(|_| Err(io::Error::other("the parser thread failed")));
        }
    }
    work()
}

/// Writes the greeting. Nothing else may come before it.
fn greet(output: &mut impl Write) -> io::Result<()> {
    writeln!(output, "{}", greeting())?;
    output.flush()
}

/// Writes the answer for file [index] and flushes it.
fn answer(output: &mut impl Write, index: usize, outcome: &SyntaxOutcome, with_diagnostics: bool) -> io::Result<()> {
    for result_line in result_lines(index, outcome, with_diagnostics) {
        writeln!(output, "{result_line}")?;
    }
    output.flush()
}

/// Answers each path on standard input until it ends, one file at a time.
/// An error is the output pipe closing: the CLI has gone, and there is
/// nobody to answer.
fn answer_every_path(with_diagnostics: bool) -> io::Result<()> {
    let standard_output = io::stdout();
    let mut output = standard_output.lock();
    greet(&mut output)?;
    for (index, line) in io::stdin().lock().lines().enumerate() {
        let path = line?;
        answer(&mut output, index, &check_file(Path::new(&path)), with_diagnostics)?;
    }
    Ok(())
}

/// Answers each path on standard input until it ends, parsing up to [jobs]
/// files at once and answering in the order the paths came.
///
/// This thread reads the paths and hands them out; the parser threads send
/// back what they found; a writer thread answers each file once every file
/// before it has been answered. Falls back to one file at a time when the
/// system gives no parser thread at all.
fn answer_every_path_in_parallel(with_diagnostics: bool, jobs: usize) -> io::Result<()> {
    let (path_sender, path_receiver) = mpsc::channel::<(usize, String)>();
    let path_receiver = Arc::new(Mutex::new(path_receiver));
    let (outcome_sender, outcome_receiver) = mpsc::channel::<(usize, SyntaxOutcome)>();

    let mut parsers = Vec::with_capacity(jobs);
    for number in 0..jobs {
        let paths = Arc::clone(&path_receiver);
        let outcomes = outcome_sender.clone();
        let parse_paths = move || {
            loop {
                // The lock is held only to take the next path, not to parse it.
                let next = match paths.lock() {
                    Ok(receiver) => receiver.recv(),
                    Err(_) => return,
                };
                let Ok((index, path)) = next else { return };
                if outcomes.send((index, check_file(Path::new(&path)))).is_err() {
                    return;
                }
            }
        };
        for stack_bytes in [PARSER_STACK_BYTES, SMALLER_PARSER_STACK_BYTES] {
            let spawned = thread::Builder::new()
                .name(format!("parser {number}"))
                .stack_size(stack_bytes)
                .spawn(parse_paths.clone());
            if let Ok(parser) = spawned {
                parsers.push(parser);
                break;
            }
        }
    }
    drop(outcome_sender);
    if parsers.is_empty() {
        return answer_every_path(with_diagnostics);
    }

    let writer = thread::Builder::new().name("writer".to_string()).spawn(move || {
        let standard_output = io::stdout();
        let mut output = standard_output.lock();
        greet(&mut output)?;
        let mut waiting: BTreeMap<usize, SyntaxOutcome> = BTreeMap::new();
        let mut next_to_answer = 0;
        for (index, outcome) in outcome_receiver {
            waiting.insert(index, outcome);
            while let Some(outcome) = waiting.remove(&next_to_answer) {
                answer(&mut output, next_to_answer, &outcome, with_diagnostics)?;
                next_to_answer += 1;
            }
        }
        Ok::<(), io::Error>(())
    })?;

    let mut read = Ok(());
    for (index, line) in io::stdin().lock().lines().enumerate() {
        match line {
            Ok(path) => {
                if path_sender.send((index, path)).is_err() {
                    break;
                }
            }
            Err(error) => {
                read = Err(error);
                break;
            }
        }
    }
    drop(path_sender);
    for parser in parsers {
        let _ = parser.join();
    }
    let written = writer
        .join()
        .unwrap_or_else(|_| Err(io::Error::other("the writer thread failed")));
    read.and(written)
}
