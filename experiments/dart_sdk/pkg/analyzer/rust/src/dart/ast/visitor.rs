// Port of lib/dart/ast/visitor.dart (the visitors written by hand; the
// generated ones are in visitor_g.rs), and of the `Stopwatch` of dart:core
// that `TimedAstVisitor` uses.

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::dart::ast::visitor_g::{GeneralizingAstVisitor, UnifyingAstVisitor, UnifyingAstVisitor2};
use crate::src::dart::ast::ast_g::{AstVisitor, AstVisitor2};
use crate::src::dart::ast::ast_store::{Ast, NodeId};

/// `Stopwatch` (dart:core): the time elapsed while running.
#[derive(Default, Clone, Debug)]
pub struct Stopwatch {
    elapsed: Duration,
    started: Option<Instant>,
}

impl Stopwatch {
    /// Starts measuring; does nothing while running.
    pub fn start(&mut self) {
        if self.started.is_none() {
            self.started = Some(Instant::now());
        }
    }

    /// Stops measuring; does nothing while stopped.
    pub fn stop(&mut self) {
        if let Some(started) = self.started.take() {
            self.elapsed += started.elapsed();
        }
    }

    /// `elapsed`.
    pub fn elapsed(&self) -> Duration {
        match self.started {
            Some(started) => self.elapsed + started.elapsed(),
            None => self.elapsed,
        }
    }

    pub fn is_running(&self) -> bool {
        self.started.is_some()
    }
}

/// An AST visitor that will recursively visit all of the nodes in an AST
/// structure, similar to [GeneralizingAstVisitor]. This visitor uses a
/// breadth-first ordering rather than the depth-first ordering of
/// [GeneralizingAstVisitor].
///
/// A type is a `BreadthFirstVisitor` by holding the queue
/// (`breadth_first_queue`) and implementing `GeneralizingAstVisitor` with a
/// `visit_node` that calls `breadth_first_visitor::visit_node` (upstream's
/// override), with the macro `generalizing_ast_visitor!`. Clients start the
/// visit with `breadth_first_visitor::visit_all_nodes(visitor, ast, root)`.
pub trait BreadthFirstVisitor: GeneralizingAstVisitor {
    /// `_queue`: the nodes that have not yet been visited, in the order in
    /// which they ought to be visited.
    fn breadth_first_queue(&mut self) -> &mut VecDeque<NodeId>;
}

/// The methods of `BreadthFirstVisitor`.
pub mod breadth_first_visitor {
    use super::*;

    /// `visitAllNodes(root)`: visit all nodes in the tree starting at the
    /// given [root] node, in breadth-first order.
    pub fn visit_all_nodes<V: BreadthFirstVisitor + ?Sized>(v: &mut V, ast: Ast<'_>, root: NodeId) {
        v.breadth_first_queue().push_back(root);
        while let Some(next) = v.breadth_first_queue().pop_front() {
            ast.accept(next, v);
        }
    }

    /// `visitNode(node)`: queues the children, through
    /// `_BreadthFirstChildVisitor`.
    pub fn visit_node<V: BreadthFirstVisitor + ?Sized>(v: &mut V, ast: Ast<'_>, node: NodeId) -> Option<V::R> {
        let mut child_visitor = BreadthFirstChildVisitor {
            queue: v.breadth_first_queue(),
        };
        ast.visit_children(node, &mut child_visitor);
        None
    }
}

/// `_BreadthFirstChildVisitor`: adds the nodes it visits to the outer
/// visitor's queue.
struct BreadthFirstChildVisitor<'q> {
    queue: &'q mut VecDeque<NodeId>,
}

impl UnifyingAstVisitor for BreadthFirstChildVisitor<'_> {
    fn visit_node(&mut self, _ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.queue.push_back(node);
        None
    }
}

unifying_ast_visitor!(BreadthFirstChildVisitor<'_>, ());

/// An AST visitor that will recursively visit all of the nodes in an AST
/// structure. For each node that is visited, the corresponding visit method
/// on one or more other visitors (the 'delegates') will be invoked.
pub struct DelegatingAstVisitor<'a, T> {
    /// The delegates whose visit methods will be invoked.
    pub delegates: Vec<&'a mut dyn AstVisitor<R = T>>,
}

impl<'a, T> DelegatingAstVisitor<'a, T> {
    /// Initialize a newly created visitor to use each of the given delegate
    /// visitors to visit the nodes of an AST structure.
    pub fn new(delegates: Vec<&'a mut dyn AstVisitor<R = T>>) -> Self {
        DelegatingAstVisitor { delegates }
    }
}

impl<'a, T> UnifyingAstVisitor for DelegatingAstVisitor<'a, T> {
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<T> {
        for delegate in self.delegates.iter_mut() {
            ast.accept(node, &mut **delegate);
        }
        ast.visit_children(node, self);
        None
    }
}

unifying_ast_visitor!(['a, T] DelegatingAstVisitor<'a, T>, T);

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
