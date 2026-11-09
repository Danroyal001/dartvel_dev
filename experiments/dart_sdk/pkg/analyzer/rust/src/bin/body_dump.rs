// Rust side of oracle/body_dump.dart (oracle driver, not an upstream port).
#![forbid(unsafe_code)]
use analyzer::dart::analysis::utilities::parse_string;
use analyzer::src::context::packages::parse_package_config_json_file;
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::ast::ast::AstNodeImpl;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue1, NO_NODE, NodeId};
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::ElementStore;
use analyzer::src::dart::element::r#type::TypeImpl;
use analyzer::src::dart::element::type_provider::TypeProviderImpl;
use analyzer::src::dart::resolver::method_invocation_resolver::MemberAccessKind;
use fe_analyzer_shared::scanner::token::NO_TOKEN;
use analyzer::src::dart::resolver::type_analyzer::{
    Declarations, TypeAnalyzer, VariableRead, is_context_independent_literal, is_declared_context_integer,
};
use analyzer::src::dart::sdk::sdk::FolderBasedDartSdk;
use analyzer::src::summary2::link::Linker;
use std::{
    collections::{HashMap, HashSet},
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
    /// `--integers`: integer literals whose context comes from a declared
    /// type annotation or which have none (`is_declared_context_integer`).
    Integers,
    /// `--identifiers`: reads of local variables and formal parameters
    /// declared with a type that flow analysis cannot promote
    /// (`TypeAnalyzer::variable_reads`), with their declarations.
    Identifiers,
    /// `--user-operators`: invocations of `==`, `!=` and the user-definable
    /// binary, unary and index operators the analyzer typed
    /// (`TypeAnalyzer::operator_invocations`), the integer literals that are
    /// their operands, and parentheses around either.
    UserOperators,
    /// `--members`: method invocations and property reads on a typed
    /// receiver the analyzer typed (`TypeAnalyzer::member_accesses`), and the
    /// integer literals that are arguments of those invocations.
    Members,
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
            "--literals" | "--operators" | "--integers" | "--identifiers" | "--user-operators" | "--members" if selection.is_some() => usage(),
            "--literals" => selection = Some(Selection::Literals),
            "--operators" => selection = Some(Selection::Operators),
            "--integers" => selection = Some(Selection::Integers),
            "--identifiers" => selection = Some(Selection::Identifiers),
            "--user-operators" => selection = Some(Selection::UserOperators),
            "--members" => selection = Some(Selection::Members),
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
    let mut files = Vec::new();
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
        corpus_files(&root, &root, &out.join(label), &mut files);
    }
    for (path, target) in files {
        dump_file(&mut linker, &provider, selection, &path, &target);
    }
}

fn usage() -> ! {
    eprintln!(
        "usage: body_dump --sdk <dir> --packages <file> (--literals|--operators|--integers|--identifiers|--user-operators|--members) --out <dir> <root>..."
    );
    std::process::exit(64)
}

/// Every `.dart` file under [dir], sorted by name within each directory,
/// with the path of its dump.
fn corpus_files(root: &Path, dir: &Path, out: &Path, files: &mut Vec<(PathBuf, PathBuf)>) {
    let mut entries: Vec<_> = fs::read_dir(dir).unwrap().map(Result::unwrap).collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let path = entry.path();
        let kind = entry.file_type().unwrap();
        if kind.is_dir() {
            corpus_files(root, &path, out, files);
        } else if kind.is_file() && path.extension().is_some_and(|e| e == "dart") {
            let target = out.join(format!("{}.body", path.strip_prefix(root).unwrap().display()));
            files.push((path, target));
        }
    }
}

