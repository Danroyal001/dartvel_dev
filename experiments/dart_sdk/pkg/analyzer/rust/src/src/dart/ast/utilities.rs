// Port of lib/src/dart/ast/utilities.dart (`NodeLocator2`).
//
// `NodeLocator`, `ScopedNameFinder` and `ScopedNameFinder2` are not ported:
// the first visits the V1 view, the others need elements. Where upstream
// catches an exception thrown while visiting and logs it, the port has
// nothing that throws.

use crate::dart::ast::visitor_g::UnifyingAstVisitor2;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};

/// An object used to locate the [AstNode] associated with a source range.
/// More specifically, they will return the deepest [AstNode] which
/// completely encompasses the specified range with some exceptions:
///
/// - Offsets that fall between the name and type/formal parameter list of
///   a declaration will return the declaration node and not the parameter
///   list node.
pub struct NodeLocator2 {
    /// The inclusive start offset of the range used to identify the node.
    start_offset: i32,

    /// The inclusive end offset of the range used to identify the node.
    end_offset: i32,

    /// The found node or `NO_NODE` if there is no such node.
    found_node: NodeId,
}

impl NodeLocator2 {
    /// Initialize a newly created locator to locate the deepest [AstNode]
    /// for which `node.offset <= [startOffset]` and `[endOffset] < node.end`.
    ///
    /// If [endOffset] is not provided, then it is considered the same as the
    /// given [startOffset].
    pub fn new(start_offset: i32, end_offset: Option<i32>) -> NodeLocator2 {
        NodeLocator2 {
            start_offset,
            end_offset: end_offset.unwrap_or(start_offset),
            found_node: NO_NODE,
        }
    }

    /// Search within the given AST [node] and return the node that was
    /// found, or `NO_NODE` if no node was found.
    pub fn search_within(&mut self, ast: Ast<'_>, node: NodeId) -> NodeId {
        if node == NO_NODE {
            return NO_NODE;
        }
        ast.accept2(node, self);
        self.found_node
    }

    /// Whether the offset is a single one, at [end]: names do not have
    /// AstNodes but offsets at the end should be treated as part of the
    /// declaration (not parameter list).
    fn at_name_end(&self, ast: Ast<'_>, name: fe_analyzer_shared::scanner::token::TokenId) -> bool {
        self.start_offset == self.end_offset && self.start_offset == ast.tokens.end(name)
    }

    fn visit_method_declaration(
        &mut self,
        ast: Ast<'_>,
        node: NodeId,
        visit_super: fn(&mut Self, Ast<'_>, NodeId) -> Option<()>,
    ) -> Option<()> {
        // Names do not have AstNodes but offsets at the end should be
        // treated as part of the declaration (not parameter list).
        let name_token = match ast.node(node) {
            AstNodeImpl::GetterDeclarationImpl(n) => n.name,
            AstNodeImpl::MethodDeclaration2Impl(n) => n.name,
            AstNodeImpl::OperatorDeclarationImpl(n) => n.operator_,
            AstNodeImpl::SetterDeclarationImpl(n) => n.name,
            other => panic!("{} has no nameToken", other.runtime_type()),
        };
        if self.at_name_end(ast, name_token) {
            self.found_node = node;
            return None;
        }
        visit_super(self, ast, node)
    }
}

use crate::dart::ast::visitor_g::unifying_ast_visitor2 as super_;

impl UnifyingAstVisitor2 for NodeLocator2 {
    fn visit_class_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let name_part = ast.node(node).as_class_declaration2_impl().name_part;
        let type_name = match ast.node(name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(n) => n.type_name,
            AstNodeImpl::PrimaryConstructorDeclarationImpl(n) => n.type_name,
            other => panic!("{} is not a ClassNamePart", other.runtime_type()),
        };
        if self.at_name_end(ast, type_name) {
            self.found_node = node;
            return None;
        }
        super_::visit_class_declaration2(self, ast, node)
    }

    fn visit_constructor_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        if self.start_offset == self.end_offset {
            let n = ast.node(node).as_constructor_declaration2_impl();
            let token = if n.name != fe_analyzer_shared::scanner::token::NO_TOKEN {
                n.name
            } else {
                n.type_name
            };
            if token != fe_analyzer_shared::scanner::token::NO_TOKEN
                && self.start_offset == ast.tokens.end(token)
            {
                self.found_node = node;
                return None;
            }
        }
        super_::visit_constructor_declaration2(self, ast, node)
    }

    fn visit_getter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration(ast, node, super_::visit_getter_declaration)
    }

    fn visit_local_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        if self.at_name_end(ast, ast.node(node).as_local_function_declaration_impl().name) {
            self.found_node = node;
            return None;
        }
        super_::visit_local_function_declaration(self, ast, node)
    }

    fn visit_method_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration(ast, node, super_::visit_method_declaration2)
    }

    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // Don't visit a new tree if the result has been already found.
        if self.found_node != NO_NODE {
            return None;
        }
        // Check whether the current node covers the selection.
        let begin_token = ast.begin_token(node);
        let mut end_token = ast.end_token(node);
        // Don't include synthetic tokens.
        while end_token != begin_token {
            // Fasta scanner reports unterminated string literal errors
            // and generates a synthetic string token with non-zero length.
            // Because of this, check for length > 0 rather than !isSynthetic.
            if ast.tokens.is_eof(end_token) || ast.tokens.length(end_token) > 0 {
                break;
            }
            end_token = ast.tokens.previous(end_token);
        }
        let end = ast.tokens.end(end_token);
        let start = ast.offset(node);
        if end <= self.start_offset || start > self.end_offset {
            return None;
        }
        // Check children.
        ast.visit_children2(node, self);
        // Found a child.
        if self.found_node != NO_NODE {
            return None;
        }
        // Check this node.
        if start <= self.start_offset && self.end_offset < end {
            self.found_node = node;
        }
        None
    }

    fn visit_operator_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration(ast, node, super_::visit_operator_declaration)
    }

    fn visit_setter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration(ast, node, super_::visit_setter_declaration)
    }

    fn visit_top_level_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        if self.at_name_end(ast, ast.node(node).as_top_level_function_declaration_impl().name) {
            self.found_node = node;
            return None;
        }
        super_::visit_top_level_function_declaration(self, ast, node)
    }

    fn visit_top_level_getter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        if self.at_name_end(ast, ast.node(node).as_top_level_getter_declaration_impl().name) {
            self.found_node = node;
            return None;
        }
        super_::visit_top_level_getter_declaration(self, ast, node)
    }

    fn visit_top_level_setter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        if self.at_name_end(ast, ast.node(node).as_top_level_setter_declaration_impl().name) {
            self.found_node = node;
            return None;
        }
        super_::visit_top_level_setter_declaration(self, ast, node)
    }
}

unifying_ast_visitor2!(NodeLocator2, ());
