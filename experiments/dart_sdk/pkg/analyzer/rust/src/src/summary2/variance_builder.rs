// Port of lib/src/summary2/variance_builder.dart: `VarianceBuilder`, which
// gives the type parameters of the typedefs being linked the variance of
// their occurrences in the aliased type (or the old-style typedef's return
// and parameter types), and the type parameters of classes, enums and mixins
// the variance their `in`, `out` or `inout` keyword states. It runs after the
// reference resolver, on the types it made (builders), before the default
// types are computed, which replace a contravariant occurrence by `Never`.

use std::collections::{HashMap, HashSet};

use crate::fe_analyzer_shared::types::shared_type::Variance;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentId, LibraryId, UnitId};
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::summary2::type_builder::TypeBuilder;

pub struct VarianceBuilder<'a> {
    pub store: &'a mut ElementStore,
    pub asts: &'a HashMap<UnitId, Ast<'a>>,
    /// `TypeAnnotation.type`, as the reference resolver set it.
    pub node_types: &'a HashMap<(UnitId, NodeId), TypeImpl>,
    pub fragment_of_node: &'a HashMap<(UnitId, NodeId), FragmentId>,
    pub linking_libraries: &'a HashSet<LibraryId>,
    /// `_pending`: the typedefs not computed yet.
    pub pending: HashSet<(UnitId, NodeId)>,
    /// `_visit`: the typedefs being computed.
    pub visit: HashSet<(UnitId, NodeId)>,
}

