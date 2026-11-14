// Tests of the V2 visitors of lib/dart/ast/visitor.dart and visitor.g.dart
// (not a mirrored file).
//
// Upstream's visitor_test.dart tests only `BreadthFirstVisitor`, which visits
// the V1 view and is not ported. These test what the API oracle does not
// see: that `ThrowingAstVisitor2` throws upstream's exception, the order in
// which `DelegatingAstVisitor2` calls its delegates (its documentation's
// example), and that an override of a `RecursiveAstVisitor2` method that
// does not call the overridden one stops the descent there.

use std::rc::Rc;

use analyzer::dart::analysis::utilities::{ParseStringResult, parse_string};
use analyzer::dart::ast::visitor::DelegatingAstVisitor2;
use analyzer::dart::ast::visitor_g::{
    RecursiveAstVisitor2, SimpleAstVisitor2, ThrowingAstVisitor2, recursive_ast_visitor2,
};
use analyzer::src::dart::ast::ast_g::AstVisitor2;
use analyzer::src::dart::ast::ast_store::{Ast, NodeId};
use analyzer::{recursive_ast_visitor2, simple_ast_visitor2, throwing_ast_visitor2};

fn parse(code: &str) -> ParseStringResult {
    let units: Vec<u16> = code.encode_utf16().collect();
    parse_string(Rc::from(units), None, None)
}

/// Records the binary operator invocations, identifiers and integer
/// literals it is asked to visit, prefixed with its name.
struct Recorder<'l> {
    name: &'static str,
    log: &'l std::cell::RefCell<Vec<String>>,
}

impl SimpleAstVisitor2 for Recorder<'_> {
    fn visit_binary_operator_invocation(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.log.borrow_mut().push(format!("{}.visitBinaryOperatorInvocation", self.name));
        None
    }

    fn visit_parsed_unqualified_name(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.log.borrow_mut().push(format!("{}.visitParsedUnqualifiedName", self.name));
        None
    }

    fn visit_integer_literal(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.log.borrow_mut().push(format!("{}.visitIntegerLiteral", self.name));
        None
    }
}

simple_ast_visitor2!(Recorder<'_>, ());

/// The initializer of `var v = <expression>;`.
fn expression(result: &ParseStringResult) -> NodeId {
    let ast = Ast::new(&result.ast, &result.tokens);
    let variables = ast.node(result.unit).as_compilation_unit_impl().declarations2[0];
    let mut found = None;
    struct Find<'f>(&'f mut Option<NodeId>);
    impl RecursiveAstVisitor2 for Find<'_> {
        fn visit_top_level_variable2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
            *self.0 = Some(ast.node(node).as_top_level_variable2_impl().initializer);
            None
        }
    }
    recursive_ast_visitor2!(Find<'_>, ());
    ast.accept2(variables, &mut Find(&mut found));
    found.unwrap()
}

#[test]
fn delegating_visits_each_node_with_every_delegate_in_order() {
    let result = parse("var v = x + 1;");
    let ast = Ast::new(&result.ast, &result.tokens);
    let log = std::cell::RefCell::new(Vec::new());
    let mut v1 = Recorder { name: "V1", log: &log };
    let mut v2 = Recorder { name: "V2", log: &log };
    let delegates: Vec<&mut dyn AstVisitor2<R = ()>> = vec![&mut v1, &mut v2];
    ast.accept2(expression(&result), &mut DelegatingAstVisitor2::new(delegates));
    assert_eq!(
        log.into_inner(),
        [
            "V1.visitBinaryOperatorInvocation",
            "V2.visitBinaryOperatorInvocation",
            "V1.visitParsedUnqualifiedName",
            "V2.visitParsedUnqualifiedName",
            "V1.visitIntegerLiteral",
            "V2.visitIntegerLiteral",
        ]
    );
}

struct Throwing;

impl ThrowingAstVisitor2 for Throwing {}

throwing_ast_visitor2!(Throwing, ());

#[test]
fn throwing_names_the_missing_method() {
    let result = parse("var v = x + 1;");
    let ast = Ast::new(&result.ast, &result.tokens);
    let node = expression(&result);
    let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        ast.accept2(node, &mut Throwing);
    }))
    .unwrap_err();
    assert_eq!(
        panic.downcast_ref::<String>().unwrap(),
        "Exception: Missing implementation of visitBinaryOperatorInvocation"
    );
}

/// Counts integer literals, and does not descend into blocks.
struct Counter {
    literals: usize,
}

impl RecursiveAstVisitor2 for Counter {
    fn visit_integer_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.literals += 1;
        recursive_ast_visitor2::visit_integer_literal(self, ast, node)
    }

    fn visit_block(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        None
    }
}

recursive_ast_visitor2!(Counter, ());

#[test]
fn recursive_descends_unless_an_override_stops_it() {
    let result = parse("var a = [1, 2, 3]; void f() { print(4); } int g() => 5;");
    let ast = Ast::new(&result.ast, &result.tokens);
    let mut counter = Counter { literals: 0 };
    ast.accept2(result.unit, &mut counter);
    assert_eq!(counter.literals, 4);
}
