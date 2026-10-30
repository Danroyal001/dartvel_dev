// Port of rust/oracle/ast_dump.dart: the Rust side of the AST oracle.
//
// Writes, for every `.dart` file under the corpus roots, the syntax tree and
// parse diagnostics the Rust port produces, in exactly the format the Dart
// oracle writes for the analyzer, so the two outputs can be compared byte
// for byte.
//
// Usage: ast_dump [--api] [--bench=N | --retain] --out <dir> <root>...
//
// `--api` writes the API dump instead of the tree (see api.rs); with
// `--bench=N` it times `toSource` of every unit instead of parsing.

mod api;
mod recorders;

use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

use analyzer::dart::analysis::utilities::{ParseStringResult, parse_string};
use analyzer::dart::ast::doc_comment::{DocDirective, DocDirectiveArgument, DocDirectiveTag};
use analyzer::src::dart::ast::ast::AstNodeImpl;
use analyzer::src::dart::ast::ast_store::{ChildValue, NodeId};
use fe_analyzer_shared::scanner::token::{TokenId, TokenStore};

fn main() {
    let mut out: Option<String> = None;
    let mut bench = 0usize;
    let mut retain = false;
    let mut api = false;
    let mut roots: Vec<String> = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if let Some(n) = arg.strip_prefix("--bench=") {
            bench = n.parse().expect("--bench=N");
        } else if arg == "--api" {
            api = true;
        } else if arg == "--retain" {
            retain = true;
        } else if arg == "--out" {
            out = args.next();
        } else {
            roots.push(arg);
        }
    }
    if roots.is_empty() || (out.is_none() && bench == 0 && !retain) {
        eprintln!("usage: ast_dump [--bench=N | --retain] --out <dir> <root>...");
        std::process::exit(64);
    }

    let inputs = corpus_files(&roots);

    if bench > 0 && api {
        run_to_source_bench(&inputs, bench);
        return;
    }
    if bench > 0 {
        run_bench(&inputs, bench);
        return;
    }
    if retain {
        run_retain(&inputs);
        return;
    }

    if api {
        // A panic stands for an upstream exception, which the dump records.
        std::panic::set_hook(Box::new(|_| {}));
    }
    let out = out.unwrap();
    for (path, relative) in &inputs {
        let source = read_source(path);
        if std::env::var_os("AST_TRACE").is_some() {
            eprintln!("{relative}");
        }
        let dump = if api { api::dump_api(source) } else { dump_file(source) };
        let extension = if api { "api" } else { "ast" };
        let target = PathBuf::from(format!("{out}/{relative}.{extension}"));
        fs::create_dir_all(target.parent().unwrap()).expect("create output directory");
        fs::write(&target, dump).expect("write dump");
    }
}

/// `utf8.decode(bytes, allowMalformed: true)`, as UTF-16 code units: Dart's
/// decoder drops a byte order mark at the start.
fn read_source(path: &Path) -> Rc<[u16]> {
    let bytes = fs::read(path).expect("read corpus file");
    let bytes = bytes
        .strip_prefix(&[0xEF, 0xBB, 0xBF][..])
        .unwrap_or(&bytes);
    let text = String::from_utf8_lossy(bytes);
    let units: Vec<u16> = text.encode_utf16().collect();
    Rc::from(units)
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

fn dump_file(source: Rc<[u16]>) -> String {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        parse_string(source, None, None)
    }));
    let Ok(result) = result else {
        // Upstream throws where the port panics; neither message is
        // compared, only that it happened.
        return "crash\n".to_string();
    };
    let mut dumper = AstDumper {
        sb: String::new(),
        result: &result,
    };
    dumper.node("unit", result.unit, 0);
    let mut sb = dumper.sb;
    for diagnostic in &result.errors {
        let _ = writeln!(
            sb,
            "diagnostic {}@{}+{}",
            diagnostic.diagnostic_code.unique_name, diagnostic.offset, diagnostic.length
        );
    }
    sb
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

fn format_token(tokens: &TokenStore, token: TokenId) -> String {
    let synthetic = if tokens.is_synthetic(token) { "~" } else { "" };
    format!(
        "{}@{}\"{}\"{}",
        tokens.type_(token).name,
        tokens.offset(token),
        escape(&tokens.lexeme(token)),
        synthetic
    )
}

/// Dart's `double.toString()`.
fn dart_double_to_string(value: f64) -> String {
    if value.is_nan() {
        return "NaN".to_string();
    }
    if value.is_infinite() {
        return if value > 0.0 { "Infinity" } else { "-Infinity" }.to_string();
    }
    if value == 0.0 {
        return if value.is_sign_negative() {
            "-0.0"
        } else {
            "0.0"
        }
        .to_string();
    }
    let sign = if value < 0.0 { "-" } else { "" };
    // The shortest digits that round trip, and the exponent.
    let e = format!("{:e}", value.abs());
    let (mantissa, exponent) = e.split_once('e').unwrap();
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let exponent: i32 = exponent.parse().unwrap();
    let k = digits.len() as i32;
    let n = exponent + 1;
    let body = if k <= n && n <= 21 {
        format!("{}{}.0", digits, "0".repeat((n - k) as usize))
    } else if 0 < n && n <= 21 {
        format!("{}.{}", &digits[..n as usize], &digits[n as usize..])
    } else if -6 < n && n <= 0 {
        format!("0.{}{}", "0".repeat((-n) as usize), digits)
    } else {
        let rest = if k > 1 {
            format!(".{}", &digits[1..])
        } else {
            String::new()
        };
        let e = n - 1;
        format!(
            "{}{}e{}{}",
            &digits[..1],
            rest,
            if e >= 0 { "+" } else { "-" },
            e.abs()
        )
    };
    format!("{sign}{body}")
}

