// Port of lib/src/summary2/not_serializable_nodes.dart: whether an
// expression can be written to a summary, and the marker that replaces it
// when it cannot (`replaceNotSerializableExpression`, which
// detach_nodes.dart applies to constant initializers and default values).

use crate::dart::ast::visitor_g::RecursiveAstVisitor2;
use crate::src::dart::ast::ast_store::{Ast, NodeId};

/// `_notSerializableName`.
pub const NOT_SERIALIZABLE_NAME: &str = "_notSerializableExpression";

/// `_IsSerializableNodeVisitor`.
struct IsSerializableNodeVisitor {
    result: bool,
}

impl RecursiveAstVisitor2 for IsSerializableNodeVisitor {
    fn visit_anonymous_method_invocation(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.result = false;
        None
    }

    fn visit_for_element(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.result = false;
        None
    }

    fn visit_function_expression(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.result = false;
        None
    }

    fn visit_pattern_assignment(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.result = false;
        None
    }

    fn visit_switch_expression(&mut self, _: Ast<'_>, _: NodeId) -> Option<()> {
        self.result = false;
        None
    }
}

recursive_ast_visitor2!(IsSerializableNodeVisitor, ());

/// `isSerializable`.
pub fn is_serializable(ast: Ast<'_>, node: NodeId) -> bool {
    let mut visitor = IsSerializableNodeVisitor { result: true };
    ast.accept2(node, &mut visitor);
    visitor.result
}

/// The source of `replaceNotSerializableExpression(node)`: the node's, or
/// the marker's name.
pub fn serializable_source(ast: Ast<'_>, node: NodeId) -> String {
    if is_serializable(ast, node) {
        ast.to_source(node)
    } else {
        NOT_SERIALIZABLE_NAME.to_string()
    }
}
