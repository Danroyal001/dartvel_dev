// Port of lib/src/summary2/default_types_builder.dart (`DefaultTypesBuilder`:
// the default type of every type parameter, which a raw type uses as its
// type argument), with the `_UpperLowerReplacementVisitor` it runs, built on
// the parts of lib/src/dart/element/replacement_visitor.dart that visitor
// reaches.
//
// Before the defaults are computed, cycles through bounds are broken by
// setting the type of a bound's node to `dynamic`, as upstream does: a type
// parameter whose bound leads back to itself through other type parameters'
// names, and raw types whose bounds lead back to the declaration.

use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::fe_analyzer_shared::types::shared_type::Variance;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementId, ElementKind, FragmentId, NO_ELEMENT, NO_FRAGMENT, UnitId};
use crate::src::dart::element::r#type::{FunctionTypeImpl, InterfaceTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_algebra::{substitute, Substitution};
use crate::src::summary2::type_builder::{BuildContext, FunctionTypeBuilder, NamedTypeBuilder, RecordTypeBuilder, TypeBuilder};
use crate::src::util::graph::compute_strong_components;

type ParameterNode = (UnitId, NodeId);

/// `DefaultTypesBuilder.build`.
pub fn build_default_types(ctx: &mut BuildContext<'_>, declarations: &[(UnitId, NodeId)]) {
    // `_computeDefaultTypes`.
    for &(unit, node) in declarations {
        let Some((fragment, list)) = fragment_type_parameters(ctx, unit, node) else {
            continue;
        };
        if list == NO_NODE || ctx.store.fragment(fragment).previous_fragment != NO_FRAGMENT {
            continue;
        }
        let element = ctx.store.fragment(fragment).element;
        break_self_cycles(ctx, unit, list);
        break_raw_type_cycles(ctx, element, unit, list);
        compute_default_type(ctx, unit, list);
    }
    // `_buildDefaultTypes`.
    for &(unit, node) in declarations {
        let Some((_, list)) = fragment_type_parameters(ctx, unit, node) else {
            continue;
        };
        if list == NO_NODE {
            continue;
        }
        for p in type_parameter_nodes(ctx, unit, list) {
            let element = element_of(ctx, unit, p);
            let default_type = ctx.store.types(element).and_then(|t| t.default_type.clone());
            if let Some(TypeImpl::Builder(id)) = default_type {
                let built = ctx.build(id);
                ctx.store.types_mut(element).default_type = Some(built);
            }
        }
    }
}

fn type_parameter_nodes(ctx: &BuildContext<'_>, unit: UnitId, list: NodeId) -> Vec<NodeId> {
    ctx.asts[&unit].node(list).as_type_parameter_list_impl().type_parameters.iter().copied().collect()
}

fn element_of(ctx: &BuildContext<'_>, unit: UnitId, node: NodeId) -> ElementId {
    let fragment = ctx.fragment_of_node[&(unit, node)];
    ctx.store.fragment(fragment).element
}

fn bound_node(ctx: &BuildContext<'_>, (unit, node): ParameterNode) -> NodeId {
    ctx.asts[&unit].node(node).as_type_parameter_impl().bound
}

fn node_type(ctx: &BuildContext<'_>, unit: UnitId, node: NodeId) -> TypeImpl {
    ctx.node_types[&(unit, node)].clone()
}

