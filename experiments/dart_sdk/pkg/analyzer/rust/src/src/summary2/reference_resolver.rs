// Port of lib/src/summary2/reference_resolver.dart (`ReferenceResolver`),
// with the parts of lib/src/dart/resolver/scope_context.dart it uses
// (`ScopeContext`: the scope each declaration's type annotations are
// resolved in), and the `of` factories of named_type_builder.dart,
// function_type_builder.dart and record_type_builder.dart.
//
// Resolving a unit's outline gives every type annotation a type: a
// `TypeBuilder` (kept in the store's `type_builders`) for named, function
// and record types, `void`, an invalid type, or a type parameter type.
// They are kept in `LinkingTypes::node_types`, keyed by unit and node, as
// upstream sets `node.type`. Declarations whose types are built from their
// nodes are listed in `NodesToBuildType` order for `TypesBuilder`.
//
// Not ported: the scopes kept on nodes for later resolution (`nameScope`,
// `bodyScope`, `initializerScope`), metadata, documentation comments and
// bodies, which linking does not resolve.

use std::collections::HashMap;
use std::rc::Rc;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentId, NO_FRAGMENT, UnitId};
use crate::src::dart::element::r#type::{BuilderId, FormalParameter, TypeImpl};
use crate::src::dart::element::scope::{ScopeElement, ScopeFeatures, ScopeId, Scopes};
use crate::src::summary2::type_builder::{FunctionTypeBuilder, NamedTypeBuilder, RecordTypeBuilder, TypeBuilder};

/// What resolving the outlines of a library cycle gives: the types of the
/// type annotations, the elements of named types, and `NodesToBuildType`.
#[derive(Debug, Default)]
pub struct LinkingTypes {
    pub scopes: Scopes,
    /// `TypeAnnotation.type`.
    pub node_types: HashMap<(UnitId, NodeId), TypeImpl>,
    /// `NamedType.element`.
    pub node_elements: HashMap<(UnitId, NodeId), Option<ScopeElement>>,
    /// `node.declaredFragment`.
    pub fragment_of_node: HashMap<(UnitId, NodeId), FragmentId>,
    /// `NodesToBuildType._declarations`.
    pub declarations: Vec<(UnitId, NodeId)>,
    /// `NodesToBuildType._typeBuilders`.
    pub type_builders: Vec<BuilderId>,
}

impl LinkingTypes {
    /// Fills [fragment_of_node] from the fragments' declaring nodes.
    pub fn index_fragments(&mut self, store: &ElementStore) {
        for (id, fragment) in store.fragments.iter().enumerate() {
            if fragment.node != NO_NODE {
                self.fragment_of_node.insert((fragment.unit, fragment.node), id as FragmentId);
            }
        }
    }

    pub fn node_type(&self, unit: UnitId, node: NodeId) -> TypeImpl {
        self.node_types[&(unit, node)].clone()
    }
}

pub struct ReferenceResolver<'a> {
    pub store: &'a mut ElementStore,
    pub types: &'a mut LinkingTypes,
    pub ast: Ast<'a>,
    pub unit: UnitId,
    pub features: ScopeFeatures,
    pub primary_constructors: bool,
    scope: ScopeId,
    /// `ScopeContext._isInStaticMember`.
    is_in_static_member: bool,
}

impl<'a> ReferenceResolver<'a> {
    pub fn new(
        store: &'a mut ElementStore,
        types: &'a mut LinkingTypes,
        ast: Ast<'a>,
        unit: UnitId,
        features: ScopeFeatures,
        primary_constructors: bool,
    ) -> Self {
        ReferenceResolver {
            store,
            types,
            ast,
            unit,
            features,
            primary_constructors,
            scope: ScopeId::LibraryFragment(unit),
            is_in_static_member: false,
        }
    }

    fn fragment(&self, node: NodeId) -> FragmentId {
        *self
            .types
            .fragment_of_node
            .get(&(self.unit, node))
            .unwrap_or_else(|| panic!("no declared fragment for node {node}"))
    }