/// Parses and analyzes the file at [path] and writes its dump to [target].
/// With `--integers`, `--identifiers` and `--user-operators` the file's library is linked first, so that type
/// annotations resolve against it.
fn dump_file(linker: &mut Linker, provider: &TypeProviderImpl, selection: Selection, path: &Path, target: &Path) {
    let bytes = fs::read(path).unwrap();
    let bytes = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(&bytes);
    let source: Rc<[u16]> = String::from_utf8_lossy(bytes)
        .encode_utf16()
        .collect::<Vec<_>>()
        .into();
    let unit = if matches!(selection, Selection::Integers | Selection::Identifiers | Selection::UserOperators | Selection::Members) {
        let uri = linker.fs.path_to_uri(path);
        let file = linker.fs.get_file_for_uri(&uri).expect("a corpus file has a URI");
        linker.unit_of_file(file)
    } else {
        None
    };
    let parsed = parse_string(source, None, path.to_str());
    let ast = Ast::new(&parsed.ast, &parsed.tokens);
    let Linker { store, types, .. } = linker;
    let mut analyzer = match unit {
        Some(unit) => TypeAnalyzer::with_declarations(
            provider,
            Declarations {
                store: &mut *store,
                scopes: &mut types.scopes,
                fragment_of_node: &types.fragment_of_node,
                unit,
            },
        ),
        None => TypeAnalyzer::new(provider),
    };
    analyzer.analyze(ast, parsed.unit);
    let results = Results {
        static_types: analyzer.static_types,
        variable_reads: analyzer.variable_reads,
        operator_invocations: analyzer.operator_invocations,
        member_spans: analyzer
            .member_accesses
            .iter()
            .map(|(&node, &kind)| (v1_span(ast, node), (kind, node)))
            .collect(),
        member_nodes: analyzer.member_accesses.keys().copied().collect(),
        member_arguments: analyzer.member_arguments,
    };
    let mut dump = String::new();
    Dumper { store, selection }.dump_node(ast, parsed.unit, &results, &mut dump);
    fs::create_dir_all(target.parent().unwrap()).unwrap();
    fs::write(target, dump).unwrap();
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

/// What the analyzer recorded for the file.
struct Results {
    static_types: HashMap<NodeId, TypeImpl>,
    variable_reads: HashMap<NodeId, VariableRead>,
    operator_invocations: HashSet<NodeId>,
    /// The member accesses by offset and length, which is how the V1
    /// projections find them: the projection of `a.f().g()` gives the inner
    /// invocation the whole chain as its origin.
    member_spans: HashMap<(i32, i32), (MemberAccessKind, NodeId)>,
    /// The member accesses by their canonical nodes.
    member_nodes: HashSet<NodeId>,
    member_arguments: HashSet<NodeId>,
}

struct Dumper<'a> {
    store: &'a ElementStore,
    selection: Selection,
}

