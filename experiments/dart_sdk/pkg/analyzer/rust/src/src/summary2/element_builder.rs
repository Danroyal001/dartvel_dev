// Port of lib/src/summary2/element_builder.dart: `FragmentBuilder`, which
// creates a fragment for every declaration of a unit, and `ElementBuilder`,
// which joins the fragments of a library into elements (an element per
// declaration, and per augmentation chain).
//
// The fragments get their offsets (`firstTokenOffset`, `nameOffset`) from
// their nodes when they are created; upstream writes them into the unit's
// informative data and `InformativeDataApplier` copies them back, pairing
// each fragment with the node it came from, which gives the same numbers.
// A fragment's default value is kept as the source it is written as
// (`defaultValueCode`) rather than as the node.
//
// Type annotations are visited as upstream visits them, so that generic
// function types and the formal and type parameters of function-typed
// formal parameters get their fragments and elements.
//
// Not ported yet: metadata.

use std::collections::HashMap;
use std::rc::Rc;

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId};
use fe_analyzer_shared::scanner::token_impl::corresponding_public_name;

use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::ast::invokes_super_self::invokes_super_self;
use crate::src::dart::element::element::{
    ElementId, ElementKind, ElementStore, FragmentFlag, FragmentId, FragmentImpl, FragmentKind,
    LibraryId, NO_ELEMENT, NO_FRAGMENT, UnitId,
};
use crate::src::generated::utilities_dart::ParameterKind;
use crate::src::summary2::not_serializable_nodes::serializable_source;

use FragmentFlag::*;

/// The state of `LibraryBuilder` that the builders below fill.
#[derive(Debug, Default)]
pub struct LibraryFragments {
    /// `_topFragments`: the top fragments of each unit, in AST order.
    pub top_fragments: Vec<(UnitId, Vec<FragmentId>)>,
    /// `_parentChildFragments`.
    pub parent_child_fragments: HashMap<FragmentId, Vec<FragmentId>>,
    /// `_declaredReferences`: the local declarations, by lookup name, in
    /// the order they were first declared.
    pub declared: Vec<(Rc<str>, ElementId)>,
    pub declared_index: HashMap<Rc<str>, usize>,
}

impl LibraryFragments {
    /// `LibraryBuilder.addTopFragment`.
    pub fn add_top_fragment(&mut self, unit: UnitId, fragment: FragmentId) {
        match self.top_fragments.iter_mut().find(|(u, _)| *u == unit) {
            Some((_, list)) => list.push(fragment),
            None => self.top_fragments.push((unit, vec![fragment])),
        }
    }

    /// `LibraryBuilder.addChildFragment`.
    pub fn add_child_fragment(&mut self, store: &mut ElementStore, parent: FragmentId, child: FragmentId) {
        store.fragment_mut(child).enclosing_fragment = parent;
        self.parent_child_fragments.entry(parent).or_default().push(child);
    }

    /// `LibraryBuilder.declare`.
    pub fn declare(&mut self, store: &ElementStore, element: ElementId) {
        if let Some(lookup_name) = store.lookup_name(element) {
            match self.declared_index.get(&lookup_name) {
                Some(&index) => self.declared[index].1 = element,
                None => {
                    self.declared_index.insert(lookup_name.clone(), self.declared.len());
                    self.declared.push((lookup_name, element));
                }
            }
        }
    }
}

/// `_EnclosingContext`.
struct EnclosingContext {
    fragment: FragmentId,
    formal_parameters: Vec<FragmentId>,
    type_parameters: Vec<FragmentId>,
}

/// `DeclaringFormalParameterInfo`: the field and the formal parameter
/// fragments a declaring formal parameter of a primary constructor creates.
#[derive(Clone, Copy)]
struct DeclaringFormalParameterInfo {
    formal_fragment: FragmentId,
}

/// `FragmentBuilder`.
pub struct FragmentBuilder<'a> {
    store: &'a mut ElementStore,
    library: &'a mut LibraryFragments,
    ast: Ast<'a>,
    unit: UnitId,
    enclosing: EnclosingContext,
    /// `Linker.declaringFormalParameters`, for this unit's nodes.
    declaring_formal_parameters: HashMap<NodeId, DeclaringFormalParameterInfo>,
    /// Whether the library's feature set enables primary constructors and
    /// private named parameters.
    pub primary_constructors: bool,
    pub private_named_parameters: bool,
}

fn name_of(ast: Ast<'_>, token: TokenId) -> Option<Rc<str>> {
    if token == NO_TOKEN || ast.tokens.is_synthetic(token) {
        return None;
    }
    Some(Rc::from(ast.tokens.lexeme_string(token)))
}

/// `Token.offsetIfNotEmpty`.
fn offset_if_not_empty(ast: Ast<'_>, token: TokenId) -> Option<u32> {
    if token == NO_TOKEN || ast.tokens.lexeme(token).is_empty() {
        None
    } else {
        Some(ast.tokens.offset(token) as u32)
    }
}

/// `FunctionBody.isAsynchronous` and `isGenerator`.
fn body_kind(ast: Ast<'_>, body: NodeId) -> (bool, bool) {
    let (keyword, star) = match ast.node(body) {
        AstNodeImpl::BlockFunctionBodyImpl(b) => (b.keyword, b.star),
        AstNodeImpl::ExpressionFunctionBodyImpl(b) => (b.keyword, b.star),
        _ => return (false, false),
    };
    let is_async = keyword != NO_TOKEN && ast.tokens.lexeme_string(keyword) == "async";
    (is_async, star != NO_TOKEN)
}

fn is_empty_function_body(ast: Ast<'_>, body: NodeId) -> bool {
    matches!(ast.node(body), AstNodeImpl::EmptyFunctionBodyImpl(_))
}

/// `FormalParameterImpl.functionTypedSuffix`, `type`, `name`,
/// `defaultClause` and `metadata`'s owner, for the three formal parameter
/// classes.
fn formal_parts(ast: Ast<'_>, node: NodeId) -> (NodeId, NodeId, TokenId, NodeId, TokenId, ParameterKind) {
    match ast.node(node) {
        AstNodeImpl::RegularFormalParameterImpl(p) => {
            (p.type_, p.function_typed_suffix, p.name, p.default_clause, p.covariant_keyword, p.kind)
        }
        AstNodeImpl::FieldFormalParameterImpl(p) => {
            (p.type_, p.function_typed_suffix, p.name, p.default_clause, p.covariant_keyword, p.kind)
        }
        AstNodeImpl::SuperFormalParameterImpl(p) => {
            (p.type_, p.function_typed_suffix, p.name, p.default_clause, p.covariant_keyword, p.kind)
        }
        other => panic!("{} is not a FormalParameterImpl", other.runtime_type()),
    }
}

/// `RegularFormalParameterImpl.finalOrVarKeyword` is not null.
fn has_final_or_var_keyword(ast: Ast<'_>, node: NodeId) -> bool {
    match ast.node(node) {
        AstNodeImpl::RegularFormalParameterImpl(p) => {
            let keyword = p.const_final_or_var_keyword;
            keyword != NO_TOKEN && matches!(ast.tokens.lexeme_string(keyword).as_str(), "final" | "var")
        }
        _ => false,
    }
}

fn is_final_keyword(ast: Ast<'_>, keyword: TokenId) -> bool {
    keyword != NO_TOKEN && ast.tokens.lexeme_string(keyword) == "final"
}

fn is_named(kind: ParameterKind) -> bool {
    matches!(kind, ParameterKind::NAMED | ParameterKind::NAMED_REQUIRED)
}