    fn element_of_node(&self, node: NodeId) -> ElementId {
        let fragment = self.fragment(node);
        self.store.fragment(fragment).element
    }

    /// `element.typeParameters`: the elements of the first fragment's type
    /// parameters.
    fn type_parameters_of(&self, element: ElementId) -> Vec<ElementId> {
        let first = self.store.element(element).first_fragment;
        self.store
            .fragment(first)
            .type_parameters
            .iter()
            .map(|&f| self.store.fragment(f).element)
            .collect()
    }

    fn with_scope(&mut self, scope: ScopeId, f: impl FnOnce(&mut Self)) {
        let outer = self.scope;
        self.scope = scope;
        f(self);
        self.scope = outer;
    }

    /// `withTypeParameterScope`.
    fn with_type_parameter_scope(&mut self, elements: &[ElementId], f: impl FnOnce(&mut Self)) {
        let scope = self.types.scopes.type_parameter_scope(self.store, self.scope, elements, self.features);
        self.with_scope(scope, f);
    }

    /// `withTypeParameterList`: the scope of the type parameters a list
    /// declares (of a generic function type or a function-typed suffix).
    fn with_type_parameter_list(&mut self, list: NodeId, f: impl FnOnce(&mut Self)) {
        if list == NO_NODE {
            f(self);
            return;
        }
        let elements: Vec<ElementId> = self
            .ast
            .node(list)
            .as_type_parameter_list_impl()
            .type_parameters
            .iter()
            .map(|&p| self.element_of_node(p))
            .collect();
        self.with_type_parameter_scope(&elements, f);
    }

    /// `withInstanceScope` and `withExtensionScope`.
    fn with_instance_scope(&mut self, element: ElementId, instance: bool, f: impl FnOnce(&mut Self)) {
        let scope = self.types.scopes.instance_scope(self.store, self.scope, element, instance);
        self.with_scope(scope, f);
    }

    fn with_in_static_member(&mut self, is_static: bool, f: impl FnOnce(&mut Self)) {
        let outer = self.is_in_static_member;
        self.is_in_static_member = is_static;
        f(self);
        self.is_in_static_member = outer;
    }

    fn add_declaration(&mut self, node: NodeId) {
        self.types.declarations.push((self.unit, node));
    }

    fn add_type_builder(&mut self, builder: TypeBuilder) -> TypeImpl {
        let id = self.store.type_builders.len() as BuilderId;
        self.store.type_builders.push(builder);
        self.types.type_builders.push(id);
        TypeImpl::Builder(id)
    }

    /// `visitCompilationUnit`.
    pub fn resolve_unit(&mut self, unit_node: NodeId) {
        let declarations = self.ast.node(unit_node).as_compilation_unit_impl().declarations2.clone();
        for declaration in declarations.iter() {
            self.visit(*declaration);
        }
    }

    fn visit_list(&mut self, nodes: Vec<NodeId>) {
        for node in nodes {
            self.visit(node);
        }
    }

    fn visit_opt(&mut self, node: NodeId) {
        if node != NO_NODE {
            self.visit(node);
        }
    }