/// `_fragmentTypeParameters`: the fragment a declaration node declares and
/// its type parameter list.
fn fragment_type_parameters(ctx: &BuildContext<'_>, unit: UnitId, node: NodeId) -> Option<(FragmentId, NodeId)> {
    let ast = ctx.asts[&unit];
    let name_part_list = |name_part: NodeId| match ast.node(name_part) {
        AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_parameters,
        AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_parameters,
        _ => NO_NODE,
    };
    let list = match ast.node(node) {
        AstNodeImpl::ClassDeclaration2Impl(n) => name_part_list(n.name_part),
        AstNodeImpl::ClassTypeAlias2Impl(n) => n.type_parameters,
        AstNodeImpl::EnumDeclaration2Impl(n) => name_part_list(n.name_part),
        AstNodeImpl::ExtensionDeclaration2Impl(n) => n.type_parameters,
        AstNodeImpl::ExtensionTypeDeclaration2Impl(n) => name_part_list(n.name_part),
        AstNodeImpl::FunctionTypeAlias2Impl(n) => n.type_parameters,
        AstNodeImpl::GenericTypeAlias2Impl(n) => n.type_parameters,
        AstNodeImpl::MixinDeclaration2Impl(n) => n.type_parameters,
        // `MethodDeclarationV1OriginImpl.writtenTypeParameters`.
        AstNodeImpl::MethodDeclaration2Impl(n) => n.type_parameters,
        AstNodeImpl::GetterDeclarationImpl(_) | AstNodeImpl::SetterDeclarationImpl(_) => NO_NODE,
        AstNodeImpl::OperatorDeclarationImpl(n) => n.recovery_type_parameters,
        AstNodeImpl::TopLevelFunctionDeclarationImpl(n) => n.type_parameters,
        _ => return None,
    };
    let fragment = *ctx.fragment_of_node.get(&(unit, node))?;
    Some((fragment, list))
}

/// `_breakSelfCycles`.
fn break_self_cycles(ctx: &mut BuildContext<'_>, unit: UnitId, list: NodeId) {
    let ast = ctx.asts[&unit];
    let parameters = type_parameter_nodes(ctx, unit, list);
    let mut by_name: Option<HashMap<String, NodeId>> = None;
    for &parameter in &parameters {
        let bound = ast.node(parameter).as_type_parameter_impl().bound;
        if bound == NO_NODE || !matches!(ast.node(bound), AstNodeImpl::NamedTypeImpl(_)) {
            continue;
        }
        let by_name = by_name.get_or_insert_with(|| {
            let mut map = HashMap::new();
            for &p in &parameters {
                let name = ast.tokens.lexeme_string(ast.node(p).as_type_parameter_impl().name);
                map.insert(name, p);
            }
            map
        });
        let mut current = Some(parameter);
        let mut step = 0;
        while let Some(c) = current {
            if step >= parameters.len() {
                break;
            }
            let b = ast.node(c).as_type_parameter_impl().bound;
            if b != NO_NODE {
                if let AstNodeImpl::NamedTypeImpl(named) = ast.node(b) {
                    if named.import_prefix == NO_NODE {
                        current = by_name.get(&ast.tokens.lexeme_string(named.name)).copied();
                        step += 1;
                        continue;
                    }
                }
            }
            current = None;
            break;
        }
        if current.is_some() {
            ctx.node_types.insert((unit, bound), TypeImpl::Dynamic);
        }
    }
}

/// `_breakRawTypeCycles`.
fn break_raw_type_cycles(ctx: &mut BuildContext<'_>, declaration: ElementId, unit: UnitId, list: NodeId) {
    let mut all_cycles: Vec<Vec<ParameterNode>> = Vec::new();
    for parameter in type_parameter_nodes(ctx, unit, list) {
        let bound = bound_node(ctx, (unit, parameter));
        if bound == NO_NODE {
            continue;
        }
        let start_type = node_type(ctx, unit, bound);
        let mut visited = HashSet::new();
        all_cycles.extend(find_raw_type_paths_to_declaration(
            ctx,
            (unit, parameter),
            &start_type,
            declaration,
            &mut visited,
        ));
    }
    for cycle in all_cycles {
        for parameter in cycle {
            let bound = bound_node(ctx, parameter);
            match ctx.asts[&parameter.0].node(bound) {
                AstNodeImpl::GenericFunctionTypeImpl(_) | AstNodeImpl::NamedTypeImpl(_) => {
                    ctx.node_types.insert((parameter.0, bound), TypeImpl::Dynamic);
                }
                other => panic!("UnimplementedError: ({}) {bound}", other.runtime_type()),
            }
        }
    }
}

