// Port of lib/src/summary2/type_builder.dart, with the state of its three
// subclasses: NamedTypeBuilder (named_type_builder.dart), FunctionTypeBuilder
// (function_type_builder.dart) and RecordTypeBuilder (record_type_builder.dart).
//
// A builder lives in `ElementStore::type_builders` and is named by its id
// from `TypeImpl::Builder`. `build` is ported with the rest of the linker's
// type resolution; this file holds the builders' data and the members a
// `TypeImpl` forwards to them (`nullabilitySuffix`, `withNullability`).

use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use fe_analyzer_shared::scanner::token::NO_TOKEN;

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentId, LibraryId, NO_ELEMENT, UnitId};
use crate::src::dart::element::r#type::{BuilderId, FormalParameter, FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use crate::src::dart::element::type_algebra::{substitute, Substitution};

/// `TypeBuilder` and its subclasses.
#[derive(Clone, Debug)]
pub enum TypeBuilder {
    Named(NamedTypeBuilder),
    Function(FunctionTypeBuilder),
    Record(RecordTypeBuilder),
}

/// `NamedTypeBuilder`.
#[derive(Clone, Debug)]
pub struct NamedTypeBuilder {
    pub element: ElementId,
    pub arguments: Vec<TypeImpl>,
    pub nullability_suffix: NullabilitySuffix,
    /// The `NamedType` this builder is for, with its unit; `None` once
    /// detached.
    pub node: Option<(UnitId, NodeId)>,
    /// `_type`: the built type, once `build` has run.
    pub type_: Option<TypeImpl>,
}

/// `FunctionTypeBuilder`.
#[derive(Clone, Debug)]
pub struct FunctionTypeBuilder {
    pub type_parameters: Vec<ElementId>,
    pub formal_parameters: Vec<FormalParameter>,
    pub return_type: TypeImpl,
    pub nullability_suffix: NullabilitySuffix,
    /// The `GenericFunctionType` this builder is for, with its unit.
    pub node: Option<(UnitId, NodeId)>,
    pub type_: Option<TypeImpl>,
}

/// `RecordTypeBuilder`.
#[derive(Clone, Debug)]
pub struct RecordTypeBuilder {
    pub node: (UnitId, NodeId),
    /// `fieldTypes`: first the positional fields, then the named ones.
    pub field_types: Vec<TypeImpl>,
    /// The names of the named fields, in the order of `field_types`' tail.
    pub field_names: Vec<Rc<str>>,
    pub nullability_suffix: NullabilitySuffix,
    /// `_isBuilding`.
    pub is_building: bool,
    pub type_: Option<TypeImpl>,
}

impl TypeBuilder {
    /// `TypeBuilder.nullabilitySuffix`.
    pub fn nullability_suffix(&self) -> NullabilitySuffix {
        match self {
            TypeBuilder::Named(b) => b.nullability_suffix,
            TypeBuilder::Function(b) => b.nullability_suffix,
            TypeBuilder::Record(b) => b.nullability_suffix,
        }
    }
}

/// `withNullability` of the three builders: the same builder when the
/// nullability is unchanged, otherwise a copy with the new nullability.
/// `RecordTypeBuilder` has no `withNullability` of its own, so the call
/// reaches `TypeBuilder.noSuchMethod` and throws.
pub fn with_nullability(store: &mut ElementStore, id: BuilderId, nullability_suffix: NullabilitySuffix) -> TypeImpl {
    let builder = &store.type_builders[id as usize];
    if builder.nullability_suffix() == nullability_suffix {
        return TypeImpl::Builder(id);
    }
    let copy = match builder {
        TypeBuilder::Named(b) => TypeBuilder::Named(NamedTypeBuilder {
            element: b.element,
            arguments: b.arguments.clone(),
            nullability_suffix,
            node: b.node,
            type_: None,
        }),
        TypeBuilder::Function(b) => TypeBuilder::Function(FunctionTypeBuilder {
            type_parameters: b.type_parameters.clone(),
            formal_parameters: b.formal_parameters.clone(),
            return_type: b.return_type.clone(),
            nullability_suffix,
            node: b.node,
            type_: None,
        }),
        TypeBuilder::Record(_) => panic!("NoSuchMethodError: RecordTypeBuilder.withNullability"),
    };
    let new_id = store.type_builders.len() as BuilderId;
    store.type_builders.push(copy);
    TypeImpl::Builder(new_id)
}