    fn visit(&mut self, node: NodeId) {
        let ast = self.ast;
        match ast.node(node) {
            AstNodeImpl::ClassDeclaration2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (name_part, ext, with, imp, body) =
                    (n.name_part, n.extends_clause, n.with_clause, n.implements_clause, n.body);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_name_part_type_parameters(name_part);
                    this.visit_opt(ext);
                    this.visit_opt(with);
                    this.visit_opt(imp);
                    this.with_instance_scope(element, true, |this| {
                        this.visit_primary_constructor_formal_parameters(name_part);
                        this.visit_body(body);
                    });
                });
                self.add_declaration(node);
            }
            AstNodeImpl::ClassTypeAlias2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (type_parameters, superclass, with, imp) =
                    (n.type_parameters, n.superclass, n.with_clause, n.implements_clause);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_opt(type_parameters);
                    this.visit(superclass);
                    this.visit_opt(with);
                    this.visit_opt(imp);
                });
                self.add_declaration(node);
            }
            AstNodeImpl::ConstructorDeclaration2Impl(n) => {
                self.visit_opt(n.formal_parameters);
            }
            AstNodeImpl::EnumDeclaration2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (name_part, with, imp, body) = (n.name_part, n.with_clause, n.implements_clause, n.body);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_name_part_type_parameters(name_part);
                    this.visit_opt(with);
                    this.visit_opt(imp);
                    this.with_instance_scope(element, true, |this| {
                        this.visit_primary_constructor_formal_parameters(name_part);
                        this.visit_body(body);
                    });
                });
                self.add_declaration(node);
            }
            AstNodeImpl::ExtensionDeclaration2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (type_parameters, on, body) = (n.type_parameters, n.on_clause, n.body);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_opt(type_parameters);
                    this.visit_opt(on);
                    this.with_instance_scope(element, false, |this| {
                        this.visit_body(body);
                    });
                });
                self.add_declaration(node);
            }
            AstNodeImpl::ExtensionTypeDeclaration2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (name_part, imp, body) = (n.name_part, n.implements_clause, n.body);
                let primary_constructors = self.primary_constructors;
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_name_part_type_parameters(name_part);
                    this.visit_opt(imp);
                    if primary_constructors {
                        this.with_instance_scope(element, true, |this| {
                            this.visit_primary_constructor_formal_parameters(name_part);
                            this.visit_body(body);
                        });
                    } else {
                        this.visit_primary_constructor_formal_parameters(name_part);
                        this.with_instance_scope(element, true, |this| {
                            this.visit_body(body);
                        });
                    }
                });
                self.add_declaration(node);
            }
            AstNodeImpl::FieldsDeclarationImpl(n) => {
                let is_static = n.static_keyword != fe_analyzer_shared::scanner::token::NO_TOKEN;
                let type_ = n.type_;
                self.with_in_static_member(is_static, |this| {
                    this.visit_opt(type_);
                });
                self.add_declaration(node);
            }
            AstNodeImpl::RegularFormalParameterImpl(_)
            | AstNodeImpl::FieldFormalParameterImpl(_)
            | AstNodeImpl::SuperFormalParameterImpl(_) => {
                let (type_, suffix) = formal_type_and_suffix(ast, node);
                if suffix == NO_NODE {
                    self.visit_opt(type_);
                } else {
                    let s = ast.node(suffix).as_function_typed_formal_parameter_suffix_impl();
                    let (type_parameters, formal_parameters) = (s.type_parameters, s.formal_parameters);
                    self.with_type_parameter_list(type_parameters, |this| {
                        this.visit_opt(type_);
                        this.visit_opt(type_parameters);
                        this.visit_opt(formal_parameters);
                    });
                }
                self.add_declaration(node);
            }
            AstNodeImpl::FormalParameterListImpl(n) => {
                let required = n.required_positional_formal_parameters.iter().copied().collect();
                let delimited = n.delimited_formal_parameters;
                self.visit_list(required);
                if delimited != NO_NODE {
                    let rest = ast
                        .node(delimited)
                        .as_delimited_formal_parameters_impl()
                        .formal_parameters
                        .iter()
                        .copied()
                        .collect();
                    self.visit_list(rest);
                }
            }
            AstNodeImpl::FunctionTypeAlias2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (return_type, type_parameters, parameters) = (n.return_type, n.type_parameters, n.parameters);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_opt(return_type);
                    this.visit_opt(type_parameters);
                    this.visit_opt(parameters);
                });
                self.add_declaration(node);
            }
            AstNodeImpl::GenericFunctionTypeImpl(n) => {
                let (type_parameters, parameters, return_type, question) =
                    (n.type_parameters, n.parameters, n.return_type, n.question);
                self.with_type_parameter_list(type_parameters, |this| {
                    this.visit_opt(type_parameters);
                    this.visit_opt(parameters);
                    this.visit_opt(return_type);
                });
                let builder = self.function_type_builder_of(node, nullability(question));
                let t = self.add_type_builder(TypeBuilder::Function(builder));
                self.types.node_types.insert((self.unit, node), t);
                self.add_declaration(node);
            }
            AstNodeImpl::GenericTypeAlias2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (type_parameters, type_) = (n.type_parameters, n.type_);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_opt(type_parameters);
                    this.visit(type_);
                });
                self.add_declaration(node);
            }
            AstNodeImpl::GetterDeclarationImpl(_)
            | AstNodeImpl::MethodDeclaration2Impl(_)
            | AstNodeImpl::OperatorDeclarationImpl(_)
            | AstNodeImpl::SetterDeclarationImpl(_)
            | AstNodeImpl::TopLevelFunctionDeclarationImpl(_)
            | AstNodeImpl::TopLevelGetterDeclarationImpl(_)
            | AstNodeImpl::TopLevelSetterDeclarationImpl(_) => {
                let parts = executable_parts(ast, node);
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                // `visitMethodDeclaration` enters a static member or leaves one;
                // the top-level visits keep the current state.
                let is_static = if parts.top_level { self.is_in_static_member } else { parts.is_static };
                self.with_in_static_member(is_static, |this| {
                    this.with_type_parameter_scope(&tps, |this| {
                        this.visit_opt(parts.return_type);
                        this.visit_opt(parts.type_parameters);
                        this.visit_opt(parts.formal_parameters);
                    });
                });
                self.add_declaration(node);
            }
            AstNodeImpl::MixinDeclaration2Impl(n) => {
                let element = self.element_of_node(node);
                let tps = self.type_parameters_of(element);
                let (type_parameters, on, imp, body) = (n.type_parameters, n.on_clause, n.implements_clause, n.body);
                self.with_type_parameter_scope(&tps, |this| {
                    this.visit_opt(type_parameters);
                    this.visit_opt(on);
                    this.visit_opt(imp);
                    this.with_instance_scope(element, true, |this| {
                        this.visit_body(body);
                    });
                });
                self.add_declaration(node);
            }
            AstNodeImpl::NamedTypeImpl(_) => self.visit_named_type(node),
            AstNodeImpl::PrimaryConstructorBody2Impl(_) => {}
            AstNodeImpl::RecordTypeAnnotationImpl(n) => {
                let mut field_types_nodes: Vec<NodeId> = n
                    .positional_fields
                    .iter()
                    .map(|&f| ast.node(f).as_record_type_annotation_positional_field_impl().type_)
                    .collect();
                let mut names: Vec<Rc<str>> = Vec::new();
                if n.named_fields != NO_NODE {
                    for &f in ast.node(n.named_fields).as_record_type_annotation_named_fields_impl().fields.iter() {
                        let field = ast.node(f).as_record_type_annotation_named_field_impl();
                        field_types_nodes.push(field.type_);
                        names.push(Rc::from(ast.tokens.lexeme_string(field.name)));
                    }
                }
                let question = n.question;
                for &t in &field_types_nodes {
                    self.visit(t);
                }
                let field_types = field_types_nodes.iter().map(|&t| self.types.node_type(self.unit, t)).collect();
                let t = self.add_type_builder(TypeBuilder::Record(RecordTypeBuilder {
                    node: (self.unit, node),
                    field_types,
                    field_names: names,
                    nullability_suffix: nullability(question),
                    is_building: false,
                    type_: None,
                }));
                self.types.node_types.insert((self.unit, node), t);
            }
            AstNodeImpl::ExtendsClauseImpl(c) => self.visit(c.superclass),
            AstNodeImpl::WithClauseImpl(c) => self.visit_list(c.mixin_types.iter().copied().collect()),
            AstNodeImpl::ImplementsClauseImpl(c) => self.visit_list(c.interfaces.iter().copied().collect()),
            AstNodeImpl::MixinOnClauseImpl(c) => self.visit_list(c.superclass_constraints.iter().copied().collect()),
            AstNodeImpl::ExtensionOnClauseImpl(c) => self.visit(c.extended_type),
            AstNodeImpl::TopLevelVariablesDeclarationImpl(n) => {
                self.visit_opt(n.type_);
                self.add_declaration(node);
            }
            AstNodeImpl::TypeArgumentListImpl(n) => self.visit_list(n.arguments.iter().copied().collect()),
            AstNodeImpl::TypeParameterListImpl(n) => self.visit_list(n.type_parameters.iter().copied().collect()),
            AstNodeImpl::TypeParameterImpl(n) => {
                let bound = n.bound;
                if bound != NO_NODE {
                    self.visit(bound);
                    let fragment = self.fragment(node);
                    if self.store.fragment(fragment).previous_fragment == NO_FRAGMENT {
                        let element = self.store.fragment(fragment).element;
                        let t = self.types.node_type(self.unit, bound);
                        self.store.elements[element as usize].type_ = Some(t);
                    }
                    self.add_declaration(node);
                }
            }
            other => panic!("ThrowingAstVisitor2: visit{} is not overridden", other.runtime_type()),
        }
    }

    /// `visitNameWithTypeParameters` / the type parameters of a primary
    /// constructor declaration.
    fn visit_name_part_type_parameters(&mut self, name_part: NodeId) {
        let type_parameters = match self.ast.node(name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_parameters,
            AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_parameters,
            _ => NO_NODE,
        };
        self.visit_opt(type_parameters);
    }

    /// `namePart.tryCast<PrimaryConstructorDeclarationImpl>()?.formalParameters`.
    fn visit_primary_constructor_formal_parameters(&mut self, name_part: NodeId) {
        if let AstNodeImpl::PrimaryConstructorDeclarationImpl(p) = self.ast.node(name_part) {
            self.visit_opt(p.formal_parameters);
        }
    }

    /// `visitBlockInstanceDeclarationBody`, `visitBlockEnumDeclarationBody`
    /// (constants resolve nothing) and the semicolon bodies.
    fn visit_body(&mut self, body: NodeId) {
        let members: Vec<NodeId> = match self.ast.node(body) {
            AstNodeImpl::BlockInstanceDeclarationBodyImpl(b) => b.members.iter().copied().collect(),
            AstNodeImpl::BlockEnumDeclarationBodyImpl(b) => b.members.iter().copied().collect(),
            _ => Vec::new(),
        };
        self.visit_list(members);
    }

    /// `visitNamedType`.
    fn visit_named_type(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_named_type_impl();
        let (import_prefix, name_token, type_arguments, question) =
            (n.import_prefix, n.name, n.type_arguments, n.question);
        let name = ast.tokens.lexeme_string(name_token);
        let element: Option<ScopeElement>;
        if import_prefix != NO_NODE {
            let prefix_name = ast.tokens.lexeme_string(ast.node(import_prefix).as_import_prefix_reference_impl().name);
            let prefix_element = self.types.scopes.lookup(self.store, self.scope, &prefix_name).getter;
            element = match prefix_element {
                Some(ScopeElement::Prefix(p)) => self.types.scopes.lookup_prefix(p, &name).getter,
                _ => None,
            };
        } else {
            if name == "void" {
                self.types.node_types.insert((self.unit, node), TypeImpl::Void);
                return;
            }
            element = self.types.scopes.lookup(self.store, self.scope, &name).getter;
        }
        self.types.node_elements.insert((self.unit, node), element.clone());

        self.visit_opt(type_arguments);

        let nullability_suffix = nullability(question);
        let t = match element {
            None => TypeImpl::Invalid,
            Some(ScopeElement::Element(e)) if self.store.element(e).kind == ElementKind::TYPE_PARAMETER => {
                // `instantiateTypeParameter`.
                if self.is_in_static_member && self.store.is_instance_type_parameter(e) {
                    TypeImpl::Invalid
                } else {
                    TypeImpl::type_parameter(e, nullability_suffix)
                }
            }
            Some(element) => {
                // `NamedTypeBuilder.of`.
                let arguments = if type_arguments != NO_NODE {
                    ast.node(type_arguments)
                        .as_type_argument_list_impl()
                        .arguments
                        .iter()
                        .map(|&a| self.types.node_type(self.unit, a))
                        .collect()
                } else {
                    Vec::new()
                };
                let element_id = match element {
                    ScopeElement::Element(e) => Some(e),
                    _ => None,
                };
                self.add_type_builder(TypeBuilder::Named(NamedTypeBuilder {
                    element: element_id.unwrap_or(crate::src::dart::element::element::NO_ELEMENT),
                    arguments,
                    nullability_suffix,
                    node: Some((self.unit, node)),
                    type_: None,
                }))
            }
        };
        self.types.node_types.insert((self.unit, node), t);
    }

    /// `FunctionTypeBuilder.of`.
    fn function_type_builder_of(&mut self, node: NodeId, nullability_suffix: NullabilitySuffix) -> FunctionTypeBuilder {
        let n = self.ast.node(node).as_generic_function_type_impl();
        let (type_parameters, parameters, return_type) = (n.type_parameters, n.parameters, n.return_type);
        FunctionTypeBuilder {
            type_parameters: self.type_parameters_of_list(type_parameters),
            formal_parameters: self.get_parameters(parameters),
            return_type: self.node_type_or_dynamic(return_type),
            nullability_suffix,
            node: Some((self.unit, node)),
            type_: None,
        }
    }

    /// `_getTypeParameters`.
    fn type_parameters_of_list(&self, list: NodeId) -> Vec<ElementId> {
        if list == NO_NODE {
            return Vec::new();
        }
        self.ast
            .node(list)
            .as_type_parameter_list_impl()
            .type_parameters
            .iter()
            .map(|&p| self.element_of_node(p))
            .collect()
    }

    /// `_getNodeType`.
    fn node_type_or_dynamic(&self, node: NodeId) -> TypeImpl {
        if node == NO_NODE {
            TypeImpl::Dynamic
        } else {
            self.types.node_type(self.unit, node)
        }
    }

    /// `FunctionTypeBuilder.getParameters`: synthetic formal parameters with
    /// the parameters' names, types and kinds.
    fn get_parameters(&mut self, list: NodeId) -> Vec<FormalParameter> {
        if list == NO_NODE {
            return Vec::new();
        }
        let ast = self.ast;
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
        all.into_iter()
            .map(|p| {
                let (name, kind) = formal_name_and_kind(ast, p);
                let type_ = self.get_parameter_type(p);
                FormalParameter { name, type_, kind }
            })
            .collect()
    }

    /// `_getParameterType`.
    fn get_parameter_type(&mut self, node: NodeId) -> TypeImpl {
        let (type_, suffix) = formal_type_and_suffix(self.ast, node);
        if suffix == NO_NODE {
            return self.node_type_or_dynamic(type_);
        }
        let s = self.ast.node(suffix).as_function_typed_formal_parameter_suffix_impl();
        let (type_parameters, formal_parameters, question) = (s.type_parameters, s.formal_parameters, s.question);
        let builder = FunctionTypeBuilder {
            type_parameters: self.type_parameters_of_list(type_parameters),
            formal_parameters: self.get_parameters(formal_parameters),
            return_type: self.node_type_or_dynamic(type_),
            nullability_suffix: nullability(question),
            node: None,
            type_: None,
        };
        // Built when the enclosing type is built, not by `TypesBuilder`.
        let id = self.store.type_builders.len() as BuilderId;
        self.store.type_builders.push(TypeBuilder::Function(builder));
        TypeImpl::Builder(id)
    }
}

