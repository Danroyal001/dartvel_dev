// Port of lib/dart/ast/visitor.dart (the V2 visitors; the generated ones
// are in visitor_g.rs).
//
// `BreadthFirstVisitor` and `DelegatingAstVisitor` visit the V1 view of the
// tree, which is not ported; `DelegatingAstVisitor2` is.

use crate::dart::ast::visitor_g::UnifyingAstVisitor2;
use crate::src::dart::ast::ast_g::AstVisitor2;
use crate::src::dart::ast::ast_store::{Ast, NodeId};

/// An AST visitor that will recursively visit all of the nodes in an AST
/// structure. For each node that is visited, the corresponding visit method
/// on one or more other visitors (the 'delegates') will be invoked.
///
/// For example, if an instance of this class is created with two delegates
/// V1 and V2, and that instance is used to visit the expression 'x + 1',
/// then the following visit methods will be invoked:
/// 1. V1.visitBinaryOperatorInvocation
/// 2. V2.visitBinaryOperatorInvocation
/// 3. V1.visitSimpleIdentifier
/// 4. V2.visitSimpleIdentifier
/// 5. V1.visitIntegerLiteral
/// 6. V2.visitIntegerLiteral
pub struct DelegatingAstVisitor2<'a, T> {
    /// The delegates whose visit methods will be invoked.
    pub delegates: Vec<&'a mut dyn AstVisitor2<R = T>>,
}

impl<'a, T> DelegatingAstVisitor2<'a, T> {
    /// Initialize a newly created visitor to use each of the given delegate
    /// visitors to visit the nodes of an AST structure.
    pub fn new(delegates: Vec<&'a mut dyn AstVisitor2<R = T>>) -> Self {
        DelegatingAstVisitor2 { delegates }
    }
}

impl<'a, T> UnifyingAstVisitor2 for DelegatingAstVisitor2<'a, T> {
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<T> {
        for delegate in self.delegates.iter_mut() {
            ast.accept2(node, &mut **delegate);
        }
        ast.visit_children2(node, self);
        None
    }
}

unifying_ast_visitor2!(['a, T] DelegatingAstVisitor2<'a, T>, T);