impl VarianceBuilder<'_> {
    /// `perform`, on the declarations of [units].
    pub fn perform(&mut self, units: &[(UnitId, NodeId)]) {
        for &(unit, unit_node) in units {
            for &node in self.declarations(unit, unit_node).iter() {
                if matches!(
                    self.asts[&unit].node(node),
                    AstNodeImpl::FunctionTypeAlias2Impl(_) | AstNodeImpl::GenericTypeAlias2Impl(_)
                ) {
                    self.pending.insert((unit, node));
                }
            }
        }
        for &(unit, unit_node) in units {
            for node in self.declarations(unit, unit_node) {
                let ast = self.asts[&unit];
                match ast.node(node) {
                    AstNodeImpl::ClassTypeAlias2Impl(d) => self.type_parameters(unit, d.type_parameters),
                    AstNodeImpl::ClassDeclaration2Impl(d) => {
                        self.type_parameters(unit, name_part_type_parameters(ast, d.name_part))
                    }
                    AstNodeImpl::EnumDeclaration2Impl(d) => {
                        self.type_parameters(unit, name_part_type_parameters(ast, d.name_part))
                    }
                    AstNodeImpl::FunctionTypeAlias2Impl(_) => self.function_type_alias(unit, node),
                    AstNodeImpl::GenericTypeAlias2Impl(_) => self.generic_type_alias(unit, node),
                    AstNodeImpl::MixinDeclaration2Impl(d) => self.type_parameters(unit, d.type_parameters),
                    _ => (),
                }
            }
        }
    }

    fn declarations(&self, unit: UnitId, unit_node: NodeId) -> Vec<NodeId> {
        self.asts[&unit].node(unit_node).as_compilation_unit_impl().declarations2.iter().copied().collect()
    }

    fn element_of(&self, unit: UnitId, node: NodeId) -> ElementId {
        self.store.fragment(self.fragment_of_node[&(unit, node)]).element
    }

    /// `_compute`: the variance of [variable] in [type_].
    fn compute(&mut self, variable: ElementId, type_: &TypeImpl) -> Variance {
        match type_ {
            TypeImpl::TypeParameter(t) => {
                if t.element == variable {
                    Variance::covariant
                } else {
                    Variance::unrelated
                }
            }
            TypeImpl::Builder(id) => match self.store.type_builders[*id as usize].clone() {
                TypeBuilder::Named(b) => {
                    if b.element == crate::src::dart::element::element::NO_ELEMENT {
                        return Variance::unrelated;
                    }
                    let kind = self.store.element(b.element).kind;
                    match kind {
                        ElementKind::CLASS | ElementKind::ENUM | ElementKind::MIXIN | ElementKind::EXTENSION_TYPE => {}
                        ElementKind::TYPE_ALIAS => self.type_alias_element(b.element),
                        _ => return Variance::unrelated,
                    }
                    let parameters = self.type_parameters_of(b.element);
                    let mut result = Variance::unrelated;
                    for (parameter, argument) in parameters.iter().zip(b.arguments.iter()) {
                        let variance = self.store.variance(*parameter);
                        result = result.meet(variance.combine(self.compute(variable, argument)));
                    }
                    result
                }
                TypeBuilder::Function(b) => {
                    let parameters: Vec<TypeImpl> = b.formal_parameters.iter().map(|p| p.type_.clone()).collect();
                    self.compute_function_type(variable, &b.return_type, &b.type_parameters, &parameters)
                }
                TypeBuilder::Record(b) => {
                    let mut result = Variance::unrelated;
                    for field in &b.field_types {
                        result = result.meet(self.compute(variable, field));
                    }
                    result
                }
            },
            _ => Variance::unrelated,
        }
    }

    /// `_computeFunctionType`.
    fn compute_function_type(
        &mut self,
        variable: ElementId,
        return_type: &TypeImpl,
        type_parameters: &[ElementId],
        formal_parameters: &[TypeImpl],
    ) -> Variance {
        let mut result = Variance::unrelated.meet(self.compute(variable, return_type));
        // If [variable] is referenced in a bound at all, it makes the
        // variance of [variable] in the entire type invariant.
        for &type_parameter in type_parameters {
            if let Some(bound) = self.store.element(type_parameter).type_.clone() {
                if self.compute(variable, &bound) != Variance::unrelated {
                    result = Variance::invariant;
                }
            }
        }
        for parameter in formal_parameters {
            result = result.meet(Variance::contravariant.combine(self.compute(variable, parameter)));
        }
        result
    }

    /// `FunctionTypeBuilder.getParameters(list)` as `_computeFunctionType`
    /// reads it: the type of each formal parameter of the list [list], where
    /// a function-typed suffix (which the reference resolver gave a builder
    /// no node names) is computed from its own parts.
    fn formal_list_variance(&mut self, variable: ElementId, unit: UnitId, list: NodeId) -> Variance {
        let ast = self.asts[&unit];
        let mut result = Variance::unrelated;
        if list == NO_NODE {
            return result;
        }
        let l = ast.node(list).as_formal_parameter_list_impl();
        let mut parameters: Vec<NodeId> = l.required_positional_formal_parameters.iter().copied().collect();
        if l.delimited_formal_parameters != NO_NODE {
            parameters.extend(
                ast.node(l.delimited_formal_parameters).as_delimited_formal_parameters_impl().formal_parameters.iter(),
            );
        }
        for parameter in parameters {
            let (type_, suffix) = match ast.node(parameter) {
                AstNodeImpl::RegularFormalParameterImpl(p) => (p.type_, p.function_typed_suffix),
                AstNodeImpl::FieldFormalParameterImpl(p) => (p.type_, p.function_typed_suffix),
                AstNodeImpl::SuperFormalParameterImpl(p) => (p.type_, p.function_typed_suffix),
                _ => (NO_NODE, NO_NODE),
            };
            let variance = if suffix != NO_NODE {
                let s = ast.node(suffix).as_function_typed_formal_parameter_suffix_impl();
                let (type_parameters, formal_parameters) = (s.type_parameters, s.formal_parameters);
                self.suffix_variance(variable, unit, type_, type_parameters, formal_parameters)
            } else {
                let t = self.node_type(unit, type_);
                self.compute(variable, &t)
            };
            result = result.meet(Variance::contravariant.combine(variance));
        }
        result
    }

    /// `_computeFunctionType` of the function type of a function-typed
    /// suffix (or an old-style typedef) from its nodes.
    fn suffix_variance(
        &mut self,
        variable: ElementId,
        unit: UnitId,
        return_type: NodeId,
        type_parameters: NodeId,
        formal_parameters: NodeId,
    ) -> Variance {
        let return_type = self.node_type(unit, return_type);
        let mut result = Variance::unrelated.meet(self.compute(variable, &return_type));
        if type_parameters != NO_NODE {
            let ast = self.asts[&unit];
            let nodes: Vec<NodeId> =
                ast.node(type_parameters).as_type_parameter_list_impl().type_parameters.iter().copied().collect();
            for node in nodes {
                let element = self.element_of(unit, node);
                if let Some(bound) = self.store.element(element).type_.clone() {
                    if self.compute(variable, &bound) != Variance::unrelated {
                        result = Variance::invariant;
                    }
                }
            }
        }
        result.meet(self.formal_list_variance(variable, unit, formal_parameters))
    }

    fn node_type(&self, unit: UnitId, node: NodeId) -> TypeImpl {
        if node == NO_NODE {
            return TypeImpl::Dynamic;
        }
        self.node_types.get(&(unit, node)).cloned().unwrap_or(TypeImpl::Dynamic)
    }

    fn type_parameter_nodes(&self, unit: UnitId, list: NodeId) -> Vec<NodeId> {
        if list == NO_NODE {
            return Vec::new();
        }
        self.asts[&unit].node(list).as_type_parameter_list_impl().type_parameters.iter().copied().collect()
    }

    /// `element.typeParameters`.
    fn type_parameters_of(&self, element: ElementId) -> Vec<ElementId> {
        let first = self.store.element(element).first_fragment;
        self.store.fragment(first).type_parameters.iter().map(|&f| self.store.fragment(f).element).collect()
    }

    /// `_functionTypeAlias`.
    fn function_type_alias(&mut self, unit: UnitId, node: NodeId) {
        let ast = self.asts[&unit];
        let d = ast.node(node).as_function_type_alias2_impl();
        let (type_parameters, return_type, parameters) = (d.type_parameters, d.return_type, d.parameters);
        if type_parameters == NO_NODE {
            return;
        }
        let nodes = self.type_parameter_nodes(unit, type_parameters);
        // Recursion detected, recover.
        if self.visit.contains(&(unit, node)) {
            for &p in &nodes {
                self.set_variance(unit, p, Variance::covariant);
            }
            return;
        }
        // Not being linked, or already linked.
        if !self.pending.remove(&(unit, node)) {
            return;
        }
        self.visit.insert((unit, node));
        for &p in &nodes {
            let variable = self.element_of(unit, p);
            let variance = self.suffix_variance(variable, unit, return_type, NO_NODE, parameters);
            self.set_variance(unit, p, variance);
        }
        self.visit.remove(&(unit, node));
    }

    /// `_genericTypeAlias`.
    fn generic_type_alias(&mut self, unit: UnitId, node: NodeId) {
        let ast = self.asts[&unit];
        let d = ast.node(node).as_generic_type_alias2_impl();
        let (type_parameters, aliased) = (d.type_parameters, d.type_);
        if type_parameters == NO_NODE {
            return;
        }
        let nodes = self.type_parameter_nodes(unit, type_parameters);
        // Recursion detected, recover.
        if self.visit.contains(&(unit, node)) {
            for &p in &nodes {
                self.set_variance(unit, p, Variance::covariant);
            }
            return;
        }
        // Not being linked, or already linked.
        if !self.pending.remove(&(unit, node)) {
            return;
        }
        let type_ = if aliased == NO_NODE { None } else { self.node_types.get(&(unit, aliased)).cloned() };
        // Not a function type, recover.
        if type_.is_none() {
            for &p in &nodes {
                self.set_variance(unit, p, Variance::covariant);
            }
        }
        self.visit.insert((unit, node));
        for &p in &nodes {
            let variable = self.element_of(unit, p);
            let variance = match &type_ {
                Some(t) => self.compute(variable, t),
                None => Variance::unrelated,
            };
            self.set_variance(unit, p, variance);
        }
        self.visit.remove(&(unit, node));
    }

    /// `_typeAliasElement`.
    fn type_alias_element(&mut self, element: ElementId) {
        if !self.linking_libraries.contains(&self.store.element(element).library) {
            return;
        }
        let first = self.store.element(element).first_fragment;
        let (unit, node) = (self.store.fragment(first).unit, self.store.fragment(first).node);
        let Some(ast) = self.asts.get(&unit) else {
            return;
        };
        match ast.node(node) {
            AstNodeImpl::GenericTypeAlias2Impl(_) => self.generic_type_alias(unit, node),
            AstNodeImpl::FunctionTypeAlias2Impl(_) => self.function_type_alias(unit, node),
            other => panic!("UnimplementedError: ({}) {node}", other.runtime_type()),
        }
    }

    /// `_typeParameters`: the variance a keyword states.
    fn type_parameters(&mut self, unit: UnitId, list: NodeId) {
        for p in self.type_parameter_nodes(unit, list) {
            let keyword = self.asts[&unit].node(p).as_type_parameter_impl().variance_keyword;
            if keyword != fe_analyzer_shared::scanner::token::NO_TOKEN {
                let variance = Variance::from_keyword_string(&self.asts[&unit].tokens.lexeme_string(keyword));
                self.set_variance(unit, p, variance);
            }
        }
    }

    /// `_setVariance`.
    fn set_variance(&mut self, unit: UnitId, node: NodeId, variance: Variance) {
        let element = self.element_of(unit, node);
        self.store.types_mut(element).variance = Some(variance);
    }
}

fn name_part_type_parameters(ast: Ast<'_>, name_part: NodeId) -> NodeId {
    match ast.node(name_part) {
        AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_parameters,
        AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_parameters,
        _ => NO_NODE,
    }
}