struct AstDumper<'a> {
    sb: String,
    result: &'a ParseStringResult,
}

impl AstDumper<'_> {
    fn indent(&mut self, depth: usize) {
        for _ in 0..depth {
            self.sb.push_str("  ");
        }
    }

    fn node(&mut self, name: &str, node: NodeId, depth: usize) {
        let ast = &self.result.ast;
        let tokens = &self.result.tokens;
        self.indent(depth);
        let _ = writeln!(
            self.sb,
            "{name}: {} {}+{}",
            ast.node(node).runtime_type(),
            ast.offset(node, tokens),
            ast.length(node, tokens)
        );
        self.extras(node, depth + 1);
        for child in ast.named_child_entities2(node, tokens) {
            match child.value {
                ChildValue::Node(n) => self.node(child.name, n, depth + 1),
                ChildValue::Token(t) => {
                    self.indent(depth + 1);
                    let _ = writeln!(self.sb, "{}: {}", child.name, format_token(tokens, t));
                }
                ChildValue::NodeList(list) => {
                    self.indent(depth + 1);
                    let _ = writeln!(self.sb, "{}: [{}]", child.name, list.len());
                    for (i, &element) in list.iter().enumerate() {
                        self.node(&format!("{}[{i}]", child.name), element, depth + 2);
                    }
                }
                ChildValue::TokenList(list) => {
                    self.indent(depth + 1);
                    let _ = writeln!(self.sb, "{}: [{}]", child.name, list.len());
                    for (i, &element) in list.iter().enumerate() {
                        self.indent(depth + 2);
                        let _ = writeln!(
                            self.sb,
                            "{}[{i}]: {}",
                            child.name,
                            format_token(tokens, element)
                        );
                    }
                }
            }
        }
    }

    fn line(&mut self, depth: usize, text: &str) {
        self.indent(depth);
        self.sb.push('~');
        self.sb.push_str(text);
        self.sb.push('\n');
    }

    fn extras(&mut self, node: NodeId, depth: usize) {
        let ast = &self.result.ast;
        match ast.node(node) {
            AstNodeImpl::SimpleStringLiteralImpl(n) => {
                let text = format!("value \"{}\"", escape(&n.value));
                self.line(depth, &text);
            }
            AstNodeImpl::InterpolationStringImpl(n) => {
                let text = format!("value \"{}\"", escape(&n.value));
                self.line(depth, &text);
            }
            AstNodeImpl::IntegerLiteralImpl(n) => {
                let text = match n.value {
                    Some(v) => format!("value {v}"),
                    None => "value -".to_string(),
                };
                self.line(depth, &text);
            }
            AstNodeImpl::DoubleLiteralImpl(n) => {
                let text = format!("value {}", dart_double_to_string(n.value));
                self.line(depth, &text);
            }
            AstNodeImpl::CommentReferenceImpl(n) => {
                let text = format!("isSynthetic {}", n.is_synthetic);
                self.line(depth, &text);
            }
            AstNodeImpl::CommentImpl(n) => {
                self.line(depth, &format!("hasNodoc {}", n.has_nodoc));
                for block in &n.code_blocks {
                    let info = match &block.info_string {
                        None => "-".to_string(),
                        Some(s) => format!("\"{}\"", escape(s)),
                    };
                    let lines: Vec<String> = block
                        .lines
                        .iter()
                        .map(|l| format!("{}+{}", l.offset, l.length))
                        .collect();
                    let text = format!(
                        "codeBlock {} {info} [{}]",
                        block.type_.name(),
                        lines.join(" ")
                    );
                    self.line(depth, &text);
                }
                for directive in &n.doc_directives {
                    let text = match directive {
                        DocDirective::SimpleDocDirective(d) => {
                            format!("docDirective simple {}", tag(&d.tag))
                        }
                        DocDirective::BlockDocDirective(d) => {
                            let closing = match &d.closing_tag {
                                None => "-".to_string(),
                                Some(t) => tag(t),
                            };
                            format!("docDirective block {} {closing}", tag(&d.opening_tag))
                        }
                    };
                    self.line(depth, &text);
                }
                for doc_import in &n.doc_imports {
                    self.line(depth, &format!("docImport {}", doc_import.offset));
                    self.node("import", doc_import.import, depth + 1);
                }
            }
            _ => {}
        }
    }
}

