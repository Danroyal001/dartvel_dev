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
// - Integer literals: `int` with no context; with a context from a declared
//   type annotation, `double` when the annotation is `double`, `double?`,
//   `FutureOr<double>` or an alias of one (resolved where it is written:
//   type parameters, members, parameters and locals shadow names, and an
//   explicit `dart:core` import removes the implicit one), else `int`;
//   untyped when the annotation cannot be resolved because the unit is
//   analyzed without its library.
// - Reads of local variables and formal parameters declared with a type: that
//   type, the declaration the innermost scope gives, and no type when flow
//   analysis may promote the variable.
// - Operator invocations, analyzed with the library: the return type of the
//   operator method the receiver's interface has, substituted and refined for
//   numbers; `==` is `bool`; integer literal operands get the operator's
//   context; `dynamic`, `Never` and type parameter receivers.
// - Not in the slice, so no type: unresolved identifiers, operator
//   invocations without the library or whose resolution is not ported
//   (nullable receivers, extensions, inferred member types), integer literals
//   in other contexts (call arguments) and parentheses around any of those.

use std::path::{Path, PathBuf};
use std::rc::Rc;

use analyzer::dart::analysis::utilities::parse_string;
use analyzer::src::context::packages::parse_package_config_json_file;
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue, NodeId};
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::type_provider::TypeProviderImpl;
use analyzer::src::dart::resolver::type_analyzer::{Declarations, TypeAnalyzer};
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
    let code = "f() { a == b; -c; g(1); (d); g((2)); x is int; }";
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

/// Links a `dart:core` and a `dart:async` declaring what the tests read, and
/// [code] as the library `test.dart`; analyzes [code] against that library
/// and returns the types of [queries] as [types_of] does.
fn types_in_library(name: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    types_in_library_with_core(
        name,
        "library dart.core;\nclass Object {}\nclass Null {}\nclass bool {}\nclass num {}\n\
         class int extends num {}\nclass double extends num {}\nclass String {}\nclass Symbol {}\n",
        code,
        queries,
    )
}

/// [types_in_library] with [core] as the source of `dart:core`.
fn types_in_library_with_core(name: &str, core: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    let dir: PathBuf =
        std::env::temp_dir().join(format!("type_analyzer_test_{}_{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    write(
        &dir.join("sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart"),
        "const Map<String, LibraryInfo> libraries = const {\n  'async': const LibraryInfo('async/async.dart'),\n  'core': const LibraryInfo('core/core.dart'),\n};\n",
    );
    write(&dir.join("sdk/lib/core/core.dart"), core);
    write(
        &dir.join("sdk/lib/async/async.dart"),
        "library dart.async;\nclass Future<T> {}\nclass FutureOr<T> {}\n",
    );
    write(&dir.join("package_config.json"), "{\"configVersion\": 2, \"packages\": []}");
    let path = dir.join("test.dart");
    write(&path, code);
    let fs = FileSystemState::new(
        FolderBasedDartSdk::new(&dir.join("sdk")),
        parse_package_config_json_file(&dir.join("package_config.json")),
    );
    let mut linker = Linker::new(fs);
    let core_file = linker.fs.get_file_for_uri("dart:core").unwrap();
    let core = linker.library_for(core_file).unwrap();
    let file = linker.fs.get_file_for_path(&path);
    let unit = linker.unit_of_file(file).expect("test.dart is a library");
    let _ = std::fs::remove_dir_all(&dir);
    let provider = TypeProviderImpl::new(&linker.store, core);
    let units: Vec<u16> = code.encode_utf16().collect();
    let parsed = parse_string(Rc::from(units), None, path.to_str());
    let ast = Ast::new(&parsed.ast, &parsed.tokens);
    let Linker { store, types, .. } = &mut linker;
    let mut analyzer = TypeAnalyzer::with_declarations(
        &provider,
        Declarations {
            store,
            scopes: &mut types.scopes,
            fragment_of_node: &types.fragment_of_node,
            unit,
        },
    );
    analyzer.analyze(ast, parsed.unit);
    let static_types = analyzer.static_types;
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
                .unwrap_or_else(|| panic!("no {kind} at {source:?}"));
            match static_types.get(&node) {
                Some(type_) => display_string(&linker.store, type_),
                None => "-".to_string(),
            }
        })
        .collect()
}