impl Dumper<'_> {
    /// Writes the read of a getter that the V1 node [node], a
    /// `MethodInvocation` `r.g(...)`, invokes, when the analyzer typed it.
    /// Upstream's resolver rewrites such an invocation into a
    /// `FunctionExpressionInvocation` whose function is the read (a
    /// `PrefixedIdentifier` on a name, else a `PropertyAccess`), which comes
    /// first in pre-order; the parse-time projection here keeps the
    /// `MethodInvocation`.
    fn dump_invoked_getter(&self, ast: Ast<'_>, node: NodeId, analyzer: &Results, out: &mut String) {
        let AstNodeImpl::MethodInvocationImpl(invocation) = ast.node(node) else {
            return;
        };
        // `..g()` of a getter in a cascade section: the read begins at the
        // section's `..` or `?..`, which is the invocation's operator.
        let cascaded = invocation.target2 == NO_NODE
            && invocation.operator_ != NO_TOKEN
            && matches!(ast.tokens.lexeme_string(invocation.operator_).as_str(), ".." | "?..");
        if invocation.target2 == NO_NODE && !cascaded {
            return;
        }
        let offset = if cascaded { ast.tokens.offset(invocation.operator_) } else { ast.offset(invocation.target2) };
        let length = ast.end(invocation.method_name) - offset;
        let Some(&(MemberAccessKind::Property, access)) = analyzer.member_spans.get(&(offset, length)) else {
            return;
        };
        let runtime_type = match (cascaded, ast.node(invocation.target2)) {
            (false, AstNodeImpl::SimpleIdentifierImpl(_)) if !self.has_record_receiver(ast, access, analyzer) => {
                "PrefixedIdentifierImpl"
            }
            _ => "PropertyAccessImpl",
        };
        let type_ = analyzer
            .static_types
            .get(&access)
            .map(|type_| display_string(self.store, type_))
            .unwrap_or_else(|| "-".into());
        writeln!(out, "{runtime_type} {offset}+{length} type={type_}").unwrap();
    }

    /// Whether the receiver of the member access [access] has a record type
    /// (past type parameters, to their bounds): `V1Projection` then projects
    /// `r.p` as a `PropertyAccess`, not a `PrefixedIdentifier`
    /// (`_usesPrefixedIdentifier`).
    fn has_record_receiver(&self, ast: Ast<'_>, access: NodeId, analyzer: &Results) -> bool {
        let AstNodeImpl::ParsedNameAccessImpl(n) = ast.node(access) else {
            return false;
        };
        let mut type_ = analyzer.static_types.get(&n.operand).cloned();
        while let Some(TypeImpl::TypeParameter(t)) = &type_ {
            type_ = match &t.promoted_bound {
                Some(bound) => Some((**bound).clone()),
                None => self.store.element(t.element).type_.clone(),
            };
        }
        matches!(type_, Some(TypeImpl::Record(_)))
    }

    /// Writes the selected expressions under the V1 node [node], in the
    /// oracle's order. Types are recorded on canonical nodes, so a V1
    /// projection is looked up by the node it projects.
    fn dump_node(&self, ast: Ast<'_>, node: NodeId, analyzer: &Results, out: &mut String) {
        let source = match ast.v1_projection_source(node) {
            NO_NODE => node,
            origin => origin,
        };
        let source = if source == node { called_name_source(ast, node).unwrap_or(node) } else { source };
        // The canonical node whose type the row writes.
        let mut typed = source;
        let selected = match self.selection {
            Selection::Literals => is_context_independent_literal(ast.node(node)),
            Selection::Operators => is_operator_typed(ast, source),
            Selection::Integers => {
                matches!(ast.node(source), AstNodeImpl::IntegerLiteralImpl(_))
                    && is_declared_context_integer(ast, source)
            }
            Selection::Identifiers => {
                matches!(ast.node(node), AstNodeImpl::SimpleIdentifierImpl(_))
                    && analyzer.variable_reads.contains_key(&source)
            }
            Selection::UserOperators => is_selected_operator_node(ast, node, source, &analyzer.operator_invocations),
            Selection::Members => {
                let kind = match ast.node(node) {
                    AstNodeImpl::MethodInvocationImpl(_) => Some(MemberAccessKind::Invocation),
                    // An implicit `this` read projects a `SimpleIdentifier`.
                    AstNodeImpl::PrefixedIdentifierImpl(_)
                    | AstNodeImpl::PropertyAccessImpl(_)
                    | AstNodeImpl::SimpleIdentifierImpl(_) => Some(MemberAccessKind::Property),
                    _ => None,
                };
                match kind {
                    Some(kind) => match analyzer.member_spans.get(&(ast.offset(node), ast.length(node))) {
                        Some(&(found, access)) if found == kind => {
                            typed = access;
                            true
                        }
                        _ => false,
                    },
                    None => match ast.node(node) {
                        AstNodeImpl::IntegerLiteralImpl(_) => analyzer.member_arguments.contains(&source),
                        AstNodeImpl::ThisExpressionImpl(_) => is_selected_receiver(ast, source, &analyzer.member_nodes),
                        _ => false,
                    },
                }
            }
        };
        if self.selection == Selection::Members {
            self.dump_invoked_getter(ast, node, analyzer, out);
        }
        if selected {
            let type_ = analyzer
                .static_types
                .get(&typed)
                .map(|type_| display_string(self.store, type_))
                .unwrap_or_else(|| "-".into());
            writeln!(
                out,
                "{} {}+{} type={}{}",
                match ast.node(node).runtime_type() {
                    "PrefixedIdentifierImpl" if self.selection == Selection::Members && self.has_record_receiver(ast, typed, analyzer) => {
                        "PropertyAccessImpl"
                    }
                    runtime_type => runtime_type,
                },
                ast.offset(node),
                ast.length(node),
                type_,
                match analyzer.variable_reads.get(&source) {
                    Some(read) if self.selection == Selection::Identifiers => {
                        format!(" element={} {}", read.kind, read.name_offset)
                    }
                    _ => String::new(),
                }
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

/// The offset and length of the V1 projection of the canonical node [node]:
/// a node that begins a cascade section's body (a cascade head, or an access
/// chained on one) projects to a V1 node that begins at the section's `..`
/// or `?..`.
fn v1_span(ast: Ast<'_>, node: NodeId) -> (i32, i32) {
    let mut offset = ast.offset(node);
    let mut ancestor = ast.parent2(node);
    while ancestor != NO_NODE {
        if let AstNodeImpl::CascadeSectionImpl(section) = ast.node(ancestor) {
            if ast.offset(section.body) == offset {
                offset = ast.tokens.offset(section.operator_);
            }
            break;
        }
        ancestor = ast.parent2(ancestor);
    }
    (offset, ast.end(node) - offset)
}

/// The parsed name the `methodName` [node] of an unqualified call `f()` was
/// projected from. Upstream's resolver rewrites the call of a variable into
/// a `FunctionExpressionInvocation` whose function is that name's
/// identifier; the parse-time projection here keeps a `MethodInvocation`
/// whose `methodName` is a new identifier with no origin.
fn called_name_source(ast: Ast<'_>, node: NodeId) -> Option<NodeId> {
    let AstNodeImpl::SimpleIdentifierImpl(identifier) = ast.node(node) else {
        return None;
    };
    let AstNodeImpl::MethodInvocationImpl(invocation) = ast.node(ast.parent1_now(node)) else {
        return None;
    };
    if invocation.method_name != node || invocation.target2 != NO_NODE {
        return None;
    }
    let mut operand = invocation.parsed_expression_origin;
    loop {
        operand = match ast.node(operand) {
            AstNodeImpl::ParsedValueArgumentsImpl(n) => n.operand,
            AstNodeImpl::ParsedTypeArgumentsImpl(n) => n.operand,
            // The projection of `f().g()` gives the inner call the whole chain
            // as its origin.
            AstNodeImpl::ParsedNameAccessImpl(n) => n.operand,
            AstNodeImpl::ParsedUnqualifiedNameImpl(n) => {
                return (n.name == identifier.token).then_some(operand);
            }
            _ => return None,
        };
    }
}

/// Whether `--user-operators` selects the V1 node [node], which projects the
/// canonical node [source]: a binary, prefix or index expression projecting
/// an operator invocation the analyzer typed, an integer literal whose
/// parent past parentheses is one, or parentheses around either.
fn is_selected_operator_node(ast: Ast<'_>, node: NodeId, source: NodeId, invocations: &HashSet<NodeId>) -> bool {
    let is_operand = |literal: NodeId| {
        let mut parent = ast.parent2(literal);
        while let AstNodeImpl::ParenthesizedExpressionImpl(_) = ast.node(parent) {
            parent = ast.parent2(parent);
        }
        invocations.contains(&parent)
    };
    match ast.node(node) {
        AstNodeImpl::BinaryExpressionImpl(_) | AstNodeImpl::PrefixExpressionImpl(_) | AstNodeImpl::IndexExpressionImpl(_) => {
            invocations.contains(&source)
        }
        AstNodeImpl::IntegerLiteralImpl(_) | AstNodeImpl::ThisExpressionImpl(_) => is_operand(source),
        AstNodeImpl::ParenthesizedExpressionImpl(_) => {
            let mut inner = source;
            while let AstNodeImpl::ParenthesizedExpressionImpl(p) = ast.node(inner) {
                inner = p.expression2;
            }
            invocations.contains(&inner)
                || (matches!(ast.node(inner), AstNodeImpl::IntegerLiteralImpl(_)) && is_operand(inner))
        }
        _ => false,
    }
}

/// Whether the canonical node [receiver] (`this`) is, past parentheses, the
/// receiver of a member access the analyzer typed: a read `this.p`
/// (`ReceiverPropertyExtraction`), or the `ParsedNameAccess` of an
/// invocation `this.m(...)` (whose `ParsedValueArguments` is the access, or
/// which is itself the read of an invoked getter).
fn is_selected_receiver(ast: Ast<'_>, receiver: NodeId, accesses: &HashSet<NodeId>) -> bool {
    let mut node = receiver;
    while let AstNodeImpl::ParenthesizedExpressionImpl(_) = ast.node(ast.parent2(node)) {
        node = ast.parent2(node);
    }
    let parent = ast.parent2(node);
    match ast.node(parent) {
        AstNodeImpl::ReceiverPropertyExtractionImpl(r) => r.receiver == node && accesses.contains(&parent),
        AstNodeImpl::ParsedNameAccessImpl(n) if n.operand == node => {
            accesses.contains(&parent) || {
                let invocation = ast.parent2(parent);
                matches!(ast.node(invocation), AstNodeImpl::ParsedValueArgumentsImpl(v) if v.operand == parent)
                    && accesses.contains(&invocation)
            }
        }
        _ => false,
    }
}