fn argument(a: &DocDirectiveArgument) -> String {
    format!("\"{}\"@{}-{}", escape(&a.value), a.offset, a.end)
}

fn tag(tag: &DocDirectiveTag) -> String {
    let positional: Vec<String> = tag.positional_arguments.iter().map(argument).collect();
    let named: Vec<String> = tag
        .named_arguments
        .iter()
        .map(|a| {
            format!(
                "{}={}",
                String::from_utf16_lossy(a.name.as_deref().unwrap_or(&[])),
                argument(a)
            )
        })
        .collect();
    format!(
        "{}@{}-{}({}-{})[{}][{}]",
        tag.type_.name(),
        tag.offset,
        tag.end,
        tag.name_offset,
        tag.name_end,
        positional.join(" "),
        named.join(" ")
    )
}

/// Reads every file once, then parses the sources [rounds] times, timing
/// scanning and building the tree (`parseString`) and nothing else, as the
/// Dart oracle does.
fn run_bench(inputs: &[(PathBuf, String)], rounds: usize) {
    let sources: Vec<Rc<[u16]>> = inputs.iter().map(|(p, _)| read_source(p)).collect();
    let total_bytes: u64 = inputs
        .iter()
        .map(|(p, _)| fs::metadata(p).unwrap().len())
        .sum();
    let mut times = Vec::new();
    let mut check = 0i64;
    for _ in 0..rounds {
        let watch = Instant::now();
        for source in &sources {
            let result = parse_string(source.clone(), None, None);
            let end = result.ast.end_token(result.unit, &result.tokens);
            check += (result.tokens.offset(end) & 1) as i64;
        }
        times.push(watch.elapsed().as_micros());
    }
    times.sort();
    println!(
        "rust ast files={} bytes={total_bytes} rounds={rounds} min_us={} median_us={} check={check} max_rss={}",
        sources.len(),
        times[0],
        times[times.len() / 2],
        status_bytes("VmHWM"),
    );
}

/// A field of /proc/self/status (`VmRSS`, `VmHWM`), in bytes.
fn status_bytes(field: &str) -> u64 {
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    for line in status.lines() {
        if let Some(rest) = line.strip_prefix(field).and_then(|r| r.strip_prefix(':')) {
            let kb: u64 = rest
                .trim()
                .trim_end_matches(" kB")
                .trim()
                .parse()
                .unwrap_or(0);
            return kb * 1024;
        }
    }
    0
}

/// Reads every file, then parses them all once and keeps every result (the
/// tokens, the tree and the diagnostics), printing the resident set size
/// before and after parsing, as the Dart oracle does, and what the results
/// hold: the token store and the node store, each as the bytes of its
/// arrays.
fn run_retain(inputs: &[(PathBuf, String)]) {
    let sources: Vec<Rc<[u16]>> = inputs.iter().map(|(p, _)| read_source(p)).collect();
    let before = status_bytes("VmRSS");
    let results: Vec<ParseStringResult> = sources
        .iter()
        .map(|s| parse_string(s.clone(), None, None))
        .collect();
    let after = status_bytes("VmRSS");
    let mut nodes = 0usize;
    let mut node_bytes = 0usize;
    let mut token_count = 0usize;
    let mut token_bytes = 0usize;
    for r in &results {
        nodes += r.ast.nodes.len();
        node_bytes +=
            r.ast.nodes.capacity() * std::mem::size_of::<AstNodeImpl>() + r.ast.list_heap_bytes();
        token_count += r.tokens.tokens.len();
        token_bytes += r.tokens.tokens.capacity()
            * std::mem::size_of::<fe_analyzer_shared::scanner::token::TokenData>()
            + r.tokens.strings.iter().map(|s| s.len() * 2).sum::<usize>();
    }
    println!(
        "rust retain files={} rss_sources={before} rss_parsed={after} delta={} max_rss={} \
         nodes={nodes} node_bytes={node_bytes} node_size={} tokens={token_count} token_bytes={token_bytes}",
        results.len(),
        after - before,
        status_bytes("VmHWM"),
        std::mem::size_of::<AstNodeImpl>()
    );
}

/// Parses every file once, then calls `toSource` on every unit [rounds]
/// times, timing only `toSource`, as the Dart oracle does.
fn run_to_source_bench(inputs: &[(PathBuf, String)], rounds: usize) {
    let results: Vec<ParseStringResult> = inputs
        .iter()
        .map(|(p, _)| parse_string(read_source(p), None, None))
        .collect();
    let mut times = Vec::new();
    let mut chars = 0usize;
    for _ in 0..rounds {
        let watch = Instant::now();
        for result in &results {
            let ast = analyzer::src::dart::ast::ast_store::Ast::new(&result.ast, &result.tokens);
            chars += ast.to_source_units(result.unit).len();
        }
        times.push(watch.elapsed().as_micros());
    }
    times.sort();
    println!(
        "rust toSource files={} rounds={rounds} min_us={} median_us={} chars={chars} max_rss={}",
        results.len(),
        times[0],
        times[times.len() / 2],
        status_bytes("VmHWM"),
    );
}
