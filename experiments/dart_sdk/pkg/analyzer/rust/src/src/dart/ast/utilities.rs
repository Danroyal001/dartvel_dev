// Port of lib/src/dart/ast/utilities.dart (`NodeLocator`, `NodeLocator2`).
//
// `ScopedNameFinder2` is ported; `ScopedNameFinder`, its V1 counterpart, is
// not. Where upstream catches an exception thrown while visiting and
// logs it, the port catches the panic and logs nothing; `NodeLocator2` has
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

/// An object used to locate the [AstNode] associated with a source range,
/// given the AST structure built from the source. More specifically, they
/// will return the [AstNode] with the shortest length whose source range
/// completely encompasses the specified range, in the V1 view.
pub struct NodeLocator {
    /// The start offset of the range used to identify the node.
    start_offset: i32,

    /// The end offset of the range used to identify the node.
    end_offset: i32,

    /// The element that was found that corresponds to the given source
    /// range, or `NO_NODE` if there is no such element.
    found_node: NodeId,
}

impl NodeLocator {
    /// Initialize a newly created locator to locate an [AstNode] by locating
    /// the node within an AST structure that corresponds to the given range
    /// of characters (between the [startOffset] and [endOffset] in the
    /// source.
    pub fn new(start_offset: i32, end_offset: Option<i32>) -> NodeLocator {
        NodeLocator {
            start_offset,
            end_offset: end_offset.unwrap_or(start_offset),
            found_node: NO_NODE,
        }
    }

    /// Search within the given AST [node] for an identifier representing an
    /// element in the specified source range. Return the element that was
    /// found, or `NO_NODE` if no element was found.
    pub fn search_within(&mut self, ast: Ast<'_>, node: NodeId) -> NodeId {
        if node == NO_NODE {
            return NO_NODE;
        }
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            ast.accept(node, self);
        }));
        if outcome.is_err() {
            // Upstream logs the exception (a SilentException) and finds
            // nothing.
            return NO_NODE;
        }
        self.found_node
    }

    fn at_end(&self, end: i32) -> bool {
        self.start_offset == self.end_offset && self.start_offset == end
    }
}

use crate::dart::ast::visitor_g::UnifyingAstVisitor;
use crate::dart::ast::visitor_g::unifying_ast_visitor as super1;

impl UnifyingAstVisitor for NodeLocator {
    fn visit_class_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // Names do not have AstNodes but offsets at the end should be
        // treated as part of the declaration (not parameter list).
        let n = ast.node(node).as_class_declaration_impl();
        let name_part = n.name_part(ast, node);
        let type_name = match ast.node(name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(n) => n.type_name,
            AstNodeImpl::PrimaryConstructorDeclarationImpl(n) => n.type_name,
            other => panic!("{} is not a ClassNamePart", other.runtime_type()),
        };
        if self.at_end(ast.tokens.end(type_name)) {
            self.found_node = node;
            return None;
        }
        super1::visit_class_declaration(self, ast, node)
    }

    fn visit_constructor_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // Names do not have AstNodes but offsets at the end should be
        // treated as part of the declaration (not parameter list).
        if self.start_offset == self.end_offset {
            let n = ast.node(node).as_constructor_declaration_impl();
            let type_name2 = ast
                .node(n.v1_projection_origin)
                .as_constructor_declaration2_impl()
                .type_name;
            let token = if n.name != fe_analyzer_shared::scanner::token::NO_TOKEN {
                n.name
            } else {
                type_name2
            };
            if token != fe_analyzer_shared::scanner::token::NO_TOKEN
                && self.start_offset == ast.tokens.end(token)
            {
                self.found_node = node;
                return None;
            }
        }
        super1::visit_constructor_declaration(self, ast, node)
    }

    fn visit_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let name = ast.node(node).as_function_declaration_impl().name;
        if self.at_end(ast.tokens.end(name)) {
            self.found_node = node;
            return None;
        }
        super1::visit_function_declaration(self, ast, node)
    }

    fn visit_method_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let name = ast.node(node).as_method_declaration_impl().name;
        if self.at_end(ast.tokens.end(name)) {
            self.found_node = node;
            return None;
        }
        super1::visit_method_declaration(self, ast, node)
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
        // Check children; ignore an exception and proceed in order to visit
        // the rest of the structure.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            ast.visit_children(node, self);
        }));
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
}

