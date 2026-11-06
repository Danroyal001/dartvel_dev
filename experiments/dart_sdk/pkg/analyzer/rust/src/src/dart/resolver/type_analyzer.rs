// Port of lib/src/dart/resolver/type_analyzer.dart: static types for
// BooleanLiteral, DoubleLiteral, NullLiteral, SimpleStringLiteral,
// AdjacentStrings, StringInterpolation and SymbolLiteral only.
// Flow state, diagnostics, rewrites, contextual integer typing and all other
// expression visitors remain unported. Types are stored beside the AST by
// NodeId, as linking's annotation types are, rather than changing parsed nodes.
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NodeId};
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::type_provider::TypeProviderImpl;
use std::collections::HashMap;

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

    /// Visits a parsed unit; only the seven literal visitors record types.
    /// This is not a substitute for full body resolution.
    pub fn analyze_literals(&mut self, ast: Ast<'_>, node: NodeId) {
        for child in ast.named_child_entities2(node) {
            match child.value {
                ChildValue::Node(id) => self.analyze_literals(ast, id),
                ChildValue::NodeList(ids) => {
                    for &id in ids {
                        self.analyze_literals(ast, id);
                    }
                }
                _ => (),
            }
        }
        let type_ = match ast.node(node) {
            AstNodeImpl::BooleanLiteralImpl(_) => &self.type_provider.bool_type,
            AstNodeImpl::DoubleLiteralImpl(_) => &self.type_provider.double_type,
            AstNodeImpl::NullLiteralImpl(_) => &self.type_provider.null_type,
            AstNodeImpl::SimpleStringLiteralImpl(_)
            | AstNodeImpl::AdjacentStringsImpl(_)
            | AstNodeImpl::StringInterpolationImpl(_) => &self.type_provider.string_type,
            AstNodeImpl::SymbolLiteralImpl(_) => &self.type_provider.symbol_type,
            _ => return,
        };
        self.static_types.insert(node, type_.clone());
    }
}
