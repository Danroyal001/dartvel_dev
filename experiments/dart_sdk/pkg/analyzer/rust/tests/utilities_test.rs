// Port of test/src/dart/ast/utilities_test.dart (`NodeLocator2Test`).
//
// `ScopedNameFinder2Test` and `ScopedNameFinderTest` test classes that are
// not ported (see src/src/dart/ast/utilities.rs).

use std::rc::Rc;

use analyzer::dart::analysis::utilities::{ParseStringResult, parse_string};
use analyzer::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use analyzer::src::dart::ast::utilities::NodeLocator2;

fn parse(code: &str) -> ParseStringResult {
    let units: Vec<u16> = code.encode_utf16().collect();
    parse_string(Rc::from(units), None, None)
}

fn locate(ast: Ast<'_>, unit: NodeId, start: i32, end: Option<i32>) -> NodeId {
    NodeLocator2::new(start, end).search_within(ast, unit)
}

/// `_assertLocate`: the node at [start], which must cover it.
fn assert_locate(ast: Ast<'_>, unit: NodeId, start: i32) -> NodeId {
    let end = start;
    let node = locate(ast, unit, start, Some(end));
    assert_ne!(node, NO_NODE);
    assert!(ast.offset(node) <= start, "Node starts after range");
    assert!(
        ast.offset(node) + ast.length(node) > end,
        "Node ends before range"
    );
    node
}

fn index_of(source: &str, pattern: &str) -> i32 {
    source.find(pattern).unwrap() as i32
}

fn assert_locates(source: &str, pattern: &str, expected: &str) {
    let result = parse(source);
    let ast = Ast::new(&result.ast, &result.tokens);
    let node = assert_locate(ast, result.unit, index_of(source, pattern));
    assert_eq!(ast.node(node).runtime_type(), expected);
}

#[test]
fn test_onlyStartOffset() {
    let code = " f() {} ";
    //          01234567
    let result = parse(code);
    let ast = Ast::new(&result.ast, &result.tokens);
    let unit = result.unit;
    let function = *ast
        .node(unit)
        .as_compilation_unit_impl()
        .declarations2
        .first()
        .unwrap();
    let f = ast.node(function).as_top_level_function_declaration_impl();
    let block = ast.node(f.body).as_block_function_body_impl().block;
    assert_eq!(locate(ast, unit, 0, None), unit);
    assert_eq!(locate(ast, unit, 1, None), function);
    assert_eq!(locate(ast, unit, 2, None), function);
    assert_eq!(locate(ast, unit, 3, None), f.formal_parameters);
    assert_eq!(locate(ast, unit, 4, None), function);
    assert_eq!(locate(ast, unit, 5, None), block);
    assert_eq!(locate(ast, unit, 6, None), block);
    assert_eq!(locate(ast, unit, 7, None), unit);
    assert_eq!(locate(ast, unit, 100, None), NO_NODE);
}

#[test]
fn test_searchWithin_class_afterName_beforeTypeParameters() {
    let source = "class A<T> {}\n";
    assert_locates(source, "<T> {}", "ClassDeclaration2Impl");
}

#[test]
fn test_searchWithin_constructor_afterName_beforeParameters() {
    let source = "class A {\n  A() {}\n}\n";
    assert_locates(source, "() {}", "ConstructorDeclaration2Impl");
}

#[test]
fn test_searchWithin_function_afterName_beforeParameters() {
    let source = "void f() {}\n";
    assert_locates(source, "() {}", "TopLevelFunctionDeclarationImpl");
}

#[test]
fn test_searchWithin_function_afterName_beforeTypeParameters() {
    let source = "void f<T>() {}\n";
    assert_locates(source, "<T>() {}", "TopLevelFunctionDeclarationImpl");
}

#[test]
fn test_searchWithin_method_afterName_beforeParameters() {
    let source = "class A {\n  void m() {}\n}\n";
    assert_locates(source, "() {}", "MethodDeclaration2Impl");
}

#[test]
fn test_searchWithin_method_afterName_beforeTypeParameters() {
    let source = "class A {\n  void m<T>() {}\n}\n";
    assert_locates(source, "<T>() {}", "MethodDeclaration2Impl");
}

#[test]
fn test_searchWithin_namedConstructor_afterName_beforeParameters() {
    let source = "class A {\n  A.c() {}\n}\n";
    assert_locates(source, "() {}", "ConstructorDeclaration2Impl");
}

#[test]
fn test_searchWithin_setter_afterName_beforeParameters() {
    let source = "set s(int i) {}\n";
    assert_locates(source, "(int i)", "TopLevelSetterDeclarationImpl");
}

#[test]
fn test_searchWithin_topLevelGetter_afterName_beforeBody() {
    let source = "int get g=>0;\n";
    assert_locates(source, "=>0", "TopLevelGetterDeclarationImpl");
}

#[test]
fn test_searchWithin_topLevelGetter_afterName_beforeRecoveryParameters() {
    // Upstream's test code ends with the expected diagnostic as comments.
    let source = "int get g(int i) => 0;\n";
    let result = parse(source);
    assert_eq!(
        result
            .errors
            .iter()
            .map(|e| (e.diagnostic_code.unique_name, e.offset, e.message.as_str()))
            .collect::<Vec<_>>(),
        [(
            "getter_with_parameters",
            9,
            "Getters must be declared without a parameter list."
        )]
    );
    assert_locates(source, "(int i)", "TopLevelGetterDeclarationImpl");
}

#[test]
fn test_startEndOffset() {
    let code = " f() {} ";
    //          01234567
    let result = parse(code);
    let ast = Ast::new(&result.ast, &result.tokens);
    let unit = result.unit;
    let function = ast.node(unit).as_compilation_unit_impl().declarations2[0];
    assert_eq!(locate(ast, unit, -1, Some(2)), NO_NODE);
    assert_eq!(locate(ast, unit, 0, Some(2)), unit);
    assert_eq!(locate(ast, unit, 1, Some(2)), function);
    assert_eq!(locate(ast, unit, 1, Some(3)), function);
    assert_eq!(locate(ast, unit, 1, Some(4)), function);
    assert_eq!(locate(ast, unit, 5, Some(7)), unit);
    assert_eq!(locate(ast, unit, 5, Some(100)), NO_NODE);
    assert_eq!(locate(ast, unit, 100, Some(200)), NO_NODE);
}