fn integers(sources: &[&'static str]) -> Vec<(&'static str, &'static str)> {
    sources.iter().map(|&s| ("IntegerLiteralImpl", s)).collect()
}

#[test]
fn integer_literals_without_a_context_are_int() {
    let code = "f() { 1; (2); -3; '${4}'; }";
    let mut queries = integers(&["1", "2", "3", "4"]);
    queries.push(("ParenthesizedExpressionImpl", "(2)"));
    assert_eq!(types_of("no_context", code, &queries), ["int", "int", "int", "int", "int"]);
}

/// The silent failure: `int` for a literal whose context an unresolved
/// annotation gives, which may be `double`.
#[test]
fn annotated_contexts_are_unknown_without_the_library() {
    let code = "double a = 1;\nf([double b = 2]) {}\ndouble g() => 3;\nvar l = <double>[4];\n";
    assert_eq!(
        types_of("without_library", code, &integers(&["1", "2", "3", "4"])),
        ["-", "-", "-", "-"]
    );
}

#[test]
fn declared_types_give_integer_literals_their_context() {
    let code = "import 'dart:async';\n\
        typedef Real = double;\n\
        typedef Maybe<T> = FutureOr<T>;\n\
        double a = 1;\n\
        double? b = -2;\n\
        int c = 3;\n\
        num d = 4;\n\
        Real e = 5;\n\
        Maybe<double> f = 6;\n\
        Maybe<int> g = 7;\n\
        Future<double> h() async => 8;\n\
        double i() async => 9;\n\
        void j([double k = 10]) {\n\
          double l = 11;\n\
          var m = <double>[12];\n\
          var n = <String, double>{'x': 13};\n\
        }\n\
        FutureOr<double> o = 14;\n";
    assert_eq!(
        types_in_library(
            "declared",
            code,
            &integers(&["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14"])
        ),
        [
            "double", "double", "int", "int", "double", "double", "int", "double", "int", "double", "double",
            "double", "double", "double"
        ]
    );
}

#[test]
fn annotations_resolve_where_they_are_written() {
    let code = "typedef Real = double;\n\
        class C<double> { double a = 1; }\n\
        class D { int Real = 0; Real b = 2; }\n\
        void f(int double) { double c = 3; }\n\
        void g<Real>() { Real d = 4; }\n\
        Real h = 5;\n";
    assert_eq!(
        types_in_library("shadowed", code, &integers(&["1", "2", "3", "4", "5"])),
        ["int", "int", "int", "int", "double"]
    );
}

#[test]
fn an_explicit_dart_core_import_removes_the_implicit_one() {
    let code = "import 'dart:core' as core;\ncore.double a = 1;\ndouble b = 2;\n";
    assert_eq!(
        types_in_library("prefixed_core", code, &integers(&["1", "2"])),
        ["double", "int"]
    );
}

/// Links [code] as the library `test.dart` (as [types_in_library] does) and
/// returns, for each `(context, name)` in [queries], what the analyzer
/// records for the read `name` inside the first occurrence of `context`: its
/// type, the declaration's element kind and the declared name found at the
/// declaration's name offset, or `-` when the read is not selected.
fn variable_reads(name: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    let dir: PathBuf =
        std::env::temp_dir().join(format!("type_analyzer_test_{}_{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    write(
        &dir.join("sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart"),
        "const Map<String, LibraryInfo> libraries = const {\n  'async': const LibraryInfo('async/async.dart'),\n  'core': const LibraryInfo('core/core.dart'),\n};\n",
    );
    write(
        &dir.join("sdk/lib/core/core.dart"),
        "library dart.core;\nclass Object {}\nclass Null {}\nclass bool {}\nclass num {}\n\
         class int extends num {}\nclass double extends num {}\nclass String {}\nclass Symbol {}\n\
         class Function {}\nclass Record {}\nclass List<E> {}\n",
    );
    write(
        &dir.join("sdk/lib/async/async.dart"),
        "library dart.async;\nclass Future<T> {}\nclass FutureOr<T> {}\n",
    );
    write(&dir.join("package_config.json"), "{\"configVersion\": 2, \"packages\": []}");
    let path = dir.join("test.dart");
    write(&path, code);
    let fs = FileSystemState::new(
        FolderBasedDartSdk::new(&dir.join("sdk")),
        parse_package_config_json_file(&dir.join("package_config.json")),
    );
    let mut linker = Linker::new(fs);
    let core_file = linker.fs.get_file_for_uri("dart:core").unwrap();
    let core = linker.library_for(core_file).unwrap();
    let file = linker.fs.get_file_for_path(&path);
    let unit = linker.unit_of_file(file).expect("test.dart is a library");
    let _ = std::fs::remove_dir_all(&dir);
    let provider = TypeProviderImpl::new(&linker.store, core);
    let units: Vec<u16> = code.encode_utf16().collect();
    let parsed = parse_string(Rc::from(units), None, path.to_str());
    let ast = Ast::new(&parsed.ast, &parsed.tokens);
    let Linker { store, types, .. } = &mut linker;
    let mut analyzer = TypeAnalyzer::with_declarations(
        &provider,
        Declarations {
            store,
            scopes: &mut types.scopes,
            fragment_of_node: &types.fragment_of_node,
            unit,
        },
    );
    analyzer.analyze(ast, parsed.unit);
    let (static_types, reads) = (analyzer.static_types, analyzer.variable_reads);
    let mut all = Vec::new();
    nodes(ast, parsed.unit, &mut all);
    queries
        .iter()
        .map(|&(context, read)| {
            let start = code.find(context).unwrap_or_else(|| panic!("no {context:?}"));
            let offset = (start + context.find(read).unwrap_or_else(|| panic!("no {read:?}"))) as i32;
            let node = all
                .iter()
                .copied()
                .find(|&id| {
                    ast.node(id).runtime_type() == "ParsedUnqualifiedNameImpl"
                        && ast.offset(id) == offset
                        && ast.length(id) == read.len() as i32
                })
                .unwrap_or_else(|| panic!("no read {read:?} in {context:?}"));
            match (static_types.get(&node), reads.get(&node)) {
                (Some(type_), Some(variable)) => {
                    let declared: String = code[variable.name_offset as usize..]
                        .chars()
                        .take_while(|c| c.is_alphanumeric() || *c == '_')
                        .collect();
                    format!("{} {} {declared}", display_string(&linker.store, type_), variable.kind)
                }
                (None, None) => "-".to_string(),
                (type_, variable) => panic!("type {type_:?} without its variable {variable:?}, or the reverse"),
            }
        })
        .collect()
}

#[test]
fn reads_of_declared_variables_have_their_declared_types() {
    let code = "import 'dart:async' as async;\n\
        typedef Callback = int Function(String);\n\
        typedef Pair<T> = (T, T);\n\
        class Box<T> {\n\
          T value;\n\
          Box(T initial, {required int count}) : value = initial { count; }\n\
          S pick<S extends num>(S s, List<T> ts, Pair<S> pair, int g(String x)?) {\n\
            s; ts; pair; g;\n\
            List<T> local = ts;\n\
            local;\n\
            S Function<R>(R) generic = <R>(R r) => s;\n\
            generic;\n\
            return s;\n\
          }\n\
        }\n\
        void f(int a, [double? b, async.Future<int>? c]) {\n\
          a; b; c;\n\
          Callback callback = (s) => 1;\n\
          callback;\n\
          callback('x');\n\
          (int, {String name}) record = (1, name: 'n');\n\
          record;\n\
          Unknown unknown;\n\
          unknown;\n\
          dynamic d;\n\
          d;\n\
          for (int i = 0; i < 1; i++) { i; }\n\
          void local<U>(U u, Object? o) { u; o; a; }\n\
          var closure = (num n) => n;\n\
        }\n";
    assert_eq!(
        variable_reads(
            "declared_reads",
            code,
            &[
                ("{ count; }", "count"),
                ("s; ts;", "s"),
                ("ts; pair;", "ts"),
                ("pair; g;", "pair"),
                ("g;\n", "g"),
                ("\nlocal;", "local"),
                ("\ngeneric;", "generic"),
                ("a; b; c;", "a"),
                ("b; c;", "b"),
                ("b; c;", "c"),
                ("\ncallback;", "callback"),
                ("callback('x')", "callback"),
                ("\nrecord;", "record"),
                ("\nunknown;", "unknown"),
                ("\nd;", "d"),
                ("{ i; }", "i"),
                ("{ u; o; a; }", "u"),
                ("o; a; }", "o"),
                ("a; }", "a"),
                ("=> n;", "n"),
            ],
        ),
        [
            "int PARAMETER count",
            "S PARAMETER s",
            "List<T> PARAMETER ts",
            "(S, S) PARAMETER pair",
            "int Function(String)? PARAMETER g",
            "List<T> LOCAL_VARIABLE local",
            "S Function<R>(R) LOCAL_VARIABLE generic",
            "int PARAMETER a",
            "double? PARAMETER b",
            "Future<int>? PARAMETER c",
            "int Function(String) LOCAL_VARIABLE callback",
            "int Function(String) LOCAL_VARIABLE callback",
            "(int, {String name}) LOCAL_VARIABLE record",
            "InvalidType LOCAL_VARIABLE unknown",
            "dynamic LOCAL_VARIABLE d",
            "int LOCAL_VARIABLE i",
            "U PARAMETER u",
            "Object? PARAMETER o",
            "int PARAMETER a",
            "num PARAMETER n",
        ]
    );
}

/// A name finds the innermost declaration of it: a block declares all of its
/// locals for the whole block, and untyped variables, local functions, type
/// parameters, catch and pattern variables hide what they shadow.
#[test]
fn reads_find_the_innermost_declaration() {
    let code = "void f(int p, String q, int r, int s, int t, int u, int v) {\n\
          { String p = 'x'; p; }\n\
          { var q = 1; q; }\n\
          { void r() {} r; }\n\
          void g<s>() { s; }\n\
          try {} catch (t) { t; }\n\
          if (v case int u) { u; }\n\
          { v; int v = 2; }\n\
          q;\n\
        }\n\
        void w(int _, int __) { _; __; }\n";
    assert_eq!(
        variable_reads(
            "innermost",
            code,
            &[
                ("p; }", "p"),
                ("q; }", "q"),
                ("r; }", "r"),
                ("s; }", "s"),
                ("t; }", "t"),
                ("u; }", "u"),
                ("v; int v", "v"),
                ("q;\n}", "q"),
                ("_; __;", "_"),
                ("__; }", "__"),
            ],
        ),
        [
            "String LOCAL_VARIABLE p",
            "-",
            "-",
            "-",
            "-",
            "-",
            "int LOCAL_VARIABLE v",
            "String PARAMETER q",
            "-",
            "int PARAMETER __",
        ]
    );
}

/// The silent failure: the declared type where flow analysis promotes the
/// variable. Such variables are left out entirely.
#[test]
fn variables_flow_analysis_may_promote_are_left_out() {
    let code = "void f(int? n, num q, Object o, int? w, int? z, int k, int? y, int? x) {\n\
          if (n != null) { n; }\n\
          if (q is int) { q; }\n\
          o as int; o;\n\
          w = 1; w;\n\
          z!; z;\n\
          k = 2; k;\n\
          y;\n\
          x?.toString(); x;\n\
          int? initialized = 1; initialized;\n\
          int? uninitialized; uninitialized;\n\
        }\n";
    assert_eq!(
        variable_reads(
            "promoted",
            code,
            &[
                ("{ n; }", "n"),
                ("{ q; }", "q"),
                ("o;\n", "o"),
                ("w;\n", "w"),
                ("z;\n", "z"),
                ("k;\n", "k"),
                ("y;\n", "y"),
                ("x;\n", "x"),
                ("initialized;", "initialized"),
                ("; uninitialized;", "uninitialized"),
            ],
        ),
        ["-", "-", "-", "-", "-", "int PARAMETER k", "int? PARAMETER y", "-", "-", "int? LOCAL_VARIABLE uninitialized"]
    );
}

/// A `dart:core` whose classes declare the operators the operator tests
/// invoke.
const OPERATOR_CORE: &str = "library dart.core;\n\
    class Object { bool operator ==(Object other) => true; }\n\
    class Null {}\n\
    class bool {}\n\
    abstract class num {\n\
      num operator +(num other); num operator -(num other); num operator *(num other);\n\
      num operator %(num other); double operator /(num other); int operator ~/(num other);\n\
      num operator -(); bool operator <(num other);\n\
    }\n\
    abstract class int extends num {\n\
      int operator +(num other); int operator -(num other); int operator *(num other);\n\
      int operator %(num other); int operator -(); int operator ~(); int operator <<(int count);\n\
    }\n\
    abstract class double extends num {\n\
      double operator +(num other); double operator -(num other); double operator *(num other);\n\
      double operator %(num other); double operator -();\n\
    }\n\
    class String { String operator +(String other) => this; String operator [](int index) => this; }\n\
    class Symbol {}\n\
    class Function {}\n\
    class Record {}\n\
    abstract class List<E> { E operator [](int index); }\n";

fn operator_types(name: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    types_in_library_with_core(name, OPERATOR_CORE, code, queries)
}

fn binary(source: &'static str) -> (&'static str, &'static str) {
    ("BinaryOperatorInvocationImpl", source)
}

fn unary(source: &'static str) -> (&'static str, &'static str) {
    ("UnaryOperatorInvocationImpl", source)
}

fn index(source: &'static str) -> (&'static str, &'static str) {
    ("ReceiverIndexExpressionImpl", source)
}

fn integer(source: &'static str) -> (&'static str, &'static str) {
    ("IntegerLiteralImpl", source)
}

/// An operator invocation has the return type of the operator method the
/// interface of its receiver's static type declares, refined for `+`, `-`,
/// `*` and `%` on numbers (`refineBinaryExpressionType`).
#[test]
fn operators_have_the_return_type_of_their_method() {
    let code = "f(int i, double d, num n, String s) {\n\
        i + i; i + d; n + i; d - n; i / i; i ~/ i; i < i; -i; ~i; -d; i << i; s + s; s[i];\n\
    }";
    assert_eq!(
        operator_types(
            "operators_return_type",
            code,
            &[
                binary("i + i"),
                binary("i + d"),
                binary("n + i"),
                binary("d - n"),
                binary("i / i"),
                binary("i ~/ i"),
                binary("i < i"),
                unary("-i"),
                unary("~i"),
                unary("-d"),
                binary("i << i"),
                binary("s + s"),
                index("s[i]"),
            ],
        ),
        ["int", "double", "num", "double", "double", "int", "bool", "int", "int", "double", "int", "String", "String"]
    );
}

/// An integer literal operand has no context as a receiver, the operator's
/// parameter type as an argument, refined from the invocation's own context
/// for `+`, `-`, `*` and `%` on a `num` receiver
/// (`refineNumericInvocationContext`), and the context of a unary minus whose
/// operand it is.
#[test]
fn integer_operands_get_their_context_from_the_operator() {
    let code = "double f(int i, double d, num n) {\n\
        i + 1; d + 2; double x = n + 3; double y = i + 4; num z = n + 5; double w = -6;\n\
        i < 7; double v = n + -8; return n * 9;\n\
    }";
    assert_eq!(
        operator_types(
            "integer_operands",
            code,
            &[
                integer("1"),
                integer("2"),
                integer("3"),
                integer("4"),
                integer("5"),
                integer("6"),
                integer("7"),
                integer("8"),
                integer("9"),
                binary("d + 2"),
                binary("n + 3"),
                binary("i + 4"),
                binary("n + 5"),
                unary("-6"),
                binary("n + -8"),
                unary("-8"),
                binary("n * 9"),
            ],
        ),
        [
            "int", "int", "double", "double", "int", "double", "int", "double", "double", "double", "double",
            "double", "num", "double", "double", "double", "double"
        ]
    );
}

/// Members are substituted with the receiver's type arguments, through
/// superclasses too.
#[test]
fn operators_of_generic_classes_are_substituted() {
    let code = "class Box<T> { T operator [](int i) => throw 0; Box<T> operator +(Box<T> o) => this; }\n\
        class Sub extends Box<String> {}\n\
        f(List<int> l, Box<bool> b, Sub s) { l[0]; b[1]; b + b; s[2]; l[0] + 3; }";
    assert_eq!(
        operator_types(
            "generic_operators",
            code,
            &[index("l[0]"), index("b[1]"), binary("b + b"), index("s[2]"), binary("l[0] + 3")],
        ),
        ["int", "bool", "Box<bool>", "String", "int"]
    );
}

/// `==` is `bool` (`Never` on a `Never` receiver) whatever method it finds;
/// `!=` has the return type of the `==` method it finds, on the receiver's
/// type made non-nullable.
#[test]
fn equality_is_bool_and_inequality_has_the_equality_return_type() {
    let code = "class A { A operator +(A o) => this; }\n\
        class B { B operator +(B o) => this; String operator ==(Object o) => ''; }\n\
        f(A a, B b) { (a + a) == 1; (a + a) != 1; (b + b) != 1; (b + b) == 1; (throw 0) == 1; null != 1; }";
    assert_eq!(
        operator_types(
            "equality",
            code,
            &[
                binary("(a + a) == 1"),
                binary("(a + a) != 1"),
                binary("(b + b) != 1"),
                binary("(b + b) == 1"),
                binary("(throw 0) == 1"),
                binary("null != 1"),
            ],
        ),
        ["bool", "bool", "String", "bool", "Never", "bool"]
    );
}

/// A member a class inherits from its superclass or a mixin, and the most
/// specific of the members its superinterfaces declare.
#[test]
fn inherited_operators_are_found() {
    let code = "class Base { int operator +(int x) => x; }\n\
        class Both extends Base {}\n\
        class Wide { num operator *(num x) => x; }\n\
        abstract class Narrow { int operator *(num x); }\n\
        abstract class Combined implements Wide, Narrow {}\n\
        mixin M on Base { String operator -(int x) => ''; }\n\
        class Mixed extends Base with M {}\n\
        f(Both b, Combined c, Mixed m) { b + 1; c * 2; m - 3; m + 4; }";
    assert_eq!(
        operator_types(
            "inherited_operators",
            code,
            &[binary("b + 1"), binary("c * 2"), binary("m - 3"), binary("m + 4")],
        ),
        ["int", "int", "String", "int"]
    );
}

/// Receivers that resolve no member: `dynamic` makes `dynamic`, `Never`
/// makes `Never`, and a type parameter is resolved through its bound.
#[test]
fn dynamic_never_and_type_parameter_receivers() {
    let code = "f<T extends num>(dynamic d, Never n, T t) { d + 1; -d; d[0]; n + 2; -n; n[3]; t + 4; -t; }";
    assert_eq!(
        operator_types(
            "dynamic_receivers",
            code,
            &[
                binary("d + 1"),
                unary("-d"),
                index("d[0]"),
                binary("n + 2"),
                unary("-n"),
                index("n[3]"),
                binary("t + 4"),
                unary("-t"),
            ],
        ),
        ["dynamic", "dynamic", "dynamic", "Never", "Never", "Never", "num", "num"]
    );
}

/// The silent failure: a plausible type where upstream's comes from what is
/// not ported. A receiver that may be null, a member the interface lacks
/// (an extension may supply it), a member with an implicit return or
/// parameter type (override inference is not ported), and operands that are
/// not typed all leave the invocation untyped.
#[test]
fn operators_resolution_does_not_reach_are_left_untyped() {
    let code = "extension on String { String operator -(String o) => this; }\n\
        class C { operator +(int x) => 1; int operator *(o) => 1; }\n\
        f<U>(int? maybe, Object o, String s, C c, int i, U u) {\n\
          maybe + 1; o + 1; s - s; c + 1; c * 2; foo + 1; i + foo; u + 1; -maybe;\n\
        }";
    assert_eq!(
        operator_types(
            "untyped_operators",
            code,
            &[
                binary("maybe + 1"),
                binary("o + 1"),
                binary("s - s"),
                binary("c + 1"),
                binary("c * 2"),
                binary("foo + 1"),
                binary("i + foo"),
                binary("u + 1"),
                unary("-maybe"),
            ],
        ),
        ["-", "-", "-", "-", "-", "-", "-", "-", "-"]
    );
}
