// Port of lib/src/dart/ast/invokes_super_self.dart: whether a method,
// getter, setter or operator invokes the member of the same name on
// `super`.
//
// `visitReceiverMethodInvocation` is not ported: the AstBuilder builds no
// `ReceiverMethodInvocation` (resolution does), and the element builder
// reads unresolved bodies.

use fe_analyzer_shared::scanner::token::TokenId;

use crate::dart::ast::visitor_g::RecursiveAstVisitor2;
use crate::dart::ast::visitor_g::recursive_ast_visitor2 as super_visitor;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NodeId};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Usage {
    Writing,
    Reading,
}

/// `_SuperVisitor`.
struct SuperVisitor {
    name: String,
    usage: Usage,
    /// Set to `true` if a super invocation with the [name] is found.
    has_super_invocation: bool,
}

fn is_super_reference(ast: Ast<'_>, node: NodeId) -> bool {
    matches!(ast.node(node), AstNodeImpl::SuperReferenceImpl(_))
}

/// `BinaryOperatorInvocationImpl.binaryOperator != null`.
fn is_binary_operator(ast: Ast<'_>, operator: TokenId) -> bool {
    matches!(
        ast.tokens.type_(operator).name,
        "STAR"
            | "SLASH"
            | "PERCENT"
            | "TILDE_SLASH"
            | "PLUS"
            | "MINUS"
            | "LT_LT"
            | "GT_GT"
            | "GT_GT_GT"
            | "AMPERSAND"
            | "CARET"
            | "BAR"
            | "LT"
            | "LT_EQ"
            | "GT"
            | "GT_EQ"
            | "EQ_EQ"
            | "BANG_EQ"
    )
}

impl RecursiveAstVisitor2 for SuperVisitor {
    fn visit_binary_operator_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        if self.usage == Usage::Reading {
            let n = ast.node(node).as_binary_operator_invocation_impl();
            if is_super_reference(ast, n.left_operand)
                && is_binary_operator(ast, n.operator_)
                && ast.tokens.lexeme_string(n.operator_) == self.name
            {
                self.has_super_invocation = true;
                return None;
            }
        }
        super_visitor::visit_binary_operator_invocation(self, ast, node)
    }

    fn visit_parsed_name_access(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parsed_name_access_impl();
        if self.usage == Usage::Reading
            && is_super_reference(ast, n.operand)
            && ast.tokens.lexeme_string(n.name) == self.name
        {
            self.has_super_invocation = true;
            return None;
        }
        super_visitor::visit_parsed_name_access(self, ast, node)
    }

    fn visit_receiver_property_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_receiver_property_assignment_target_impl();
        // `AssignmentTargetImpl.hasRead`.
        let has_read = matches!(
            ast.node(ast.parent2(node)),
            AstNodeImpl::CompoundAssignmentImpl(_)
                | AstNodeImpl::IfNullAssignmentImpl(_)
                | AstNodeImpl::IncrementOrDecrementExpressionImpl(_)
        );
        if is_super_reference(ast, n.receiver)
            && ast.tokens.lexeme_string(n.name) == self.name
            && (self.usage == Usage::Writing || has_read)
        {
            self.has_super_invocation = true;
            return None;
        }
        super_visitor::visit_receiver_property_assignment_target(self, ast, node)
    }

    fn visit_receiver_property_extraction(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_receiver_property_extraction_impl();
        if self.usage == Usage::Reading
            && is_super_reference(ast, n.receiver)
            && ast.tokens.lexeme_string(n.name) == self.name
        {
            self.has_super_invocation = true;
            return None;
        }
        super_visitor::visit_receiver_property_extraction(self, ast, node)
    }
}

recursive_ast_visitor2!(SuperVisitor, ());

/// `MethodDeclarationExtension.invokesSuperSelf`, given the declaration's
/// name token (`nameToken`) and body, and whether it is a setter.
pub fn invokes_super_self(ast: Ast<'_>, _declaration: NodeId, name: TokenId, body: NodeId, is_setter: bool) -> bool {
    let mut visitor = SuperVisitor {
        name: ast.tokens.lexeme_string(name),
        usage: if is_setter { Usage::Writing } else { Usage::Reading },
        has_super_invocation: false,
    };
    ast.accept2(body, &mut visitor);
    visitor.has_super_invocation
}