unifying_ast_visitor!(NodeLocator, ());

/// Traverses the AST from the node up to the root, collecting the names of
/// the local variables and parameters in scope at [position], and the
/// declaration that contains it. Start it with
/// `ast.accept2(node, &mut finder)` on the node covering the position.
pub struct ScopedNameFinder2 {
    /// `_declarationNode`.
    declaration_node: NodeId,

    /// `immediateChild`: the node the search came from.
    pub immediate_child: NodeId,

    /// `_locals`, in the order they were added (a Dart `Set` is ordered).
    locals: Vec<Vec<u16>>,

    /// `_referenceIsWithinLocalFunction`.
    reference_is_within_local_function: bool,

    /// The offset of the reference.
    pub position: i32,
}

impl ScopedNameFinder2 {
    pub fn new(position: i32) -> ScopedNameFinder2 {
        ScopedNameFinder2 {
            declaration_node: NO_NODE,
            immediate_child: NO_NODE,
            locals: Vec::new(),
            reference_is_within_local_function: false,
            position,
        }
    }

    /// `declaration`.
    pub fn declaration(&self) -> NodeId {
        self.declaration_node
    }

    /// `locals`.
    pub fn locals(&self) -> Vec<String> {
        self.locals.iter().map(|l| String::from_utf16_lossy(l)).collect()
    }

    /// `_addParameters(formalParameterList.allFormalParameters)`.
    fn add_parameters(&mut self, ast: Ast<'_>, formal_parameter_list: NodeId) {
        for parameter in ast.store.all_formal_parameters(formal_parameter_list) {
            let name = match ast.node(parameter) {
                AstNodeImpl::RegularFormalParameterImpl(p) => p.name,
                AstNodeImpl::FieldFormalParameterImpl(p) => p.name,
                AstNodeImpl::SuperFormalParameterImpl(p) => p.name,
                other => panic!("{} is not a formal parameter", other.runtime_type()),
            };
            self.add_to_scope(ast, name);
        }
    }

    /// `_addStatementNames(statement)`.
    fn add_statement_names(&mut self, ast: Ast<'_>, statement: NodeId) {
        match ast.node(statement) {
            AstNodeImpl::LocalVariablesDeclarationStatementImpl(s) => {
                let declaration = ast.node(s.declaration).as_local_variables_declaration_impl();
                for &variable in &declaration.variables {
                    self.add_to_scope(ast, ast.node(variable).as_local_variable_impl().name);
                }
            }
            AstNodeImpl::LocalFunctionDeclarationImpl(f) if !self.reference_is_within_local_function => {
                self.add_to_scope(ast, f.name);
            }
            _ => {}
        }
    }

    /// `_addToScope(identifier)`.
    fn add_to_scope(&mut self, ast: Ast<'_>, identifier: fe_analyzer_shared::scanner::token::TokenId) {
        if identifier != fe_analyzer_shared::scanner::token::NO_TOKEN && self.is_in_range(ast, identifier) {
            let lexeme = ast.tokens.lexeme(identifier);
            if !self.locals.contains(&lexeme) {
                self.locals.push(lexeme);
            }
        }
    }

    /// `_checkStatements(statements)`.
    fn check_statements(&mut self, ast: Ast<'_>, statements: &[NodeId]) {
        for &statement in statements {
            if statement == self.immediate_child {
                return;
            }
            self.add_statement_names(ast, statement);
        }
    }

    /// `_isInRange(token)`.
    fn is_in_range(&self, ast: Ast<'_>, token: fe_analyzer_shared::scanner::token::TokenId) -> bool {
        if self.position < 0 {
            // if source position is not set then all nodes are in range
            return true;
        }
        ast.tokens.end(token) < self.position
    }

    /// `_visitMethodDeclaration(node)`.
    fn visit_method_declaration_origin(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.declaration_node = node;
        let parameters = ast.method_origin_parts(node).written_formal_parameters;
        if parameters != NO_NODE && self.immediate_child != parameters {
            self.add_parameters(ast, parameters);
        }
        None
    }

    /// `_declarationNode = node` and the parameters of a top-level
    /// function, getter or setter.
    fn visit_top_level_executable(&mut self, ast: Ast<'_>, node: NodeId, parameters: NodeId) -> Option<()> {
        self.declaration_node = node;
        if parameters != NO_NODE && self.immediate_child != parameters {
            self.add_parameters(ast, parameters);
        }
        None
    }
}

