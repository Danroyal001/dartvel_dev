// Tests of the V1 view and of ScopedNameFinder2 (not a mirrored file).
//
// Ports `BreadthFirstVisitorTest` of test/dart/ast/visitor_test.dart,
// `ScopedNameFinder2Test` of test/src/dart/ast/utilities_test.dart and the
// parse-only V1 test of `ExpressionImplTest` in test/src/dart/ast/ast_test.dart
// (`test_constantContext_constructorInvocation_v1Projection`, its node
// covering part), which the API oracle does not check. It also tests what the
// oracle does not see: `ThrowingAstVisitor`'s exception, the parents the
// projections of a declaration get, and `visitChildrenWithHooks`.

use std::collections::VecDeque;
use std::rc::Rc;

use analyzer::dart::analysis::utilities::{ParseStringResult, parse_string};
use analyzer::dart::ast::visitor::{BreadthFirstVisitor, breadth_first_visitor};
use analyzer::dart::ast::visitor_g::{GeneralizingAstVisitor, ThrowingAstVisitor};
use analyzer::src::dart::ast::ast::AstNodeImpl;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue1, NO_NODE, NodeId};
use analyzer::src::dart::ast::utilities::ScopedNameFinder2;
use analyzer::{generalizing_ast_visitor, throwing_ast_visitor};

fn parse(code: &str) -> ParseStringResult {
    let units: Vec<u16> = code.encode_utf16().collect();
    parse_string(Rc::from(units), None, None)
}

/// `_BreadthFirstVisitorTestHelper`: collects the nodes visited, in order.
struct BreadthFirstHelper {
    nodes: Vec<NodeId>,
    queue: VecDeque<NodeId>,
}

impl BreadthFirstVisitor for BreadthFirstHelper {
    fn breadth_first_queue(&mut self) -> &mut VecDeque<NodeId> {
        &mut self.queue
    }
}

impl GeneralizingAstVisitor for BreadthFirstHelper {
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.nodes.push(node);
        breadth_first_visitor::visit_node(self, ast, node)
    }
}

generalizing_ast_visitor!(BreadthFirstHelper, ());

/// The V1 children of [node] that are nodes, lists flattened.
fn children(ast: Ast<'_>, node: NodeId) -> Vec<NodeId> {
    let mut result = Vec::new();
    for entity in ast.named_child_entities(node) {
        match entity.value {
            ChildValue1::Node(n) => result.push(n),
            ChildValue1::NodeList(l) => result.extend(l),
            _ => {}
        }
    }
    result
}

/// The V1 child named [name] of [node].
fn child(ast: Ast<'_>, node: NodeId, name: &str) -> NodeId {
    for entity in ast.named_child_entities(node) {
        if entity.name == name {
            if let ChildValue1::Node(n) = entity.value {
                return n;
            }
        }
    }
    NO_NODE
}

/// The V1 list named [name] of [node].
fn list(ast: Ast<'_>, node: NodeId, name: &str) -> Vec<NodeId> {
    for entity in ast.named_child_entities(node) {
        if entity.name == name {
            if let ChildValue1::NodeList(l) = entity.value {
                return l;
            }
        }
    }
    Vec::new()
}