impl<'a> FragmentBuilder<'a> {
    pub fn new(
        store: &'a mut ElementStore,
        library: &'a mut LibraryFragments,
        ast: Ast<'a>,
        unit: UnitId,
    ) -> FragmentBuilder<'a> {
        FragmentBuilder {
            store,
            library,
            ast,
            unit,
            enclosing: EnclosingContext {
                fragment: NO_FRAGMENT,
                formal_parameters: Vec::new(),
                type_parameters: Vec::new(),
            },
            declaring_formal_parameters: HashMap::new(),
            primary_constructors: true,
            private_named_parameters: true,
        }
    }

    fn new_fragment(&mut self, kind: FragmentKind, name: Option<Rc<str>>) -> FragmentId {
        let mut fragment = FragmentImpl::new(kind, name);
        fragment.unit = self.unit;
        self.store.add_fragment(fragment)
    }

    fn f(&mut self, id: FragmentId) -> &mut FragmentImpl {
        self.store.fragment_mut(id)
    }

    fn set_offsets(&mut self, id: FragmentId, node: NodeId, name: TokenId) {
        let first = self.ast.offset(node) as u32;
        let name_offset = offset_if_not_empty(self.ast, name);
        let f = self.f(id);
        f.first_token_offset = Some(first);
        f.name_offset = name_offset;
        f.node = node;
    }

    /// `buildDeclarationFragments`.
    pub fn build_declaration_fragments(&mut self, unit: NodeId) {
        let declarations = self.ast.node(unit).as_compilation_unit_impl().declarations2.clone();
        for declaration in declarations {
            self.visit(declaration);
        }
    }

    fn with_enclosing<R>(&mut self, fragment: FragmentId, f: impl FnOnce(&mut Self) -> R) -> (R, EnclosingContext) {
        let previous = std::mem::replace(
            &mut self.enclosing,
            EnclosingContext {
                fragment,
                formal_parameters: Vec::new(),
                type_parameters: Vec::new(),
            },
        );
        let result = f(self);
        let context = std::mem::replace(&mut self.enclosing, previous);
        (result, context)
    }

    fn add_child_fragment(&mut self, child: FragmentId) {
        let parent = self.enclosing.fragment;
        self.library.add_child_fragment(self.store, parent, child);
    }

    /// `_EnclosingContext.addParameter`.
    fn add_parameter(&mut self, fragment: FragmentId) {
        let parent = self.enclosing.fragment;
        self.f(fragment).enclosing_fragment = parent;
        self.enclosing.formal_parameters.push(fragment);
    }

    /// The `accept2` of the declarations and members this builder visits.
    fn visit(&mut self, node: NodeId) {
        let ast = self.ast;
        match ast.node(node) {
            AstNodeImpl::ClassDeclaration2Impl(_) => self.visit_class_declaration2(node),
            AstNodeImpl::ClassTypeAlias2Impl(_) => self.visit_class_type_alias2(node),
            AstNodeImpl::ConstructorDeclaration2Impl(_) => self.visit_constructor_declaration2(node),
            AstNodeImpl::EnumDeclaration2Impl(_) => self.visit_enum_declaration2(node),
            AstNodeImpl::ExtensionDeclaration2Impl(_) => self.visit_extension_declaration2(node),
            AstNodeImpl::ExtensionTypeDeclaration2Impl(_) => self.visit_extension_type_declaration2(node),
            AstNodeImpl::FieldsDeclarationImpl(_) => self.visit_fields_declaration(node),
            AstNodeImpl::FunctionTypeAlias2Impl(_) => self.visit_function_type_alias2(node),
            AstNodeImpl::GenericTypeAlias2Impl(_) => self.visit_generic_type_alias2(node),
            AstNodeImpl::GetterDeclarationImpl(_) => self.visit_method_like(node, FragmentKind::Getter),
            AstNodeImpl::MethodDeclaration2Impl(_) => self.visit_method_like(node, FragmentKind::Method),
            AstNodeImpl::MixinDeclaration2Impl(_) => self.visit_mixin_declaration2(node),
            AstNodeImpl::OperatorDeclarationImpl(_) => self.visit_method_like(node, FragmentKind::Method),
            AstNodeImpl::PrimaryConstructorBody2Impl(_) => {}
            AstNodeImpl::SetterDeclarationImpl(_) => self.visit_method_like(node, FragmentKind::Setter),
            AstNodeImpl::TopLevelFunctionDeclarationImpl(_) => self.visit_top_level_function_declaration(node),
            AstNodeImpl::TopLevelGetterDeclarationImpl(_) => self.visit_top_level_accessor(node, FragmentKind::Getter),
            AstNodeImpl::TopLevelSetterDeclarationImpl(_) => self.visit_top_level_accessor(node, FragmentKind::Setter),
            AstNodeImpl::TopLevelVariablesDeclarationImpl(_) => self.visit_top_level_variables_declaration(node),
            other => panic!("ThrowingAstVisitor2: visit{} is not overridden", other.runtime_type()),
        }
    }

    /// `visitBlockInstanceDeclarationBody` and
    /// `visitSemicolonInstanceDeclarationBody`.
    fn visit_body(&mut self, body: NodeId) {
        match self.ast.node(body) {
            AstNodeImpl::BlockInstanceDeclarationBodyImpl(b) => {
                for member in b.members.clone() {
                    self.visit(member);
                }
            }
            AstNodeImpl::SemicolonInstanceDeclarationBodyImpl(_) => {}
            other => panic!("ThrowingAstVisitor2: visit{} is not overridden", other.runtime_type()),
        }
    }

    /// The members of the body of the declaration a primary constructor is
    /// in (`classMembers2`).
    fn class_members(&self, body: NodeId) -> Vec<NodeId> {
        match self.ast.node(body) {
            AstNodeImpl::BlockInstanceDeclarationBodyImpl(b) => b.members.clone(),
            AstNodeImpl::BlockEnumDeclarationBodyImpl(b) => b.members.clone(),
            _ => Vec::new(),
        }
    }

    /// `visitNameWithTypeParameters` and
    /// `visitPrimaryConstructorDeclaration`, for the name part of a class,
    /// an enum or an extension type.
    fn visit_name_part(&mut self, name_part: NodeId, declaration: NodeId, body: NodeId) {
        match self.ast.node(name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(n) => {
                let type_parameters = n.type_parameters;
                self.visit_type_parameter_list(type_parameters);
            }
            AstNodeImpl::PrimaryConstructorDeclarationImpl(_) => {
                self.visit_primary_constructor_declaration(name_part, declaration, body)
            }
            other => panic!("ThrowingAstVisitor2: visit{} is not overridden", other.runtime_type()),
        }
    }

    fn visit_class_declaration2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_class_declaration2_impl();
        let name_token = match ast.node(n.name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_name,
            AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_name,
            _ => NO_TOKEN,
        };
        let fragment = self.new_fragment(FragmentKind::Class, name_of(ast, name_token));
        self.set_offsets(fragment, node, name_token);
        let f = self.f(fragment);
        f.set_flag(classFragment_isAbstract, n.abstract_keyword != NO_TOKEN);
        f.set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);
        f.set_flag(classFragment_isBase, n.base_keyword != NO_TOKEN);
        f.set_flag(classFragment_isFinal, n.final_keyword != NO_TOKEN);
        f.set_flag(classFragment_isInterface, n.interface_keyword != NO_TOKEN);
        f.set_flag(classFragment_isMixinClass, n.mixin_keyword != NO_TOKEN);
        f.set_flag(classFragment_isSealed, n.sealed_keyword != NO_TOKEN);
        f.set_flag(classFragment_hasExtendsClause, n.extends_clause != NO_NODE);

        self.library.add_top_fragment(self.unit, fragment);

        let (name_part, body) = (n.name_part, n.body);
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_name_part(name_part, node, body);
            this.visit_body(body);
        });
        self.f(fragment).type_parameters = holder.type_parameters;
        self.visit_clause(n.extends_clause);
        self.visit_clause(n.with_clause);
        self.visit_clause(n.implements_clause);
    }

    fn visit_class_type_alias2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_class_type_alias2_impl();
        let fragment = self.new_fragment(FragmentKind::Class, name_of(ast, n.name));
        self.set_offsets(fragment, node, n.name);
        let f = self.f(fragment);
        f.set_flag(classFragment_isAbstract, n.abstract_keyword != NO_TOKEN);
        f.set_flag(classFragment_isBase, n.base_keyword != NO_TOKEN);
        f.set_flag(classFragment_isFinal, n.final_keyword != NO_TOKEN);
        f.set_flag(classFragment_isInterface, n.interface_keyword != NO_TOKEN);
        f.set_flag(classFragment_isMixinApplication, true);
        f.set_flag(classFragment_isMixinClass, n.mixin_keyword != NO_TOKEN);
        f.set_flag(classFragment_isSealed, n.sealed_keyword != NO_TOKEN);

        self.library.add_top_fragment(self.unit, fragment);

        let type_parameters = n.type_parameters;
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_type_parameter_list(type_parameters);
        });
        if type_parameters != NO_NODE {
            self.f(fragment).type_parameters = holder.type_parameters;
        }
        self.visit_type_annotation(n.superclass);
        self.visit_clause(n.with_clause);
        self.visit_clause(n.implements_clause);
    }

    fn visit_constructor_declaration2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_constructor_declaration2_impl();
        let name = name_of(ast, n.name).unwrap_or_else(|| Rc::from("new"));
        let fragment = self.new_fragment(FragmentKind::Constructor, Some(name));
        self.set_offsets(fragment, node, n.name);
        let is_redirecting = n.factory_redirection_target != NO_NODE
            || n
                .initializers
                .iter()
                .any(|i| matches!(ast.node(*i), AstNodeImpl::RedirectingConstructorInvocationImpl(_)));
        // `ConstructorDeclaration2Impl.isComplete`.
        let is_complete = n.external_keyword != NO_TOKEN
            || !is_empty_function_body(ast, n.body)
            || n.factory_redirection_target != NO_NODE
            || !n.initializers.is_empty()
            || ast.store.all_formal_parameters(n.formal_parameters).iter().any(|p| {
                matches!(
                    ast.node(*p),
                    AstNodeImpl::FieldFormalParameterImpl(_) | AstNodeImpl::SuperFormalParameterImpl(_)
                )
            });
        let type_name = if n.type_name != NO_TOKEN {
            Some(Rc::from(ast.tokens.lexeme_string(n.type_name)))
        } else {
            None
        };
        let enclosing_is_enum = self.store.fragment(self.enclosing.fragment).kind == FragmentKind::Enum;
        let primary_constructors = self.primary_constructors;
        let f = self.f(fragment);
        f.set_flag(constructorFragment_isOriginDeclaration, true);
        f.set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);
        f.set_flag(constructorFragment_isConst, n.const_keyword != NO_TOKEN);
        f.set_flag(executableFragment_isExternal, n.external_keyword != NO_TOKEN);
        f.set_flag(constructorFragment_isFactory, n.factory_keyword != NO_TOKEN);
        f.set_flag(constructorFragment_isRedirecting, is_redirecting);
        f.set_flag(fragment_isComplete, is_complete);
        f.type_name = type_name;
        if enclosing_is_enum && f.is_generative() && primary_constructors {
            f.set_flag(constructorFragment_isConst, true);
        }

        self.add_child_fragment(fragment);

        let formal_parameters = n.formal_parameters;
        self.build_executable_element_children(fragment, formal_parameters, NO_NODE);
    }

    fn visit_enum_declaration2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_enum_declaration2_impl();
        let name_token = match ast.node(n.name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_name,
            AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_name,
            _ => NO_TOKEN,
        };
        let fragment = self.new_fragment(FragmentKind::Enum, name_of(ast, name_token));
        self.set_offsets(fragment, node, name_token);
        self.f(fragment).set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);

        self.library.add_top_fragment(self.unit, fragment);
        self.visit_clause(n.with_clause);
        self.visit_clause(n.implements_clause);

        let (name_part, body) = (n.name_part, n.body);
        let (constants, members) = match ast.node(body) {
            AstNodeImpl::BlockEnumDeclarationBodyImpl(b) => (b.constants.clone(), b.members.clone()),
            _ => (Vec::new(), Vec::new()),
        };
        let ((), holder) = self.with_enclosing(fragment, |this| {
            // Build fields for all enum constants.
            for constant in constants {
                let c = ast.node(constant).as_enum_constant_declaration2_impl();
                let field = this.new_fragment(FragmentKind::Field, name_of(ast, c.name));
                this.set_offsets(field, constant, c.name);
                let f = this.f(field);
                f.set_flag(variableFragment_hasImplicitType, true);
                f.set_flag(nonParameterVariableFragment_hasInitializer, true);
                f.set_flag(fragment_isAugmentation, c.augment_keyword != NO_TOKEN);
                f.set_flag(variableFragment_isConst, true);
                f.set_flag(fieldFragment_isEnumConstant, true);
                f.set_flag(propertyInducingFragment_isOriginDeclaration, true);
                f.set_flag(variableFragment_isStatic, true);
                this.add_child_fragment(field);
            }

            // Build the 'values' field.
            let values = this.new_fragment(FragmentKind::Field, Some(Rc::from("values")));
            let f = this.f(values);
            f.set_flag(variableFragment_isConst, true);
            f.set_flag(variableFragment_isStatic, true);
            f.set_flag(fieldFragment_isOriginEnumValues, true);
            this.add_child_fragment(values);

            this.visit_name_part(name_part, node, body);
            for member in members {
                this.visit(member);
            }
        });
        self.f(fragment).type_parameters = holder.type_parameters;
    }

    fn visit_extension_declaration2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_extension_declaration2_impl();
        let fragment = self.new_fragment(FragmentKind::Extension, name_of(ast, n.name));
        self.set_offsets(fragment, node, n.name);
        self.f(fragment).set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);

        self.library.add_top_fragment(self.unit, fragment);

        let (type_parameters, body) = (n.type_parameters, n.body);
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_type_parameter_list(type_parameters);
            this.visit_body(body);
        });
        self.f(fragment).type_parameters = holder.type_parameters;
        self.visit_clause(n.on_clause);
    }

    fn visit_extension_type_declaration2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_extension_type_declaration2_impl();
        let name_token = match ast.node(n.name_part) {
            AstNodeImpl::NameWithTypeParametersImpl(p) => p.type_name,
            AstNodeImpl::PrimaryConstructorDeclarationImpl(p) => p.type_name,
            _ => NO_TOKEN,
        };
        let fragment = self.new_fragment(FragmentKind::ExtensionType, name_of(ast, name_token));
        self.set_offsets(fragment, node, name_token);
        self.f(fragment).set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);

        self.library.add_top_fragment(self.unit, fragment);

        let (name_part, body) = (n.name_part, n.body);
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_name_part(name_part, node, body);
            this.visit_body(body);
        });
        self.f(fragment).type_parameters = holder.type_parameters;
        self.visit_clause(n.implements_clause);
    }

    /// `visitFieldFormalParameter`, `visitRegularFormalParameter` and
    /// `visitSuperFormalParameter`.
    fn visit_formal_parameter(&mut self, node: NodeId) {
        let ast = self.ast;
        let (type_, suffix, name_token, default_clause, covariant_keyword, kind) = formal_parts(ast, node);
        let fragment;
        match ast.node(node) {
            AstNodeImpl::FieldFormalParameterImpl(_) => {
                let mut name = name_of(ast, name_token);
                // A private named parameter gets the corresponding public
                // name; the original private name is kept separately.
                let mut private_name = None;
                if let Some(n) = &name {
                    if is_named(kind) && self.private_named_parameters {
                        if let Some(public_name) = corresponding_public_name(n) {
                            private_name = name.clone();
                            name = Some(Rc::from(public_name));
                        }
                    }
                }
                fragment = self.new_fragment(FragmentKind::FieldFormalParameter, name);
                let f = self.f(fragment);
                f.parameter_kind = kind;
                f.private_name = private_name;
            }
            AstNodeImpl::SuperFormalParameterImpl(_) => {
                fragment = self.new_fragment(FragmentKind::SuperFormalParameter, name_of(ast, name_token));
                self.f(fragment).parameter_kind = kind;
            }
            _ => {
                let declaring = self.declaring_formal_parameters.get(&node).copied();
                match declaring {
                    Some(info) => fragment = info.formal_fragment,
                    None => {
                        fragment = self.new_fragment(FragmentKind::FormalParameter, name_of(ast, name_token));
                        self.f(fragment).parameter_kind = kind;
                    }
                }
                let is_final = match ast.node(node) {
                    AstNodeImpl::RegularFormalParameterImpl(p) => is_final_keyword(ast, p.const_final_or_var_keyword),
                    _ => false,
                };
                let f = self.f(fragment);
                f.set_flag(
                    formalParameterFragment_isExplicitlyCovariant,
                    declaring.is_none() && covariant_keyword != NO_TOKEN,
                );
                f.set_flag(variableFragment_isFinal, is_final);
            }
        }
        self.set_offsets(fragment, node, name_token);
        self.add_parameter(fragment);

        let default_value_code = if default_clause != NO_NODE {
            let value = ast.node(default_clause).as_formal_parameter_default_clause_impl().value2;
            // What a summary keeps of it (detach_nodes.dart).
            Some(Rc::from(serializable_source(ast, value)))
        } else {
            None
        };
        let f = self.f(fragment);
        f.default_value_code = default_value_code;
        f.set_flag(variableFragment_hasImplicitType, type_ == NO_NODE && suffix == NO_NODE);
        f.set_flag(formalParameterFragment_isOriginDeclaration, true);
        self.build_function_typed_parameter_suffix(fragment, suffix);
        self.visit_type_annotation(type_);
    }

    fn visit_fields_declaration(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_fields_declaration_impl();
        let keyword = if n.const_final_or_var_keyword != NO_TOKEN {
            ast.tokens.lexeme_string(n.const_final_or_var_keyword)
        } else {
            String::new()
        };
        let is_const = keyword == "const";
        let is_final = keyword == "final";
        let is_static = n.static_keyword != NO_TOKEN;
        for &field in &n.fields {
            let field_node = ast.node(field).as_field2_impl();
            let fragment = self.new_fragment(FragmentKind::Field, name_of(ast, field_node.name));
            self.set_offsets(fragment, field, field_node.name);
            let f = self.f(fragment);
            f.set_flag(nonParameterVariableFragment_hasInitializer, field_node.initializer != NO_NODE);
            f.set_flag(variableFragment_isAbstract, n.abstract_keyword != NO_TOKEN);
            f.set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);
            f.set_flag(variableFragment_isConst, is_const);
            f.set_flag(fieldFragment_isExplicitlyCovariant, n.covariant_keyword != NO_TOKEN);
            f.set_flag(variableFragment_isExternal, n.external_keyword != NO_TOKEN);
            f.set_flag(variableFragment_isFinal, is_final);
            f.set_flag(variableFragment_isLate, n.late_keyword != NO_TOKEN);
            f.set_flag(propertyInducingFragment_isOriginDeclaration, true);
            f.set_flag(variableFragment_isStatic, is_static);
            if n.type_ == NO_NODE {
                f.set_flag(variableFragment_hasImplicitType, true);
            }
            self.add_child_fragment(fragment);
        }
        self.visit_type_annotation(n.type_);
    }

    /// `visitFormalParameterList`.
    fn visit_formal_parameter_list(&mut self, list: NodeId) {
        if list == NO_NODE {
            return;
        }
        for parameter in self.ast.store.all_formal_parameters(list) {
            self.visit_formal_parameter(parameter);
        }
    }

    fn visit_function_type_alias2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_function_type_alias2_impl();
        let fragment = self.new_fragment(FragmentKind::TypeAlias, name_of(ast, n.name));
        self.set_offsets(fragment, node, n.name);

        self.library.add_top_fragment(self.unit, fragment);

        let type_parameters = n.type_parameters;
        let (return_type, parameters) = (n.return_type, n.parameters);
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_type_parameter_list(type_parameters);
            this.visit_type_annotation(return_type);
            if parameters != NO_NODE {
                this.visit_formal_parameter_list(parameters);
            }
        });
        self.f(fragment).type_parameters = holder.type_parameters;
        let library = self.store.units[self.unit as usize].library;
        for parameter in holder.formal_parameters {
            self.store.init_formal_parameter_element(parameter, library);
        }
    }

    fn visit_generic_type_alias2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_generic_type_alias2_impl();
        let fragment = self.new_fragment(FragmentKind::TypeAlias, name_of(ast, n.name));
        self.set_offsets(fragment, node, n.name);
        self.f(fragment).set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);

        self.library.add_top_fragment(self.unit, fragment);

        let type_parameters = n.type_parameters;
        let aliased_type = n.type_;
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_type_parameter_list(type_parameters);
        });
        self.f(fragment).type_parameters = holder.type_parameters;
        self.visit_type_annotation(aliased_type);
    }

    /// `visitGetterDeclaration`, `visitMethodDeclaration2`,
    /// `visitOperatorDeclaration` and `visitSetterDeclaration`, with
    /// `_buildMethodDeclaration`.
    fn visit_method_like(&mut self, node: NodeId, kind: FragmentKind) {
        let ast = self.ast;
        let (augment, external, static_, return_type, name, type_parameters, formal_parameters, body) =
            match ast.node(node) {
                AstNodeImpl::MethodDeclaration2Impl(n) => (
                    n.augment_keyword,
                    n.external_keyword,
                    n.static_keyword,
                    n.return_type,
                    n.name,
                    n.type_parameters,
                    n.formal_parameters,
                    n.body,
                ),
                AstNodeImpl::GetterDeclarationImpl(n) => (
                    n.augment_keyword,
                    n.external_keyword,
                    n.static_keyword,
                    n.return_type,
                    n.name,
                    NO_NODE,
                    n.recovery_formal_parameters,
                    n.body,
                ),
                AstNodeImpl::SetterDeclarationImpl(n) => (
                    n.augment_keyword,
                    n.external_keyword,
                    n.static_keyword,
                    n.return_type,
                    n.name,
                    NO_NODE,
                    n.formal_parameters,
                    n.body,
                ),
                AstNodeImpl::OperatorDeclarationImpl(n) => (
                    n.augment_keyword,
                    n.external_keyword,
                    NO_TOKEN,
                    n.return_type,
                    n.operator_,
                    n.recovery_type_parameters,
                    n.formal_parameters,
                    n.body,
                ),
                other => panic!("{} is not a method declaration", other.runtime_type()),
            };
        let fragment = self.new_fragment(kind, name_of(ast, name));
        self.set_offsets(fragment, node, name);
        let is_complete = external != NO_TOKEN || !is_empty_function_body(ast, body);
        let (is_async, is_generator) = body_kind(ast, body);
        let is_native = matches!(ast.node(body), AstNodeImpl::NativeFunctionBodyImpl(_));
        let invokes = invokes_super_self(ast, node, name, body, kind == FragmentKind::Setter);
        let f = self.f(fragment);
        match kind {
            FragmentKind::Method => f.set_flag(methodFragment_isOriginDeclaration, true),
            _ => f.set_flag(propertyAccessorFragment_isOriginDeclaration, true),
        }
        f.set_flag(executableFragment_isAbstract, !is_complete);
        f.set_flag(fragment_isAugmentation, augment != NO_TOKEN);
        f.set_flag(executableFragment_isStatic, static_ != NO_TOKEN);
        f.set_flag(executableFragment_hasImplicitReturnType, return_type == NO_NODE);
        f.set_flag(executableFragment_invokesSuperSelf, invokes);
        f.set_flag(executableFragment_isAsynchronous, is_async);
        f.set_flag(executableFragment_isExternal, external != NO_TOKEN || is_native);
        f.set_flag(executableFragment_isGenerator, is_generator);
        f.set_flag(fragment_isComplete, is_complete);

        self.add_child_fragment(fragment);

        self.build_executable_element_children(fragment, formal_parameters, type_parameters);
        self.visit_type_annotation(return_type);
    }

    fn visit_mixin_declaration2(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_mixin_declaration2_impl();
        let fragment = self.new_fragment(FragmentKind::Mixin, name_of(ast, n.name));
        self.set_offsets(fragment, node, n.name);
        let f = self.f(fragment);
        f.set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);
        f.set_flag(mixinFragment_isBase, n.base_keyword != NO_TOKEN);

        self.library.add_top_fragment(self.unit, fragment);

        let (type_parameters, body) = (n.type_parameters, n.body);
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_type_parameter_list(type_parameters);
            this.visit_body(body);
        });
        self.f(fragment).type_parameters = holder.type_parameters;
        self.visit_clause(n.on_clause);
        self.visit_clause(n.implements_clause);
    }

    fn visit_primary_constructor_declaration(&mut self, node: NodeId, declaration: NodeId, body: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_primary_constructor_declaration_impl();
        self.visit_type_parameter_list(n.type_parameters);

        let mut name_token = NO_TOKEN;
        let mut name: Rc<str> = Rc::from("new");
        if n.constructor_name != NO_NODE {
            name_token = ast.node(n.constructor_name).as_primary_constructor_name_impl().name;
            if let Some(constructor_name) = name_of(ast, name_token) {
                name = constructor_name;
            }
        }

        let (parent_is_extension_type, parent_is_enum, is_augmentation) = match ast.node(declaration) {
            AstNodeImpl::ExtensionTypeDeclaration2Impl(d) => (true, false, d.augment_keyword != NO_TOKEN),
            AstNodeImpl::EnumDeclaration2Impl(_) => (false, true, false),
            _ => (false, false, false),
        };

        let members = self.class_members(body);
        let body2 = members
            .iter()
            .copied()
            .find(|m| matches!(ast.node(*m), AstNodeImpl::PrimaryConstructorBody2Impl(_)));
        let formal_parameters = ast.store.all_formal_parameters(n.formal_parameters);

        // `PrimaryConstructorDeclarationImpl.isComplete`.
        let is_complete = {
            let mut complete = false;
            if let Some(b) = body2 {
                let b = ast.node(b).as_primary_constructor_body2_impl();
                if !is_empty_function_body(ast, b.body) || !b.initializers.is_empty() {
                    complete = true;
                }
            }
            complete
                || parent_is_extension_type
                || formal_parameters.iter().any(|p| match ast.node(*p) {
                    AstNodeImpl::FieldFormalParameterImpl(_) | AstNodeImpl::SuperFormalParameterImpl(_) => true,
                    AstNodeImpl::RegularFormalParameterImpl(_) => has_final_or_var_keyword(ast, *p),
                    _ => false,
                })
        };

        let fragment = self.new_fragment(FragmentKind::Constructor, Some(name));
        self.set_offsets(fragment, node, name_token);
        let type_name = Rc::from(ast.tokens.lexeme_string(n.type_name));
        let f = self.f(fragment);
        f.set_flag(fragment_isAugmentation, is_augmentation);
        f.set_flag(constructorFragment_isOriginDeclaration, true);
        f.set_flag(constructorFragment_isConst, n.const_keyword != NO_TOKEN || parent_is_enum);
        f.set_flag(constructorFragment_isPrimary, true);
        f.set_flag(fragment_isComplete, is_complete);
        f.type_name = Some(type_name);

        self.add_child_fragment(fragment);

        // Handle declaring formal parameters.
        let mut is_first_formal_extension_type_representation = false;
        if parent_is_extension_type {
            is_first_formal_extension_type_representation = formal_parameters
                .first()
                .is_some_and(|p| matches!(ast.node(*p), AstNodeImpl::RegularFormalParameterImpl(_)));
            if !is_first_formal_extension_type_representation {
                let field = self.new_fragment(FragmentKind::Field, None);
                let f = self.f(field);
                f.set_flag(fragment_isAugmentation, is_augmentation);
                f.set_flag(variableFragment_isFinal, true);
                f.set_flag(fieldFragment_isOriginExtensionTypeRecoveryRepresentation, true);
                self.add_child_fragment(field);
            }
        }
        for (i, &formal_parameter) in formal_parameters.iter().enumerate() {
            let AstNodeImpl::RegularFormalParameterImpl(p) = ast.node(formal_parameter) else {
                continue;
            };
            let is_extension_type_representation = i == 0 && is_first_formal_extension_type_representation;
            if has_final_or_var_keyword(ast, formal_parameter) || is_extension_type_representation {
                let name = name_of(ast, p.name);
                let field = self.new_fragment(FragmentKind::Field, name.clone());
                let is_final = is_final_keyword(ast, p.const_final_or_var_keyword);
                let is_explicitly_typed = p.type_ != NO_NODE || p.function_typed_suffix != NO_NODE;
                let f = self.f(field);
                f.set_flag(fragment_isAugmentation, is_augmentation);
                f.set_flag(fieldFragment_isExplicitlyCovariant, p.covariant_keyword != NO_TOKEN);
                f.set_flag(variableFragment_isFinal, is_final || is_extension_type_representation);
                f.set_flag(fieldFragment_isOriginDeclaringFormalParameter, true);
                f.set_flag(variableFragment_hasImplicitType, !is_explicitly_typed);
                self.add_child_fragment(field);

                let mut formal_name = name;
                let mut formal_private_name = None;
                if let Some(n) = &formal_name {
                    if is_named(p.kind) && self.private_named_parameters {
                        if let Some(public_name) = corresponding_public_name(n) {
                            formal_private_name = formal_name.clone();
                            formal_name = Some(Rc::from(public_name));
                        }
                    }
                }
                let formal = self.new_fragment(FragmentKind::FieldFormalParameter, formal_name);
                let f = self.f(formal);
                f.parameter_kind = p.kind;
                f.private_name = formal_private_name;
                f.set_flag(fieldFormalParameterFragment_isDeclaring, true);
                self.declaring_formal_parameters
                    .insert(formal_parameter, DeclaringFormalParameterInfo { formal_fragment: formal });
            }
        }

        let formal_parameter_list = n.formal_parameters;
        self.build_executable_element_children(fragment, formal_parameter_list, NO_NODE);
    }

    fn visit_top_level_function_declaration(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_top_level_function_declaration_impl();
        let fragment = self.new_fragment(FragmentKind::TopLevelFunction, name_of(ast, n.name));
        self.set_offsets(fragment, node, n.name);
        let (is_async, is_generator) = body_kind(ast, n.body);
        let is_complete = n.external_keyword != NO_TOKEN || !is_empty_function_body(ast, n.body);
        let f = self.f(fragment);
        f.set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);
        f.set_flag(topLevelFunctionFragment_isOriginDeclaration, true);
        f.set_flag(executableFragment_isStatic, true);
        f.set_flag(executableFragment_hasImplicitReturnType, n.return_type == NO_NODE);
        f.set_flag(executableFragment_isAsynchronous, is_async);
        f.set_flag(executableFragment_isExternal, n.external_keyword != NO_TOKEN);
        f.set_flag(executableFragment_isGenerator, is_generator);
        f.set_flag(fragment_isComplete, is_complete);
        self.library.add_top_fragment(self.unit, fragment);

        let (formal_parameters, type_parameters) = (n.formal_parameters, n.type_parameters);
        self.build_executable_element_children(fragment, formal_parameters, type_parameters);
        self.visit_type_annotation(n.return_type);
    }

    /// `visitTopLevelGetterDeclaration` and `visitTopLevelSetterDeclaration`.
    fn visit_top_level_accessor(&mut self, node: NodeId, kind: FragmentKind) {
        let ast = self.ast;
        let (augment, external, return_type, name, formal_parameters, body) = match ast.node(node) {
            AstNodeImpl::TopLevelGetterDeclarationImpl(n) => (
                n.augment_keyword,
                n.external_keyword,
                n.return_type,
                n.name,
                n.recovery_formal_parameters,
                n.body,
            ),
            AstNodeImpl::TopLevelSetterDeclarationImpl(n) => (
                n.augment_keyword,
                n.external_keyword,
                n.return_type,
                n.name,
                n.formal_parameters,
                n.body,
            ),
            other => panic!("{} is not a top-level accessor", other.runtime_type()),
        };
        let fragment = self.new_fragment(kind, name_of(ast, name));
        self.set_offsets(fragment, node, name);
        let (is_async, is_generator) = body_kind(ast, body);
        let is_complete = external != NO_TOKEN || !is_empty_function_body(ast, body);
        let f = self.f(fragment);
        f.set_flag(fragment_isAugmentation, augment != NO_TOKEN);
        f.set_flag(propertyAccessorFragment_isOriginDeclaration, true);
        f.set_flag(executableFragment_isStatic, true);
        f.set_flag(executableFragment_hasImplicitReturnType, return_type == NO_NODE);
        f.set_flag(executableFragment_isAsynchronous, is_async);
        f.set_flag(executableFragment_isExternal, external != NO_TOKEN);
        f.set_flag(executableFragment_isGenerator, is_generator);
        f.set_flag(fragment_isComplete, is_complete);

        self.library.add_top_fragment(self.unit, fragment);

        self.build_executable_element_children(fragment, formal_parameters, NO_NODE);
        self.visit_type_annotation(return_type);
    }

    fn visit_top_level_variables_declaration(&mut self, node: NodeId) {
        let ast = self.ast;
        let n = ast.node(node).as_top_level_variables_declaration_impl();
        let keyword = if n.const_final_or_var_keyword != NO_TOKEN {
            ast.tokens.lexeme_string(n.const_final_or_var_keyword)
        } else {
            String::new()
        };
        for &variable in &n.variables {
            let v = ast.node(variable).as_top_level_variable2_impl();
            let fragment = self.new_fragment(FragmentKind::TopLevelVariable, name_of(ast, v.name));
            self.set_offsets(fragment, variable, v.name);
            let f = self.f(fragment);
            f.set_flag(nonParameterVariableFragment_hasInitializer, v.initializer != NO_NODE);
            f.set_flag(variableFragment_isAbstract, n.abstract_keyword != NO_TOKEN);
            f.set_flag(fragment_isAugmentation, n.augment_keyword != NO_TOKEN);
            f.set_flag(variableFragment_isConst, keyword == "const");
            f.set_flag(variableFragment_isExternal, n.external_keyword != NO_TOKEN);
            f.set_flag(variableFragment_isFinal, keyword == "final");
            f.set_flag(variableFragment_isLate, n.late_keyword != NO_TOKEN);
            f.set_flag(propertyInducingFragment_isOriginDeclaration, true);
            if n.type_ == NO_NODE {
                f.set_flag(variableFragment_hasImplicitType, true);
            }
            self.library.add_top_fragment(self.unit, fragment);
        }
        self.visit_type_annotation(n.type_);
    }

    /// `visitTypeParameterList` and `visitTypeParameter`.
    fn visit_type_parameter_list(&mut self, list: NodeId) {
        if list == NO_NODE {
            return;
        }
        let ast = self.ast;
        for &parameter in &ast.node(list).as_type_parameter_list_impl().type_parameters {
            let p = ast.node(parameter).as_type_parameter_impl();
            let fragment = self.new_fragment(FragmentKind::TypeParameter, name_of(ast, p.name));
            self.set_offsets(fragment, parameter, p.name);
            let parent = self.enclosing.fragment;
            self.f(fragment).enclosing_fragment = parent;
            self.enclosing.type_parameters.push(fragment);
            self.visit_type_annotation(p.bound);
        }
    }

    /// The type annotation [node]: `visitNamedType` (its type arguments),
    /// `visitGenericFunctionType`, and the record type annotation visits.
    /// Only generic function types declare fragments.
    fn visit_type_annotation(&mut self, node: NodeId) {
        if node == NO_NODE {
            return;
        }
        let ast = self.ast;
        match ast.node(node) {
            AstNodeImpl::NamedTypeImpl(n) => {
                if n.type_arguments != NO_NODE {
                    for &argument in ast.node(n.type_arguments).as_type_argument_list_impl().arguments.iter() {
                        self.visit_type_annotation(argument);
                    }
                }
            }
            AstNodeImpl::GenericFunctionTypeImpl(n) => {
                let (type_parameters, parameters, return_type) = (n.type_parameters, n.parameters, n.return_type);
                let fragment = self.new_fragment(FragmentKind::GenericFunctionType, None);
                // `_libraryFragment.encloseElement(fragment)`.
                self.f(fragment).node = node;
                let ((), holder) = self.with_enclosing(fragment, |this| {
                    this.visit_type_parameter_list(type_parameters);
                    if parameters != NO_NODE {
                        this.visit_formal_parameter_list(parameters);
                    }
                });
                let library = self.store.units[self.unit as usize].library;
                self.f(fragment).type_parameters = holder.type_parameters.clone();
                self.f(fragment).formal_parameters = holder.formal_parameters.clone();
                // `GenericFunctionTypeElementImpl(fragment)`, with the
                // elements of its type and formal parameters.
                self.store.add_element(ElementKind::GENERIC_FUNCTION_TYPE, fragment, library);
                for parameter in holder.type_parameters {
                    self.store.add_element(ElementKind::TYPE_PARAMETER, parameter, library);
                }
                for parameter in holder.formal_parameters {
                    self.store.init_formal_parameter_element(parameter, library);
                }
                self.visit_type_annotation(return_type);
            }
            AstNodeImpl::RecordTypeAnnotationImpl(n) => {
                let named_fields = n.named_fields;
                for &field in n.positional_fields.iter() {
                    let t = ast.node(field).as_record_type_annotation_positional_field_impl().type_;
                    self.visit_type_annotation(t);
                }
                if named_fields != NO_NODE {
                    for &field in ast.node(named_fields).as_record_type_annotation_named_fields_impl().fields.iter() {
                        let t = ast.node(field).as_record_type_annotation_named_field_impl().type_;
                        self.visit_type_annotation(t);
                    }
                }
            }
            _ => {}
        }
    }

    /// The types of a clause: `visitExtendsClause`, `visitWithClause`,
    /// `visitImplementsClause`, `visitMixinOnClause`,
    /// `visitExtensionOnClause`.
    fn visit_clause(&mut self, clause: NodeId) {
        if clause == NO_NODE {
            return;
        }
        let ast = self.ast;
        let types: Vec<NodeId> = match ast.node(clause) {
            AstNodeImpl::ExtendsClauseImpl(c) => vec![c.superclass],
            AstNodeImpl::WithClauseImpl(c) => c.mixin_types.iter().copied().collect(),
            AstNodeImpl::ImplementsClauseImpl(c) => c.interfaces.iter().copied().collect(),
            AstNodeImpl::MixinOnClauseImpl(c) => c.superclass_constraints.iter().copied().collect(),
            AstNodeImpl::ExtensionOnClauseImpl(c) => vec![c.extended_type],
            other => panic!("{} is not a clause", other.runtime_type()),
        };
        for t in types {
            self.visit_type_annotation(t);
        }
    }

    /// `_buildFunctionTypedParameterSuffix`: the type and formal parameters
    /// of a function-typed formal parameter get fragments and elements, but
    /// no list of [fragment] holds them.
    fn build_function_typed_parameter_suffix(&mut self, fragment: FragmentId, suffix: NodeId) {
        if suffix == NO_NODE {
            return;
        }
        let s = self.ast.node(suffix).as_function_typed_formal_parameter_suffix_impl();
        let (type_parameters, formal_parameters) = (s.type_parameters, s.formal_parameters);
        let ((), holder) = self.with_enclosing(fragment, |this| {
            this.visit_type_parameter_list(type_parameters);
            if formal_parameters != NO_NODE {
                this.visit_formal_parameter_list(formal_parameters);
            }
        });
        let library = self.store.units[self.unit as usize].library;
        for parameter in holder.type_parameters {
            self.store.add_element(ElementKind::TYPE_PARAMETER, parameter, library);
        }
        for parameter in holder.formal_parameters {
            self.store.init_formal_parameter_element(parameter, library);
        }
    }

    /// `_buildExecutableElementChildren`.
    fn build_executable_element_children(
        &mut self,
        fragment: FragmentId,
        formal_parameters: NodeId,
        type_parameters: NodeId,
    ) {
        let ((), holder) = self.with_enclosing(fragment, |this| {
            if formal_parameters != NO_NODE {
                this.visit_formal_parameter_list(formal_parameters);
            }
            if type_parameters != NO_NODE {
                this.visit_type_parameter_list(type_parameters);
            }
        });
        if formal_parameters != NO_NODE {
            self.f(fragment).formal_parameters = holder.formal_parameters;
        }
        if type_parameters != NO_NODE {
            self.f(fragment).type_parameters = holder.type_parameters;
        }
    }
}