impl UnifyingAstVisitor2 for ScopedNameFinder2 {
    fn visit_block(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let statements = ast.node(node).as_block_impl().statements2.clone();
        self.check_statements(ast, &statements);
        UnifyingAstVisitor2::visit_node(self, ast, node)
    }

    fn visit_catch_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_catch_clause_impl();
        for parameter in [n.exception_parameter, n.stack_trace_parameter] {
            if parameter != NO_NODE {
                self.add_to_scope(ast, ast.node(parameter).as_catch_clause_parameter_impl().name);
            }
        }
        UnifyingAstVisitor2::visit_node(self, ast, node)
    }

    fn visit_class_type_alias2(&mut self, _ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.declaration_node = node;
        None
    }

    fn visit_constructor_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let parameters = ast.node(node).as_constructor_declaration2_impl().formal_parameters;
        if self.immediate_child != parameters {
            self.add_parameters(ast, parameters);
        }
        self.declaration_node = node;
        None
    }

    fn visit_fields_declaration(&mut self, _ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.declaration_node = node;
        None
    }

    fn visit_for_each_parts_with_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let loop_variable = ast.node(node).as_for_each_parts_with_declaration_impl().loop_variable;
        self.add_to_scope(ast, ast.node(loop_variable).as_declared_identifier_impl().name);
        UnifyingAstVisitor2::visit_node(self, ast, node)
    }

    fn visit_for_parts_with_declarations(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let variables2 = ast.node(node).as_for_parts_with_declarations_impl().variables2;
        for &variable in &ast.node(variables2).as_local_variables_declaration_impl().variables {
            self.add_to_scope(ast, ast.node(variable).as_local_variable_impl().name);
        }
        UnifyingAstVisitor2::visit_node(self, ast, node)
    }

    fn visit_function_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let parameters = ast.node(node).as_function_expression_impl().parameters;
        if parameters != NO_NODE && self.immediate_child != parameters {
            self.add_parameters(ast, parameters);
        }
        UnifyingAstVisitor2::visit_node(self, ast, node)
    }

    fn visit_function_type_alias2(&mut self, _ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.declaration_node = node;
        None
    }

    fn visit_generic_type_alias2(&mut self, _ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.declaration_node = node;
        None
    }

    fn visit_getter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration_origin(ast, node)
    }

    fn visit_local_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let parameters = ast.node(node).as_local_function_declaration_impl().formal_parameters;
        if self.immediate_child != parameters {
            self.add_parameters(ast, parameters);
        }
        self.reference_is_within_local_function = true;
        UnifyingAstVisitor2::visit_node(self, ast, node)
    }

    fn visit_method_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration_origin(ast, node)
    }

    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let statements = match ast.node(node) {
            AstNodeImpl::SwitchCaseImpl(n) => Some(n.statements2.clone()),
            AstNodeImpl::SwitchDefaultImpl(n) => Some(n.statements2.clone()),
            AstNodeImpl::SwitchPatternCaseImpl(n) => Some(n.statements2.clone()),
            _ => None,
        };
        if let Some(statements) = statements {
            self.check_statements(ast, &statements);
        }
        self.immediate_child = node;
        let parent = ast.parent2(node);
        if parent != NO_NODE {
            ast.accept2(parent, self);
        }
        None
    }

    fn visit_operator_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration_origin(ast, node)
    }

    fn visit_setter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_method_declaration_origin(ast, node)
    }

    fn visit_top_level_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let parameters = ast.node(node).as_top_level_function_declaration_impl().formal_parameters;
        self.visit_top_level_executable(ast, node, parameters)
    }

    fn visit_top_level_getter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let parameters = ast.node(node).as_top_level_getter_declaration_impl().recovery_formal_parameters;
        self.visit_top_level_executable(ast, node, parameters)
    }

    fn visit_top_level_setter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let parameters = ast.node(node).as_top_level_setter_declaration_impl().formal_parameters;
        self.visit_top_level_executable(ast, node, parameters)
    }

    fn visit_top_level_variables_declaration(&mut self, _ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.declaration_node = node;
        None
    }
}

unifying_ast_visitor2!(ScopedNameFinder2, ());
