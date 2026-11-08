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
// - Member accesses, analyzed with the library: an invocation `r.m(...)` has
//   the return type of the method the receiver's interface has, a read `r.p`
//   the type of its getter or field, or of the method torn off, substituted;
//   integer literal arguments get their parameter's type as the context; an
//   invoked getter is read and its call is not typed.
// - Extension members, analyzed with the library: a member the interface
//   lacks (or any member but `Object`'s on a receiver that may be null) is
//   found in the most specific accessible applicable extension, with its type
//   parameters inferred and substituted; explicit overrides `E(x)` and
//   `E<T>(x)` resolve in `E`; operators too (through an override, binary and
//   unary operators unsubstituted, as upstream). Ambiguous, inapplicable and
//   setter-only extensions, and interface setters of the name, leave the
//   access untyped.
// - Not in the slice, so no type: unresolved identifiers, operator
//   invocations without the library or whose resolution is not ported
//   (nullable receivers no extension serves, inferred member types), integer literals
//   in other contexts and parentheses around any of those; member accesses
//   with null-aware receivers, nullable receivers no extension serves,
//   members of extensions that do not apply, private names,
//   generic methods, implicit member types, `dynamic` receivers, numeric
//   `remainder`, explicit type arguments and static members.

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
    types_in_library_with_files(name, core, &[], code, queries)
}