#[test]
fn breadth_first_visitor_test_it() {
    let result = parse(
        r#"
class A {
  bool get g => true;
}
class B {
  int f() {
    num q() {
      return 3;
    }
  return q() + 4;
  }
}
A f(p) {
  if ((p as A).g) {
    return p;
  } else {
    return null;
  }
}"#,
    );
    let ast = Ast::new(&result.ast, &result.tokens);
    let mut visitor = BreadthFirstHelper {
        nodes: Vec::new(),
        queue: VecDeque::new(),
    };
    breadth_first_visitor::visit_all_nodes(&mut visitor, ast, result.unit);
    let nodes = visitor.nodes;

    assert_eq!(nodes.len(), 51);
    assert_eq!(nodes[0], result.unit);
    let declarations = list(ast, result.unit, "declarations");
    // The V1 projection of the class `B`.
    assert_eq!(nodes[2], declarations[1]);
    // The V1 projection of the top-level function `f`.
    assert_eq!(nodes[3], declarations[2]);
    // The V1 projection of the local function `q`.
    let class_b = declarations[1];
    let body = child(ast, class_b, "body");
    let method = list(ast, body, "members")[0];
    let block = child(ast, child(ast, method, "body"), "block");
    assert_eq!(nodes[24], list(ast, block, "statements")[0]);
    assert_eq!(ast.to_source(nodes[50]), "3");
    assert!(matches!(ast.node(nodes[50]), AstNodeImpl::IntegerLiteralImpl(_)));
}

/// Every node of the V1 view of [unit], in pre-order.
fn all_nodes(ast: Ast<'_>, unit: NodeId) -> Vec<NodeId> {
    let mut result = vec![unit];
    let mut i = 0;
    while i < result.len() {
        let node = result[i];
        let mut kids = children(ast, node);
        kids.reverse();
        for kid in kids {
            result.insert(i + 1, kid);
        }
        i += 1;
    }
    result
}

#[test]
fn every_v1_node_has_the_node_that_walks_to_it_as_parent() {
    let result = parse(
        r#"
@a.b<int>.c(1)
class A extends B with C implements D {
  int x = 1, y;
  A.named(this.x) : super.s(), y = 2;
  get g => x..y = 1..z();
  set s(v) {}
  operator +(o) => -x + o!;
}
void f() { var v = a.b.c(); v++; ++v; !v; f<int>; new p.C<int>.n(); }
"#,
    );
    let ast = Ast::new(&result.ast, &result.tokens);
    for node in all_nodes(ast, result.unit) {
        for kid in children(ast, node) {
            assert_eq!(
                ast.parent(kid),
                node,
                "{} under {}",
                ast.node(kid).runtime_type(),
                ast.node(node).runtime_type()
            );
            assert_eq!(ast.root(kid), result.unit);
        }
    }
}

#[test]
fn a_projection_is_made_once() {
    let result = parse("void f() { a.b(); }");
    let ast = Ast::new(&result.ast, &result.tokens);
    let first = all_nodes(ast, result.unit);
    let count = result.ast.v1_projection_count();
    let second = all_nodes(ast, result.unit);
    assert_eq!(first, second);
    assert_eq!(result.ast.v1_projection_count(), count);
}

#[test]
fn node_covering_projects_the_constructor_invocation() {
    // ExpressionImplTest.test_constantContext_constructorInvocation_v1Projection
    let code = "class C {\n  const C(Object value);\n}\nvar x = const C(0);\n";
    let result = parse(code);
    let ast = Ast::new(&result.ast, &result.tokens);
    let offset = code.find('0').unwrap() as i32;
    let literal = ast.node_covering(result.unit, offset, 0);
    assert!(matches!(ast.node(literal), AstNodeImpl::IntegerLiteralImpl(_)));
    let argument_list = ast.parent(literal);
    let creation = ast.parent(argument_list);
    assert_eq!(ast.node(creation).runtime_type(), "InstanceCreationExpressionImpl");
}

struct Throwing;

impl ThrowingAstVisitor for Throwing {}

throwing_ast_visitor!(Throwing, ());

#[test]
fn throwing_ast_visitor_names_the_missing_method() {
    let result = parse("var x = a.b;");
    let ast = Ast::new(&result.ast, &result.tokens);
    let declaration = list(ast, result.unit, "declarations")[0];
    let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        ast.accept(declaration, &mut Throwing);
    }))
    .unwrap_err();
    assert_eq!(
        panic.downcast_ref::<String>().unwrap(),
        "Exception: Missing implementation of visitTopLevelVariableDeclaration"
    );
}

