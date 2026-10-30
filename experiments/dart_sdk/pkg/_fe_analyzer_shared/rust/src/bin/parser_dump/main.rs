// Port of rust/oracle/parser_dump.dart: the Rust side of the parser oracle.
//
// Writes, for every `.dart` file under the corpus roots, the listener event
// trace the Rust parser produces, in exactly the format the Dart oracle
// writes for the upstream parser, so the two outputs can be compared byte
// for byte.
//
// Usage: parser_dump [--bench=N] --out <dir> <root>...

#![forbid(unsafe_code)]

// Generated (see oracle/generate_parser_trace.dart), so not reformatted.
#[rustfmt::skip]
mod trace_listener;

use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

use fe_analyzer_shared::messages::codes::Message;
use fe_analyzer_shared::parser::experimental_features::{
    DefaultExperimentalFeatures, ExperimentalFeatures,
};
use fe_analyzer_shared::parser::forwarding_listener::{ForwardingListener, NullListener};
use fe_analyzer_shared::parser::listener::Listener;
use fe_analyzer_shared::parser::parser_impl::Parser;
use fe_analyzer_shared::scanner::scanner::{ScannerResult, scan};
use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

fn main() {
    let mut out: Option<String> = None;
    let mut bench = 0usize;
    let mut roots: Vec<String> = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if let Some(n) = arg.strip_prefix("--bench=") {
            bench = n.parse().expect("--bench=N");
        } else if arg == "--out" {
            out = args.next();
        } else {
            roots.push(arg);
        }
    }
    if roots.is_empty() || (out.is_none() && bench == 0) {
        eprintln!("usage: parser_dump [--bench=N] --out <dir> <root>...");
        std::process::exit(64);
    }

    let inputs = corpus_files(&roots);

    if bench > 0 {
        run_bench(&inputs, bench);
        return;
    }

    let out = out.unwrap();
    for (path, relative) in &inputs {
        let bytes = fs::read(path).expect("read corpus file");
        let dump = dump_file(&bytes);
        let target = PathBuf::from(format!("{out}/{relative}.trace"));
        fs::create_dir_all(target.parent().unwrap()).expect("create output directory");
        fs::write(&target, dump).expect("write dump");
    }
}

/// Every `.dart` file under [roots] as (path, label/relative path), sorted by
/// relative path within each root, as the Dart oracle lists them.
fn corpus_files(roots: &[String]) -> Vec<(PathBuf, String)> {
    let mut seen: std::collections::HashMap<String, usize> = Default::default();
    let mut result = Vec::new();
    for root in roots {
        let dir = std::path::absolute(root).expect("absolute corpus root");
        let base = dir.file_name().unwrap().to_string_lossy().to_string();
        let count = seen.entry(base.clone()).or_insert(0);
        *count += 1;
        let label = if *count == 1 {
            base
        } else {
            format!("{base}~{count}")
        };
        let mut files = Vec::new();
        walk(&dir, &dir, &label, &mut files);
        files.sort_by(|a: &(PathBuf, String), b| a.1.as_bytes().cmp(b.1.as_bytes()));
        result.extend(files);
    }
    result
}

fn walk(root: &Path, dir: &Path, label: &str, files: &mut Vec<(PathBuf, String)>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if meta.is_dir() {
            walk(root, &path, label, files);
        } else if meta.is_file() && path.to_string_lossy().ends_with(".dart") {
            let relative = path
                .strip_prefix(root)
                .unwrap()
                .to_string_lossy()
                .to_string();
            files.push((path.clone(), format!("{label}/{relative}")));
        }
    }
}

fn run_scanner(bytes: &[u8]) -> ScannerResult {
    let configuration = DefaultExperimentalFeatures.build_scanner_configuration();
    scan(Rc::from(bytes), Some(configuration), true, || None, true)
}

fn new_parser(listener: Box<dyn Listener>, result: ScannerResult) -> (Parser, TokenId) {
    let parser = Parser::new(
        listener,
        result.store,
        true,
        Box::new(DefaultExperimentalFeatures),
    );
    (parser, result.tokens)
}