/// [types_in_library_with_core] with [files] (paths relative to `test.dart`
/// and their contents) beside the test library.
fn types_in_library_with_files(
    name: &str,
    core: &str,
    files: &[(&str, &str)],
    code: &str,
    queries: &[(&str, &str)],
) -> Vec<String> {
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
    for (file, content) in files {
        write(&dir.join(file), content);
    }
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
                .unwrap_or_else(|| {
                    let found: Vec<_> = all
                        .iter()
                        .filter(|&&id| ast.offset(id) == offset)
                        .map(|&id| (ast.node(id).runtime_type(), ast.length(id)))
                        .collect();
                    panic!("no {kind} at {source:?}; there: {found:?}")
                });
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
/// not ported. A receiver that may be null, a member neither the interface
/// nor an applicable extension has, a member with an implicit return or
/// parameter type (override inference is not ported), and operands that are
/// not typed all leave the invocation untyped.
#[test]
fn operators_resolution_does_not_reach_are_left_untyped() {
    let code = "extension on int { String operator -(String o) => this; }\n\
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

/// A `dart:core` whose classes declare the members the member access tests
/// read and invoke.
const MEMBER_CORE: &str = "library dart.core;\n\
    class Object { bool operator ==(Object other) => true; external int get hashCode; }\n\
    class Null {}\n\
    class bool {}\n\
    abstract class num { num remainder(num other); }\n\
    abstract class int extends num { bool get isEven; int remainder(num other); }\n\
    abstract class double extends num {}\n\
    abstract class String { int get length; }\n\
    class Symbol {}\n\
    class Function {}\n\
    class Record {}\n\
    abstract class List<E> { E get first; }\n";

fn member_types(name: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    types_in_library_with_core(name, MEMBER_CORE, code, queries)
}

/// A method invocation `r.m(...)`.
fn call(source: &'static str) -> (&'static str, &'static str) {
    ("ParsedValueArgumentsImpl", source)
}

/// A property read `r.p` (a getter, a field or a method tear-off).
fn property(source: &'static str) -> (&'static str, &'static str) {
    ("ParsedNameAccessImpl", source)
}

/// A property read whose receiver is a literal, parenthesized, an index
/// expression, `this` or such a read (`ReceiverPropertyExtraction`).
fn extraction(source: &'static str) -> (&'static str, &'static str) {
    ("ReceiverPropertyExtractionImpl", source)
}

/// A method invocation has the return type of the method the interface of
/// its receiver's static type has, and a property read the type of the getter
/// (or field) it finds, or the function type of the method it tears off; both
/// substituted with the receiver's type arguments, through superclasses, and
/// on receivers that are literals, parenthesized or member accesses
/// themselves.
#[test]
fn member_accesses_have_the_types_of_their_members() {
    let code = "class A { int m(int x) => x; String get g => ''; final double f; A(this.f); bool n({required int k}) => true; }\n\
        class Box<T> { T get value => throw 0; T take(T t) => t; List<T> all() => throw 0; }\n\
        class Sub extends Box<String> {}\n\
        f(A a, Box<int> b, Sub s, String str, int i) {\n\
          a.m; a.m(1); a.g; a.f; a.n(k: 2); b.value; b.take(3); b.all(); s.value; s.take('x');\n\
          str.length; i.isEven; 'lit'.length; (a).g; a.g.length; b.all().first; a.hashCode;\n\
        }";
    assert_eq!(
        member_types(
            "member_types",
            code,
            &[
                property("a.m"),
                call("a.m(1)"),
                property("a.g"),
                property("a.f"),
                call("a.n(k: 2)"),
                property("b.value"),
                call("b.take(3)"),
                call("b.all()"),
                property("s.value"),
                call("s.take('x')"),
                property("str.length"),
                property("i.isEven"),
                extraction("'lit'.length"),
                extraction("(a).g"),
                property("a.g.length"),
                property("b.all().first"),
                property("a.hashCode"),
            ],
        ),
        [
            "int Function(int)", "int", "String", "double", "bool", "int", "int", "List<int>", "String", "String",
            "int", "bool", "int", "String", "int", "int", "int"
        ]
    );
}

/// An integer literal argument has the type of the parameter it is passed
/// to as its context; one that matches no parameter is not typed.
#[test]
fn integer_arguments_get_their_context_from_the_parameter() {
    let code = "class C { void d(double x, [num y = 0, double z = 0]) {} void n({double? k, int j = 0}) {} }\n\
        f(C c) { c.d(11, 22, 33); c.n(k: 44, j: 55); c.d((66)); c.d(77, 88, 99, 100); }";
    assert_eq!(
        member_types(
            "member_arguments",
            code,
            &[
                integer("11"),
                integer("22"),
                integer("33"),
                integer("44"),
                integer("55"),
                integer("66"),
                integer("100"),
                call("c.d(11, 22, 33)"),
            ],
        ),
        ["double", "int", "double", "double", "int", "double", "-", "void"]
    );
}

/// The silent failure: a plausible type where upstream's comes from what is
/// not ported. Null-aware and nullable receivers, members of an extension
/// that does not apply, private names (whose fields flow analysis may promote), generic
/// methods, members with implicit types, `dynamic` and unresolved receivers,
/// numeric refinement of `remainder`, calls of function-typed getters,
/// explicit type arguments and static members are left untyped, as are the
/// integer arguments of untyped invocations.
#[test]
fn member_accesses_resolution_does_not_reach_are_left_untyped() {
    let code = "extension on int { int get ext => 0; }\n\
        class A { String get g => ''; int _p = 0; T gen<T>(T t) => t; get imp => 1; var inferred = 1;\n\
          int Function() fn = f0; int m(int x) => x; static int st() => 0; }\n\
        int f0() => 0;\n\
        f(A a, A other, A? maybe, String s, dynamic d, int i) {\n\
          other?.g; maybe.g; s.ext; a._p; a.gen(11); a.imp; a.inferred; d.g; foo.g; i.remainder(22); a.fn();\n\
          a.m<int>(33); A.st();\n\
        }";
    assert_eq!(
        member_types(
            "untyped_members",
            code,
            &[
                property("other?.g"),
                property("maybe.g"),
                property("s.ext"),
                property("a._p"),
                call("a.gen(11)"),
                integer("11"),
                property("a.imp"),
                property("a.inferred"),
                property("d.g"),
                property("foo.g"),
                call("i.remainder(22)"),
                call("a.fn()"),
                call("a.m<int>(33)"),
                call("A.st()"),
            ],
        ),
        ["-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-", "-"]
    );
}

/// `r.g()` of a getter reads the getter, whose type the read has, and calls
/// its value, which is not typed (`FunctionExpressionInvocation`).
#[test]
fn invoked_getters_are_read() {
    let code = "class A { int Function(int) adder = f0; Function get callback => f0; }\n\
        int f0(int x) => x;\n\
        f(A a) { a.adder(11); a.callback(); }";
    assert_eq!(
        member_types(
            "invoked_getters",
            code,
            &[property("a.adder"), call("a.adder(11)"), integer("11"), property("a.callback"), call("a.callback()")],
        ),
        ["int Function(int)", "-", "-", "Function", "-"]
    );
}

/// A mixin replaces a member only with one it declares itself; a member its
/// interface inherits from its superclass constraint is merged with the
/// superclass's, the most specific winning (`_getInterfaceClass`).
#[test]
fn mixins_replace_only_the_members_they_declare() {
    let code = "abstract class Shape { num get size; }\n\
        class Square implements Shape { int get size => 0; }\n\
        mixin Named on Shape { String get label => ''; }\n\
        mixin Sized on Shape { double get size => 0; }\n\
        class NamedSquare extends Square with Named {}\n\
        class SizedSquare extends Square with Sized {}\n\
        f(NamedSquare n, SizedSquare s) { n.size; n.label; s.size; }";
    assert_eq!(
        member_types(
            "mixin_members",
            code,
            &[property("n.size"), property("n.label"), property("s.size")],
        ),
        ["int", "String", "double"]
    );
}

/// Valid overrides of different types combine into the top merge of their
/// types (`_topMerge`).
#[test]
fn valid_overrides_combine_into_their_top_merge() {
    let code = "abstract class A { (Object?, dynamic) m(); }\n\
        abstract class B { (dynamic, Object?) m(); }\n\
        abstract class C implements A, B {}\n\
        f(C c) { c.m(); }";
    assert_eq!(member_types("top_merge", code, &[call("c.m()")]), ["(Object?, Object?)"]);
}

/// A `dart:core` whose classes declare members and operators for the
/// extension tests, `Object` among them (a receiver that may be null finds
/// `Object`'s members before any extension's).
const EXTENSION_CORE: &str = "library dart.core;\n\
    class Object { bool operator ==(Object other) => true; external int get hashCode; external String toString(); }\n\
    class Null {}\n\
    class bool {}\n\
    abstract class num { num operator +(num other); }\n\
    abstract class int extends num { bool get isEven; int operator +(num other); }\n\
    abstract class double extends num { double operator +(num other); }\n\
    abstract class String { int get length; }\n\
    class Symbol {}\n\
    class Function {}\n\
    class Record {}\n\
    abstract class Iterable<E> {}\n\
    abstract class List<E> implements Iterable<E> { E get first; }\n";

fn extension_types(name: &str, code: &str, queries: &[(&str, &str)]) -> Vec<String> {
    types_in_library_with_core(name, EXTENSION_CORE, code, queries)
}

/// A member the interface of the receiver's static type lacks is found in
/// the most specific applicable extension, with the extension's type
/// parameters inferred from the receiver's type and substituted: a method's
/// return type, a getter's type, a method torn off, the getter an invocation
/// reads, and the parameter types integer arguments take as their context.
/// A receiver that may be null finds `Object`'s members first, then an
/// extension that applies to its type.
#[test]
fn extension_members_apply_implicitly() {
    let code = "class Shape { int get sides => 0; }\n\
        class Square extends Shape {}\n\
        extension Strings on String { int get size => 0; String pad(double width, {int count = 0}) => this;\n\
          int Function(int) get adder => throw 0; }\n\
        extension Shapes on Shape { String name(int precision) => ''; int get sides => 0; }\n\
        extension Squares on Square { bool name(int precision) => true; }\n\
        extension Lists<T> on List<T> { T get head => first; List<T> twice() => this; T at(int index) => first; }\n\
        extension Nums<N extends num> on N { N get self => this; N plus(N other) => this; }\n\
        extension OnNum on num { String get kind => ''; }\n\
        extension OnInt on int { bool get kind => true; }\n\
        extension Maybe on Shape? { bool get missing => true; }\n\
        extension Any on Object? { double get tag => 0; }\n\
        f(String s, Shape shape, Square square, List<String> strings, int i, double d, String? maybe, Shape? maybeShape) {\n\
          s.size; s.pad; s.pad(1, count: 2); s.adder(3); shape.name(4); square.name(5); shape.sides;\n\
          strings.head; strings.twice(); strings.at(6); strings.twice().head; i.self; d.plus(7); i.kind; d.kind;\n\
          maybe.hashCode; maybe.toString(); maybe.tag; maybeShape.missing; s.size.isEven; 'x'.size;\n\
        }";
    assert_eq!(
        extension_types(
            "extension_members",
            code,
            &[
                property("s.size"),
                call("s.pad(1, count: 2)"),
                integer("1"),
                integer("2"),
                property("s.pad"),
                property("s.adder"),
                call("s.adder(3)"),
                call("shape.name(4)"),
                call("square.name(5)"),
                property("shape.sides"),
                property("strings.head"),
                call("strings.twice()"),
                call("strings.at(6)"),
                property("strings.twice().head"),
                property("i.self"),
                call("d.plus(7)"),
                integer("7"),
                property("i.kind"),
                property("d.kind"),
                property("maybe.hashCode"),
                call("maybe.toString()"),
                property("maybe.tag"),
                property("maybeShape.missing"),
                property("s.size.isEven"),
                extraction("'x'.size"),
            ],
        ),
        [
            "int", "String", "double", "int", "String Function(double, {int count})", "int Function(int)", "-",
            "String", "bool", "int", "String", "List<String>", "String", "String", "int", "double", "double",
            "bool", "String", "int", "String", "double", "bool", "bool", "int"
        ]
    );
}

/// An explicit override `E(x)` or `E<T>(x)` resolves the member in `E`, with
/// the type arguments written, or inferred from the argument's type, or
/// `dynamic` when their number is wrong; it applies even where `E` is not the
/// most specific extension, or does not apply at all.
#[test]
fn extension_overrides_resolve_in_the_named_extension() {
    let code = "class Shape {}\n\
        class Square extends Shape {}\n\
        extension Shapes on Shape { String name(int precision) => ''; int get sides => 0; }\n\
        extension Squares on Square { bool name(int precision) => true; }\n\
        extension Lists<T> on List<T> { T get head => first; T at(int index) => first; }\n\
        extension Strings on String { int get size => 0; }\n\
        f(Square square, List<int> ints, int i) {\n\
          Shapes(square).name; Shapes(square).name(1); Squares(square).name(2); Shapes(square).sides; Lists(ints).head;\n\
          Lists<num>(ints).at(3); Lists<int, int>(ints).head; Strings(i).size; Shapes(square).name;\n\
        }";
    assert_eq!(
        extension_types(
            "extension_overrides",
            code,
            &[
                call("Shapes(square).name(1)"),
                integer("1"),
                call("Squares(square).name(2)"),
                property("Shapes(square).sides"),
                property("Lists(ints).head"),
                call("Lists<num>(ints).at(3)"),
                integer("3"),
                property("Lists<int, int>(ints).head"),
                property("Strings(i).size"),
                property("Shapes(square).name"),
            ],
        ),
        ["String", "int", "bool", "int", "int", "num", "int", "dynamic", "int", "String Function(int)"]
    );
}

/// Operators a class lacks are found in an applicable extension, also on a
/// receiver that may be null (`Object` has no operator but `==`), with the
/// extension's type parameters substituted. Through an explicit override,
/// a binary or unary operator has the extension's method unsubstituted, as
/// upstream's `extension.getMethod` gives it, and an index operator the
/// substituted one (`getOverrideMember`).
#[test]
fn extension_operators_apply_to_classes_that_lack_them() {
    let code = "class Matrix {}\n\
        extension Matrices on Matrix { Matrix operator +(Matrix o) => this; Matrix operator *(double k) => this;\n\
          Matrix operator -() => this; int operator [](int row) => row; }\n\
        extension Maybe on Matrix? { Matrix operator ~() => Matrix(); }\n\
        extension Lists<T> on List<T> { T operator -() => first; List<T> operator *(int n) => this;\n\
          T operator [](String key) => first; }\n\
        f(Matrix m, Matrix? maybe, List<bool> flags) {\n\
          m + m; m * 1; -m; m[2]; ~maybe; -flags; flags * 3; flags['k']; Matrices(m) * 4; -Lists(flags);\n\
          Lists(flags) * 5; Lists(flags)['j'];\n\
        }";
    assert_eq!(
        extension_types(
            "extension_operators",
            code,
            &[
                binary("m + m"),
                binary("m * 1"),
                integer("1"),
                unary("-m"),
                index("m[2]"),
                integer("2"),
                unary("~maybe"),
                unary("-flags"),
                binary("flags * 3"),
                index("flags['k']"),
                binary("Matrices(m) * 4"),
                integer("4"),
                unary("-Lists(flags)"),
                binary("Lists(flags) * 5"),
                index("Lists(flags)['j']"),
            ],
        ),
        [
            "Matrix", "Matrix", "double", "Matrix", "int", "int", "Matrix", "bool", "List<bool>", "bool", "Matrix",
            "double", "T", "List<T>", "bool"
        ]
    );
}

/// The silent failure: a plausible type where upstream finds nothing or
/// reports an error. Two applicable extensions neither more specific than the
/// other, an extension with only a setter of the name, an interface setter of
/// the name (which stops the lookup before extensions), an interface member
/// (which wins over an extension), an extension that does not apply, a
/// receiver that may be null and only its interface has the member, a static
/// member through an override, and an override of `==` leave the access
/// untyped or typed by the interface.
#[test]
fn extension_lookups_upstream_rejects_are_left_untyped() {
    let code = "class Shape { set label(int v) {} int get sides => 0; }\n\
        extension First on int { int get clash => 0; int operator -(int o) => 0; }\n\
        extension Second on int { int get clash => 1; int operator -(int o) => 1; }\n\
        extension Setters on String { set only(int v) {} }\n\
        extension Shapes on Shape { int get label => 0; String get sides => ''; static int make() => 0; }\n\
        extension Ints on int { int get twice => 0; }\n\
        f(int i, String s, Shape shape, int? maybe, Shape other) {\n\
          i.clash; i - 1; s.only; shape.label; shape.sides; s.twice; maybe.isEven; maybe.twice;\n\
          Shapes(shape).make(); Shapes(other) == other;\n\
        }";
    assert_eq!(
        extension_types(
            "extension_rejected",
            code,
            &[
                property("i.clash"),
                binary("i - 1"),
                property("s.only"),
                property("shape.label"),
                property("shape.sides"),
                property("s.twice"),
                property("maybe.isEven"),
                property("maybe.twice"),
                call("Shapes(shape).make()"),
                binary("Shapes(other) == other"),
            ],
        ),
        ["-", "-", "-", "-", "int", "-", "-", "-", "-", "-"]
    );
}

/// The extensions accessible in a file are its library's (unnamed and
/// private ones too, in every part), and those its imports and its library's
/// imports provide, prefixed or not, as their combinators filter them; an
/// unnamed extension of another library is not exported. An extension of a
/// platform library loses to any other, however specific its type.
#[test]
fn accessible_extensions_come_from_the_library_and_its_imports() {
    let core = format!("{EXTENSION_CORE}extension CoreInts on int {{ String get origin => ''; int get core => 0; }}\n");
    let library = "extension Shown on String { int get shown => 0; }\n\
        extension Hidden on String { int get hidden => 0; }\n\
        extension Prefixed on String { bool get prefixed => true; }\n\
        extension on String { int get unnamed => 0; }\n";
    let code = "import 'other.dart' hide Hidden, Prefixed;\n\
        import 'other.dart' as p show Prefixed;\n\
        extension Mine on num { bool get origin => true; }\n\
        extension on String { double get local => 0; }\n\
        extension _Private on String { bool get private => true; }\n\
        f(String s, int i) { s.shown; s.hidden; s.prefixed; s.unnamed; s.local; s.private; i.origin; i.core; }";
    assert_eq!(
        types_in_library_with_files(
            "accessible_extensions",
            &core,
            &[("other.dart", library)],
            code,
            &[
                property("s.shown"),
                property("s.hidden"),
                property("s.prefixed"),
                property("s.unnamed"),
                property("s.local"),
                property("s.private"),
                property("i.origin"),
                property("i.core"),
            ],
        ),
        ["int", "-", "bool", "-", "double", "bool", "bool", "int"]
    );
}