#[test]
fn a_v2_only_node_is_not_in_the_v1_view() {
    let result = parse("var x = a.b;");
    let ast = Ast::new(&result.ast, &result.tokens);
    let declaration = result.ast.node(result.unit).as_compilation_unit_impl().declarations2[0];
    let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| ast.parent(declaration))).unwrap_err();
    assert_eq!(
        panic.downcast_ref::<String>().unwrap(),
        "StateError: TopLevelVariablesDeclarationImpl is not in the V1 AST view."
    );
}

/// ScopedNameFinder2Test: the finder run from the node covering `new C();`.
fn scoped_names(code: &str) -> (Vec<String>, bool) {
    let result = parse(code);
    let ast = Ast::new(&result.ast, &result.tokens);
    let offset = code.find("new C();").unwrap() as i32;
    let node = ast.node_covering2(result.unit, offset, 7);
    let mut finder = ScopedNameFinder2::new(offset);
    ast.accept2(node, &mut finder);
    let declaration = result.ast.node(result.unit).as_compilation_unit_impl().declarations2[0];
    let mut locals = finder.locals();
    locals.sort();
    (locals, finder.declaration() == declaration)
}

#[test]
fn scoped_name_finder2_constructor_invocation() {
    let code = "void f(int parameter) {\n  var local = 0;\n  new C();\n  var after = 1;\n}\n";
    assert_eq!(scoped_names(code), (vec!["local".into(), "parameter".into()], true));
}

#[test]
fn scoped_name_finder2_local_function() {
    let code = "void f() {\n  void g() {}\n  new C();\n  void h() {}\n}\n";
    assert_eq!(scoped_names(code), (vec!["g".into()], true));
}

#[test]
fn scoped_name_finder2_switch_member() {
    let code = "void f(int x) {\n  switch (x) {\n    case 0:\n      var local = 0;\n      new C();\n      var after = 1;\n  }\n}\n";
    assert_eq!(scoped_names(code), (vec!["local".into(), "x".into()], true));
}

#[test]
fn scoped_name_finder2_top_level_getter() {
    let code = "int get foo {\n  var local = 0;\n  new C();\n  return local;\n}\n";
    assert_eq!(scoped_names(code), (vec!["local".into()], true));
}

#[test]
fn scoped_name_finder2_top_level_getter_recovery_formal_parameters() {
    let code = "int get foo(int parameter) {\n  var local = 0;\n  new C();\n  return local;\n}\n";
    assert_eq!(scoped_names(code), (vec!["local".into(), "parameter".into()], true));
}

#[test]
fn scoped_name_finder2_top_level_setter() {
    let code = "set foo(int parameter) {\n  var local = 0;\n  new C();\n  var after = 1;\n}\n";
    assert_eq!(scoped_names(code), (vec!["local".into(), "parameter".into()], true));
}

mod hooks {
    use super::*;
    use analyzer::dart::ast::visitor_g::{SimpleAstVisitor2, simple_ast_visitor2};
    use analyzer::src::dart::ast::ast::Hooked;
    use analyzer::simple_ast_visitor2;

    /// Records the visit of every node it is asked to visit.
    struct Names<'l> {
        log: &'l mut Vec<String>,
    }

    impl SimpleAstVisitor2 for Names<'_> {
        fn visit_parsed_unqualified_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
            self.log.push(format!("visit {}", ast.to_source(node)));
            None
        }

        fn visit_integer_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
            self.log.push(format!("visit {}", ast.to_source(node)));
            None
        }
    }

    simple_ast_visitor2!(Names<'_>, ());

    #[test]
    fn visit_children_with_hooks_calls_the_hook_in_place_of_the_visit() {
        let result = parse("var x = a + 1;");
        let ast = Ast::new(&result.ast, &result.tokens);
        let unit = result.unit;
        let declaration = result.ast.node(unit).as_compilation_unit_impl().declarations2[0];
        let variable = result.ast.node(declaration).as_top_level_variables_declaration_impl().variables[0];
        let binary = result.ast.node(variable).as_top_level_variable2_impl().initializer;
        let mut log = Vec::new();
        let mut hooked = Vec::new();
        ast.visit_children_with_hooks(binary, &mut Names { log: &mut log }, &mut |name, child| {
            if name == "visitRightOperand" {
                if let Hooked::Node(n) = child {
                    hooked.push(format!("{name} {}", ast.to_source(n)));
                }
                return true;
            }
            false
        });
        assert_eq!(log, vec!["visit a"]);
        assert_eq!(hooked, vec!["visitRightOperand 1"]);

        // Without hooks, it is visitChildren2.
        let mut log = Vec::new();
        ast.visit_children_with_hooks(binary, &mut Names { log: &mut log }, &mut |_, _| false);
        assert_eq!(log, vec!["visit a", "visit 1"]);
    }
}