/// What `build` reads besides the store: the types of type annotations
/// (`node.type`, which `build` also sets), the trees of the units being
/// linked (for typedefs, `Linker.getLinkingNode`), the libraries being
/// linked (`Linker.isLinkingElement`), and whether each of them enables
/// non-function type aliases.
pub struct BuildContext<'a> {
    pub store: &'a mut ElementStore,
    pub node_types: &'a mut HashMap<(UnitId, NodeId), TypeImpl>,
    pub asts: &'a HashMap<UnitId, Ast<'a>>,
    pub linking_libraries: &'a HashSet<LibraryId>,
    pub nonfunction_type_aliases: &'a HashMap<LibraryId, bool>,
    /// `node.declaredFragment`.
    pub fragment_of_node: &'a HashMap<(UnitId, NodeId), FragmentId>,
    /// `namedType.element`, as the reference resolver found it.
    pub node_elements: &'a HashMap<(UnitId, NodeId), Option<crate::src::dart::element::scope::ScopeElement>>,
    /// Whether each linking library has `inference-using-bounds`.
    pub inference_using_bounds: &'a HashMap<LibraryId, bool>,
}

impl BuildContext<'_> {
    /// `_buildType`: build [type_] if it is a builder.
    pub fn build_type(&mut self, type_: &TypeImpl) -> TypeImpl {
        match type_ {
            TypeImpl::Builder(id) => self.build(*id),
            other => other.clone(),
        }
    }

    fn nonfunction_type_aliases_enabled(&self, element: ElementId) -> bool {
        let library = self.store.element(element).library;
        *self.nonfunction_type_aliases.get(&library).unwrap_or(&true)
    }

    /// `TypeBuilder.build`.
    pub fn build(&mut self, id: BuilderId) -> TypeImpl {
        let builder = self.store.type_builders[id as usize].clone();
        let (type_, node) = match builder {
            TypeBuilder::Named(b) => {
                if let Some(t) = b.type_ {
                    return t;
                }
                (self.build_named(&b), b.node)
            }
            TypeBuilder::Function(b) => {
                if let Some(t) = b.type_ {
                    return t;
                }
                (self.build_function(&b), b.node)
            }
            TypeBuilder::Record(b) => {
                if let Some(t) = b.type_ {
                    return t;
                }
                let t = if b.is_building {
                    self.build_record(&b, true)
                } else {
                    if let TypeBuilder::Record(r) = &mut self.store.type_builders[id as usize] {
                        r.is_building = true;
                    }
                    let t = self.build_record(&b, false);
                    if let TypeBuilder::Record(r) = &mut self.store.type_builders[id as usize] {
                        r.is_building = false;
                    }
                    t
                };
                (t, Some(b.node))
            }
        };
        match &mut self.store.type_builders[id as usize] {
            TypeBuilder::Named(b) => b.type_ = Some(type_.clone()),
            TypeBuilder::Function(b) => b.type_ = Some(type_.clone()),
            TypeBuilder::Record(b) => b.type_ = Some(type_.clone()),
        }
        if let Some(key) = node {
            self.node_types.insert(key, type_.clone());
        }
        type_
    }

    /// `NamedTypeBuilder.build`.
    fn build_named(&mut self, b: &NamedTypeBuilder) -> TypeImpl {
        if b.element == NO_ELEMENT {
            return TypeImpl::Invalid;
        }
        let kind = self.store.element(b.element).kind;
        match kind {
            ElementKind::CLASS | ElementKind::ENUM | ElementKind::MIXIN | ElementKind::EXTENSION_TYPE => {
                let parameters = self.type_parameters(b.element);
                let arguments = self.build_arguments(b, &parameters);
                TypeImpl::interface(b.element, arguments, b.nullability_suffix)
            }
            ElementKind::TYPE_ALIAS => {
                let aliased_type = self.get_aliased_type(b.element);
                let parameters = self.type_parameters(b.element);
                let arguments = self.build_arguments(b, &parameters);
                self.store.elements[b.element as usize].type_ = Some(aliased_type);
                self.instantiate_type_alias(b.element, &parameters, arguments, b.nullability_suffix)
            }
            ElementKind::NEVER => TypeImpl::Never(b.nullability_suffix),
            ElementKind::TYPE_PARAMETER => TypeImpl::type_parameter(b.element, b.nullability_suffix),
            ElementKind::DYNAMIC => TypeImpl::Dynamic,
            _ => TypeImpl::Invalid,
        }
    }

    /// `element.typeParameters`.
    pub fn type_parameters(&self, element: ElementId) -> Vec<ElementId> {
        let first = self.store.element(element).first_fragment;
        self.store
            .fragment(first)
            .type_parameters
            .iter()
            .map(|&f| self.store.fragment(f).element)
            .collect()
    }

    /// `_buildArguments`.
    fn build_arguments(&mut self, b: &NamedTypeBuilder, parameters: &[ElementId]) -> Vec<TypeImpl> {
        if parameters.is_empty() {
            Vec::new()
        } else if !b.arguments.is_empty() {
            if b.arguments.len() == parameters.len() {
                b.arguments.iter().map(|t| self.build_type(t)).collect()
            } else {
                vec![TypeImpl::Dynamic; parameters.len()]
            }
        } else {
            parameters
                .iter()
                .map(|&p| {
                    let default_type = self
                        .store
                        .types(p)
                        .and_then(|t| t.default_type.clone())
                        .unwrap_or_else(|| panic!("the default type of a type parameter is not computed"));
                    self.build_type(&default_type)
                })
                .collect()
        }
    }

    /// `TypeAliasElementImpl.instantiateImpl`, without the alias
    /// information `getDisplayString(preferTypeAlias: true)` would read.
    pub fn instantiate_type_alias(
        &mut self,
        element: ElementId,
        parameters: &[ElementId],
        arguments: Vec<TypeImpl>,
        nullability_suffix: NullabilitySuffix,
    ) -> TypeImpl {
        let has_self_reference = self.store.types(element).map(|t| t.has_self_reference).unwrap_or(false);
        if has_self_reference {
            return if self.nonfunction_type_aliases_enabled(element) {
                TypeImpl::Dynamic
            } else {
                error_function_type(nullability_suffix)
            };
        }
        let aliased = self.store.element(element).type_.clone().unwrap_or(TypeImpl::Dynamic);
        let substitution = Substitution::from_pairs(parameters.to_vec(), arguments);
        let type_ = substitute(self.store, &substitution, &aliased);
        let result_nullability = if type_.nullability_suffix(self.store) == NullabilitySuffix::question {
            NullabilitySuffix::question
        } else {
            nullability_suffix
        };
        type_.with_nullability(self.store, result_nullability)
    }

    /// `_getAliasedType`.
    fn get_aliased_type(&mut self, element: ElementId) -> TypeImpl {
        let library = self.store.element(element).library;
        if !self.linking_libraries.contains(&library) {
            return self.store.element(element).type_.clone().unwrap_or(TypeImpl::Dynamic);
        }
        // Break a possible recursion.
        if let Some(existing) = self.store.element(element).type_.clone() {
            return existing;
        }
        self.store.elements[element as usize].type_ = Some(TypeImpl::Dynamic);

        let first = self.store.element(element).first_fragment;
        let (unit, node) = (self.store.fragment(first).unit, self.store.fragment(first).node);
        let ast = self.asts[&unit];
        let result = match ast.node(node) {
            AstNodeImpl::FunctionTypeAlias2Impl(n) => {
                let (return_type, parameters) = (n.return_type, n.parameters);
                let return_type = self.build_node_type(unit, return_type);
                let formal_parameters = self.formal_parameters(unit, parameters);
                TypeImpl::Function(Rc::new(FunctionTypeImpl::new(
                    Vec::new(),
                    formal_parameters,
                    return_type,
                    NullabilitySuffix::none,
                )))
            }
            AstNodeImpl::GenericTypeAlias2Impl(n) => {
                let aliased_type_node = n.type_;
                // `_buildAliasedType`.
                if self.nonfunction_type_aliases_enabled(element) {
                    self.build_node_type(unit, aliased_type_node)
                } else if matches!(ast.node(aliased_type_node), AstNodeImpl::GenericFunctionTypeImpl(_)) {
                    self.build_node_type(unit, aliased_type_node)
                } else {
                    error_function_type(NullabilitySuffix::none)
                }
            }
            other => panic!("StateError: ({}) {element}", other.runtime_type()),
        };
        self.store.elements[element as usize].type_ = Some(result.clone());
        result
    }

    /// `_buildNodeType`.
    fn build_node_type(&mut self, unit: UnitId, node: NodeId) -> TypeImpl {
        if node == NO_NODE {
            return TypeImpl::Dynamic;
        }
        let t = self.node_types[&(unit, node)].clone();
        self.build_type(&t)
    }

    /// `NamedTypeBuilder._formalParameters`: synthetic formal parameters
    /// named `name ?? ''`.
    fn formal_parameters(&mut self, unit: UnitId, list: NodeId) -> Vec<FormalParameter> {
        let ast = self.asts[&unit];
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
                let (name, kind, type_node, suffix) = match ast.node(p) {
                    AstNodeImpl::RegularFormalParameterImpl(f) => (f.name, f.kind, f.type_, f.function_typed_suffix),
                    other => panic!("UnimplementedError: ({}) {p}", other.runtime_type()),
                };
                let name = if name == NO_TOKEN {
                    Rc::from("")
                } else {
                    Rc::from(ast.tokens.lexeme_string(name))
                };
                // `_buildFormalParameterType`.
                let type_ = if suffix != NO_NODE {
                    let s = ast.node(suffix).as_function_typed_formal_parameter_suffix_impl();
                    let (type_parameters, formal_parameters, question) =
                        (s.type_parameters, s.formal_parameters, s.question);
                    let return_type = self.build_node_type(unit, type_node);
                    let type_parameters = self.type_parameters_of_list(unit, type_parameters);
                    let parameters = self.formal_parameters(unit, formal_parameters);
                    let suffix = if question != NO_TOKEN {
                        NullabilitySuffix::question
                    } else {
                        NullabilitySuffix::none
                    };
                    TypeImpl::Function(Rc::new(FunctionTypeImpl::new(type_parameters, parameters, return_type, suffix)))
                } else {
                    self.build_node_type(unit, type_node)
                };
                FormalParameter {
                    name: Some(name),
                    type_,
                    kind,
                }
            })
            .collect()
    }

    /// `_typeParameters`.
    fn type_parameters_of_list(&self, unit: UnitId, list: NodeId) -> Vec<ElementId> {
        if list == NO_NODE {
            return Vec::new();
        }
        let ast = self.asts[&unit];
        ast.node(list)
            .as_type_parameter_list_impl()
            .type_parameters
            .iter()
            .map(|&p| {
                let fragment = self.fragment_of_node[&(unit, p)];
                self.store.fragment(fragment).element
            })
            .collect()
    }

    /// `FunctionTypeBuilder.build`.
    fn build_function(&mut self, b: &FunctionTypeBuilder) -> TypeImpl {
        for &p in &b.type_parameters {
            if let Some(bound) = self.store.element(p).type_.clone() {
                let built = self.build_type(&bound);
                self.store.elements[p as usize].type_ = Some(built);
            }
        }
        let formal_parameters: Vec<FormalParameter> = b
            .formal_parameters
            .iter()
            .map(|p| {
                let t = self.build_type(&p.type_);
                p.copy_with(Some(t), None)
            })
            .collect();
        let return_type = self.build_type(&b.return_type);
        let type_ = FunctionTypeImpl::new(b.type_parameters.clone(), formal_parameters, return_type, b.nullability_suffix);
        // `getFreshTypeParameters(typeParameters).applyToFunctionType(type)`.
        TypeImpl::Function(Rc::new(fresh_type_parameters(self.store, &type_)))
    }

    /// `RecordTypeBuilder._buildRecordType`.
    fn build_record(&mut self, b: &RecordTypeBuilder, recursion_found: bool) -> TypeImpl {
        let named_count = b.field_names.len();
        let positional_count = b.field_types.len() - named_count;
        let mut fields = b.field_types.iter();
        let mut next = |this: &mut Self| {
            let t = fields.next().unwrap();
            if recursion_found { TypeImpl::Dynamic } else { this.build_type(t) }
        };
        let positional: Vec<TypeImpl> = (0..positional_count).map(|_| next(self)).collect();
        let named: Vec<(Rc<str>, TypeImpl)> = b.field_names.iter().map(|n| (n.clone(), next(self))).collect();
        TypeImpl::Record(Rc::new(RecordTypeImpl::new(positional, named, b.nullability_suffix)))
    }
}