/// `ElementBuilder`.
pub struct ElementBuilder<'a> {
    store: &'a mut ElementStore,
    library: &'a mut LibraryFragments,
    library_element: LibraryId,
    units: &'a [UnitId],
    is_dart_core: bool,
    executable_elements: Vec<ElementId>,
}

impl<'a> ElementBuilder<'a> {
    pub fn new(
        store: &'a mut ElementStore,
        library: &'a mut LibraryFragments,
        library_element: LibraryId,
        units: &'a [UnitId],
        is_dart_core: bool,
    ) -> ElementBuilder<'a> {
        ElementBuilder {
            store,
            library,
            library_element,
            units,
            is_dart_core,
            executable_elements: Vec::new(),
        }
    }

    /// `buildElements`.
    pub fn build_elements(&mut self) {
        self.build_top_fragments();
        self.add_extension_type_recovery_fragments();
        self.build_instance_element_members();
        self.build_formal_parameter_elements();
    }

    fn lib(&mut self) -> &mut crate::src::dart::element::element::LibraryElementImpl {
        &mut self.store.libraries[self.library_element as usize]
    }

    fn new_element(&mut self, kind: ElementKind, fragment: FragmentId) -> ElementId {
        self.store.add_element(kind, fragment, self.library_element)
    }

    fn new_fragment(&mut self, kind: FragmentKind, name: Option<Rc<str>>, unit: UnitId) -> FragmentId {
        let mut fragment = FragmentImpl::new(kind, name);
        fragment.unit = unit;
        self.store.add_fragment(fragment)
    }

    /// `_addExtensionTypeRecoveryFragments`.
    fn add_extension_type_recovery_fragments(&mut self) {
        let extension_types = self.store.libraries[self.library_element as usize].extension_types.clone();
        for extension_type in extension_types {
            let first_fragment = self.store.element(extension_type).first_fragment;
            let unit = self.store.fragment(first_fragment).unit;
            let has_primary_constructor = self
                .library
                .parent_child_fragments
                .get(&first_fragment)
                .is_some_and(|children| {
                    children.iter().any(|c| {
                        let f = self.store.fragment(*c);
                        f.kind == FragmentKind::Constructor && f.has_flag(constructorFragment_isPrimary)
                    })
                });
            if !has_primary_constructor {
                let type_name = self.store.element(extension_type).name.clone();
                let constructor = self.new_fragment(FragmentKind::Constructor, Some(Rc::from("new")), unit);
                let f = self.store.fragment_mut(constructor);
                f.set_flag(constructorFragment_isPrimary, true);
                f.set_flag(constructorFragment_isConst, true);
                f.set_flag(constructorFragment_isOriginExtensionTypeRecovery, true);
                f.type_name = type_name;
                f.enclosing_fragment = first_fragment;

                let field = self.new_fragment(FragmentKind::Field, None, unit);
                let f = self.store.fragment_mut(field);
                f.set_flag(variableFragment_isFinal, true);
                f.set_flag(fieldFragment_isOriginExtensionTypeRecoveryRepresentation, true);
                f.set_flag(variableFragment_hasImplicitType, true);
                f.enclosing_fragment = first_fragment;

                let children = self.library.parent_child_fragments.entry(first_fragment).or_default();
                children.insert(0, constructor);
                children.insert(0, field);
            }
        }
    }

    /// `_buildFormalParameterElements`.
    fn build_formal_parameter_elements(&mut self) {
        for element in std::mem::take(&mut self.executable_elements) {
            let first = self.store.element(element).first_fragment;
            for parameter in self.store.fragment(first).formal_parameters.clone() {
                self.store.init_formal_parameter_element(parameter, self.library_element);
            }
        }
    }

    /// The type parameters of a fragment get their elements with the
    /// element of the fragment (`TypeParameterElementImpl` is created by
    /// the element of the declaration upstream).
    fn build_type_parameter_elements(&mut self, fragment: FragmentId) {
        for parameter in self.store.fragment(fragment).type_parameters.clone() {
            self.store.add_element(ElementKind::TYPE_PARAMETER, parameter, self.library_element);
        }
    }

    /// `_buildInstanceElementMembers`.
    fn build_instance_element_members(&mut self) {
        let library = &self.store.libraries[self.library_element as usize];
        let instance_elements: Vec<ElementId> = library
            .classes
            .iter()
            .chain(&library.enums)
            .chain(&library.extensions)
            .chain(&library.extension_types)
            .chain(&library.mixins)
            .copied()
            .collect();
        for instance_element in instance_elements {
            let child_fragments: Vec<FragmentId> = self
                .store
                .element_fragments(instance_element)
                .iter()
                .flat_map(|f| self.library.parent_child_fragments.get(f).cloned().unwrap_or_default())
                .collect();

            let mut last_instance_fragments: HashMap<Option<Rc<str>>, FragmentId> = HashMap::new();
            let mut last_static_fragments: HashMap<Option<Rc<str>>, FragmentId> = HashMap::new();
            for fragment in child_fragments {
                let f = self.store.fragment(fragment);
                let is_in_static_namespace = match f.kind {
                    FragmentKind::Constructor => true,
                    FragmentKind::Field | FragmentKind::Getter | FragmentKind::Setter | FragmentKind::Method => {
                        f.is_static()
                    }
                    _ => false,
                };
                let name = f.name.clone();
                let kind = f.kind;
                let last_fragments = if is_in_static_namespace {
                    &last_static_fragments
                } else {
                    &last_instance_fragments
                };
                let last_fragment = last_fragments.get(&name).copied().unwrap_or(NO_FRAGMENT);
                let mut fragment_to_track = fragment;
                match kind {
                    FragmentKind::Field => {
                        fragment_to_track =
                            self.handle_instance_field_fragment(instance_element, last_fragment, fragment);
                    }
                    FragmentKind::Getter => {
                        self.handle_instance_getter_fragment(instance_element, last_fragment, fragment)
                    }
                    FragmentKind::Setter => {
                        self.handle_instance_setter_fragment(instance_element, last_fragment, fragment)
                    }
                    FragmentKind::Method => {
                        self.handle_instance_method_fragment(instance_element, last_fragment, fragment)
                    }
                    FragmentKind::Constructor => {
                        self.handle_instance_constructor_fragment(instance_element, last_fragment, fragment)
                    }
                    other => panic!("UnimplementedError: {other:?}"),
                }
                let tracked_name = self.store.fragment(fragment_to_track).name.clone();
                let last_fragments = if is_in_static_namespace {
                    &mut last_static_fragments
                } else {
                    &mut last_instance_fragments
                };
                last_fragments.insert(tracked_name, fragment_to_track);
            }

            // Mark extension type members.
            if self.store.element(instance_element).kind == ElementKind::EXTENSION_TYPE {
                let members = self.store.element(instance_element).members().clone();
                for executable in members
                    .getters
                    .iter()
                    .chain(&members.setters)
                    .chain(&members.methods)
                    .chain(&members.constructors)
                {
                    self.store.element_mut(*executable).is_extension_type_member = true;
                }
            }
        }
    }

    /// `_buildTopFragments`.
    fn build_top_fragments(&mut self) {
        let mut last_fragments: HashMap<Option<Rc<str>>, FragmentId> = HashMap::new();
        for (unit, fragments) in self.library.top_fragments.clone() {
            for fragment in fragments {
                let f = self.store.fragment(fragment);
                let (kind, name, is_augmentation) = (f.kind, f.name.clone(), f.is_augmentation());
                if kind == FragmentKind::Extension && is_augmentation && name.is_none() {
                    self.handle_interface_fragment(unit, NO_FRAGMENT, fragment);
                    continue;
                }
                let last_fragment = last_fragments.get(&name).copied().unwrap_or(NO_FRAGMENT);
                match kind {
                    FragmentKind::Class
                    | FragmentKind::Enum
                    | FragmentKind::Extension
                    | FragmentKind::ExtensionType
                    | FragmentKind::Mixin => self.handle_interface_fragment(unit, last_fragment, fragment),
                    FragmentKind::Getter => self.handle_top_level_getter_fragment(unit, last_fragment, fragment),
                    FragmentKind::Setter => self.handle_top_level_setter_fragment(unit, last_fragment, fragment),
                    FragmentKind::TopLevelFunction => {
                        self.handle_top_level_function_fragment(unit, last_fragment, fragment)
                    }
                    FragmentKind::TopLevelVariable => {
                        self.handle_top_level_variable_fragment(unit, last_fragment, fragment)
                    }
                    FragmentKind::TypeAlias => self.handle_type_alias_fragment(unit, fragment),
                    other => panic!("UnimplementedError: {other:?}"),
                }
                last_fragments.insert(name, fragment);
            }
        }
    }

    /// `_fieldElement`.
    fn field_element(&self, fragment: FragmentId) -> ElementId {
        if fragment == NO_FRAGMENT {
            return NO_ELEMENT;
        }
        let f = self.store.fragment(fragment);
        match f.kind {
            FragmentKind::Field => f.element,
            FragmentKind::Getter | FragmentKind::Setter => {
                let variable = self.store.element(f.element).variable;
                if variable != NO_ELEMENT && self.store.element(variable).kind == ElementKind::FIELD {
                    variable
                } else {
                    NO_ELEMENT
                }
            }
            _ => NO_ELEMENT,
        }
    }

    /// `_topLevelVariableElement`.
    fn top_level_variable_element(&self, fragment: FragmentId) -> ElementId {
        if fragment == NO_FRAGMENT {
            return NO_ELEMENT;
        }
        let f = self.store.fragment(fragment);
        match f.kind {
            FragmentKind::TopLevelVariable => f.element,
            FragmentKind::Getter | FragmentKind::Setter => {
                let variable = self.store.element(f.element).variable;
                if variable != NO_ELEMENT && self.store.element(variable).kind == ElementKind::TOP_LEVEL_VARIABLE {
                    variable
                } else {
                    NO_ELEMENT
                }
            }
            _ => NO_ELEMENT,
        }
    }

    /// `_handleClassFragment`, `_handleEnumFragment`,
    /// `_handleExtensionFragment`, `_handleExtensionTypeFragment` and
    /// `_handleMixinFragment`.
    fn handle_interface_fragment(&mut self, unit: UnitId, last_fragment: FragmentId, fragment: FragmentId) {
        let f = self.store.fragment(fragment);
        let kind = f.kind;
        let is_augmentation = f.is_augmentation();
        let unit_data = &mut self.store.units[unit as usize];
        match kind {
            FragmentKind::Class => unit_data.classes.push(fragment),
            FragmentKind::Enum => unit_data.enums.push(fragment),
            FragmentKind::Extension => unit_data.extensions.push(fragment),
            FragmentKind::ExtensionType => unit_data.extension_types.push(fragment),
            _ => unit_data.mixins.push(fragment),
        }

        if is_augmentation && last_fragment != NO_FRAGMENT {
            let last = self.store.fragment(last_fragment);
            let joins = last.kind == kind
                && !(kind == FragmentKind::Class && last.has_flag(classFragment_isMixinApplication));
            if joins {
                let last_in_chain = self.store.last_fragment(last.element);
                self.store.add_fragment_to_chain(last_in_chain, fragment);
                self.link_type_parameters(last_fragment, fragment);
                return;
            }
        }

        let element_kind = match kind {
            FragmentKind::Class => ElementKind::CLASS,
            FragmentKind::Enum => ElementKind::ENUM,
            FragmentKind::Extension => ElementKind::EXTENSION,
            FragmentKind::ExtensionType => ElementKind::EXTENSION_TYPE,
            _ => ElementKind::MIXIN,
        };
        let element = self.new_element(element_kind, fragment);
        self.build_type_parameter_elements(fragment);
        if is_augmentation && last_fragment != NO_FRAGMENT {
            self.store.element_mut(element).previous_fragment_of_different_kind = last_fragment;
        }
        let lib = self.lib();
        match kind {
            FragmentKind::Class => lib.classes.push(element),
            FragmentKind::Enum => lib.enums.push(element),
            FragmentKind::Extension => lib.extensions.push(element),
            FragmentKind::ExtensionType => lib.extension_types.push(element),
            _ => lib.mixins.push(element),
        }
        self.library.declare(self.store, element);
    }

    /// `_handleInstanceConstructorFragment`.
    fn handle_instance_constructor_fragment(
        &mut self,
        interface_element: ElementId,
        last_fragment: FragmentId,
        fragment: FragmentId,
    ) {
        let interface_fragment = self.store.fragment(fragment).enclosing_fragment;
        self.store.fragment_mut(interface_fragment).members_mut().constructors.push(fragment);

        if self.store.fragment(fragment).is_augmentation()
            && last_fragment != NO_FRAGMENT
            && self.store.fragment(last_fragment).kind == FragmentKind::Constructor
        {
            self.store.add_fragment_to_chain(last_fragment, fragment);
            self.link_type_parameters(last_fragment, fragment);
            self.link_formal_parameters(last_fragment, fragment);
            return;
        }

        let element = self.new_element(ElementKind::CONSTRUCTOR, fragment);
        self.executable_elements.push(element);
        if self.store.fragment(fragment).is_augmentation() && last_fragment != NO_FRAGMENT {
            self.store.element_mut(element).previous_fragment_of_different_kind = last_fragment;
        }
        self.store.element_mut(interface_element).members_mut().constructors.push(element);
    }

    /// `_handleInstanceFieldFragment`.
    fn handle_instance_field_fragment(
        &mut self,
        instance_element: ElementId,
        last_fragment: FragmentId,
        field_fragment: FragmentId,
    ) -> FragmentId {
        let instance_fragment = self.store.fragment(field_fragment).enclosing_fragment;
        let unit = self.store.fragment(field_fragment).unit;

        // Move elements of `values` from an augmentation to the first
        // fragment: the augmentation's `values` is dropped (its constants
        // are not kept as initializer nodes here).
        if self.store.fragment(field_fragment).has_flag(fieldFragment_isOriginEnumValues)
            && self.store.fragment(instance_fragment).kind == FragmentKind::Enum
            && self.store.fragment(instance_fragment).previous_fragment != NO_FRAGMENT
        {
            let first = self.store.element(instance_element).first_fragment;
            let first_values = self.store.fragment(first).members().fields.iter().copied().find(|f| {
                self.store.fragment(*f).has_flag(fieldFragment_isOriginEnumValues)
            });
            return first_values.expect("the first fragment has `values`");
        }

        self.store.fragment_mut(instance_fragment).members_mut().fields.push(field_fragment);

        let field_element;
        let last_field_element = self.field_element(last_fragment);
        let last_field_fragment = if last_field_element != NO_ELEMENT {
            self.store.last_fragment(last_field_element)
        } else {
            NO_FRAGMENT
        };
        let ff = self.store.fragment(field_fragment);
        let (is_augmentation, is_abstract, is_static, name, is_covariant, has_setter) = (
            ff.is_augmentation(),
            ff.is_abstract_variable(),
            ff.is_static(),
            ff.name.clone(),
            ff.has_flag(fieldFragment_isExplicitlyCovariant),
            ff.has_setter(),
        );
        if is_augmentation
            && last_field_fragment != NO_FRAGMENT
            && self.store.fragment(last_field_fragment).kind == FragmentKind::Field
        {
            self.store.add_fragment_to_chain(last_field_fragment, field_fragment);
            field_element = last_field_element;
        } else {
            field_element = self.new_element(ElementKind::FIELD, field_fragment);
            if is_augmentation && last_fragment != NO_FRAGMENT {
                self.store.element_mut(field_element).previous_fragment_of_different_kind = last_fragment;
            }
            self.store.element_mut(instance_element).members_mut().fields.push(field_element);
        }

        {
            let getter_fragment = self.new_fragment(FragmentKind::Getter, name.clone(), unit);
            let g = self.store.fragment_mut(getter_fragment);
            g.set_flag(propertyAccessorFragment_isOriginVariable, true);
            g.set_flag(executableFragment_isAbstract, is_abstract);
            g.set_flag(fragment_isAugmentation, is_augmentation);
            g.set_flag(fragment_isComplete, !is_abstract);
            g.set_flag(executableFragment_isStatic, is_static);
            g.enclosing_fragment = instance_fragment;
            self.store.fragment_mut(field_fragment).induced_getter = getter_fragment;
            self.store.fragment_mut(instance_fragment).members_mut().getters.push(getter_fragment);

            // A field augmentation can target a setter-only property, so
            // create or append each induced accessor independently.
            let getter_element = self.store.element(field_element).getter;
            if getter_element != NO_ELEMENT {
                let last_getter_fragment = self.store.last_fragment(getter_element);
                self.store.add_fragment_to_chain(last_getter_fragment, getter_fragment);
                self.link_formal_parameters(last_getter_fragment, getter_fragment);
            } else {
                let getter_element = self.new_element(ElementKind::GETTER, getter_fragment);
                self.executable_elements.push(getter_element);
                self.store.element_mut(instance_element).members_mut().getters.push(getter_element);
                self.store.element_mut(field_element).getter = getter_element;
                self.store.element_mut(getter_element).variable = field_element;
            }
        }

        if has_setter {
            let setter_fragment = self.new_fragment(FragmentKind::Setter, name, unit);
            let s = self.store.fragment_mut(setter_fragment);
            s.set_flag(propertyAccessorFragment_isOriginVariable, true);
            s.set_flag(executableFragment_isAbstract, is_abstract);
            s.set_flag(fragment_isAugmentation, is_augmentation);
            s.set_flag(fragment_isComplete, !is_abstract);
            s.set_flag(executableFragment_isStatic, is_static);
            s.enclosing_fragment = instance_fragment;
            self.store.fragment_mut(field_fragment).induced_setter = setter_fragment;
            self.store.fragment_mut(instance_fragment).members_mut().setters.push(setter_fragment);

            let value = self.new_fragment(FragmentKind::FormalParameter, Some(Rc::from("value")), unit);
            let v = self.store.fragment_mut(value);
            v.parameter_kind = ParameterKind::REQUIRED;
            v.set_flag(formalParameterFragment_isExplicitlyCovariant, is_covariant);
            v.enclosing_fragment = setter_fragment;
            self.store.fragment_mut(setter_fragment).formal_parameters = vec![value];

            let setter_element = self.store.element(field_element).setter;
            if setter_element != NO_ELEMENT {
                let last_setter_fragment = self.store.last_fragment(setter_element);
                self.store.add_fragment_to_chain(last_setter_fragment, setter_fragment);
                self.link_formal_parameters(last_setter_fragment, setter_fragment);
            } else {
                let setter_element = self.new_element(ElementKind::SETTER, setter_fragment);
                self.executable_elements.push(setter_element);
                self.store.element_mut(instance_element).members_mut().setters.push(setter_element);
                self.store.element_mut(field_element).setter = setter_element;
                self.store.element_mut(setter_element).variable = field_element;
            }
        }

        field_fragment
    }

    /// `_handleInstanceGetterFragment` and `_handleInstanceSetterFragment`.
    fn handle_instance_accessor_fragment(
        &mut self,
        instance_element: ElementId,
        last_fragment: FragmentId,
        accessor_fragment: FragmentId,
        is_getter: bool,
    ) {
        let instance_fragment = self.store.fragment(accessor_fragment).enclosing_fragment;
        let unit = self.store.fragment(accessor_fragment).unit;
        let members = self.store.fragment_mut(instance_fragment).members_mut();
        if is_getter {
            members.getters.push(accessor_fragment);
        } else {
            members.setters.push(accessor_fragment);
        }

        let mut last_field_element = self.field_element(last_fragment);
        let last_accessor_fragment = if last_field_element != NO_ELEMENT {
            let accessor = if is_getter {
                self.store.element(last_field_element).getter
            } else {
                self.store.element(last_field_element).setter
            };
            if accessor != NO_ELEMENT {
                self.store.last_fragment(accessor)
            } else {
                NO_FRAGMENT
            }
        } else {
            NO_FRAGMENT
        };

        let is_augmentation = self.store.fragment(accessor_fragment).is_augmentation();
        if is_augmentation && last_accessor_fragment != NO_FRAGMENT {
            self.store.add_fragment_to_chain(last_accessor_fragment, accessor_fragment);
            self.link_formal_parameters(last_accessor_fragment, accessor_fragment);
            return;
        }

        // Not augmentation, create new element.
        let kind = if is_getter { ElementKind::GETTER } else { ElementKind::SETTER };
        let accessor_element = self.new_element(kind, accessor_fragment);
        self.executable_elements.push(accessor_element);
        if is_augmentation && last_fragment != NO_FRAGMENT {
            self.store.element_mut(accessor_element).previous_fragment_of_different_kind = last_fragment;
        }
        let members = self.store.element_mut(instance_element).members_mut();
        if is_getter {
            members.getters.push(accessor_element);
        } else {
            members.setters.push(accessor_element);
        }

        let name = self.store.fragment(accessor_fragment).name.clone();
        // `class Enum {}` in `dart:core` declares `int get index` as
        // abstract. But the specification says that practically a
        // different class implementing `Enum` is used as a superclass, so
        // `index` should be considered to have non-abstract implementation.
        if is_getter
            && self.is_dart_core
            && self.store.element(instance_element).kind == ElementKind::CLASS
            && self.store.element(instance_element).name.as_deref() == Some("Enum")
            && name.as_deref() == Some("index")
        {
            self.store.fragment_mut(accessor_fragment).set_flag(executableFragment_isAbstract, false);
        }

        // If the accessor is already set, this is a compile-time error.
        // Reset to `null`, so create a new variable.
        if last_field_element != NO_ELEMENT {
            let existing = if is_getter {
                self.store.element(last_field_element).getter
            } else {
                self.store.element(last_field_element).setter
            };
            if existing != NO_ELEMENT {
                last_field_element = NO_ELEMENT;
            }
        }

        if last_field_element == NO_ELEMENT {
            let is_static = self.store.fragment(accessor_fragment).is_static();
            let field_fragment = self.new_fragment(FragmentKind::Field, name, unit);
            let f = self.store.fragment_mut(field_fragment);
            f.set_flag(propertyInducingFragment_isOriginGetterSetter, true);
            f.set_flag(variableFragment_isStatic, is_static);
            f.enclosing_fragment = instance_fragment;
            self.store.fragment_mut(instance_fragment).members_mut().fields.push(field_fragment);

            last_field_element = self.new_element(ElementKind::FIELD, field_fragment);
            self.store.element_mut(instance_element).members_mut().fields.push(last_field_element);
        }

        self.store.element_mut(accessor_element).variable = last_field_element;
        if is_getter {
            self.store.element_mut(last_field_element).getter = accessor_element;
        } else {
            self.store.element_mut(last_field_element).setter = accessor_element;
        }
    }

    fn handle_instance_getter_fragment(&mut self, instance: ElementId, last: FragmentId, fragment: FragmentId) {
        self.handle_instance_accessor_fragment(instance, last, fragment, true);
    }

    fn handle_instance_setter_fragment(&mut self, instance: ElementId, last: FragmentId, fragment: FragmentId) {
        self.handle_instance_accessor_fragment(instance, last, fragment, false);
    }

    /// `_handleInstanceMethodFragment`.
    fn handle_instance_method_fragment(
        &mut self,
        instance_element: ElementId,
        last_fragment: FragmentId,
        fragment: FragmentId,
    ) {
        let instance_fragment = self.store.fragment(fragment).enclosing_fragment;
        self.store.fragment_mut(instance_fragment).members_mut().methods.push(fragment);

        let is_augmentation = self.store.fragment(fragment).is_augmentation();
        if last_fragment != NO_FRAGMENT
            && self.store.fragment(last_fragment).kind == FragmentKind::Method
            && is_augmentation
        {
            self.store.add_fragment_to_chain(last_fragment, fragment);
            self.link_type_parameters(last_fragment, fragment);
            self.link_formal_parameters(last_fragment, fragment);
            return;
        }

        let element = self.new_element(ElementKind::METHOD, fragment);
        self.build_type_parameter_elements(fragment);
        self.executable_elements.push(element);
        if is_augmentation && last_fragment != NO_FRAGMENT {
            self.store.element_mut(element).previous_fragment_of_different_kind = last_fragment;
        }
        self.store.element_mut(instance_element).members_mut().methods.push(element);
    }

    /// `_handleTopLevelFunctionFragment`.
    fn handle_top_level_function_fragment(&mut self, unit: UnitId, last_fragment: FragmentId, fragment: FragmentId) {
        self.store.units[unit as usize].functions.push(fragment);

        let is_augmentation = self.store.fragment(fragment).is_augmentation();
        if last_fragment != NO_FRAGMENT
            && self.store.fragment(last_fragment).kind == FragmentKind::TopLevelFunction
            && is_augmentation
        {
            self.store.add_fragment_to_chain(last_fragment, fragment);
            self.link_type_parameters(last_fragment, fragment);
            self.link_formal_parameters(last_fragment, fragment);
            return;
        }

        let element = self.new_element(ElementKind::FUNCTION, fragment);
        self.build_type_parameter_elements(fragment);
        self.executable_elements.push(element);
        if is_augmentation && last_fragment != NO_FRAGMENT {
            self.store.element_mut(element).previous_fragment_of_different_kind = last_fragment;
        }
        self.lib().top_level_functions.push(element);
        self.library.declare(self.store, element);
    }

    /// `_handleTopLevelGetterFragment` and `_handleTopLevelSetterFragment`.
    fn handle_top_level_accessor_fragment(
        &mut self,
        unit: UnitId,
        last_fragment: FragmentId,
        accessor_fragment: FragmentId,
        is_getter: bool,
    ) {
        if is_getter {
            self.store.units[unit as usize].getters.push(accessor_fragment);
        } else {
            self.store.units[unit as usize].setters.push(accessor_fragment);
        }

        let mut last_variable_element = self.top_level_variable_element(last_fragment);
        let last_accessor_fragment = if last_variable_element != NO_ELEMENT {
            let accessor = if is_getter {
                self.store.element(last_variable_element).getter
            } else {
                self.store.element(last_variable_element).setter
            };
            if accessor != NO_ELEMENT {
                self.store.last_fragment(accessor)
            } else {
                NO_FRAGMENT
            }
        } else {
            NO_FRAGMENT
        };

        let is_augmentation = self.store.fragment(accessor_fragment).is_augmentation();
        if is_augmentation && last_accessor_fragment != NO_FRAGMENT {
            self.store.add_fragment_to_chain(last_accessor_fragment, accessor_fragment);
            self.link_formal_parameters(last_accessor_fragment, accessor_fragment);
            return;
        }

        // Not augmentation, create new element.
        let kind = if is_getter { ElementKind::GETTER } else { ElementKind::SETTER };
        let accessor_element = self.new_element(kind, accessor_fragment);
        self.executable_elements.push(accessor_element);
        if is_augmentation && last_fragment != NO_FRAGMENT {
            self.store.element_mut(accessor_element).previous_fragment_of_different_kind = last_fragment;
        }
        if is_getter {
            self.lib().getters.push(accessor_element);
        } else {
            self.lib().setters.push(accessor_element);
        }
        self.library.declare(self.store, accessor_element);

        // If the accessor is already set, this is a compile-time error.
        // Reset to `null`, so create a new variable.
        if last_variable_element != NO_ELEMENT {
            let existing = if is_getter {
                self.store.element(last_variable_element).getter
            } else {
                self.store.element(last_variable_element).setter
            };
            if existing != NO_ELEMENT {
                last_variable_element = NO_ELEMENT;
            }
        }

        if last_variable_element == NO_ELEMENT {
            let name = self.store.fragment(accessor_fragment).name.clone();
            let variable_fragment = self.new_fragment(FragmentKind::TopLevelVariable, name, unit);
            self.store
                .fragment_mut(variable_fragment)
                .set_flag(propertyInducingFragment_isOriginGetterSetter, true);
            self.store.units[unit as usize].top_level_variables.push(variable_fragment);

            last_variable_element = self.new_element(ElementKind::TOP_LEVEL_VARIABLE, variable_fragment);
            self.lib().top_level_variables.push(last_variable_element);
        }

        self.store.element_mut(accessor_element).variable = last_variable_element;
        if is_getter {
            self.store.element_mut(last_variable_element).getter = accessor_element;
        } else {
            self.store.element_mut(last_variable_element).setter = accessor_element;
        }
    }

    fn handle_top_level_getter_fragment(&mut self, unit: UnitId, last: FragmentId, fragment: FragmentId) {
        self.handle_top_level_accessor_fragment(unit, last, fragment, true);
    }

    fn handle_top_level_setter_fragment(&mut self, unit: UnitId, last: FragmentId, fragment: FragmentId) {
        self.handle_top_level_accessor_fragment(unit, last, fragment, false);
    }

    /// `_handleTopLevelVariableFragment`.
    fn handle_top_level_variable_fragment(
        &mut self,
        unit: UnitId,
        last_fragment: FragmentId,
        variable_fragment: FragmentId,
    ) {
        self.store.units[unit as usize].top_level_variables.push(variable_fragment);

        let vf = self.store.fragment(variable_fragment);
        let (is_augmentation, is_abstract, is_external, name, has_setter) = (
            vf.is_augmentation(),
            vf.is_abstract_variable(),
            vf.is_external_variable(),
            vf.name.clone(),
            vf.has_setter(),
        );
        let variable_element;
        let last_variable_element = self.top_level_variable_element(last_fragment);
        if is_augmentation && last_variable_element != NO_ELEMENT {
            let last = self.store.last_fragment(last_variable_element);
            self.store.add_fragment_to_chain(last, variable_fragment);
            variable_element = last_variable_element;
        } else {
            variable_element = self.new_element(ElementKind::TOP_LEVEL_VARIABLE, variable_fragment);
            if is_augmentation && last_fragment != NO_FRAGMENT {
                self.store.element_mut(variable_element).previous_fragment_of_different_kind = last_fragment;
            }
            self.lib().top_level_variables.push(variable_element);
        }

        {
            let getter_fragment = self.new_fragment(FragmentKind::Getter, name.clone(), unit);
            let g = self.store.fragment_mut(getter_fragment);
            g.set_flag(propertyAccessorFragment_isOriginVariable, true);
            g.set_flag(executableFragment_isAbstract, is_abstract);
            g.set_flag(fragment_isAugmentation, is_augmentation);
            g.set_flag(fragment_isComplete, is_external || !is_abstract);
            g.set_flag(executableFragment_isStatic, true);
            self.store.fragment_mut(variable_fragment).induced_getter = getter_fragment;
            self.store.units[unit as usize].getters.push(getter_fragment);

            let getter_element = self.store.element(variable_element).getter;
            if getter_element != NO_ELEMENT {
                let last_getter_fragment = self.store.last_fragment(getter_element);
                self.store.add_fragment_to_chain(last_getter_fragment, getter_fragment);
                self.link_formal_parameters(last_getter_fragment, getter_fragment);
            } else {
                let getter_element = self.new_element(ElementKind::GETTER, getter_fragment);
                self.executable_elements.push(getter_element);
                self.lib().getters.push(getter_element);
                self.library.declare(self.store, getter_element);
                self.store.element_mut(variable_element).getter = getter_element;
                self.store.element_mut(getter_element).variable = variable_element;
            }
        }

        if has_setter {
            let setter_fragment = self.new_fragment(FragmentKind::Setter, name, unit);
            let s = self.store.fragment_mut(setter_fragment);
            s.set_flag(propertyAccessorFragment_isOriginVariable, true);
            s.set_flag(executableFragment_isAbstract, is_abstract);
            s.set_flag(fragment_isAugmentation, is_augmentation);
            s.set_flag(fragment_isComplete, is_external || !is_abstract);
            s.set_flag(executableFragment_isStatic, true);
            self.store.fragment_mut(variable_fragment).induced_setter = setter_fragment;
            self.store.units[unit as usize].setters.push(setter_fragment);

            let value = self.new_fragment(FragmentKind::FormalParameter, Some(Rc::from("value")), unit);
            let v = self.store.fragment_mut(value);
            v.parameter_kind = ParameterKind::REQUIRED;
            v.enclosing_fragment = setter_fragment;
            self.store.fragment_mut(setter_fragment).formal_parameters = vec![value];

            let setter_element = self.store.element(variable_element).setter;
            if setter_element != NO_ELEMENT {
                let last_setter_fragment = self.store.last_fragment(setter_element);
                self.store.add_fragment_to_chain(last_setter_fragment, setter_fragment);
                self.link_formal_parameters(last_setter_fragment, setter_fragment);
            } else {
                let setter_element = self.new_element(ElementKind::SETTER, setter_fragment);
                self.executable_elements.push(setter_element);
                self.lib().setters.push(setter_element);
                self.library.declare(self.store, setter_element);
                self.store.element_mut(variable_element).setter = setter_element;
                self.store.element_mut(setter_element).variable = variable_element;
            }
        }
    }

    /// `_handleTypeAliasFragment`.
    fn handle_type_alias_fragment(&mut self, unit: UnitId, fragment: FragmentId) {
        self.store.units[unit as usize].type_aliases.push(fragment);
        let element = self.new_element(ElementKind::TYPE_ALIAS, fragment);
        self.build_type_parameter_elements(fragment);
        self.lib().type_aliases.push(element);
        self.library.declare(self.store, element);
    }

    /// `_linkFormalParameters`: joins the formal parameters of an
    /// augmentation to the ones of the fragment it augments.
    ///
    /// Not ported yet: an augmentation that adds or misses formal
    /// parameters (upstream grows the chains with
    /// `isOriginOtherFragmentOfEnclosing` parameters). Here the parameters
    /// are joined by position, then by name, which is what upstream does
    /// when both fragments declare the same parameters.
    fn link_formal_parameters(&mut self, previous: FragmentId, current: FragmentId) {
        let previous_parameters = self.store.fragment(previous).formal_parameters.clone();
        let current_parameters = self.store.fragment(current).formal_parameters.clone();
        let mut named: Vec<FragmentId> = Vec::new();
        for (i, &p) in previous_parameters.iter().enumerate() {
            if self.store.fragment(p).is_positional() {
                if let Some(&c) = current_parameters.get(i) {
                    let last = self.last_of_chain(p);
                    self.store.add_fragment_to_chain(last, c);
                }
            } else {
                named.push(p);
            }
        }
        for p in named {
            let name = self.store.fragment(p).name.clone();
            if let Some(&c) = current_parameters
                .iter()
                .find(|c| !self.store.fragment(**c).is_positional() && self.store.fragment(**c).name == name)
            {
                let last = self.last_of_chain(p);
                self.store.add_fragment_to_chain(last, c);
            }
        }
    }

    fn last_of_chain(&self, fragment: FragmentId) -> FragmentId {
        let mut current = fragment;
        while self.store.fragment(current).next_fragment != NO_FRAGMENT {
            current = self.store.fragment(current).next_fragment;
        }
        current
    }

    /// `_linkTypeParameters`, for fragments that declare the same type
    /// parameters (see `link_formal_parameters`).
    fn link_type_parameters(&mut self, previous: FragmentId, current: FragmentId) {
        let previous_parameters = self.store.fragment(previous).type_parameters.clone();
        let current_parameters = self.store.fragment(current).type_parameters.clone();
        for (p, c) in previous_parameters.iter().zip(&current_parameters) {
            let last = self.last_of_chain(*p);
            self.store.add_fragment_to_chain(last, *c);
        }
    }

    #[allow(dead_code)]
    fn units(&self) -> &[UnitId] {
        self.units
    }
}