/// `_getNullabilitySuffix`.
fn nullability(question: fe_analyzer_shared::scanner::token::TokenId) -> NullabilitySuffix {
    if question != fe_analyzer_shared::scanner::token::NO_TOKEN {
        NullabilitySuffix::question
    } else {
        NullabilitySuffix::none
    }
}

fn formal_type_and_suffix(ast: Ast<'_>, node: NodeId) -> (NodeId, NodeId) {
    match ast.node(node) {
        AstNodeImpl::RegularFormalParameterImpl(p) => (p.type_, p.function_typed_suffix),
        AstNodeImpl::FieldFormalParameterImpl(p) => (p.type_, p.function_typed_suffix),
        AstNodeImpl::SuperFormalParameterImpl(p) => (p.type_, p.function_typed_suffix),
        other => panic!("{} is not a FormalParameterImpl", other.runtime_type()),
    }
}

/// `parameter.name?.lexeme.nullIfEmpty` and `parameter.kind`.
fn formal_name_and_kind(
    ast: Ast<'_>,
    node: NodeId,
) -> (Option<Rc<str>>, crate::src::generated::utilities_dart::ParameterKind) {
    let (name, kind) = match ast.node(node) {
        AstNodeImpl::RegularFormalParameterImpl(p) => (p.name, p.kind),
        AstNodeImpl::FieldFormalParameterImpl(p) => (p.name, p.kind),
        AstNodeImpl::SuperFormalParameterImpl(p) => (p.name, p.kind),
        other => panic!("{} is not a FormalParameterImpl", other.runtime_type()),
    };
    let name = if name == fe_analyzer_shared::scanner::token::NO_TOKEN {
        None
    } else {
        let s = ast.tokens.lexeme_string(name);
        if s.is_empty() { None } else { Some(Rc::from(s)) }
    };
    (name, kind)
}

