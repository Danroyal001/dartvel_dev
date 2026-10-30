// Port of lib/src/summary2/types_builder.dart: `TypesBuilder`, which, once
// the type builders are built, gives the elements of the declarations their
// types: supertypes, mixins, interfaces and superclass constraints; return,
// variable and formal parameter types; bounds; aliased and extended types.
//
// An element's types live in `ElementImpl::type_` (a variable's or a formal
// parameter's type, an executable's return type, a bound, an aliased type, an
// extended type or a supertype) and in `ElementTypes`.
//
// Not ported yet: mixin inference (`_MixinsInference`), which needs the class
// hierarchy -- a mixin's type is used as written, which is what inference
// gives whenever type arguments are written -- and `breakInterfaceCycles`.

use std::rc::Rc;

use fe_analyzer_shared::scanner::token::NO_TOKEN;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::element::element::{
    ElementId, ElementKind, FragmentFlag, FragmentId, NO_ELEMENT, NO_FRAGMENT, UnitId,
};
use crate::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, TypeImpl};
use crate::src::summary2::type_builder::{error_function_type, BuildContext};

use FragmentFlag::*;

pub struct TypesBuilder<'c, 'a> {
    pub ctx: &'c mut BuildContext<'a>,
}

impl<'c, 'a> TypesBuilder<'c, 'a> {
    fn ast(&self, unit: UnitId) -> Ast<'a> {
        let asts: &'a std::collections::HashMap<UnitId, Ast<'a>> = self.ctx.asts;
        asts[&unit]
    }

    fn fragment(&self, unit: UnitId, node: NodeId) -> FragmentId {
        self.ctx.fragment_of_node[&(unit, node)]
    }

    fn element(&self, unit: UnitId, node: NodeId) -> ElementId {
        let f = self.fragment(unit, node);
        self.ctx.store.fragment(f).element
    }

    fn node_type(&self, unit: UnitId, node: NodeId) -> Option<TypeImpl> {
        if node == NO_NODE {
            None
        } else {
            self.ctx.node_types.get(&(unit, node)).cloned()
        }
    }

    fn set_type(&mut self, element: ElementId, type_: TypeImpl) {
        self.ctx.store.elements[element as usize].type_ = Some(type_);
    }

    /// `_toInterfaceTypeList`.
    fn to_interface_type_list(&self, unit: UnitId, nodes: &[NodeId]) -> Vec<TypeImpl> {
        nodes
            .iter()
            .filter_map(|&n| self.node_type(unit, n))
            .filter(|t| t.as_interface().is_some_and(|i| i.is_valid_superinterface(self.ctx.store)))
            .collect()
    }

    fn clause_types(&self, unit: UnitId, clause: NodeId) -> Vec<NodeId> {
        if clause == NO_NODE {
            return Vec::new();
        }
        match self.ast(unit).node(clause) {
            AstNodeImpl::WithClauseImpl(c) => c.mixin_types.iter().copied().collect(),
            AstNodeImpl::ImplementsClauseImpl(c) => c.interfaces.iter().copied().collect(),
            AstNodeImpl::MixinOnClauseImpl(c) => c.superclass_constraints.iter().copied().collect(),
            other => panic!("{} is not a clause of types", other.runtime_type()),
        }
    }

    fn add_interfaces(&mut self, element: ElementId, types: Vec<TypeImpl>) {
        self.ctx.store.types_mut(element).interfaces.extend(types);
    }

    /// `TypesBuilder.build`, after the default types and the builders:
    /// `_declaration` for every declaration, then `_setDefaultSupertypes`
    /// and `_copyDeclaringFormalParametersExplicitTypes`.
    pub fn build(&mut self, declarations: &[(UnitId, NodeId)], libraries: &[crate::src::dart::element::element::LibraryId]) {
        for &(unit, node) in declarations {
            self.declaration(unit, node);
        }
        self.set_default_supertypes(libraries);
    }

    /// `_declaration`.
    fn declaration(&mut self, unit: UnitId, node: NodeId) {
        let ast = self.ast(unit);
        match ast.node(node) {
            AstNodeImpl::ClassDeclaration2Impl(n) => {
                let element = self.element(unit, node);
                if self.ctx.store.element(element).type_.is_none() && n.extends_clause != NO_NODE {
                    let superclass = ast.node(n.extends_clause).as_extends_clause_impl().superclass;
                    if let Some(t) = self.node_type(unit, superclass) {
                        if t.as_interface().is_some_and(|i| i.is_valid_superclass(self.ctx.store)) {
                            self.set_type(element, t);
                        }
                    }
                }
                let interfaces = self.clause_types(unit, n.implements_clause);
                let interfaces = self.to_interface_type_list(unit, &interfaces);
                self.add_interfaces(element, interfaces);
                self.add_mixins(unit, element, n.with_clause);
            }
            AstNodeImpl::ClassTypeAlias2Impl(n) => {
                let element = self.element(unit, node);
                if let Some(t) = self.node_type(unit, n.superclass) {
                    if t.as_interface().is_some_and(|i| i.is_valid_superclass(self.ctx.store)) {
                        self.set_type(element, t);
                    }
                }
                let mixins = self.clause_types(unit, n.with_clause);
                let mixins = self.to_interface_type_list(unit, &mixins);
                self.ctx.store.types_mut(element).mixins = mixins;
                let interfaces = self.clause_types(unit, n.implements_clause);
                let interfaces = self.to_interface_type_list(unit, &interfaces);
                self.ctx.store.types_mut(element).interfaces = interfaces;
            }
            AstNodeImpl::EnumDeclaration2Impl(n) => {
                let element = self.element(unit, node);
                let interfaces = self.clause_types(unit, n.implements_clause);
                let interfaces = self.to_interface_type_list(unit, &interfaces);
                self.add_interfaces(element, interfaces);
                self.add_mixins(unit, element, n.with_clause);
            }
            AstNodeImpl::ExtensionDeclaration2Impl(n) => {
                if n.on_clause != NO_NODE {
                    let fragment = self.fragment(unit, node);
                    if self.ctx.store.fragment(fragment).previous_fragment == NO_FRAGMENT {
                        let extended = ast.node(n.on_clause).as_extension_on_clause_impl().extended_type;
                        let t = self.node_type(unit, extended).unwrap_or(TypeImpl::Invalid);
                        let element = self.ctx.store.fragment(fragment).element;
                        self.set_type(element, t);
                    }
                }
            }
            AstNodeImpl::ExtensionTypeDeclaration2Impl(n) => {
                let element = self.element(unit, node);
                if n.implements_clause != NO_NODE {
                    let nodes = self.clause_types(unit, n.implements_clause);
                    // `isValidExtensionTypeSuperinterface`: an interface
                    // type that is not `dynamic`-like; the type system check
                    // is ported with the type system.
                    let interfaces: Vec<TypeImpl> = nodes
                        .iter()
                        .filter_map(|&t| self.node_type(unit, t))
                        .filter(|t| matches!(t, TypeImpl::Interface(_)))
                        .collect();
                    self.add_interfaces(element, interfaces);
                }
            }
            AstNodeImpl::FieldFormalParameterImpl(_)
            | AstNodeImpl::SuperFormalParameterImpl(_)
            | AstNodeImpl::RegularFormalParameterImpl(_) => self.formal_parameter(unit, node),
            AstNodeImpl::TopLevelFunctionDeclarationImpl(n) => {
                let fragment = self.fragment(unit, node);
                if self.ctx.store.fragment(fragment).previous_fragment == NO_FRAGMENT {
                    let t = self.node_type(unit, n.return_type).unwrap_or(TypeImpl::Dynamic);
                    let element = self.ctx.store.fragment(fragment).element;
                    self.set_type(element, t);
                }
            }
            AstNodeImpl::TopLevelGetterDeclarationImpl(n) => {
                self.accessor(unit, node, n.return_type, TypeImpl::Dynamic);
            }
            AstNodeImpl::TopLevelSetterDeclarationImpl(n) => {
                self.accessor(unit, node, n.return_type, TypeImpl::Void);
            }
            AstNodeImpl::TopLevelVariablesDeclarationImpl(n) => {
                let variables: Vec<NodeId> = n.variables.iter().copied().collect();
                self.variables(unit, n.type_, &variables);
            }
            AstNodeImpl::FieldsDeclarationImpl(n) => {
                let fields: Vec<NodeId> = n.fields.iter().copied().collect();
                self.variables(unit, n.type_, &fields);
            }
            AstNodeImpl::FunctionTypeAlias2Impl(n) => {
                let element = self.element(unit, node);
                let t = self.build_function_type(unit, NO_NODE, n.return_type, n.parameters, NullabilitySuffix::none);
                self.set_type(element, t);
            }
            AstNodeImpl::GenericFunctionTypeImpl(n) => {
                let element = self.element(unit, node);
                let t = self.node_type(unit, n.return_type).unwrap_or(TypeImpl::Dynamic);
                self.set_type(element, t);
            }
            AstNodeImpl::GenericTypeAlias2Impl(n) => {
                let element = self.element(unit, node);
                let library = self.ctx.store.element(element).library;
                let nonfunction = *self.ctx.nonfunction_type_aliases.get(&library).unwrap_or(&true);
                let t = if nonfunction || matches!(ast.node(n.type_), AstNodeImpl::GenericFunctionTypeImpl(_)) {
                    self.node_type(unit, n.type_).unwrap_or(TypeImpl::Invalid)
                } else {
                    error_function_type(NullabilitySuffix::none)
                };
                self.set_type(element, t);
            }
            AstNodeImpl::MethodDeclaration2Impl(n) => self.method(unit, node, n.return_type, TypeImpl::Dynamic),
            AstNodeImpl::GetterDeclarationImpl(n) => self.method(unit, node, n.return_type, TypeImpl::Dynamic),
            AstNodeImpl::SetterDeclarationImpl(n) => self.method(unit, node, n.return_type, TypeImpl::Void),
            AstNodeImpl::OperatorDeclarationImpl(n) => {
                let default = if ast.tokens.lexeme_string(n.operator_) == "[]=" {
                    TypeImpl::Void
                } else {
                    TypeImpl::Dynamic
                };
                self.method(unit, node, n.return_type, default);
            }
            AstNodeImpl::MixinDeclaration2Impl(n) => {
                let element = self.element(unit, node);
                let constraints = self.clause_types(unit, n.on_clause);
                let constraints = self.to_interface_type_list(unit, &constraints);
                self.ctx.store.types_mut(element).superclass_constraints.extend(constraints);
                let interfaces = self.clause_types(unit, n.implements_clause);
                let interfaces = self.to_interface_type_list(unit, &interfaces);
                self.add_interfaces(element, interfaces);
            }
            AstNodeImpl::TypeParameterImpl(n) => {
                let fragment = self.fragment(unit, node);
                if self.ctx.store.fragment(fragment).previous_fragment == NO_FRAGMENT {
                    let element = self.ctx.store.fragment(fragment).element;
                    let bound = self.node_type(unit, n.bound);
                    self.ctx.store.elements[element as usize].type_ = bound;
                }
            }
            other => panic!("UnimplementedError: {}", other.runtime_type()),
        }
    }

    /// The mixins of a with clause; inference is not ported yet, so the
    /// types are used as written (`_addFragmentWithClause`).
    fn add_mixins(&mut self, unit: UnitId, element: ElementId, with_clause: NodeId) {
        if with_clause == NO_NODE {
            return;
        }
        let nodes = self.clause_types(unit, with_clause);
        let mixins = self.to_interface_type_list(unit, &nodes);
        self.ctx.store.types_mut(element).mixins.extend(mixins);
    }

    fn variables(&mut self, unit: UnitId, type_node: NodeId, variables: &[NodeId]) {
        let Some(t) = self.node_type(unit, type_node) else {
            return;
        };
        for &variable in variables {
            let fragment = self.fragment(unit, variable);
            if self.ctx.store.fragment(fragment).previous_fragment == NO_FRAGMENT {
                let element = self.ctx.store.fragment(fragment).element;
                self.set_type(element, t.clone());
            }
        }
    }

    /// `_methodDeclaration`.
    fn method(&mut self, unit: UnitId, node: NodeId, return_type: NodeId, default: TypeImpl) {
        let fragment = self.fragment(unit, node);
        if self.ctx.store.fragment(fragment).previous_fragment != NO_FRAGMENT {
            return;
        }
        let element = self.ctx.store.fragment(fragment).element;
        let t = self.node_type(unit, return_type).unwrap_or(default);
        self.set_type(element, t);
        self.set_synthetic_variable_type(element);
    }

    /// `_topLevelGetterDeclaration` and `_topLevelSetterDeclaration`.
    fn accessor(&mut self, unit: UnitId, node: NodeId, return_type: NodeId, default: TypeImpl) {
        self.method(unit, node, return_type, default);
    }

    /// `_setSyntheticVariableType`.
    fn set_synthetic_variable_type(&mut self, element: ElementId) {
        let e = self.ctx.store.element(element);
        let variable = e.variable;
        if variable == NO_ELEMENT {
            return;
        }
        let variable_first = self.ctx.store.element(variable).first_fragment;
        let is_origin_getter_setter = self.ctx.store.fragment(variable_first).has_flag(propertyInducingFragment_isOriginGetterSetter);
        if !is_origin_getter_setter {
            return;
        }
        match e.kind {
            ElementKind::GETTER => {
                let t = e.type_.clone();
                self.ctx.store.elements[variable as usize].type_ = t;
            }
            ElementKind::SETTER => {
                if self.ctx.store.element(variable).getter == NO_ELEMENT {
                    let first = e.first_fragment;
                    let value = self.ctx.store.fragment(first).formal_parameters.first().copied();
                    if let Some(value) = value {
                        let value_element = self.ctx.store.fragment(value).element;
                        let t = self.ctx.store.element(value_element).type_.clone();
                        self.ctx.store.elements[variable as usize].type_ = t;
                    }
                }
            }
            _ => {}
        }
    }

    /// `_hasPreviousFormalParameterWithType`.
    fn has_previous_formal_parameter_with_type(&self, fragment: FragmentId) -> bool {
        let mut previous = self.ctx.store.fragment(fragment).previous_fragment;
        while previous != NO_FRAGMENT {
            let p = self.ctx.store.fragment(previous);
            if !p.has_flag(formalParameterFragment_isOriginOtherFragmentOfEnclosing) {
                return true;
            }
            previous = p.previous_fragment;
        }
        false
    }

    /// `_regularFormalParameter`, `_fieldFormalParameter` and
    /// `_superFormalParameter`.
    fn formal_parameter(&mut self, unit: UnitId, node: NodeId) {
        let fragment = self.fragment(unit, node);
        if self.has_previous_formal_parameter_with_type(fragment) {
            return;
        }
        let element = self.ctx.store.fragment(fragment).element;
        let ast = self.ast(unit);
        let (type_node, suffix, is_regular) = match ast.node(node) {
            AstNodeImpl::RegularFormalParameterImpl(p) => (p.type_, p.function_typed_suffix, true),
            AstNodeImpl::FieldFormalParameterImpl(p) => (p.type_, p.function_typed_suffix, false),
            AstNodeImpl::SuperFormalParameterImpl(p) => (p.type_, p.function_typed_suffix, false),
            _ => unreachable!(),
        };
        if suffix != NO_NODE {
            let s = ast.node(suffix).as_function_typed_formal_parameter_suffix_impl();
            let suffix_nullability = if s.question != NO_TOKEN {
                NullabilitySuffix::question
            } else {
                NullabilitySuffix::none
            };
            let t = self.build_function_type(unit, s.type_parameters, type_node, s.formal_parameters, suffix_nullability);
            self.set_type(element, t);
            return;
        }
        match self.node_type(unit, type_node) {
            Some(t) => self.set_type(element, t),
            None => {
                // A declaring formal parameter's type is inferred later.
                let is_declaring = self
                    .ctx
                    .store
                    .fragment(fragment)
                    .has_flag(fieldFormalParameterFragment_isDeclaring);
                if is_regular && is_declaring {
                    return;
                }
                self.set_type(element, TypeImpl::Dynamic);
            }
        }
    }

    /// `_buildFunctionType`: the type of a function-typed formal parameter or
    /// of an old-style typedef, from the elements of its parameters.
    fn build_function_type(
        &mut self,
        unit: UnitId,
        type_parameter_list: NodeId,
        return_type_node: NodeId,
        formal_parameter_list: NodeId,
        nullability_suffix: NullabilitySuffix,
    ) -> TypeImpl {
        let ast = self.ast(unit);
        let return_type = self.node_type(unit, return_type_node).unwrap_or(TypeImpl::Dynamic);
        let type_parameters: Vec<ElementId> = if type_parameter_list == NO_NODE {
            Vec::new()
        } else {
            ast.node(type_parameter_list)
                .as_type_parameter_list_impl()
                .type_parameters
                .iter()
                .map(|&p| self.element(unit, p))
                .collect()
        };
        let mut all: Vec<NodeId> = Vec::new();
        if formal_parameter_list != NO_NODE {
            let l = ast.node(formal_parameter_list).as_formal_parameter_list_impl();
            all.extend(l.required_positional_formal_parameters.iter().copied());
            if l.delimited_formal_parameters != NO_NODE {
                all.extend(
                    ast.node(l.delimited_formal_parameters)
                        .as_delimited_formal_parameters_impl()
                        .formal_parameters
                        .iter()
                        .copied(),
                );
            }
        }
        // `_formalParameters`: the parameters' elements.
        let formal_parameters = all
            .into_iter()
            .map(|p| {
                let fragment = self.fragment(unit, p);
                let f = self.ctx.store.fragment(fragment);
                let element = f.element;
                FormalParameter {
                    name: self.ctx.store.element(element).name.clone(),
                    type_: self.ctx.store.element(element).type_.clone().unwrap_or(TypeImpl::Dynamic),
                    kind: f.parameter_kind,
                }
            })
            .collect();
        TypeImpl::Function(Rc::new(FunctionTypeImpl::new(type_parameters, formal_parameters, return_type, nullability_suffix)))
    }

    /// `_setDefaultSupertypes`.
    fn set_default_supertypes(&mut self, libraries: &[crate::src::dart::element::element::LibraryId]) {
        let Some(object) = self.ctx.store.dart_core_object() else {
            return;
        };
        let object_type = TypeImpl::interface(object, Vec::new(), NullabilitySuffix::none);
        for &library in libraries {
            let classes = self.ctx.store.libraries[library as usize].classes.clone();
            for class in classes {
                if class != object && self.ctx.store.element(class).type_.is_none() {
                    self.set_type(class, object_type.clone());
                }
            }
            let mixins = self.ctx.store.libraries[library as usize].mixins.clone();
            for mixin in mixins {
                let empty = self.ctx.store.types(mixin).map(|t| t.superclass_constraints.is_empty()).unwrap_or(true);
                if empty {
                    self.ctx.store.types_mut(mixin).superclass_constraints = vec![object_type.clone()];
                }
            }
        }
    }
}