/// `_getTypeParameterNode`: the node of a type parameter of a library being
/// linked.
fn type_parameter_node(ctx: &BuildContext<'_>, element: ElementId) -> Option<ParameterNode> {
    let first = ctx.store.element(element).first_fragment;
    if first == NO_FRAGMENT {
        return None;
    }
    let f = ctx.store.fragment(first);
    if f.node == NO_NODE || !ctx.asts.contains_key(&f.unit) {
        return None;
    }
    match ctx.asts[&f.unit].node(f.node) {
        AstNodeImpl::TypeParameterImpl(_) => Some((f.unit, f.node)),
        _ => None,
    }
}

/// `_findRawTypePathsToDeclaration`.
fn find_raw_type_paths_to_declaration(
    ctx: &BuildContext<'_>,
    start_parameter: ParameterNode,
    start_type: &TypeImpl,
    end: ElementId,
    visited: &mut HashSet<ElementId>,
) -> Vec<Vec<ParameterNode>> {
    let mut paths = Vec::new();
    let TypeImpl::Builder(id) = start_type else {
        return paths;
    };
    match &ctx.store.type_builders[*id as usize] {
        TypeBuilder::Named(b) => {
            if b.arguments.is_empty() {
                if b.element == end {
                    paths.push(vec![start_parameter]);
                } else if b.element != NO_ELEMENT && visited.insert(b.element) {
                    let kind = ctx.store.element(b.element).kind;
                    if matches!(
                        kind,
                        ElementKind::CLASS
                            | ElementKind::ENUM
                            | ElementKind::MIXIN
                            | ElementKind::EXTENSION_TYPE
                            | ElementKind::TYPE_ALIAS
                    ) {
                        for parameter in ctx.type_parameters(b.element) {
                            let Some(parameter_node) = type_parameter_node(ctx, parameter) else {
                                continue;
                            };
                            let bound = bound_node(ctx, parameter_node);
                            if bound == NO_NODE {
                                continue;
                            }
                            let bound_type = node_type(ctx, parameter_node.0, bound);
                            for tail in find_raw_type_paths_to_declaration(ctx, parameter_node, &bound_type, end, visited) {
                                let mut path = vec![start_parameter];
                                path.extend(tail);
                                paths.push(path);
                            }
                        }
                    }
                    visited.remove(&b.element);
                }
            } else {
                for argument in &b.arguments {
                    paths.extend(find_raw_type_paths_to_declaration(ctx, start_parameter, argument, end, visited));
                }
            }
        }
        TypeBuilder::Function(b) => {
            paths.extend(find_raw_type_paths_to_declaration(ctx, start_parameter, &b.return_type, end, visited));
            for &p in &b.type_parameters {
                if let Some(bound) = &ctx.store.element(p).type_ {
                    paths.extend(find_raw_type_paths_to_declaration(ctx, start_parameter, bound, end, visited));
                }
            }
            for p in &b.formal_parameters {
                paths.extend(find_raw_type_paths_to_declaration(ctx, start_parameter, &p.type_, end, visited));
            }
        }
        TypeBuilder::Record(_) => {}
    }
    paths
}

