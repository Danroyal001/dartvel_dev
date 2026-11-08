// Port of lib/src/dart/resolver/type_analyzer.dart (with the parts of
// binary_expression_resolver.dart and logical_not_resolver.dart that record a
// type): static types for the expressions whose type no other resolution
// decides. The seven context-independent literals (BooleanLiteral,
// DoubleLiteral, NullLiteral, SimpleStringLiteral, AdjacentStrings,
// StringInterpolation, SymbolLiteral); the operator-typed expressions
// IsExpression, LogicalNot, LogicalAnd and LogicalOr (`bool`) and
// ThrowExpression and RethrowExpression (`Never`); and ParenthesizedExpression,
// which takes the type of the expression it encloses when that is known.
// Flow state, diagnostics, rewrites, contextual integer typing, identifiers,
// invocations and all other expression visitors remain unported. Types are
// stored beside the AST by NodeId, as linking's annotation types are, rather
// than changing parsed nodes.
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NodeId};
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::type_provider::TypeProviderImpl;
use std::collections::HashMap;

pub fn is_context_independent_literal(node: &AstNodeImpl) -> bool {
    matches!(
        node,
        AstNodeImpl::BooleanLiteralImpl(_)
            | AstNodeImpl::DoubleLiteralImpl(_)
            | AstNodeImpl::NullLiteralImpl(_)
            | AstNodeImpl::SimpleStringLiteralImpl(_)
            | AstNodeImpl::AdjacentStringsImpl(_)
            | AstNodeImpl::StringInterpolationImpl(_)
            | AstNodeImpl::SymbolLiteralImpl(_)
    )
}

pub struct TypeAnalyzer<'a> {
    pub type_provider: &'a TypeProviderImpl,
    pub static_types: HashMap<NodeId, TypeImpl>,
}

impl<'a> TypeAnalyzer<'a> {
    pub fn new(type_provider: &'a TypeProviderImpl) -> Self {
        Self {
            type_provider,
            static_types: HashMap::new(),
        }
    }

    /// Visits a parsed unit, children before their parent, and records the
    /// types of the expressions listed at the top of this file. This is not a
    /// substitute for full body resolution: every other expression is left
    /// without a type rather than given a guessed one.
    pub fn analyze(&mut self, ast: Ast<'_>, node: NodeId) {
        // visitConfiguration: upstream deliberately does not resolve children.
        if matches!(ast.node(node), AstNodeImpl::ConfigurationImpl(_)) {
            return;
        }
        for child in ast.named_child_entities2(node) {
            match child.value {
                ChildValue::Node(id) => self.analyze(ast, id),
                ChildValue::NodeList(ids) => {
                    for &id in ids {
                        self.analyze(ast, id);
                    }
                }
                _ => (),
            }
        }
        let provider = self.type_provider;
        let type_ = match ast.node(node) {
            // visitBooleanLiteral, visitDoubleLiteral, visitNullLiteral.
            AstNodeImpl::BooleanLiteralImpl(_) => provider.bool_type.clone(),
            AstNodeImpl::DoubleLiteralImpl(_) => provider.double_type.clone(),
            AstNodeImpl::NullLiteralImpl(_) => provider.null_type.clone(),
            // visitSimpleStringLiteral, visitAdjacentStrings,
            // visitStringInterpolation.
            AstNodeImpl::SimpleStringLiteralImpl(_)
            | AstNodeImpl::AdjacentStringsImpl(_)
            | AstNodeImpl::StringInterpolationImpl(_) => provider.string_type.clone(),
            // visitSymbolLiteral.
            AstNodeImpl::SymbolLiteralImpl(_) => provider.symbol_type.clone(),
            // visitIsExpression (`is` and `is!`), LogicalNotResolver, and
            // BinaryExpressionResolver._resolveLogicalExpression (`&&`, `||`):
            // `boolType`, whatever the operands resolve to.
            AstNodeImpl::IsExpressionImpl(_)
            | AstNodeImpl::LogicalNotImpl(_)
            | AstNodeImpl::LogicalAndImpl(_)
            | AstNodeImpl::LogicalOrImpl(_) => provider.bool_type.clone(),
            // visitThrowExpression, visitRethrowExpression: `bottomType`.
            AstNodeImpl::ThrowExpressionImpl(_) | AstNodeImpl::RethrowExpressionImpl(_) => {
                provider.bottom_type.clone()
            }
            // visitParenthesizedExpression: `node.expression2.typeOrThrow`.
            // Upstream always has that type; here it is known only when the
            // enclosed expression is one this file types.
            AstNodeImpl::ParenthesizedExpressionImpl(p) => {
                match self.static_types.get(&p.expression2) {
                    Some(type_) => type_.clone(),
                    None => return,
                }
            }
            _ => return,
        };
        self.static_types.insert(node, type_);
    }
}
