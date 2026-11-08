// Rust side of oracle/body_dump.dart (oracle driver, not an upstream port).
#![forbid(unsafe_code)]
use analyzer::dart::analysis::utilities::parse_string;
use analyzer::src::context::packages::parse_package_config_json_file;
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::ast::ast::AstNodeImpl;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue1, NO_NODE, NodeId};
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::ElementStore;
use analyzer::src::dart::element::type_provider::TypeProviderImpl;
use analyzer::src::dart::resolver::type_analyzer::{TypeAnalyzer, is_context_independent_literal};
use analyzer::src::dart::sdk::sdk::FolderBasedDartSdk;
use analyzer::src::summary2::link::Linker;
use std::{
    collections::HashMap,
    fmt::Write,
    fs,
    path::{Path, PathBuf},
    rc::Rc,
};

/// Which expressions the dump writes, as the oracle's flags select them.
#[derive(Clone, Copy, PartialEq)]
enum Selection {
    /// `--literals`: the seven context-independent literal kinds.
    Literals,
    /// `--operators`: `is`, `is!`, `!`, `&&`, `||`, `throw`, `rethrow`, and
    /// parentheses around those or around literals.
    Operators,
}

fn main() {
    let mut args = std::env::args().skip(1);
    let (mut out, mut sdk, mut packages) = (None, None, None);
    let mut selection = None;
    let mut roots = Vec::new();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--out" => out = args.next(),
            "--sdk" => sdk = args.next(),
            "--packages" => packages = args.next(),
            "--literals" | "--operators" if selection.is_some() => usage(),
            "--literals" => selection = Some(Selection::Literals),
            "--operators" => selection = Some(Selection::Operators),
            _ if arg.starts_with('-') => usage(),
            _ => roots.push(arg),
        }
    }
    let (Some(out), Some(sdk), Some(packages), Some(selection)) = (out, sdk, packages, selection)
    else {
        usage()
    };
    if roots.is_empty() {
        usage();
    }
    let out = PathBuf::from(out);
    let fs = FileSystemState::new(
        FolderBasedDartSdk::new(Path::new(&sdk)),
        parse_package_config_json_file(Path::new(&packages)),
    );
    let mut linker = Linker::new(fs);
    let core_file = linker.fs.get_file_for_uri("dart:core").expect("dart:core");
    let core = linker.library_for(core_file).expect("core library");
    let provider = TypeProviderImpl::new(&linker.store, core);
    let mut labels: HashMap<String, usize> = HashMap::new();
    for root in roots {
        let root = std::path::absolute(root).unwrap();
        let base = root.file_name().unwrap().to_string_lossy().to_string();
        let count = labels.entry(base.clone()).or_default();
        *count += 1;
        let label = if *count == 1 {
            base
        } else {
            format!("{base}~{count}")
        };
        let dumper = Dumper {
            provider: &provider,
            store: &linker.store,
            selection,
        };
        dumper.walk(&root, &root, &out.join(label));
    }
}

fn usage() -> ! {
    eprintln!(
        "usage: body_dump --sdk <dir> --packages <file> (--literals|--operators) --out <dir> <root>..."
    );
    std::process::exit(64)
}

/// Whether the oracle's `--operators` selects the canonical (V2) node
/// [node]: what the AstBuilder builds from `is`, `!`, `&&`, `||`, `throw` and
/// `rethrow`, and parentheses whose `unParenthesized` expression is one of
/// those or a context-independent literal.
fn is_operator_typed(ast: Ast<'_>, node: NodeId) -> bool {
    match ast.node(node) {
        AstNodeImpl::IsExpressionImpl(_)
        | AstNodeImpl::ThrowExpressionImpl(_)
        | AstNodeImpl::RethrowExpressionImpl(_)
        | AstNodeImpl::LogicalAndImpl(_)
        | AstNodeImpl::LogicalOrImpl(_)
        | AstNodeImpl::LogicalNotImpl(_) => true,
        AstNodeImpl::ParenthesizedExpressionImpl(_) => {
            let mut inner = node;
            while let AstNodeImpl::ParenthesizedExpressionImpl(p) = ast.node(inner) {
                inner = p.expression2;
            }
            is_context_independent_literal(ast.node(inner)) || is_operator_typed(ast, inner)
        }
        _ => false,
    }
}

struct Dumper<'a> {
    provider: &'a TypeProviderImpl,
    store: &'a ElementStore,
    selection: Selection,
}

impl Dumper<'_> {
    fn walk(&self, root: &Path, dir: &Path, out: &Path) {
        let mut entries: Vec<_> = fs::read_dir(dir).unwrap().map(Result::unwrap).collect();
        entries.sort_by_key(|e| e.file_name());
        for entry in entries {
            let path = entry.path();
            let kind = entry.file_type().unwrap();
            if kind.is_dir() {
                self.walk(root, &path, out);
            } else if kind.is_file() && path.extension().is_some_and(|e| e == "dart") {
                let bytes = fs::read(&path).unwrap();
                let bytes = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(&bytes);
                let source: Rc<[u16]> = String::from_utf8_lossy(bytes)
                    .encode_utf16()
                    .collect::<Vec<_>>()
                    .into();
                let parsed = parse_string(source, None, path.to_str());
                let ast = Ast::new(&parsed.ast, &parsed.tokens);
                let mut analyzer = TypeAnalyzer::new(self.provider);
                analyzer.analyze(ast, parsed.unit);
                let mut dump = String::new();
                self.dump_node(ast, parsed.unit, &analyzer, &mut dump);
                let target = out.join(format!(
                    "{}.body",
                    path.strip_prefix(root).unwrap().display()
                ));
                fs::create_dir_all(target.parent().unwrap()).unwrap();
                fs::write(target, dump).unwrap();
            }
        }
    }

    /// Writes the selected expressions under the V1 node [node], in the
    /// oracle's order. Types are recorded on canonical nodes, so a V1
    /// projection is looked up by the node it projects.
    fn dump_node(&self, ast: Ast<'_>, node: NodeId, analyzer: &TypeAnalyzer<'_>, out: &mut String) {
        let source = match ast.v1_projection_source(node) {
            NO_NODE => node,
            origin => origin,
        };
        let selected = match self.selection {
            Selection::Literals => is_context_independent_literal(ast.node(node)),
            Selection::Operators => is_operator_typed(ast, source),
        };
        if selected {
            let type_ = analyzer
                .static_types
                .get(&source)
                .map(|type_| display_string(self.store, type_))
                .unwrap_or_else(|| "-".into());
            writeln!(
                out,
                "{} {}+{} type={}",
                ast.node(node).runtime_type(),
                ast.offset(node),
                ast.length(node),
                type_
            )
            .unwrap();
        }
        for child in ast.named_child_entities(node) {
            match child.value {
                ChildValue1::Node(id) => self.dump_node(ast, id, analyzer, out),
                ChildValue1::NodeList(ids) => {
                    for id in ids {
                        self.dump_node(ast, id, analyzer, out);
                    }
                }
                _ => (),
            }
        }
    }
}