/// `_computeDefaultType`.
fn compute_default_type(ctx: &mut BuildContext<'_>, unit: UnitId, list: NodeId) {
    let nodes = type_parameter_nodes(ctx, unit, list);
    let elements: Vec<ElementId> = nodes.iter().map(|&p| element_of(ctx, unit, p)).collect();
    let mut bounds: Vec<TypeImpl> = nodes
        .iter()
        .map(|&p| {
            let b = bound_node(ctx, (unit, p));
            if b == NO_NODE { TypeImpl::Dynamic } else { node_type(ctx, unit, b) }
        })
        .collect();

    // `_TypeParametersGraph`.
    let mut edges: Vec<Vec<usize>> = vec![Vec::new(); elements.len()];
    for (i, bound) in bounds.iter().enumerate() {
        collect_references_from(ctx, &elements, &mut edges, i, bound);
    }
    let components = compute_strong_components(elements.len(), &|i| edges[i].clone());
    for component in components {
        let mut upper = HashMap::new();
        let mut lower = HashMap::new();
        for &i in &component {
            upper.insert(elements[i], TypeImpl::Dynamic);
            lower.insert(elements[i], TypeImpl::Never(NullabilitySuffix::none));
        }
        for &i in &component {
            let variance = ctx.store.variance(elements[i]);
            bounds[i] = UpperLower { ctx, upper: &upper, lower: &lower, variance }.run(&bounds[i]);
        }
    }

    for i in 0..elements.len() {
        let mut upper = HashMap::new();
        let mut lower = HashMap::new();
        upper.insert(elements[i], bounds[i].clone());
        lower.insert(elements[i], TypeImpl::Never(NullabilitySuffix::none));
        for j in 0..elements.len() {
            let variance = ctx.store.variance(elements[j]);
            bounds[j] = UpperLower { ctx, upper: &upper, lower: &lower, variance }.run(&bounds[j]);
        }
    }

    for (i, &element) in elements.iter().enumerate() {
        ctx.store.types_mut(element).default_type = Some(bounds[i].clone());
    }
}

/// `_TypeParametersGraph._collectReferencesFrom`.
fn collect_references_from(
    ctx: &BuildContext<'_>,
    parameters: &[ElementId],
    edges: &mut [Vec<usize>],
    index: usize,
    type_: &TypeImpl,
) {
    match type_ {
        TypeImpl::Builder(id) => match &ctx.store.type_builders[*id as usize] {
            TypeBuilder::Function(b) => {
                for &p in &b.type_parameters {
                    if let Some(bound) = ctx.store.element(p).type_.clone() {
                        collect_references_from(ctx, parameters, edges, index, &bound);
                    }
                }
                for p in &b.formal_parameters {
                    collect_references_from(ctx, parameters, edges, index, &p.type_);
                }
                collect_references_from(ctx, parameters, edges, index, &b.return_type);
            }
            TypeBuilder::Named(b) => {
                for argument in &b.arguments {
                    collect_references_from(ctx, parameters, edges, index, argument);
                }
            }
            TypeBuilder::Record(_) => {}
        },
        TypeImpl::TypeParameter(t) => {
            if let Some(type_index) = parameters.iter().position(|&p| p == t.element) {
                edges[type_index].push(index);
            }
        }
        _ => {}
    }
}

/// `_UpperLowerReplacementVisitor`, over the `ReplacementVisitor` it
/// extends. A visit returns `None` when nothing changes.
struct UpperLower<'c, 'a, 'm> {
    ctx: &'c mut BuildContext<'a>,
    upper: &'m HashMap<ElementId, TypeImpl>,
    lower: &'m HashMap<ElementId, TypeImpl>,
    variance: Variance,
}

