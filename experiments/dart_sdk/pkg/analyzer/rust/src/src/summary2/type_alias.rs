// Port of lib/src/summary2/type_alias.dart: `TypeAliasSelfReferenceFinder`,
// which marks the typedefs whose type parameter bounds, parameters or
// aliased type reach the typedef itself, through other declarations being
// linked. Such a typedef instantiates to `dynamic` (or `dynamic Function()`).

use std::collections::{HashMap, HashSet};

use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementStore, LibraryId, NO_FRAGMENT, UnitId};
use crate::src::dart::element::scope::ScopeElement;

pub struct TypeAliasSelfReferenceFinder<'a> {
    pub store: &'a mut ElementStore,
    pub asts: &'a HashMap<UnitId, Ast<'a>>,
    pub node_elements: &'a HashMap<(UnitId, NodeId), Option<ScopeElement>>,
    pub fragment_of_node: &'a HashMap<(UnitId, NodeId), crate::src::dart::element::element::FragmentId>,
    pub linking_libraries: &'a HashSet<LibraryId>,
}

impl TypeAliasSelfReferenceFinder<'_> {
    /// `perform`, over the units being linked, in order.
    pub fn perform(&mut self, units: &[(UnitId, NodeId)]) {
        for &(unit, unit_node) in units {
            let ast = self.asts[&unit];
            let declarations: Vec<NodeId> =
                ast.node(unit_node).as_compilation_unit_impl().declarations2.iter().copied().collect();
            for node in declarations {
                let is_alias = matches!(
                    ast.node(node),
                    AstNodeImpl::FunctionTypeAlias2Impl(_) | AstNodeImpl::GenericTypeAlias2Impl(_)
                );
                if !is_alias {
                    continue;
                }
                let mut finder = Finder {
                    outer: self,
                    self_: (unit, node),
                    visited: HashSet::new(),
                    has_self_reference: false,
                };
                finder.alias(unit, node);
                let has_self_reference = finder.has_self_reference;
                let fragment = self.fragment_of_node[&(unit, node)];
                let element = self.store.fragment(fragment).element;
                self.store.types_mut(element).has_self_reference = has_self_reference;
            }
        }
    }
}

struct Finder<'f, 'a> {
    outer: &'f TypeAliasSelfReferenceFinder<'a>,
    self_: (UnitId, NodeId),
    visited: HashSet<(UnitId, NodeId)>,
    has_self_reference: bool,
}

