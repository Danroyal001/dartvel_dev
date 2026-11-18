// Port of lib/src/dart/ast/to_source_visitor.dart.
//
// The sink is a buffer of UTF-16 code units, as a Dart `StringSink` holds a
// string. A visit method for a class that parsing never builds (a node
// that resolution creates upstream) has nothing to visit here, since no
// such node can be in the store.
//
// Upstream's visit methods ignore the node or the sink where they have
// nothing to read.
#![allow(unused_variables)]

use crate::src::dart::ast::ast::{AstNodeImpl, IncrementOrDecrementPosition};
use crate::src::dart::ast::ast_g::AstVisitor2;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId};

/// A visitor used to write a source representation of a visited AST node
/// (and all of it's children) to a sink.
pub struct ToSourceVisitor<'s> {
    /// The sink to which the source is to be written.
    pub sink: &'s mut Vec<u16>,
}

impl<'s> ToSourceVisitor<'s> {
    /// Initialize a newly created visitor to write source code representing
    /// the visited nodes to the given [sink].
    pub fn new(sink: &'s mut Vec<u16>) -> ToSourceVisitor<'s> {
        ToSourceVisitor { sink }
    }

    /// `sink.write(string)`.
    fn write(&mut self, string: &str) {
        self.sink.extend(string.encode_utf16());
    }

    /// `sink.write(token.lexeme)`.
    fn write_lexeme(&mut self, ast: Ast<'_>, token: TokenId) {
        ast.tokens.write_lexeme(token, self.sink);
    }

    /// Visit the prefix shared by all formal parameter kinds.
    fn visit_formal_parameter_header(&mut self, ast: Ast<'_>, node: NodeId) {
        let (metadata, required_keyword, covariant_keyword, const_final_or_var_keyword, type_, name, function_typed_suffix) =
            match ast.node(node) {
                AstNodeImpl::RegularFormalParameterImpl(n) => (
                    &n.metadata,
                    n.required_keyword,
                    n.covariant_keyword,
                    n.const_final_or_var_keyword,
                    n.type_,
                    n.name,
                    n.function_typed_suffix,
                ),
                AstNodeImpl::FieldFormalParameterImpl(n) => (
                    &n.metadata,
                    n.required_keyword,
                    n.covariant_keyword,
                    n.const_final_or_var_keyword,
                    n.type_,
                    n.name,
                    n.function_typed_suffix,
                ),
                AstNodeImpl::SuperFormalParameterImpl(n) => (
                    &n.metadata,
                    n.required_keyword,
                    n.covariant_keyword,
                    n.const_final_or_var_keyword,
                    n.type_,
                    n.name,
                    n.function_typed_suffix,
                ),
                other => panic!("{} is not a FormalParameter", other.runtime_type()),
            };
        self.visit_node_list(ast, metadata, "", " ", " ");
        self.visit_token(ast, required_keyword, "", " ");
        self.visit_token(ast, covariant_keyword, "", " ");
        self.visit_token(ast, const_final_or_var_keyword, "", " ");
        self.visit_node(ast, type_, "", "");
        if type_ != NO_NODE && (name != NO_TOKEN || function_typed_suffix != NO_NODE) {
            self.write(" ");
        }
    }

    /// Visit the given function [body], printing a prefix before if the body
    /// is not empty.
    fn visit_function_body(&mut self, ast: Ast<'_>, body: NodeId) {
        if !matches!(ast.node(body), AstNodeImpl::EmptyFunctionBodyImpl(_)) {
            self.write(" ");
        }
        self.visit_node(ast, body, "", "");
    }

    /// Print the given [node], printing the [prefix] before the node,
    /// and [suffix] after the node, if it is non-`null`.
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId, prefix: &str, suffix: &str) {
        if node != NO_NODE {
            self.write(prefix);
            ast.accept2(node, self);
            self.write(suffix);
        }
    }

    /// Print a list of [nodes], separated by the given [separator]; if the
    /// list is not empty print [prefix] before the first node, and [suffix]
    /// after the last node.
    fn visit_node_list(
        &mut self,
        ast: Ast<'_>,
        nodes: &[NodeId],
        prefix: &str,
        separator: &str,
        suffix: &str,
    ) {
        let length = nodes.len();
        if length > 0 {
            self.write(prefix);
            for i in 0..length {
                if i > 0 {
                    self.write(separator);
                }
                ast.accept2(nodes[i], self);
            }
            self.write(suffix);
        }
    }

    fn visit_parsed_expression(&mut self, ast: Ast<'_>, root: NodeId) {
        let mut node = root;
        while ast.node(node).is_parsed_expression_impl()
            && !matches!(
                ast.node(node),
                AstNodeImpl::ParsedCascadeNameImpl(_)
                    | AstNodeImpl::ParsedUnqualifiedNameImpl(_)
                    | AstNodeImpl::ParsedDotShorthandNameImpl(_)
            )
        {
            node = match ast.node(node) {
                AstNodeImpl::ParsedNameAccessImpl(n) => n.operand,
                AstNodeImpl::ParsedTypeArgumentsImpl(n) => n.operand,
                AstNodeImpl::ParsedValueArgumentsImpl(n) => n.operand,
                other => panic!("Unexpected parsed expression: {}", other.runtime_type()),
            };
        }
        self.visit_node(ast, node, "", "");
        while node != root {
            node = ast.parent2(node);
            match ast.node(node) {
                AstNodeImpl::ParsedNameAccessImpl(n) => {
                    self.visit_token(ast, n.operator_, "", "");
                    self.visit_token(ast, n.name, "", "");
                }
                AstNodeImpl::ParsedTypeArgumentsImpl(n) => {
                    self.visit_node(ast, n.type_arguments, "", "");
                }
                AstNodeImpl::ParsedValueArgumentsImpl(n) => {
                    self.visit_node(ast, n.argument_list, "", "");
                }
                AstNodeImpl::ParsedCascadeNameImpl(_)
                | AstNodeImpl::ParsedUnqualifiedNameImpl(_)
                | AstNodeImpl::ParsedDotShorthandNameImpl(_) => {
                    panic!("A parsed name cannot contain an operand.");
                }
                other => panic!("{} is not a ParsedExpression", other.runtime_type()),
            }
        }
    }

    /// Print the given [token].
    fn visit_token(&mut self, ast: Ast<'_>, token: TokenId, prefix: &str, suffix: &str) {
        if token != NO_TOKEN {
            self.write(prefix);
            self.write_lexeme(ast, token);
            self.write(suffix);
        }
    }