/// The parts of an executable declaration the resolver reads.
struct ExecutableParts {
    is_static: bool,
    top_level: bool,
    return_type: NodeId,
    type_parameters: NodeId,
    formal_parameters: NodeId,
}

fn executable_parts(ast: Ast<'_>, node: NodeId) -> ExecutableParts {
    use fe_analyzer_shared::scanner::token::NO_TOKEN;
    match ast.node(node) {
        AstNodeImpl::MethodDeclaration2Impl(n) => ExecutableParts {
            is_static: n.static_keyword != NO_TOKEN,
            top_level: false,
            return_type: n.return_type,
            type_parameters: n.type_parameters,
            formal_parameters: n.formal_parameters,
        },
        AstNodeImpl::GetterDeclarationImpl(n) => ExecutableParts {
            is_static: n.static_keyword != NO_TOKEN,
            top_level: false,
            return_type: n.return_type,
            type_parameters: NO_NODE,
            formal_parameters: n.recovery_formal_parameters,
        },
        AstNodeImpl::SetterDeclarationImpl(n) => ExecutableParts {
            is_static: n.static_keyword != NO_TOKEN,
            top_level: false,
            return_type: n.return_type,
            type_parameters: NO_NODE,
            formal_parameters: n.formal_parameters,
        },
        AstNodeImpl::OperatorDeclarationImpl(n) => ExecutableParts {
            is_static: false,
            top_level: false,
            return_type: n.return_type,
            type_parameters: n.recovery_type_parameters,
            formal_parameters: n.formal_parameters,
        },
        AstNodeImpl::TopLevelFunctionDeclarationImpl(n) => ExecutableParts {
            is_static: false,
            top_level: true,
            return_type: n.return_type,
            type_parameters: n.type_parameters,
            formal_parameters: n.formal_parameters,
        },
        AstNodeImpl::TopLevelGetterDeclarationImpl(n) => ExecutableParts {
            is_static: false,
            top_level: true,
            return_type: n.return_type,
            type_parameters: NO_NODE,
            formal_parameters: n.recovery_formal_parameters,
        },
        AstNodeImpl::TopLevelSetterDeclarationImpl(n) => ExecutableParts {
            is_static: false,
            top_level: true,
            return_type: n.return_type,
            type_parameters: NO_NODE,
            formal_parameters: n.formal_parameters,
        },
        other => panic!("{} is not an executable declaration", other.runtime_type()),
    }
}