impl<'f, 'a> Finder<'f, 'a> {
    fn ast(&self, unit: UnitId) -> Ast<'a> {
        let asts: &'a HashMap<UnitId, Ast<'a>> = self.outer.asts;
        asts[&unit]
    }

    /// `functionTypeAlias` and `genericTypeAlias`.
    fn alias(&mut self, unit: UnitId, node: NodeId) {
        let ast = self.ast(unit);
        match ast.node(node) {
            AstNodeImpl::FunctionTypeAlias2Impl(n) => {
                let (type_parameters, parameters, return_type) = (n.type_parameters, n.parameters, n.return_type);
                self.type_parameter_list(unit, type_parameters);
                self.formal_parameter_list(unit, parameters);
                self.visit(unit, return_type);
            }
            AstNodeImpl::GenericTypeAlias2Impl(n) => {
                let (type_parameters, type_) = (n.type_parameters, n.type_);
                self.type_parameter_list(unit, type_parameters);
                self.visit(unit, type_);
            }
            _ => {}
        }
    }

    fn type_parameter_list(&mut self, unit: UnitId, list: NodeId) {
        if list == NO_NODE {
            return;
        }
        let ast = self.ast(unit);
        let parameters: Vec<NodeId> = ast.node(list).as_type_parameter_list_impl().type_parameters.iter().copied().collect();
        for p in parameters {
            let bound = ast.node(p).as_type_parameter_impl().bound;
            self.visit(unit, bound);
        }
    }

    fn formal_parameter_list(&mut self, unit: UnitId, list: NodeId) {
        if list == NO_NODE {
            return;
        }
        let ast = self.ast(unit);
        let l = ast.node(list).as_formal_parameter_list_impl();
        let mut all: Vec<NodeId> = l.required_positional_formal_parameters.iter().copied().collect();
        if l.delimited_formal_parameters != NO_NODE {
            all.extend(
                ast.node(l.delimited_formal_parameters)
                    .as_delimited_formal_parameters_impl()
                    .formal_parameters
                    .iter()
                    .copied(),
            );
        }
        for p in all {
            let (type_, suffix) = match ast.node(p) {
                AstNodeImpl::RegularFormalParameterImpl(f) => (f.type_, f.function_typed_suffix),
                AstNodeImpl::FieldFormalParameterImpl(f) => (f.type_, f.function_typed_suffix),
                AstNodeImpl::SuperFormalParameterImpl(f) => (f.type_, f.function_typed_suffix),
                _ => continue,
            };
            self.visit(unit, type_);
            if suffix != NO_NODE {
                let formal_parameters = ast.node(suffix).as_function_typed_formal_parameter_suffix_impl().formal_parameters;
                self.formal_parameter_list(unit, formal_parameters);
            }
        }
    }

    /// `_visit`.
    fn visit(&mut self, unit: UnitId, node: NodeId) {
        if self.has_self_reference || node == NO_NODE {
            return;
        }
        let ast = self.ast(unit);
        match ast.node(node) {
            AstNodeImpl::NamedTypeImpl(n) => {
                let type_arguments = n.type_arguments;
                if let Some(Some(ScopeElement::Element(element))) = self.outer.node_elements.get(&(unit, node)) {
                    let e = self.outer.store.element(*element);
                    let first = e.first_fragment;
                    if self.outer.linking_libraries.contains(&e.library) && first != NO_FRAGMENT {
                        let f = self.outer.store.fragment(first);
                        let type_node = (f.unit, f.node);
                        if f.node != NO_NODE && self.outer.asts.contains_key(&f.unit) {
                            if type_node == self.self_ {
                                self.has_self_reference = true;
                                return;
                            }
                            let tast = self.ast(type_node.0);
                            match tast.node(type_node.1) {
                                AstNodeImpl::ClassDeclaration2Impl(c) => {
                                    if self.visited.insert(type_node) {
                                        let list = match tast.node(c.name_part) {
                                            AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_parameters,
                                            AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_parameters,
                                            _ => NO_NODE,
                                        };
                                        self.type_parameter_list(type_node.0, list);
                                    }
                                }
                                AstNodeImpl::ClassTypeAlias2Impl(c) => {
                                    if self.visited.insert(type_node) {
                                        let list = c.type_parameters;
                                        self.type_parameter_list(type_node.0, list);
                                    }
                                }
                                AstNodeImpl::FunctionTypeAlias2Impl(_) | AstNodeImpl::GenericTypeAlias2Impl(_) => {
                                    if self.visited.insert(type_node) {
                                        self.alias(type_node.0, type_node.1);
                                    }
                                }
                                AstNodeImpl::MixinDeclaration2Impl(m) => {
                                    if self.visited.insert(type_node) {
                                        let list = m.type_parameters;
                                        self.type_parameter_list(type_node.0, list);
                                    }
                                }
                                _ => {}
                            }
                        }
                    }
                }
                if type_arguments != NO_NODE {
                    let arguments: Vec<NodeId> =
                        ast.node(type_arguments).as_type_argument_list_impl().arguments.iter().copied().collect();
                    for a in arguments {
                        self.visit(unit, a);
                    }
                }
            }
            AstNodeImpl::GenericFunctionTypeImpl(n) => {
                let (type_parameters, parameters, return_type) = (n.type_parameters, n.parameters, n.return_type);
                self.type_parameter_list(unit, type_parameters);
                self.formal_parameter_list(unit, parameters);
                self.visit(unit, return_type);
            }
            AstNodeImpl::RecordTypeAnnotationImpl(n) => {
                let mut types: Vec<NodeId> = n
                    .positional_fields
                    .iter()
                    .map(|&f| ast.node(f).as_record_type_annotation_positional_field_impl().type_)
                    .collect();
                if n.named_fields != NO_NODE {
                    for &f in ast.node(n.named_fields).as_record_type_annotation_named_fields_impl().fields.iter() {
                        types.push(ast.node(f).as_record_type_annotation_named_field_impl().type_);
                    }
                }
                for t in types {
                    self.visit(unit, t);
                }
            }
            other => panic!("UnimplementedError: ({}) {node}", other.runtime_type()),
        }
    }
}