/// `NodeLocator` in the V1 view, on the cases of `NodeLocator2Test` (the
/// test of the V1 locator upstream was removed with it): offsets between a
/// declaration's name and its parameters locate the declaration.
mod node_locator {
    use super::*;
    use analyzer::src::dart::ast::utilities::NodeLocator;

    fn assert_locates(source: &str, pattern: &str, expected: &str) {
        let result = parse(source);
        let ast = Ast::new(&result.ast, &result.tokens);
        let start = source.find(pattern).unwrap() as i32;
        let node = NodeLocator::new(start, None).search_within(ast, result.unit);
        assert_ne!(node, NO_NODE);
        assert!(ast.offset(node) <= start, "Node starts after range");
        assert!(ast.offset(node) + ast.length(node) > start, "Node ends before range");
        assert_eq!(ast.node(node).runtime_type(), expected);
    }

    #[test]
    fn class_after_name_before_type_parameters() {
        assert_locates("class A<T> {}\n", "<T> {}", "ClassDeclarationImpl");
    }

    #[test]
    fn constructor_after_name_before_parameters() {
        assert_locates("class A {\n  A() {}\n}\n", "() {}", "ConstructorDeclarationImpl");
    }

    #[test]
    fn named_constructor_after_name_before_parameters() {
        assert_locates("class A {\n  A.c() {}\n}\n", "() {}", "ConstructorDeclarationImpl");
    }

    #[test]
    fn function_after_name_before_parameters() {
        assert_locates("void f() {}\n", "() {}", "FunctionDeclarationImpl");
    }

    #[test]
    fn function_after_name_before_type_parameters() {
        assert_locates("void f<T>() {}\n", "<T>() {}", "FunctionDeclarationImpl");
    }

    #[test]
    fn method_after_name_before_parameters() {
        assert_locates("class A {\n  void m() {}\n}\n", "() {}", "MethodDeclarationImpl");
    }

    #[test]
    fn method_after_name_before_type_parameters() {
        assert_locates("class A {\n  void m<T>() {}\n}\n", "<T>() {}", "MethodDeclarationImpl");
    }

    #[test]
    fn setter_after_name_before_parameters() {
        assert_locates("set s(int x) {}\n", "(int x)", "FunctionDeclarationImpl");
    }

    #[test]
    fn only_start_offset() {
        let code = " f() {} ";
        let result = parse(code);
        let ast = Ast::new(&result.ast, &result.tokens);
        let locate = |offset| NodeLocator::new(offset, None).search_within(ast, result.unit);
        let function = list(ast, result.unit, "declarations")[0];
        assert_eq!(locate(0), result.unit);
        assert_eq!(locate(1), function);
        assert_eq!(locate(2), function);
        assert_eq!(ast.node(locate(3)).runtime_type(), "FormalParameterListImpl");
        assert_eq!(locate(4), ast.parent(locate(3)));
        assert_eq!(ast.node(locate(5)).runtime_type(), "BlockImpl");
        assert_eq!(locate(7), result.unit);
        assert_eq!(locate(100), NO_NODE);
    }
}