fn dump_file(bytes: &[u8]) -> String {
    let result = run_scanner(bytes);
    let (mut parser, tokens) = new_parser(Box::new(TraceListener::default()), result);
    let crashed = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        parser.parse_unit(tokens);
    }))
    .is_err();
    // Recovery can leave a forwarding listener installed around the trace
    // listener, as upstream does.
    let mut listener: Box<dyn std::any::Any> = parser.listener;
    loop {
        match listener.downcast::<TraceListener>() {
            Ok(trace) => {
                let mut out = trace.out;
                if crashed {
                    out.push_str("crash\n");
                }
                return out;
            }
            Err(other) => {
                let forwarding = other
                    .downcast::<ForwardingListener>()
                    .expect("trace listener");
                listener = forwarding.listener.expect("forwarded listener");
            }
        }
    }
}

/// Scans every file once per round, then parses the token streams with a
/// listener that does nothing, timing only the parsing, as the Dart oracle
/// does.
fn run_bench(inputs: &[(PathBuf, String)], rounds: usize) {
    let data: Vec<Vec<u8>> = inputs.iter().map(|(p, _)| fs::read(p).unwrap()).collect();
    let total_bytes: usize = data.iter().map(|b| b.len()).sum();
    let mut times = Vec::new();
    for _ in 0..rounds {
        let streams: Vec<ScannerResult> = data.iter().map(|b| run_scanner(b)).collect();
        let watch = Instant::now();
        for result in streams {
            let (mut parser, tokens) = new_parser(Box::new(NullListener::new()), result);
            parser.parse_unit(tokens);
        }
        times.push(watch.elapsed().as_micros());
    }
    times.sort();
    println!(
        "rust parser files={} bytes={total_bytes} rounds={rounds} min_us={} median_us={}",
        data.len(),
        times[0],
        times[times.len() / 2]
    );
}

/// The listener of the oracle: every event is a line, see
/// oracle/parser_trace_format.dart.
#[derive(Default)]
pub struct TraceListener {
    pub out: String,
}

impl TraceListener {
    fn start(&mut self, name: &str) {
        self.out.push_str(name);
    }

    fn end(&mut self) {
        self.out.push('\n');
    }

    /// `formatToken`.
    fn token(&mut self, tokens: &TokenStore, token: TokenId) {
        self.out.push(' ');
        if token == NO_TOKEN {
            self.out.push('-');
            return;
        }
        if tokens.runtime_type(token).is_error_token() {
            let _ = write!(
                self.out,
                "!{}@{}",
                tokens.error_code(token),
                tokens.offset(token)
            );
            return;
        }
        let _ = write!(
            self.out,
            "{}@{}\"{}\"",
            tokens.type_(token).name,
            tokens.offset(token),
            escape(&tokens.lexeme(token))
        );
        if tokens.is_synthetic(token) {
            self.out.push('~');
        }
    }

    fn value(&mut self, value: impl std::fmt::Display) {
        let _ = write!(self.out, " {value}");
    }

    /// `formatString`.
    fn string(&mut self, value: Option<&str>) {
        match value {
            None => self.out.push_str(" -"),
            Some(value) => {
                let units: Vec<u16> = value.encode_utf16().collect();
                let _ = write!(self.out, " \"{}\"", escape(&units));
            }
        }
    }

    /// `formatMessage`.
    fn message(&mut self, message: &Message) {
        let problem: Vec<u16> = message.problem_message.encode_utf16().collect();
        let _ = write!(self.out, " {}\"{}\"", message.code.name, escape(&problem));
        if let Some(correction) = &message.correction_message {
            let correction: Vec<u16> = correction.encode_utf16().collect();
            let _ = write!(self.out, "\"{}\"", escape(&correction));
        }
    }
}

/// Printable ASCII other than `\` and `"` as is; every other UTF-16 code
/// unit as `\uXXXX`, as the Dart oracle writes it.
fn escape(units: &[u16]) -> String {
    let mut sb = String::with_capacity(units.len());
    for &c in units {
        if (0x20..0x7f).contains(&c) && c != 0x5c && c != 0x22 {
            sb.push(c as u8 as char);
        } else {
            let _ = write!(sb, "\\u{c:04x}");
        }
    }
    sb
}