/// `_errorFunctionType`: `dynamic Function()`.
pub fn error_function_type(nullability_suffix: NullabilitySuffix) -> TypeImpl {
    TypeImpl::Function(Rc::new(FunctionTypeImpl::new(Vec::new(), Vec::new(), TypeImpl::Dynamic, nullability_suffix)))
}

/// `getFreshTypeParameters(type.typeParameters).applyToFunctionType(type)`:
/// [type_] with fresh copies of its type parameters, whose bounds are
/// substituted.
pub fn fresh_type_parameters(store: &mut ElementStore, type_: &FunctionTypeImpl) -> FunctionTypeImpl {
    if type_.type_parameters.is_empty() {
        return type_.clone();
    }
    let fresh: Vec<ElementId> = type_.type_parameters.iter().map(|&p| store.fresh_copy_type_parameter(p)).collect();
    let substitution = Substitution::from_pairs(
        type_.type_parameters.clone(),
        fresh.iter().map(|&f| TypeImpl::type_parameter(f, NullabilitySuffix::none)).collect(),
    );
    for (i, &p) in type_.type_parameters.iter().enumerate() {
        if let Some(bound) = store.element(p).type_.clone() {
            let new_bound = substitute(store, &substitution, &bound);
            store.elements[fresh[i] as usize].type_ = Some(new_bound);
        }
    }
    let formal_parameters = type_
        .formal_parameters
        .iter()
        .map(|p| {
            let t = substitute(store, &substitution, &p.type_);
            p.copy_with(Some(t), None)
        })
        .collect();
    let return_type = substitute(store, &substitution, &type_.return_type);
    FunctionTypeImpl::new(fresh, formal_parameters, return_type, type_.nullability_suffix)
}
