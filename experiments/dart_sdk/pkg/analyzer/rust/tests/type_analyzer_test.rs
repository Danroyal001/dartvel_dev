// Tests of the body type analyzer port (not a mirrored file; see
// ../README.md): the static types `TypeAnalyzer` records, and the ones it must
// leave unrecorded rather than guess, on a hand-built `dart:core` so that the
// tests read nothing else and run under Miri (with
// `-Zmiri-disable-isolation`, which lets them write and read files).
//
// - Literals: the seven context-independent kinds.
// - Operators: `is` and `is!` are `bool`, as are `!`, `&&` and `||`, whatever
//   their operands; `throw` and `rethrow` are `Never`; parentheses take the
//   type of the expression they enclose.
// - Not in the slice, so no type: identifiers, `==` (its type is the
//   operator method's return type), unary minus, integer literals and
//   parentheses around any of those.

use std::path::{Path, PathBuf};
use std::rc::Rc;

use analyzer::dart::analysis::utilities::parse_string;
use analyzer::src::context::packages::parse_package_config_json_file;
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue, NodeId};
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::type_provider::TypeProviderImpl;
use analyzer::src::dart::resolver::type_analyzer::TypeAnalyzer;
use analyzer::src::dart::sdk::sdk::FolderBasedDartSdk;
use analyzer::src::summary2::link::Linker;

fn write(path: &Path, content: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, content).unwrap();
}