    fn write_operand(&mut self, ast: Ast<'_>, node: NodeId, operand: NodeId) {
        let needs_parenthesis = ast.node(operand).is_expression_impl()
            && ast.precedence(operand) < ast.precedence(node);
        if needs_parenthesis {
            self.write("(");
        }
        ast.accept2(operand, self);
        if needs_parenthesis {
            self.write(")");
        }
    }
}

impl AstVisitor2 for ToSourceVisitor<'_> {
    type R = ();

    fn visit_adjacent_strings(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_adjacent_strings_impl();
        self.visit_node_list(ast, &n.strings, "", " ", "");
        None
    }

    fn visit_annotation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_annotation_impl();
        self.write("@");
        self.visit_node(ast, n.expression, "", "");
        None
    }

    fn visit_anonymous_block_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_anonymous_block_body_impl();
        self.visit_node(ast, n.block, "", "");
        None
    }

    fn visit_anonymous_expression_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_anonymous_expression_body_impl();
        self.write_lexeme(ast, n.function_definition);
        self.write(" ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_anonymous_method_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_anonymous_method_invocation_impl();
        self.visit_node(ast, n.target2, "", "");
        self.visit_token(ast, n.operator_, "", "");
        self.visit_node(ast, n.parameters, "", "");
        if n.parameters != NO_NODE {
            self.write(" ");
        }
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_argument_list(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_argument_list_impl();
        self.write("(");
        self.visit_node_list(ast, &n.arguments2, "", ", ", "");
        self.write(")");
        None
    }

    fn visit_as_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_as_expression_impl();
        self.visit_node(ast, n.expression2, "", "");
        self.write(" as ");
        self.visit_node(ast, n.type_, "", "");
        None
    }

    fn visit_assert_initializer(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_assert_initializer_impl();
        self.write("assert (");
        self.visit_node(ast, n.condition2, "", "");
        if n.message2 != NO_NODE {
            self.write(", ");
            self.visit_node(ast, n.message2, "", "");
        }
        self.write(")");
        None
    }

    fn visit_assert_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_assert_statement_impl();
        self.write("assert (");
        self.visit_node(ast, n.condition2, "", "");
        if n.message2 != NO_NODE {
            self.write(", ");
            self.visit_node(ast, n.message2, "", "");
        }
        self.write(");");
        None
    }

    fn visit_assigned_variable_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_assigned_variable_pattern_impl();
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_await_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_await_expression_impl();
        self.write("await ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_binary_operator_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_binary_operator_invocation_impl();
        self.write_operand(ast, node, n.left_operand);
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.write_operand(ast, node, n.right_operand);
        None
    }

    fn visit_block(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_block_impl();
        self.write("{");
        self.visit_node_list(ast, &n.statements2, "", " ", "");
        self.write("}");
        None
    }

    fn visit_block_enum_declaration_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_block_enum_declaration_body_impl();
        self.write(" {");
        self.visit_node_list(ast, &n.constants, "", ", ", "");
        self.visit_token(ast, n.members_separator, "", "");
        self.visit_node_list(ast, &n.members, " ", " ", "");
        self.write("}");
        None
    }

    fn visit_block_function_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_block_function_body_impl();
        let keyword = n.keyword;
        if keyword != NO_TOKEN {
            self.write_lexeme(ast, keyword);
            if n.star != NO_TOKEN {
                self.write("*");
            }
            self.write(" ");
        }
        self.visit_node(ast, n.block, "", "");
        None
    }

    fn visit_block_instance_declaration_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_block_instance_declaration_body_impl();
        self.write(" {");
        self.visit_node_list(ast, &n.members, "", " ", "");
        self.write("}");
        None
    }

    fn visit_boolean_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_boolean_literal_impl();
        self.write_lexeme(ast, n.literal);
        None
    }

    fn visit_break_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_break_statement_impl();
        self.write("break");
        self.visit_node(ast, n.label, " ", "");
        self.write(";");
        None
    }

    fn visit_call_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_call_invocation_impl();
        self.visit_node(ast, n.receiver, "", "");
        self.visit_node(ast, n.type_arguments, "", "");
        self.visit_node(ast, n.argument_list, "", "");
        None
    }

    fn visit_cascade_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cascade_expression_impl();
        self.visit_node(ast, n.target2, "", "");
        self.visit_node_list(ast, &n.sections, "", "", "");
        None
    }

    fn visit_cascade_index_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cascade_index_assignment_target_impl();
        self.visit_token(ast, n.left_bracket, "", "");
        self.visit_node(ast, n.index, "", "");
        self.visit_token(ast, n.right_bracket, "", "");
        None
    }

    fn visit_cascade_index_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cascade_index_expression_impl();
        self.visit_token(ast, n.left_bracket, "", "");
        self.visit_node(ast, n.index, "", "");
        self.visit_token(ast, n.right_bracket, "", "");
        None
    }

    fn visit_cascade_method_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No CascadeMethodInvocationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_cascade_property_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cascade_property_assignment_target_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_cascade_property_extraction(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cascade_property_extraction_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_cascade_section(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cascade_section_impl();
        if ast.begin_token(n.body) != n.operator_ {
            self.visit_token(ast, n.operator_, "", "");
        }
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_case_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_case_clause_impl();
        self.write("case ");
        self.visit_node(ast, n.guarded_pattern, "", "");
        None
    }

    fn visit_cast_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_cast_pattern_impl();
        self.visit_node(ast, n.pattern, "", "");
        self.write(" as ");
        self.visit_node(ast, n.type_, "", "");
        None
    }

    fn visit_catch_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_catch_clause_impl();
        self.visit_node(ast, n.exception_type, "on ", "");
        if n.catch_keyword != NO_TOKEN {
            if n.exception_type != NO_NODE {
                self.write(" ");
            }
            self.write("catch (");
            self.visit_node(ast, n.exception_parameter, "", "");
            self.visit_node(ast, n.stack_trace_parameter, ", ", "");
            self.write(") ");
        } else {
            self.write(" ");
        }
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_catch_clause_parameter(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_catch_clause_parameter_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_class_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_class_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.abstract_keyword, "", " ");
        self.visit_token(ast, n.sealed_keyword, "", " ");
        self.visit_token(ast, n.base_keyword, "", " ");
        self.visit_token(ast, n.interface_keyword, "", " ");
        self.visit_token(ast, n.final_keyword, "", " ");
        self.visit_token(ast, n.mixin_keyword, "", " ");
        self.write("class ");
        self.visit_node(ast, n.name_part, "", "");
        self.visit_node(ast, n.extends_clause, " ", "");
        self.visit_node(ast, n.with_clause, " ", "");
        self.visit_node(ast, n.implements_clause, " ", "");
        self.visit_node(ast, n.native_clause, " ", "");
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_class_type_alias2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_class_type_alias2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.abstract_keyword, "", " ");
        self.visit_token(ast, n.sealed_keyword, "", " ");
        self.visit_token(ast, n.base_keyword, "", " ");
        self.visit_token(ast, n.interface_keyword, "", " ");
        self.visit_token(ast, n.final_keyword, "", " ");
        self.visit_token(ast, n.mixin_keyword, "", " ");
        self.write("class ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.write(" = ");
        self.visit_node(ast, n.superclass, "", "");
        self.visit_node(ast, n.with_clause, " ", "");
        self.visit_node(ast, n.implements_clause, " ", "");
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_combinator_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_combinator_name_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_comment(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        None
    }

    fn visit_comment_reference(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_comment_reference_impl();
        for &component in &n.components {
            ast.accept2(component, self);
        }
        None
    }

    fn visit_comment_reference_component(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_comment_reference_component_impl();
        self.visit_token(ast, n.period, "", "");
        self.visit_token(ast, n.operator_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_compilation_unit(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_compilation_unit_impl();
        let script_tag = n.script_tag;
        let directives = &n.directives;
        self.visit_node(ast, script_tag, "", "");
        let mut prefix = if script_tag == NO_NODE { "" } else { " " };
        self.visit_node_list(ast, directives, prefix, " ", "");
        prefix = if script_tag == NO_NODE && directives.is_empty() { "" } else { " " };
        self.visit_node_list(ast, &n.declarations2, prefix, " ", "");
        None
    }

    fn visit_compound_assignment(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_compound_assignment_impl();
        self.visit_node(ast, n.target, "", "");
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.visit_node(ast, n.value, "", "");
        None
    }

    fn visit_conditional_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_conditional_expression_impl();
        self.visit_node(ast, n.condition2, "", "");
        self.write(" ? ");
        self.visit_node(ast, n.then_expression2, "", "");
        self.write(" : ");
        self.visit_node(ast, n.else_expression2, "", "");
        None
    }

    fn visit_configuration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_configuration_impl();
        self.write("if (");
        self.visit_node(ast, n.name, "", "");
        self.visit_node(ast, n.value, " == ", "");
        self.write(") ");
        self.visit_node(ast, n.uri, "", "");
        None
    }

    fn visit_constant_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constant_pattern_impl();
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_constructor_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constructor_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_token(ast, n.factory_keyword, "", " ");
        self.visit_token(ast, n.new_keyword, "", " ");
        if n.type_name != NO_TOKEN {
            self.visit_token(ast, n.type_name, "", "");
            self.visit_token(ast, n.name, ".", "");
        } else {
            self.visit_token(ast, n.name, "", "");
        }
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_node_list(ast, &n.initializers, " : ", ", ", "");
        self.visit_node(ast, n.factory_redirection_target, " = ", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_constructor_field_initializer(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constructor_field_initializer_impl();
        self.visit_token(ast, n.this_keyword, "", ".");
        self.visit_token(ast, n.field_name2, "", "");
        self.write(" = ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_constructor_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constructor_invocation_impl();
        self.visit_token(ast, n.keyword, "", " ");
        self.visit_node(ast, n.constructor_reference, "", "");
        self.visit_node(ast, n.argument_list, "", "");
        None
    }

    fn visit_constructor_reference2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constructor_reference2_impl();
        self.visit_node(ast, n.type_reference, "", "");
        self.visit_node(ast, n.selector, "", "");
        None
    }

    fn visit_constructor_selector(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constructor_selector_impl();
        self.visit_token(ast, n.period, "", "");
        self.visit_token(ast, n.name2, "", "");
        None
    }

    fn visit_constructor_tear_off(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ConstructorTearOffImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_constructor_type_reference(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_constructor_type_reference_impl();
        self.visit_node(ast, n.import_prefix, "", "");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_arguments, "", "");
        None
    }

    fn visit_continue_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_continue_statement_impl();
        self.write("continue");
        self.visit_node(ast, n.label, " ", "");
        self.write(";");
        None
    }

    fn visit_declared_identifier(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_declared_identifier_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.keyword, "", " ");
        self.visit_node(ast, n.type_, "", " ");
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_declared_variable_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_declared_variable_pattern_impl();
        self.visit_token(ast, n.keyword, "", " ");
        self.visit_node(ast, n.type_, "", " ");
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_delimited_formal_parameters(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_delimited_formal_parameters_impl();
        self.write_lexeme(ast, n.left_delimiter);
        self.visit_node_list(ast, &n.formal_parameters, "", ", ", "");
        self.write_lexeme(ast, n.right_delimiter);
        None
    }

    fn visit_direct_assignment(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_direct_assignment_impl();
        self.visit_node(ast, n.target, "", "");
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.visit_node(ast, n.value, "", "");
        None
    }

    fn visit_do_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_do_statement_impl();
        self.write("do ");
        self.visit_node(ast, n.body2, "", "");
        self.write(" while (");
        self.visit_node(ast, n.condition2, "", "");
        self.write(");");
        None
    }

    fn visit_dot_shorthand_constructor_invocation2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_dot_shorthand_constructor_invocation2_impl();
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_token(ast, n.period, "", "");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_arguments, "", "");
        self.visit_node(ast, n.argument_list, "", "");
        None
    }

    fn visit_dot_shorthand_method_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No DotShorthandMethodInvocationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_dot_shorthand_name_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_dot_shorthand_name_expression_impl();
        self.visit_token(ast, n.period, "", "");
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_dotted_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_dotted_name_impl();
        for &token in &n.tokens {
            self.write_lexeme(ast, token);
        }
        None
    }

    fn visit_double_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_double_literal_impl();
        self.write_lexeme(ast, n.literal);
        None
    }

    fn visit_empty_function_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write(";");
        None
    }

    fn visit_empty_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write(";");
        None
    }

    fn visit_enum_constant_arguments(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_enum_constant_arguments_impl();
        self.visit_node(ast, n.type_arguments, "", "");
        self.visit_node(ast, n.constructor_selector, "", "");
        self.visit_node(ast, n.argument_list, "", "");
        None
    }

    fn visit_enum_constant_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_enum_constant_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.arguments, "", "");
        None
    }

    fn visit_enum_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_enum_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.write("enum ");
        self.visit_node(ast, n.name_part, "", "");
        self.visit_node(ast, n.with_clause, " ", "");
        self.visit_node(ast, n.implements_clause, " ", "");
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_export_directive(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_export_directive_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.write("export ");
        self.visit_node(ast, n.uri, "", "");
        self.visit_node_list(ast, &n.configurations, " ", " ", "");
        self.visit_node_list(ast, &n.combinators, " ", " ", "");
        self.write(";");
        None
    }

    fn visit_expression_function_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_expression_function_body_impl();
        let keyword = n.keyword;
        if keyword != NO_TOKEN {
            self.write_lexeme(ast, keyword);
            if n.star != NO_TOKEN {
                self.write("*");
            }
            self.write(" ");
        }
        self.write_lexeme(ast, n.function_definition);
        self.write(" ");
        self.visit_node(ast, n.expression2, "", "");
        if n.semicolon != NO_TOKEN {
            self.write(";");
        }
        None
    }

    fn visit_expression_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_expression_statement_impl();
        self.visit_node(ast, n.expression2, "", "");
        self.write(";");
        None
    }

    fn visit_extends_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_extends_clause_impl();
        self.write("extends ");
        self.visit_node(ast, n.superclass, "", "");
        None
    }

    fn visit_extension_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_extension_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.extension_keyword, "", " ");
        self.visit_token(ast, n.type_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.on_clause, " ", "");
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_extension_on_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_extension_on_clause_impl();
        self.write("on ");
        self.visit_node(ast, n.extended_type, "", "");
        None
    }

    fn visit_extension_override2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ExtensionOverride2Impl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_extension_type_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_extension_type_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.extension_keyword, "", " ");
        self.visit_token(ast, n.type_keyword, "", " ");
        self.visit_node(ast, n.name_part, "", "");
        self.visit_node(ast, n.implements_clause, " ", "");
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_field2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_field2_impl();
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.initializer, " = ", "");
        None
    }

    fn visit_field_formal_parameter(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_field_formal_parameter_impl();
        self.visit_formal_parameter_header(ast, node);
        self.write("this.");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.function_typed_suffix, "", "");
        self.visit_node(ast, n.default_clause, "", "");
        None
    }

    fn visit_fields_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_fields_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_token(ast, n.static_keyword, "", " ");
        self.visit_token(ast, n.abstract_keyword, "", " ");
        self.visit_token(ast, n.covariant_keyword, "", " ");
        self.visit_token(ast, n.late_keyword, "", " ");
        self.visit_token(ast, n.const_final_or_var_keyword, "", " ");
        self.visit_node(ast, n.type_, "", " ");
        self.visit_node_list(ast, &n.fields, "", ", ", "");
        self.write(";");
        None
    }

    fn visit_for_each_parts_with_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_each_parts_with_declaration_impl();
        self.visit_node(ast, n.loop_variable, "", "");
        self.write(" in ");
        self.visit_node(ast, n.iterable2, "", "");
        None
    }

    fn visit_for_each_parts_with_identifier(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_each_parts_with_identifier_impl();
        self.visit_node(ast, n.target, "", "");
        self.write(" in ");
        self.visit_node(ast, n.iterable2, "", "");
        None
    }

    fn visit_for_each_parts_with_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_each_parts_with_pattern_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.keyword, "", " ");
        self.visit_node(ast, n.pattern, "", "");
        self.write(" in ");
        self.visit_node(ast, n.iterable2, "", "");
        None
    }

    fn visit_for_element(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_element_impl();
        self.visit_token(ast, n.await_keyword, "", " ");
        self.write("for (");
        self.visit_node(ast, n.for_loop_parts, "", "");
        self.write(") ");
        self.visit_node(ast, n.body2, "", "");
        None
    }

    fn visit_formal_parameter_default_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_formal_parameter_default_clause_impl();
        if ast.tokens.lexeme(n.separator) != [b':' as u16] {
            self.write(" ");
        }
        self.write_lexeme(ast, n.separator);
        self.visit_node(ast, n.value2, " ", "");
        None
    }

    fn visit_formal_parameter_list(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_formal_parameter_list_impl();
        self.write("(");
        self.visit_node_list(ast, &n.required_positional_formal_parameters, "", ", ", "");
        if n.delimited_formal_parameters != NO_NODE {
            if !n.required_positional_formal_parameters.is_empty() {
                self.write(", ");
            }
            ast.accept2(n.delimited_formal_parameters, self);
        }
        self.write(")");
        None
    }

    fn visit_for_parts_with_declarations(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_parts_with_declarations_impl();
        self.visit_node(ast, n.variables2, "", "");
        self.write(";");
        self.visit_node(ast, n.condition2, " ", "");
        self.write(";");
        self.visit_node_list(ast, &n.updaters2, " ", ", ", "");
        None
    }

    fn visit_for_parts_with_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_parts_with_expression_impl();
        self.visit_node(ast, n.initialization2, "", "");
        self.write(";");
        self.visit_node(ast, n.condition2, " ", "");
        self.write(";");
        self.visit_node_list(ast, &n.updaters2, " ", ", ", "");
        None
    }

    fn visit_for_parts_with_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_parts_with_pattern_impl();
        self.visit_node(ast, n.variables, "", "");
        self.write("; ");
        self.visit_node(ast, n.condition2, "", "");
        self.write("; ");
        self.visit_node_list(ast, &n.updaters2, "", ", ", "");
        None
    }

    fn visit_for_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_for_statement_impl();
        if n.await_keyword != NO_TOKEN {
            self.write("await ");
        }
        self.write("for (");
        self.visit_node(ast, n.for_loop_parts, "", "");
        self.write(") ");
        self.visit_node(ast, n.body2, "", "");
        None
    }

    fn visit_function_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_function_expression_impl();
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_function_instantiation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No FunctionInstantiationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_function_type_alias2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_function_type_alias2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.write("typedef ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.parameters, "", "");
        self.write(";");
        None
    }

    fn visit_function_typed_formal_parameter_suffix(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_function_typed_formal_parameter_suffix_impl();
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        if n.question != NO_TOKEN {
            self.write("?");
        }
        None
    }

    fn visit_generic_function_type(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_generic_function_type_impl();
        self.visit_node(ast, n.return_type, "", "");
        self.write(" Function");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.parameters, "", "");
        if n.question != NO_TOKEN {
            self.write("?");
        }
        None
    }

    fn visit_generic_type_alias2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_generic_type_alias2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.write("typedef ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.write(" = ");
        self.visit_node(ast, n.type_, "", "");
        self.write(";");
        None
    }

    fn visit_getter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_getter_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_token(ast, n.static_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.get_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_guarded_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_guarded_pattern_impl();
        self.visit_node(ast, n.pattern, "", "");
        self.visit_node(ast, n.when_clause, " ", "");
        None
    }

    fn visit_hide_combinator(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_hide_combinator_impl();
        self.write("hide ");
        self.visit_node_list(ast, &n.names, "", ", ", "");
        None
    }

    fn visit_if_element(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_if_element_impl();
        self.write("if (");
        self.visit_node(ast, n.expression2, "", "");
        self.visit_node(ast, n.case_clause, " ", "");
        self.write(") ");
        self.visit_node(ast, n.then_element2, "", "");
        self.visit_node(ast, n.else_element2, " else ", "");
        None
    }

    fn visit_if_null(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_if_null_impl();
        self.write_operand(ast, node, n.left_operand);
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.write_operand(ast, node, n.right_operand);
        None
    }

    fn visit_if_null_assignment(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_if_null_assignment_impl();
        self.visit_node(ast, n.target, "", "");
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.visit_node(ast, n.value, "", "");
        None
    }

    fn visit_if_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_if_statement_impl();
        self.write("if (");
        self.visit_node(ast, n.expression2, "", "");
        self.visit_node(ast, n.case_clause, " ", "");
        self.write(") ");
        self.visit_node(ast, n.then_statement2, "", "");
        self.visit_node(ast, n.else_statement2, " else ", "");
        None
    }

    fn visit_implements_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_implements_clause_impl();
        self.write("implements ");
        self.visit_node_list(ast, &n.interfaces, "", ", ", "");
        None
    }

    fn visit_implicit_call_tear_off(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ImplicitCallTearOffImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_implicit_function_instantiation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ImplicitFunctionInstantiationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_import_directive(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_import_directive_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.write("import ");
        self.visit_node(ast, n.uri, "", "");
        self.visit_node_list(ast, &n.configurations, " ", " ", "");
        if n.deferred_keyword != NO_TOKEN {
            self.write(" deferred");
        }
        self.visit_token(ast, n.prefix_name, " as ", "");
        self.visit_node_list(ast, &n.combinators, " ", " ", "");
        self.write(";");
        None
    }

    fn visit_import_prefixed_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ImportPrefixedAssignmentTargetImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_import_prefixed_function_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ImportPrefixedFunctionInvocationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_import_prefixed_name_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ImportPrefixedNameExpressionImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_import_prefix_reference(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_import_prefix_reference_impl();
        self.write_lexeme(ast, n.name);
        self.write(".");
        None
    }

    fn visit_increment_or_decrement_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_increment_or_decrement_expression_impl();
        match n.position {
            IncrementOrDecrementPosition::prefix => {
                self.write_lexeme(ast, n.operator_);
                self.visit_node(ast, n.target, "", "");
            }
            IncrementOrDecrementPosition::postfix => {
                self.visit_node(ast, n.target, "", "");
                self.write_lexeme(ast, n.operator_);
            }
        }
        None
    }

    fn visit_integer_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_integer_literal_impl();
        self.write_lexeme(ast, n.literal);
        None
    }

    fn visit_interpolation_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_interpolation_expression_impl();
        if n.right_bracket != NO_TOKEN {
            self.write("${");
            self.visit_node(ast, n.expression2, "", "");
            self.write("}");
        } else {
            self.write("$");
            self.visit_node(ast, n.expression2, "", "");
        }
        None
    }

    fn visit_interpolation_string(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_interpolation_string_impl();
        self.write_lexeme(ast, n.contents);
        None
    }

    fn visit_invalid_expression_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_invalid_expression_assignment_target_impl();
        self.visit_node(ast, n.expression, "", "");
        None
    }

    fn visit_invalid_extension_override_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No InvalidExtensionOverrideAssignmentTargetImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_invalid_extension_override_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No InvalidExtensionOverrideExpressionImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_invalid_super_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_invalid_super_assignment_target_impl();
        ast.accept2(n.super_reference, self);
        None
    }

    fn visit_invalid_super_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_invalid_super_expression_impl();
        ast.accept2(n.super_reference, self);
        None
    }

    fn visit_is_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_is_expression_impl();
        self.visit_node(ast, n.expression2, "", "");
        if n.not_operator == NO_TOKEN {
            self.write(" is ");
        } else {
            self.write(" is! ");
        }
        self.visit_node(ast, n.type_, "", "");
        None
    }

    fn visit_label(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_label_impl();
        self.visit_token(ast, n.name, "", "");
        self.write(":");
        None
    }

    fn visit_labeled_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_labeled_statement_impl();
        self.visit_node_list(ast, &n.labels, "", " ", " ");
        self.visit_node(ast, n.statement2, "", "");
        None
    }

    fn visit_label_reference(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_label_reference_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_library_directive(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_library_directive_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.write("library ");
        self.visit_node(ast, n.name, "", "");
        self.write(";");
        None
    }

    fn visit_list_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_list_literal_impl();
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_node(ast, n.type_arguments, "", "");
        self.write("[");
        self.visit_node_list(ast, &n.elements2, "", ", ", "");
        self.write("]");
        None
    }

    fn visit_list_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_list_pattern_impl();
        self.visit_node(ast, n.type_arguments, "", "");
        self.write("[");
        self.visit_node_list(ast, &n.elements, "", ", ", "");
        self.write("]");
        None
    }

    fn visit_local_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_local_function_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_local_variable(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_local_variable_impl();
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.initializer, " = ", "");
        None
    }

    fn visit_local_variables_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_local_variables_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.late_keyword, "", " ");
        self.visit_token(ast, n.const_final_or_var_keyword, "", " ");
        self.visit_node(ast, n.type_, "", " ");
        self.visit_node_list(ast, &n.variables, "", ", ", "");
        None
    }

    fn visit_local_variables_declaration_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_local_variables_declaration_statement_impl();
        self.visit_node(ast, n.declaration, "", "");
        self.write(";");
        None
    }

    fn visit_logical_and(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_logical_and_impl();
        self.write_operand(ast, node, n.left_operand);
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.write_operand(ast, node, n.right_operand);
        None
    }

    fn visit_logical_and_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_logical_and_pattern_impl();
        self.visit_node(ast, n.left_operand, "", "");
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.visit_node(ast, n.right_operand, "", "");
        None
    }

    fn visit_logical_not(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_logical_not_impl();
        self.write_lexeme(ast, n.operator_);
        self.write_operand(ast, node, n.operand);
        None
    }

    fn visit_logical_or(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_logical_or_impl();
        self.write_operand(ast, node, n.left_operand);
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.write_operand(ast, node, n.right_operand);
        None
    }

    fn visit_logical_or_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_logical_or_pattern_impl();
        self.visit_node(ast, n.left_operand, "", "");
        self.write(" ");
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.visit_node(ast, n.right_operand, "", "");
        None
    }

    fn visit_map_literal_entry(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_map_literal_entry_impl();
        self.visit_token(ast, n.key_question, "", "");
        self.visit_node(ast, n.key2, "", "");
        self.write(" : ");
        self.visit_token(ast, n.value_question, "", "");
        self.visit_node(ast, n.value2, "", "");
        None
    }

    fn visit_map_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_map_pattern_impl();
        self.visit_node(ast, n.type_arguments, "", "");
        self.write("{");
        self.visit_node_list(ast, &n.elements, "", ", ", "");
        self.write("}");
        None
    }

    fn visit_map_pattern_entry(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_map_pattern_entry_impl();
        self.visit_node(ast, n.key2, "", "");
        self.write(": ");
        self.visit_node(ast, n.value, "", "");
        None
    }

    fn visit_method_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_method_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_token(ast, n.static_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_mixin_declaration2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_mixin_declaration2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.base_keyword, "", " ");
        self.write("mixin ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.on_clause, " ", "");
        self.visit_node(ast, n.implements_clause, " ", "");
        self.visit_node(ast, n.body, "", "");
        None
    }

    fn visit_mixin_on_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_mixin_on_clause_impl();
        self.write("on ");
        self.visit_node_list(ast, &n.superclass_constraints, "", ", ", "");
        None
    }

    fn visit_named_argument(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_named_argument_impl();
        self.visit_token(ast, n.name, "", "");
        self.visit_token(ast, n.colon, "", "");
        self.visit_node(ast, n.argument_expression2, " ", "");
        None
    }

    fn visit_named_type(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_named_type_impl();
        self.visit_node(ast, n.import_prefix, "", "");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_arguments, "", "");
        if n.question != NO_TOKEN {
            self.write("?");
        }
        None
    }

    fn visit_name_with_type_parameters(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_name_with_type_parameters_impl();
        self.visit_token(ast, n.type_name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        None
    }

    fn visit_native_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_native_clause_impl();
        self.write("native ");
        self.visit_node(ast, n.name, "", "");
        None
    }

    fn visit_native_function_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_native_function_body_impl();
        self.write("native ");
        self.visit_node(ast, n.string_literal, "", "");
        self.write(";");
        None
    }

    fn visit_null_assertion_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_null_assertion_expression_impl();
        self.write_operand(ast, node, n.operand);
        self.write_lexeme(ast, n.operator_);
        None
    }

    fn visit_null_assert_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_null_assert_pattern_impl();
        self.visit_node(ast, n.pattern, "", "");
        self.write_lexeme(ast, n.operator_);
        None
    }

    fn visit_null_aware_element(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_null_aware_element_impl();
        self.write_lexeme(ast, n.question);
        self.visit_node(ast, n.value2, "", "");
        None
    }

    fn visit_null_check_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_null_check_pattern_impl();
        self.visit_node(ast, n.pattern, "", "");
        self.write_lexeme(ast, n.operator_);
        None
    }

    fn visit_null_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write("null");
        None
    }

    fn visit_object_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_object_pattern_impl();
        self.visit_node(ast, n.type_, "", "");
        self.write("(");
        self.visit_node_list(ast, &n.fields, "", ", ", "");
        self.write(")");
        None
    }

    fn visit_operator_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_operator_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.operator_keyword, "", " ");
        self.visit_token(ast, n.operator_, "", "");
        self.visit_node(ast, n.recovery_type_parameters, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_parenthesized_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parenthesized_expression_impl();
        self.write("(");
        self.visit_node(ast, n.expression2, "", "");
        self.write(")");
        None
    }

    fn visit_parenthesized_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parenthesized_pattern_impl();
        self.write("(");
        self.visit_node(ast, n.pattern, "", "");
        self.write(")");
        None
    }

    fn visit_parsed_cascade_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parsed_cascade_name_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_parsed_dot_shorthand_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parsed_dot_shorthand_expression_impl();
        ast.accept2(n.expression, self);
        None
    }

    fn visit_parsed_dot_shorthand_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parsed_dot_shorthand_name_impl();
        self.visit_token(ast, n.period, "", "");
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_parsed_name_access(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_parsed_expression(ast, node);
        None
    }

    fn visit_parsed_name_access_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parsed_name_access_assignment_target_impl();
        self.visit_node(ast, n.operand, "", "");
        self.visit_token(ast, n.operator_, "", "");
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_parsed_type_arguments(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_parsed_expression(ast, node);
        None
    }

    fn visit_parsed_unqualified_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_parsed_unqualified_name_impl();
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_parsed_value_arguments(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.visit_parsed_expression(ast, node);
        None
    }

    fn visit_part_directive(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_part_directive_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.write("part ");
        self.visit_node(ast, n.uri, "", "");
        self.write(";");
        None
    }

    fn visit_part_of_directive(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_part_of_directive_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.write("part of ");
        self.visit_node(ast, n.library_name, "", "");
        self.visit_node(ast, n.uri, "", "");
        self.write(";");
        None
    }

    fn visit_pattern_assignment(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_pattern_assignment_impl();
        self.visit_node(ast, n.pattern, "", "");
        self.write(" = ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_pattern_field(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_pattern_field_impl();
        self.visit_node(ast, n.name, "", " ");
        self.visit_node(ast, n.pattern, "", "");
        None
    }

    fn visit_pattern_field_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_pattern_field_name_impl();
        self.visit_token(ast, n.name, "", "");
        self.write(":");
        None
    }

    fn visit_pattern_variable_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_pattern_variable_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.write_lexeme(ast, n.keyword);
        self.write(" ");
        self.visit_node(ast, n.pattern, "", "");
        self.write(" = ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_pattern_variable_declaration_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_pattern_variable_declaration_statement_impl();
        self.visit_node(ast, n.declaration, "", "");
        self.write(";");
        None
    }

    fn visit_primary_constructor_body2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_primary_constructor_body2_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.this_keyword, "", "");
        if !n.initializers.is_empty() {
            self.visit_token(ast, n.colon, " ", " ");
            self.visit_node_list(ast, &n.initializers, "", ", ", "");
        }
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_primary_constructor_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_primary_constructor_declaration_impl();
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_token(ast, n.type_name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.constructor_name, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        None
    }

    fn visit_primary_constructor_name(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_primary_constructor_name_impl();
        self.visit_token(ast, n.period, "", "");
        self.visit_token(ast, n.name, "", "");
        None
    }

    fn visit_receiver_index_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_receiver_index_assignment_target_impl();
        self.visit_node(ast, n.receiver, "", "");
        self.visit_token(ast, n.question, "", "");
        self.visit_token(ast, n.left_bracket, "", "");
        self.visit_node(ast, n.index, "", "");
        self.visit_token(ast, n.right_bracket, "", "");
        None
    }

    fn visit_receiver_index_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_receiver_index_expression_impl();
        self.visit_node(ast, n.receiver, "", "");
        self.visit_token(ast, n.question, "", "");
        self.visit_token(ast, n.left_bracket, "", "");
        self.visit_node(ast, n.index, "", "");
        self.visit_token(ast, n.right_bracket, "", "");
        None
    }

    fn visit_receiver_method_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No ReceiverMethodInvocationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_receiver_property_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_receiver_property_assignment_target_impl();
        self.visit_node(ast, n.receiver, "", "");
        self.write_lexeme(ast, n.operator_);
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_receiver_property_extraction(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_receiver_property_extraction_impl();
        self.visit_node(ast, n.receiver, "", "");
        self.write_lexeme(ast, n.operator_);
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_record_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_literal_impl();
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_token(ast, n.left_parenthesis, "", "");
        self.visit_node_list(ast, &n.fields2, "", ", ", "");
        self.visit_token(ast, n.right_parenthesis, "", "");
        None
    }

    fn visit_record_literal_named_field(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_literal_named_field_impl();
        self.visit_token(ast, n.name, "", "");
        self.visit_token(ast, n.colon, "", "");
        self.visit_node(ast, n.field_expression2, " ", "");
        None
    }

    fn visit_record_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_pattern_impl();
        let fields = &n.fields;
        self.write("(");
        self.visit_node_list(ast, fields, "", ", ", "");
        if fields.len() == 1 {
            self.write(",");
        }
        self.write(")");
        None
    }

    fn visit_record_type_annotation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_type_annotation_impl();
        let positional_fields = &n.positional_fields;
        let named_fields = n.named_fields;
        self.write("(");
        if !positional_fields.is_empty() {
            self.visit_node_list(ast, positional_fields, "", ", ", "");
            if named_fields != NO_NODE {
                self.write(", ");
            }
        }
        self.visit_node(ast, named_fields, "", "");
        self.write(")");
        if n.question != NO_TOKEN {
            self.write("?");
        }
        None
    }

    fn visit_record_type_annotation_named_field(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_type_annotation_named_field_impl();
        self.visit_node(ast, n.type_, "", "");
        self.write(" ");
        // `sink.write(node.name)`: a token prints as its lexeme.
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_record_type_annotation_named_fields(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_type_annotation_named_fields_impl();
        self.write("{");
        self.visit_node_list(ast, &n.fields, "", ", ", "");
        self.write("}");
        None
    }

    fn visit_record_type_annotation_positional_field(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_record_type_annotation_positional_field_impl();
        self.visit_node(ast, n.type_, "", "");
        if n.name != NO_TOKEN {
            self.write(" ");
            self.write_lexeme(ast, n.name);
        }
        None
    }

    fn visit_redirecting_constructor_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_redirecting_constructor_invocation_impl();
        self.write("this");
        self.visit_node(ast, n.constructor_selector, "", "");
        self.visit_node(ast, n.argument_list, "", "");
        None
    }

    fn visit_regular_formal_parameter(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_regular_formal_parameter_impl();
        self.visit_formal_parameter_header(ast, node);
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.function_typed_suffix, "", "");
        self.visit_node(ast, n.default_clause, "", "");
        None
    }

    fn visit_relational_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_relational_pattern_impl();
        self.write_lexeme(ast, n.operator_);
        self.write(" ");
        self.visit_node(ast, n.operand2, "", "");
        None
    }

    fn visit_rest_pattern_element(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_rest_pattern_element_impl();
        self.write_lexeme(ast, n.operator_);
        self.visit_node(ast, n.pattern, "", "");
        None
    }

    fn visit_rethrow_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write("rethrow");
        None
    }

    fn visit_return_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_return_statement_impl();
        let expression = n.expression2;
        if expression == NO_NODE {
            self.write("return;");
        } else {
            self.write("return ");
            ast.accept2(expression, self);
            self.write(";");
        }
        None
    }

    fn visit_script_tag(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_script_tag_impl();
        self.write_lexeme(ast, n.script_tag);
        None
    }

    fn visit_semicolon_enum_declaration_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write(";");
        None
    }

    fn visit_semicolon_instance_declaration_body(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write(";");
        None
    }

    fn visit_set_or_map_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_set_or_map_literal_impl();
        self.visit_token(ast, n.const_keyword, "", " ");
        self.visit_node(ast, n.type_arguments, "", "");
        self.write("{");
        self.visit_node_list(ast, &n.elements2, "", ", ", "");
        self.write("}");
        None
    }

    fn visit_setter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_setter_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_token(ast, n.static_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.set_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_show_combinator(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_show_combinator_impl();
        self.write("show ");
        self.visit_node_list(ast, &n.names, "", ", ", "");
        None
    }

    fn visit_simple_string_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_simple_string_literal_impl();
        self.write_lexeme(ast, n.literal);
        None
    }

    fn visit_spread_element(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_spread_element_impl();
        self.write_lexeme(ast, n.spread_operator);
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_static_qualifier(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No StaticQualifierImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_string_interpolation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_string_interpolation_impl();
        self.visit_node_list(ast, &n.elements, "", "", "");
        None
    }

    fn visit_super_constructor_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_super_constructor_invocation_impl();
        self.write("super");
        self.visit_node(ast, n.constructor_selector, "", "");
        self.visit_node(ast, n.argument_list, "", "");
        None
    }

    fn visit_super_formal_parameter(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_super_formal_parameter_impl();
        self.visit_formal_parameter_header(ast, node);
        self.write("super.");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.function_typed_suffix, "", "");
        self.visit_node(ast, n.default_clause, "", "");
        None
    }

    fn visit_super_reference(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let _ = (ast, node);
        self.write("super");
        None
    }

    fn visit_switch_case(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_switch_case_impl();
        self.visit_node_list(ast, &n.labels, "", " ", " ");
        self.write("case ");
        self.visit_node(ast, n.expression2, "", "");
        self.write(": ");
        self.visit_node_list(ast, &n.statements2, "", " ", "");
        None
    }

    fn visit_switch_default(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_switch_default_impl();
        self.visit_node_list(ast, &n.labels, "", " ", " ");
        self.write("default: ");
        self.visit_node_list(ast, &n.statements2, "", " ", "");
        None
    }

    fn visit_switch_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_switch_expression_impl();
        self.write("switch (");
        self.visit_node(ast, n.expression2, "", "");
        self.write(") {");
        self.visit_node_list(ast, &n.cases, "", ", ", "");
        self.write("}");
        None
    }

    fn visit_switch_expression_case(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_switch_expression_case_impl();
        self.visit_node(ast, n.guarded_pattern, "", "");
        self.write(" => ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_switch_pattern_case(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_switch_pattern_case_impl();
        self.visit_node_list(ast, &n.labels, "", " ", " ");
        self.write("case ");
        self.visit_node(ast, n.guarded_pattern, "", "");
        self.write(": ");
        self.visit_node_list(ast, &n.statements2, "", " ", "");
        None
    }

    fn visit_switch_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_switch_statement_impl();
        self.write("switch (");
        self.visit_node(ast, n.expression2, "", "");
        self.write(") {");
        self.visit_node_list(ast, &n.members, "", " ", "");
        self.write("}");
        None
    }

    fn visit_symbol_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_symbol_literal_impl();
        self.write("#");
        let components = &n.components;
        for i in 0..components.len() {
            if i > 0 {
                self.write(".");
            }
            self.write_lexeme(ast, components[i]);
        }
        None
    }

    fn visit_this_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        self.write("this");
        None
    }

    fn visit_throw_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_throw_expression_impl();
        self.write("throw ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_top_level_function_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_top_level_function_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.type_parameters, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_top_level_getter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_top_level_getter_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.get_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_top_level_setter_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_top_level_setter_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_node(ast, n.return_type, "", " ");
        self.visit_token(ast, n.set_keyword, "", " ");
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.formal_parameters, "", "");
        self.visit_function_body(ast, n.body);
        None
    }

    fn visit_top_level_variable2(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_top_level_variable2_impl();
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.initializer, " = ", "");
        None
    }

    fn visit_top_level_variables_declaration(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_top_level_variables_declaration_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        self.visit_token(ast, n.augment_keyword, "", " ");
        self.visit_token(ast, n.external_keyword, "", " ");
        self.visit_token(ast, n.abstract_keyword, "", " ");
        self.visit_token(ast, n.late_keyword, "", " ");
        self.visit_token(ast, n.const_final_or_var_keyword, "", " ");
        self.visit_node(ast, n.type_, "", " ");
        self.visit_node_list(ast, &n.variables, "", ", ", "");
        self.write(";");
        None
    }

    fn visit_try_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_try_statement_impl();
        self.write("try ");
        self.visit_node(ast, n.body, "", "");
        self.visit_node_list(ast, &n.catch_clauses, " ", " ", "");
        self.visit_node(ast, n.finally_block, " finally ", "");
        None
    }

    fn visit_type_argument_list(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_type_argument_list_impl();
        self.write("<");
        self.visit_node_list(ast, &n.arguments, "", ", ", "");
        self.write(">");
        None
    }

    fn visit_type_literal(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No TypeLiteralImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_type_parameter(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_type_parameter_impl();
        self.visit_node_list(ast, &n.metadata, "", " ", " ");
        let variance_keyword = n.variance_keyword;
        if variance_keyword != NO_TOKEN {
            self.write_lexeme(ast, variance_keyword);
            self.write(" ");
        }
        self.visit_token(ast, n.name, "", "");
        self.visit_node(ast, n.bound, " extends ", "");
        None
    }

    fn visit_type_parameter_list(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_type_parameter_list_impl();
        self.write("<");
        self.visit_node_list(ast, &n.type_parameters, "", ", ", "");
        self.write(">");
        None
    }

    fn visit_unary_operator_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_unary_operator_invocation_impl();
        self.write_lexeme(ast, n.operator_);
        self.write_operand(ast, node, n.operand);
        None
    }

    fn visit_unqualified_function_invocation(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No UnqualifiedFunctionInvocationImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_unqualified_name_assignment_target(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_unqualified_name_assignment_target_impl();
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_unqualified_name_expression(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        // No UnqualifiedNameExpressionImpl is built by parsing.
        let _ = (ast, node);
        None
    }

    fn visit_when_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_when_clause_impl();
        self.write("when ");
        self.visit_node(ast, n.expression2, "", "");
        None
    }

    fn visit_while_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_while_statement_impl();
        self.write("while (");
        self.visit_node(ast, n.condition2, "", "");
        self.write(") ");
        self.visit_node(ast, n.body2, "", "");
        None
    }

    fn visit_wildcard_pattern(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_wildcard_pattern_impl();
        self.visit_token(ast, n.keyword, "", " ");
        self.visit_node(ast, n.type_, "", " ");
        self.write_lexeme(ast, n.name);
        None
    }

    fn visit_with_clause(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_with_clause_impl();
        self.write("with ");
        self.visit_node_list(ast, &n.mixin_types, "", ", ", "");
        None
    }

    fn visit_yield_statement(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let n = ast.node(node).as_yield_statement_impl();
        if n.star != NO_TOKEN {
            self.write("yield* ");
        } else {
            self.write("yield ");
        }
        self.visit_node(ast, n.expression2, "", "");
        self.write(";");
        None
    }

}
