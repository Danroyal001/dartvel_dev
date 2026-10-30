// Port of rust/oracle/scanner_dump.dart: the Rust side of the scanner oracle.
//
// Writes, for every `.dart` file under the corpus roots, the token stream
// the Rust scanner produces, in exactly the format the Dart oracle writes for
// the upstream scanner, so the two outputs can be compared byte for byte.
//
// Usage: scanner_dump [--scanner=utf8|string] [--bench=N] --out <dir> <root>...

#![forbid(unsafe_code)]

use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

use fe_analyzer_shared::scanner::scanner::{ScannerResult, scan, scan_string};
use fe_analyzer_shared::scanner::string_canonicalizer::decode_utf8_allow_malformed;
use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

fn main() {
    let mut scanner_kind = String::from("utf8");
    let mut out: Option<String> = None;
    let mut bench = 0usize;
    let mut roots: Vec<String> = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if let Some(kind) = arg.strip_prefix("--scanner=") {
            scanner_kind = kind.to_string();
        } else if let Some(n) = arg.strip_prefix("--bench=") {
            bench = n.parse().expect("--bench=N");
        } else if arg == "--out" {
            out = args.next();
        } else {
            roots.push(arg);
        }
    }
    if scanner_kind != "utf8" && scanner_kind != "string" {
        eprintln!("unknown --scanner={scanner_kind}");
        std::process::exit(64);
    }
    if roots.is_empty() || (out.is_none() && bench == 0) {
        eprintln!("usage: scanner_dump [--scanner=utf8|string] [--bench=N] --out <dir> <root>...");
        std::process::exit(64);
    }

    let inputs = corpus_files(&roots);

    if bench > 0 {
        run_bench(&scanner_kind, &inputs, bench);
        return;
    }

    let out = out.unwrap();
    for (path, relative) in &inputs {
        let bytes = fs::read(path).expect("read corpus file");
        let dump = dump_file(&scanner_kind, &bytes);
        let target = PathBuf::from(format!("{out}/{relative}.tokens"));
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

fn run_scanner(scanner_kind: &str, bytes: &[u8]) -> ScannerResult {
    if scanner_kind == "utf8" {
        scan(Rc::from(bytes), None, true, || None, true)
    } else {
        scan_string(
            Rc::from(decode_utf8_allow_malformed(bytes)),
            None,
            true,
            || None,
        )
    }
}

fn run_bench(scanner_kind: &str, inputs: &[(PathBuf, String)], rounds: usize) {
    let data: Vec<Rc<[u8]>> = inputs
        .iter()
        .map(|(p, _)| Rc::from(fs::read(p).unwrap()))
        .collect();
    let total_bytes: usize = data.iter().map(|b| b.len()).sum();
    let strings: Option<Vec<Rc<[u16]>>> = if scanner_kind == "string" {
        Some(
            data.iter()
                .map(|b| Rc::from(decode_utf8_allow_malformed(b)))
                .collect(),
        )
    } else {
        None
    };
    let mut times = Vec::new();
    let mut tokens = 0;
    for _ in 0..rounds {
        tokens = 0;
        let watch = Instant::now();
        for i in 0..data.len() {
            let result = match &strings {
                Some(s) => scan_string(s[i].clone(), None, true, || None),
                None => scan(data[i].clone(), None, true, || None, true),
            };
            let mut token = result.tokens;
            while !result.store.is_eof(token) {
                tokens += 1;
                token = result.store.next(token);
            }
        }
        times.push(watch.elapsed().as_micros());
    }
    times.sort();
    println!(
        "rust scanner={scanner_kind} files={} bytes={total_bytes} tokens={tokens} rounds={rounds} min_us={} median_us={}",
        data.len(),
        times[0],
        times[times.len() / 2]
    );
}

fn dump_file(scanner_kind: &str, bytes: &[u8]) -> String {
    let result = run_scanner(scanner_kind, bytes);
    let store = &result.store;
    let mut sb = String::new();
    let _ = writeln!(sb, "scanner={scanner_kind} hasErrors={}", result.has_errors);
    let mut token = result.tokens;
    let mut index = 0;
    loop {
        let mut comment = store.preceding_comments(token);
        while comment != NO_TOKEN {
            sb.push_str("  ");
            write_token(&mut sb, store, comment);
            comment = store.next(comment);
        }
        let _ = write!(sb, "{index} ");
        write_token(&mut sb, store, token);
        if store.is_eof(token) {
            break;
        }
        token = store.next(token);
        index += 1;
    }
    sb.push_str("lineStarts");
    for start in &result.line_starts {
        let _ = write!(sb, " {start}");
    }
    sb.push('\n');
    sb
}

fn write_token(sb: &mut String, store: &TokenStore, token: TokenId) {
    let runtime_type = store.runtime_type(token);
    let _ = write!(
        sb,
        "{} {} @{}",
        store.type_(token).name,
        runtime_type.name(),
        store.offset(token)
    );
    let _ = write!(sb, " len={}", store.length(token));
    if runtime_type.is_error_token() {
        let _ = write!(sb, " err={}", store.error_code(token));
        if let Some(character) = store.character(token) {
            let _ = write!(sb, " char={character}");
        }
        if let Some(start) = store.start(token) {
            let _ = write!(sb, " start=\"{}\"", escape(start));
        }
        if let Some(end_offset) = store.end_offset(token) {
            let _ = write!(sb, " endOffset={end_offset}");
        }
        let begin = store.begin(token);
        if begin != NO_TOKEN {
            let _ = write!(
                sb,
                " begin={}@{}",
                store.type_(begin).name,
                store.offset(begin)
            );
        }
        let operator = store.unsupported_operator_token(token);
        if operator != NO_TOKEN {
            let _ = write!(
                sb,
                " operator={}@{}",
                store.type_(operator).name,
                store.offset(operator)
            );
        }
    } else {
        let _ = write!(sb, " lex=\"{}\"", escape(&store.lexeme(token)));
    }
    if runtime_type.is_language_version_token() {
        let _ = write!(sb, " version={}.{}", store.major(token), store.minor(token));
    }
    if runtime_type.is_begin_token() {
        let end = store.end_group(token);
        if end == NO_TOKEN {
            sb.push_str(" end=null");
        } else {
            let _ = write!(sb, " end={}@{}", store.type_(end).name, store.offset(end));
        }
    }
    if store.is_synthetic(token) {
        sb.push_str(" synthetic");
    }
    sb.push('\n');
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