impl UpperLower<'_, '_, '_> {
    fn run(mut self, type_: &TypeImpl) -> TypeImpl {
        self.visit(type_).unwrap_or_else(|| type_.clone())
    }

    fn change_variance(&mut self) {
        if self.variance == Variance::covariant {
            self.variance = Variance::contravariant;
        } else if self.variance == Variance::contravariant {
            self.variance = Variance::covariant;
        }
    }

    /// `visitTypeArgument`.
    fn visit_type_argument(&mut self, parameter: ElementId, argument: &TypeImpl) -> Option<TypeImpl> {
        let saved = self.variance;
        self.variance = self.variance.combine(self.ctx.store.variance(parameter));
        let result = self.visit(argument);
        self.variance = saved;
        result
    }

    /// `_typeArguments`.
    fn type_arguments(&mut self, parameters: &[ElementId], arguments: &[TypeImpl]) -> Option<Vec<TypeImpl>> {
        if arguments.len() != parameters.len() {
            return None;
        }
        let mut new_arguments: Option<Vec<TypeImpl>> = None;
        for i in 0..arguments.len() {
            if let Some(s) = self.visit_type_argument(parameters[i], &arguments[i]) {
                new_arguments.get_or_insert_with(|| arguments.to_vec())[i] = s;
            }
        }
        new_arguments
    }

    fn parameters_of(&self, element: ElementId) -> Vec<ElementId> {
        if element == NO_ELEMENT {
            return Vec::new();
        }
        match self.ctx.store.element(element).kind {
            ElementKind::CLASS | ElementKind::ENUM | ElementKind::MIXIN | ElementKind::EXTENSION_TYPE | ElementKind::TYPE_ALIAS => {
                self.ctx.type_parameters(element)
            }
            _ => Vec::new(),
        }
    }

    /// The type parameters of a function type with their bounds visited,
    /// and the substitution to the fresh copies when any bound changed
    /// (`visitFunctionType` and `visitFunctionTypeBuilder`).
    fn visit_type_parameters(&mut self, type_parameters: &[ElementId]) -> (Option<Vec<ElementId>>, Option<Substitution>) {
        let mut new_type_parameters: Option<Vec<ElementId>> = None;
        for (i, &p) in type_parameters.iter().enumerate() {
            if let Some(bound) = self.ctx.store.element(p).type_.clone() {
                if let Some(new_bound) = self.visit(&bound) {
                    let fresh = self.ctx.store.fresh_copy_type_parameter(p);
                    self.ctx.store.elements[fresh as usize].type_ = Some(new_bound);
                    new_type_parameters.get_or_insert_with(|| type_parameters.to_vec())[i] = fresh;
                }
            }
        }
        let Some(new) = &new_type_parameters else {
            return (None, None);
        };
        let substitution = Substitution::from_pairs(
            type_parameters.to_vec(),
            new.iter().map(|&p| TypeImpl::type_parameter(p, NullabilitySuffix::none)).collect(),
        );
        for &p in new {
            if let Some(bound) = self.ctx.store.element(p).type_.clone() {
                let new_bound = substitute(self.ctx.store, &substitution, &bound);
                self.ctx.store.elements[p as usize].type_ = Some(new_bound);
            }
        }
        (new_type_parameters, Some(substitution))
    }

    /// The local `visitType` of the function visits.
    fn visit_in(&mut self, type_: &TypeImpl, substitution: &Option<Substitution>) -> Option<TypeImpl> {
        let result = self.visit(type_);
        match substitution {
            Some(s) => Some(substitute(self.ctx.store, s, result.as_ref().unwrap_or(type_))),
            None => result,
        }
    }

    fn visit(&mut self, type_: &TypeImpl) -> Option<TypeImpl> {
        match type_ {
            TypeImpl::Dynamic | TypeImpl::Void | TypeImpl::Invalid | TypeImpl::Never(_) => None,
            // `_UpperLowerReplacementVisitor.visitTypeParameterType`.
            TypeImpl::TypeParameter(t) => {
                if self.variance == Variance::contravariant {
                    self.lower.get(&t.element).cloned()
                } else {
                    self.upper.get(&t.element).cloned()
                }
            }
            TypeImpl::Interface(t) => {
                let parameters = self.ctx.type_parameters(t.element);
                let new_arguments = self.type_arguments(&parameters, &t.type_arguments)?;
                Some(TypeImpl::Interface(Rc::new(InterfaceTypeImpl {
                    element: t.element,
                    type_arguments: new_arguments,
                    nullability_suffix: t.nullability_suffix,
                })))
            }
            TypeImpl::Record(t) => {
                let mut new_positional: Option<Vec<TypeImpl>> = None;
                for (i, field) in t.positional_fields.iter().enumerate() {
                    if let Some(n) = self.visit(field) {
                        new_positional.get_or_insert_with(|| t.positional_fields.clone())[i] = n;
                    }
                }
                let mut new_named: Option<Vec<(Rc<str>, TypeImpl)>> = None;
                for (i, (name, field)) in t.named_fields.iter().enumerate() {
                    if let Some(n) = self.visit(field) {
                        new_named.get_or_insert_with(|| t.named_fields.clone())[i] = (name.clone(), n);
                    }
                }
                if new_positional.is_none() && new_named.is_none() {
                    return None;
                }
                Some(TypeImpl::Record(Rc::new(RecordTypeImpl::new(
                    new_positional.unwrap_or_else(|| t.positional_fields.clone()),
                    new_named.unwrap_or_else(|| t.named_fields.clone()),
                    t.nullability_suffix,
                ))))
            }
            TypeImpl::Function(t) => {
                let (new_type_parameters, substitution) = self.visit_type_parameters(&t.type_parameters);
                let new_return_type = self.visit_in(&t.return_type, &substitution);
                self.change_variance();
                let mut new_parameters = None;
                for (i, p) in t.formal_parameters.iter().enumerate() {
                    if let Some(n) = self.visit_in(&p.type_, &substitution) {
                        new_parameters.get_or_insert_with(|| t.formal_parameters.clone())[i] = p.copy_with(Some(n), None);
                    }
                }
                self.change_variance();
                // `createFunctionType`: new type parameters alone are not a
                // change.
                if new_return_type.is_none() && new_parameters.is_none() {
                    return None;
                }
                Some(TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
                    new_type_parameters.unwrap_or_else(|| t.type_parameters.clone()),
                    new_parameters.unwrap_or_else(|| t.formal_parameters.clone()),
                    new_return_type.unwrap_or_else(|| t.return_type.clone()),
                    t.nullability_suffix,
                ))))
            }
            TypeImpl::Builder(id) => {
                let builder = self.ctx.store.type_builders[*id as usize].clone();
                let new_builder = match builder {
                    TypeBuilder::Named(b) => {
                        let parameters = self.parameters_of(b.element);
                        let new_arguments = self.type_arguments(&parameters, &b.arguments)?;
                        TypeBuilder::Named(NamedTypeBuilder {
                            element: b.element,
                            arguments: new_arguments,
                            nullability_suffix: b.nullability_suffix,
                            node: None,
                            type_: None,
                        })
                    }
                    TypeBuilder::Function(b) => {
                        let (new_type_parameters, substitution) = self.visit_type_parameters(&b.type_parameters);
                        let new_return_type = self.visit_in(&b.return_type, &substitution);
                        self.change_variance();
                        let mut new_parameters = None;
                        for (i, p) in b.formal_parameters.iter().enumerate() {
                            if let Some(n) = self.visit_in(&p.type_, &substitution) {
                                new_parameters.get_or_insert_with(|| b.formal_parameters.clone())[i] =
                                    p.copy_with(Some(n), None);
                            }
                        }
                        self.change_variance();
                        if new_return_type.is_none() && new_parameters.is_none() {
                            return None;
                        }
                        TypeBuilder::Function(FunctionTypeBuilder {
                            type_parameters: new_type_parameters.unwrap_or(b.type_parameters),
                            formal_parameters: new_parameters.unwrap_or(b.formal_parameters),
                            return_type: new_return_type.unwrap_or(b.return_type),
                            nullability_suffix: b.nullability_suffix,
                            node: None,
                            type_: None,
                        })
                    }
                    TypeBuilder::Record(b) => {
                        let mut new_field_types: Option<Vec<TypeImpl>> = None;
                        for (i, field) in b.field_types.iter().enumerate() {
                            if let Some(n) = self.visit(field) {
                                new_field_types.get_or_insert_with(|| b.field_types.clone())[i] = n;
                            }
                        }
                        let new_field_types = new_field_types?;
                        TypeBuilder::Record(RecordTypeBuilder {
                            node: b.node,
                            field_types: new_field_types,
                            field_names: b.field_names,
                            nullability_suffix: b.nullability_suffix,
                            is_building: false,
                            type_: None,
                        })
                    }
                };
                let new_id = self.ctx.store.type_builders.len() as u32;
                self.ctx.store.type_builders.push(new_builder);
                Some(TypeImpl::Builder(new_id))
            }
        }
    }
}