/// Links a `dart:core` declaring the classes the type provider reads.
fn link_core(name: &str) -> (Linker, u32) {
    let dir: PathBuf =
        std::env::temp_dir().join(format!("type_analyzer_test_{}_{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    write(
        &dir.join("sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart"),
        "const Map<String, LibraryInfo> libraries = const {\n  'core': const LibraryInfo('core/core.dart'),\n};\n",
    );
    write(
        &dir.join("sdk/lib/core/core.dart"),
        "library dart.core;\nclass Object {}\nclass Null {}\nclass bool {}\nclass num {}\n\
         class int extends num {}\nclass double extends num {}\nclass String {}\nclass Symbol {}\n",
    );
    write(
        &dir.join("package_config.json"),
        "{\"configVersion\": 2, \"packages\": []}",
    );
    let fs = FileSystemState::new(
        FolderBasedDartSdk::new(&dir.join("sdk")),
        parse_package_config_json_file(&dir.join("package_config.json")),
    );
    let mut linker = Linker::new(fs);
    let core_file = linker.fs.get_file_for_uri("dart:core").unwrap();
    let core = linker.library_for(core_file).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    (linker, core)
}

/// Every canonical node of the tree under [node], in pre-order.
fn nodes(ast: Ast<'_>, node: NodeId, out: &mut Vec<NodeId>) {
    out.push(node);
    for child in ast.named_child_entities2(node) {
        match child.value {
            ChildValue::Node(id) => nodes(ast, id, out),
            ChildValue::NodeList(ids) => {
                for &id in ids {
                    nodes(ast, id, out);
                }
            }
            _ => (),
        }
    }
}

/// Analyzes [code] and returns, for each `(runtime type, source)` in
/// [queries], the display string of the static type recorded on the first
/// node of that runtime type covering exactly the first occurrence of that
/// source, or `-` when none was recorded.
fn types_of(name: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    let (linker, core) = link_core(name);
    let provider = TypeProviderImpl::new(&linker.store, core);
    let units: Vec<u16> = code.encode_utf16().collect();
    let parsed = parse_string(Rc::from(units), None, None);
    let ast = Ast::new(&parsed.ast, &parsed.tokens);
    let mut analyzer = TypeAnalyzer::new(&provider);
    analyzer.analyze(ast, parsed.unit);
    let mut all = Vec::new();
    nodes(ast, parsed.unit, &mut all);
    queries
        .iter()
        .map(|&(kind, source)| {
            let offset = code.find(source).unwrap_or_else(|| panic!("no {source:?}")) as i32;
            let node = all
                .iter()
                .copied()
                .find(|&id| {
                    ast.node(id).runtime_type() == kind
                        && ast.offset(id) == offset
                        && ast.length(id) == source.len() as i32
                })
                .unwrap_or_else(|| {
                    let found: Vec<_> = all
                        .iter()
                        .filter(|&&id| ast.offset(id) == offset)
                        .map(|&id| ast.node(id).runtime_type())
                        .collect();
                    panic!("no {kind} at {source:?}; there: {found:?}")
                });
            match analyzer.static_types.get(&node) {
                Some(type_) => display_string(&linker.store, type_),
                None => "-".to_string(),
            }
        })
        .collect()
}

#[test]
fn literals_have_their_class_types() {
    let code = "f() { [true, 1.5, null, 'a', 'b' 'c', 'd$e', #s]; }";
    assert_eq!(
        types_of(
            "literals",
            code,
            &[
                ("BooleanLiteralImpl", "true"),
                ("DoubleLiteralImpl", "1.5"),
                ("NullLiteralImpl", "null"),
                ("SimpleStringLiteralImpl", "'a'"),
                ("AdjacentStringsImpl", "'b' 'c'"),
                ("StringInterpolationImpl", "'d$e'"),
                ("SymbolLiteralImpl", "#s"),
            ],
        ),
        [
            "bool", "double", "Null", "String", "String", "String", "Symbol"
        ]
    );
}

#[test]
fn type_tests_and_logical_operators_are_bool_whatever_the_operands() {
    let code = "f() { a is int; b is! String; !c; d && e; g || h; }";
    assert_eq!(
        types_of(
            "logical",
            code,
            &[
                ("IsExpressionImpl", "a is int"),
                ("IsExpressionImpl", "b is! String"),
                ("LogicalNotImpl", "!c"),
                ("LogicalAndImpl", "d && e"),
                ("LogicalOrImpl", "g || h"),
            ],
        ),
        ["bool", "bool", "bool", "bool", "bool"]
    );
}

#[test]
fn throw_and_rethrow_are_never() {
    let code = "f() { try { throw x; } catch (e) { rethrow; } }";
    assert_eq!(
        types_of(
            "throw",
            code,
            &[
                ("ThrowExpressionImpl", "throw x"),
                ("RethrowExpressionImpl", "rethrow")
            ],
        ),
        ["Never", "Never"]
    );
}

#[test]
fn parentheses_take_the_type_of_what_they_enclose() {
    let code = "f() { (a && b); ((1.5)); (throw 'x'); (!(c is int)); }";
    assert_eq!(
        types_of(
            "parentheses",
            code,
            &[
                ("ParenthesizedExpressionImpl", "(a && b)"),
                ("ParenthesizedExpressionImpl", "((1.5))"),
                ("ParenthesizedExpressionImpl", "(1.5)"),
                ("ParenthesizedExpressionImpl", "(throw 'x')"),
                ("ParenthesizedExpressionImpl", "(c is int)"),
                ("LogicalNotImpl", "!(c is int)"),
            ],
        ),
        ["bool", "double", "double", "Never", "bool", "bool"]
    );
}

/// The silent failure: a plausible `bool` or `int` where upstream's type
/// depends on resolution this slice does not do.
#[test]
fn expressions_outside_the_slice_are_left_untyped() {
    let code = "f() { a == b; -c; 1; (d); (2); x is int; }";
    assert_eq!(
        types_of(
            "untyped",
            code,
            &[
                ("BinaryOperatorInvocationImpl", "a == b"),
                ("UnaryOperatorInvocationImpl", "-c"),
                ("IntegerLiteralImpl", "1"),
                ("ParenthesizedExpressionImpl", "(d)"),
                ("ParenthesizedExpressionImpl", "(2)"),
                ("ParsedUnqualifiedNameImpl", "x"),
            ],
        ),
        ["-", "-", "-", "-", "-", "-"]
    );
}
