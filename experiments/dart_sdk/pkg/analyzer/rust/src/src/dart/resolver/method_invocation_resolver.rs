// Port of the parts of lib/src/dart/resolver/method_invocation_resolver.dart
// (an invocation `r.m(...)` of a method the receiver has, or of the
// extension an override `E(x).m(...)` names), property_element_resolver.dart
// (`resolveReceiverPropertyExtraction`: a read `r.p` of a getter or field, or
// a method torn off) that type a member access on a typed receiver, with the
// context an invocation gives an integer literal argument
// (`_recordIntegerLiteralType` with the parameter's type). The member is
// found by type_property_resolver.rs (the interface, `Object` for a receiver
// that may be null, or the most specific applicable extension), or for an
// explicit extension override by extension_member_resolver.rs
// (`getOverrideMember`, with the override's type arguments written or
// inferred from its argument).
//
// A member access is typed only when its receiver (or the override's
// argument) is typed (by the earlier slices of type_analyzer.rs and
// binary_expression_resolver.rs, or by this one) and it resolves as far as
// this port resolves it: the receiver's type is not `dynamic`, invalid,
// `void` or `Never` (nor bounded by them), the name is not private, and the
// member found has declared types: for an invocation a method that is not
// generic, for a read a getter (a field's getter) or such a method; an
// override's member is not static. An implicit `this` access `m(...)` or `p`
// (an unqualified name type_analyzer.rs records as one: [ImplicitThis]) is
// resolved on the type of `this`, or to the member of the enclosing extension
// the lexical lookup found (`resolveUnqualified`, `ThisLookup`), by the same
// rules. A null-aware access `r?.m(...)` or `r?.p` looks the member up on
// the receiver's type made non-nullable (`promoteToNonNull`), and the head
// of a cascade section `t..m(...)` or `t..p` on the cascade's target (made
// non-nullable in a null-aware cascade `t?..m()`). Null shorting
// (`NullShortingMixin`): an access in a chain that a `?.` (or `?[`) starts
// has the member's type while the chain continues (it is the receiver of
// another access, an index, a call, an assignment target, type arguments or
// `!`) and that type
// made nullable where the chain ends (`finishNullShorting`). Not ported, so
// left untyped: index and assignment sections of cascades, `super`, `this` where it is not known (see type_analyzer.rs),
// static members and import
// prefixes, `dynamic`, `Never`, invalid and void receivers, `call` of
// functions, record fields, private names (a private field may be promoted
// by flow analysis, and a private name is looked up per library), generic
// methods and explicit type arguments, members with types override or
// top-level inference would infer, calls of getters (the getter read is
// typed, the call of its value is not), `remainder` and `clamp` on numbers
// (`refineNumericInvocationType` refines them from their arguments),
// implicit call tear-offs, flow analysis and diagnostics.

use std::collections::{HashMap, HashSet};

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NO_NODE, NodeId};
use crate::src::dart::element::class_hierarchy::ClassHierarchy;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentFlag, NO_ELEMENT};
use crate::src::dart::element::inheritance_manager3::Member;
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_provider::TypeProviderImpl;
use crate::src::dart::element::type_system::{is_dynamic_bounded, is_invalid_bounded, promote_to_non_null, resolve_to_bound, sdk_class};
use crate::src::dart::resolver::extension_member_resolver::{ExtensionOverride, override_member, override_type_arguments};
use crate::src::dart::resolver::type_property_resolver::{ExtensionScope, PropertyLookup, resolve};
use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId};

/// What kind of member access a node is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemberAccessKind {
    /// `r.m(...)`: a `ParsedValueArguments` whose operand is a
    /// `ParsedNameAccess`.
    Invocation,
    /// `r.p`: a `ParsedNameAccess` that is not invoked, or a
    /// `ReceiverPropertyExtraction`.
    Property,
}

/// The parts of a member access.
struct Access {
    kind: MemberAccessKind,
    receiver: NodeId,
    operator: TokenId,
    name: TokenId,
    /// The argument list of an invocation; `NO_NODE` for a read.
    argument_list: NodeId,
    /// The `ParsedNameAccess` (or, implicitly on `this`, the
    /// `ParsedUnqualifiedName`) an invocation invokes; `NO_NODE` for a read.
    name_access: NodeId,
    /// For an implicit `this` access, the `ParsedUnqualifiedName` of its
    /// name; `NO_NODE` otherwise.
    implicit: NodeId,
    /// For the head of a cascade section, the `CascadeExpression` (whose
    /// target is [receiver]); `NO_NODE` otherwise.
    cascade: NodeId,
}

/// An unqualified name that is an implicit `this` access: the type of `this`
/// where it is written, and the instance member of the enclosing extension
/// the lexical lookup found, if any (otherwise the member is looked up on
/// the type of `this`).
#[derive(Clone, Debug)]
pub struct ImplicitThis {
    pub this_type: TypeImpl,
    pub lexical: Option<ElementId>,
}

/// [node] as a member access: an invocation `r.m(...)` without type
/// arguments, or a read `r.p`. The AstBuilder builds a read as a
/// `ParsedNameAccess` when its receiver is a name (or a name access) and as a
/// `ReceiverPropertyExtraction` when it is a literal, parenthesized, `this`
/// or an index expression; a `ParsedNameAccess` that is the operand of value
/// or type arguments names the member invoked or instantiated, and is not a
/// read.
fn member_access(ast: Ast<'_>, node: NodeId) -> Option<Access> {
    match ast.node(node) {
        // The head of a cascade section: `..m(...)` is a `ParsedValueArguments`
        // whose operand is a `ParsedCascadeName`, `..p` a
        // `CascadePropertyExtraction`.
        AstNodeImpl::ParsedValueArgumentsImpl(v) if matches!(ast.node(v.operand), AstNodeImpl::ParsedCascadeNameImpl(_)) => {
            let (cascade, operator) = cascade_of(ast, node);
            Some(Access {
                kind: MemberAccessKind::Invocation,
                receiver: ast.node(cascade).as_cascade_expression_impl().target2,
                operator,
                name: ast.node(v.operand).as_parsed_cascade_name_impl().name,
                argument_list: v.argument_list,
                name_access: v.operand,
                implicit: NO_NODE,
                cascade,
            })
        }
        AstNodeImpl::CascadePropertyExtractionImpl(c) => {
            let (cascade, operator) = cascade_of(ast, node);
            Some(Access {
                kind: MemberAccessKind::Property,
                receiver: ast.node(cascade).as_cascade_expression_impl().target2,
                operator,
                name: c.name,
                argument_list: NO_NODE,
                name_access: NO_NODE,
                implicit: NO_NODE,
                cascade,
            })
        }
        AstNodeImpl::ParsedValueArgumentsImpl(v) => match ast.node(v.operand) {
            AstNodeImpl::ParsedNameAccessImpl(n) => Some(Access {
                kind: MemberAccessKind::Invocation,
                receiver: n.operand,
                operator: n.operator_,
                name: n.name,
                argument_list: v.argument_list,
                name_access: v.operand,
                implicit: NO_NODE,
            cascade: NO_NODE,
            }),
            _ => None,
        },
        AstNodeImpl::ParsedNameAccessImpl(n) => {
            let parent = ast.parent2(node);
            let applied = parent != NO_NODE
                && match ast.node(parent) {
                    AstNodeImpl::ParsedValueArgumentsImpl(v) => v.operand == node,
                    AstNodeImpl::ParsedTypeArgumentsImpl(t) => t.operand == node,
                    _ => false,
                };
            (!applied).then_some(Access {
                kind: MemberAccessKind::Property,
                receiver: n.operand,
                operator: n.operator_,
                name: n.name,
                argument_list: NO_NODE,
                name_access: NO_NODE,
                implicit: NO_NODE,
            cascade: NO_NODE,
            })
        }
        AstNodeImpl::ReceiverPropertyExtractionImpl(r) => Some(Access {
            kind: MemberAccessKind::Property,
            receiver: r.receiver,
            operator: r.operator_,
            name: r.name,
            argument_list: NO_NODE,
            name_access: NO_NODE,
            implicit: NO_NODE,
            cascade: NO_NODE,
        }),
        _ => None,
    }
}

/// The `CascadeExpression` whose section [head] begins, and that section's
/// `..` or `?..`.
fn cascade_of(ast: Ast<'_>, head: NodeId) -> (NodeId, TokenId) {
    let mut section = ast.parent2(head);
    while !matches!(ast.node(section), AstNodeImpl::CascadeSectionImpl(_)) {
        section = ast.parent2(section);
    }
    (ast.parent2(section), ast.node(section).as_cascade_section_impl().operator_)
}

/// Whether the cascade [cascade] is null aware: its first section begins
/// with `?..` (`CascadeExpression.isNullAware`).
fn is_null_aware_cascade(ast: Ast<'_>, cascade: NodeId) -> bool {
    let sections = &ast.node(cascade).as_cascade_expression_impl().sections;
    sections.first().is_some_and(|&section| {
        ast.tokens.lexeme_string(ast.node(section).as_cascade_section_impl().operator_) == "?.."
    })
}

/// Whether [node] is in a chain of null-aware accesses that a `?.` or `?[`
/// starts: a null-aware access or index, or an access, index, call, type
/// arguments or `!` whose operand is.
fn is_shorted(ast: Ast<'_>, node: NodeId) -> bool {
    match ast.node(node) {
        AstNodeImpl::ParsedNameAccessImpl(n) => ast.tokens.lexeme_string(n.operator_) == "?." || is_shorted(ast, n.operand),
        AstNodeImpl::ReceiverPropertyExtractionImpl(r) => {
            ast.tokens.lexeme_string(r.operator_) == "?." || is_shorted(ast, r.receiver)
        }
        AstNodeImpl::ParsedValueArgumentsImpl(v) => is_shorted(ast, v.operand),
        AstNodeImpl::ParsedTypeArgumentsImpl(t) => is_shorted(ast, t.operand),
        AstNodeImpl::CallInvocationImpl(c) => is_shorted(ast, c.receiver),
        AstNodeImpl::ReceiverIndexExpressionImpl(i) => i.question != NO_TOKEN || is_shorted(ast, i.receiver),
        AstNodeImpl::NullAssertionExpressionImpl(n) => is_shorted(ast, n.operand),
        _ => false,
    }
}

/// Whether null shorting continues past [node]: it is the receiver (not
/// parenthesized) of an access, an index, a call or an assignment target,
/// the operand of type or value arguments, or the operand of `!`
/// (`continueNullShorting`).
fn continues_null_shorting(ast: Ast<'_>, node: NodeId) -> bool {
    let parent = ast.parent2(node);
    if parent == NO_NODE {
        return false;
    }
    match ast.node(parent) {
        AstNodeImpl::ParsedNameAccessImpl(n) => n.operand == node,
        AstNodeImpl::ReceiverPropertyExtractionImpl(r) => r.receiver == node,
        AstNodeImpl::ParsedValueArgumentsImpl(v) => v.operand == node,
        AstNodeImpl::ParsedTypeArgumentsImpl(t) => t.operand == node,
        AstNodeImpl::CallInvocationImpl(c) => c.receiver == node,
        AstNodeImpl::ReceiverIndexExpressionImpl(i) => i.receiver == node,
        AstNodeImpl::NullAssertionExpressionImpl(n) => n.operand == node,
        AstNodeImpl::ParsedNameAccessAssignmentTargetImpl(t) => t.operand == node,
        AstNodeImpl::ReceiverIndexAssignmentTargetImpl(t) => t.receiver == node,
        AstNodeImpl::ReceiverPropertyAssignmentTargetImpl(t) => t.receiver == node,
        _ => false,
    }
}

fn un_parenthesized(ast: Ast<'_>, mut node: NodeId) -> NodeId {
    while let AstNodeImpl::ParenthesizedExpressionImpl(p) = ast.node(node) {
        node = p.expression2;
    }
    node
}

pub struct MemberResolver<'s> {
    pub store: &'s mut ElementStore,
    pub hierarchy: ClassHierarchy,
    pub type_provider: &'s TypeProviderImpl,
    pub static_types: &'s mut HashMap<NodeId, TypeImpl>,
    pub accesses: &'s mut HashMap<NodeId, MemberAccessKind>,
    pub arguments: &'s mut HashSet<NodeId>,
    /// The extensions accessible in the file.
    pub extensions: &'s [ElementId],
    /// The explicit extension overrides of the file, by node.
    pub overrides: &'s HashMap<NodeId, ExtensionOverride>,
    /// The implicit `this` accesses of the file, by name.
    pub implicit_this: &'s HashMap<NodeId, ImplicitThis>,
    pub inference_using_bounds: bool,
}

impl MemberResolver<'_> {
    /// Types the member accesses under [node] (outside configurations and
    /// comments), receivers before the accesses on them.
    pub fn resolve(&mut self, ast: Ast<'_>, node: NodeId) {
        if matches!(ast.node(node), AstNodeImpl::ConfigurationImpl(_) | AstNodeImpl::CommentImpl(_)) {
            return;
        }
        for child in ast.named_child_entities2(node) {
            match child.value {
                ChildValue::Node(id) => self.resolve(ast, id),
                ChildValue::NodeList(ids) => {
                    for &id in ids {
                        self.resolve(ast, id);
                    }
                }
                _ => (),
            }
        }
        if let Some(access) = member_access(ast, node).or_else(|| self.implicit_access(ast, node)) {
            if let Some(mut type_) = self.type_access(ast, &access) {
                // `finishNullShorting`: where a null-shorting chain ends, the
                // access is nullable.
                if is_shorted(ast, node) && !continues_null_shorting(ast, node) {
                    type_ = type_.with_nullability(self.store, NullabilitySuffix::question);
                }
                self.static_types.insert(node, type_);
                self.accesses.insert(node, access.kind);
            }
        }
    }

    /// [node] as an implicit `this` access (an unqualified name the analyzer
    /// recorded as one): an invocation `m(...)` without type arguments, or a
    /// read `p` that is not invoked.
    fn implicit_access(&self, ast: Ast<'_>, node: NodeId) -> Option<Access> {
        match ast.node(node) {
            AstNodeImpl::ParsedValueArgumentsImpl(v) if self.implicit_this.contains_key(&v.operand) => Some(Access {
                kind: MemberAccessKind::Invocation,
                receiver: NO_NODE,
                operator: NO_TOKEN,
                name: ast.node(v.operand).as_parsed_unqualified_name_impl().name,
                argument_list: v.argument_list,
                name_access: v.operand,
                implicit: v.operand,
                cascade: NO_NODE,
            }),
            AstNodeImpl::ParsedUnqualifiedNameImpl(n) if self.implicit_this.contains_key(&node) => {
                let parent = ast.parent2(node);
                if let AstNodeImpl::ParsedValueArgumentsImpl(v) = ast.node(parent) {
                    if v.operand == node {
                        return None;
                    }
                }
                Some(Access {
                    kind: MemberAccessKind::Property,
                    receiver: NO_NODE,
                    operator: NO_TOKEN,
                    name: n.name,
                    argument_list: NO_NODE,
                    name_access: NO_NODE,
                    implicit: node,
                    cascade: NO_NODE,
                })
            }
            _ => None,
        }
    }

    /// Whether a member access on a receiver of type [type_] is resolved by
    /// member lookup here: not `dynamic`, invalid, `void` or `Never`, nor
    /// bounded by them.
    fn is_member_receiver(&mut self, type_: &TypeImpl) -> bool {
        !(matches!(type_, TypeImpl::Never(_) | TypeImpl::Void)
            || is_dynamic_bounded(self.store, type_)
            || is_invalid_bounded(self.store, type_)
            || matches!(resolve_to_bound(self.store, type_), TypeImpl::Never(_)))
    }

    /// The static type of a receiver: an integer literal has no context
    /// (`int`); otherwise what an earlier slice or this one typed.
    fn receiver_type(&self, ast: Ast<'_>, receiver: NodeId) -> Option<TypeImpl> {
        let receiver = un_parenthesized(ast, receiver);
        if let AstNodeImpl::IntegerLiteralImpl(_) = ast.node(receiver) {
            return Some(self.type_provider.int_type.clone());
        }
        self.static_types.get(&receiver).cloned()
    }

    /// The type of [access], typing the integer literal arguments of an
    /// invocation; `None` when it is not resolved as far as this port goes.
    fn type_access(&mut self, ast: Ast<'_>, access: &Access) -> Option<TypeImpl> {
        // An implicit `this` access has no operator.
        let operator = if access.operator == NO_TOKEN { String::new() } else { ast.tokens.lexeme_string(access.operator) };
        let null_aware = if access.cascade != NO_NODE {
            if operator != ".." && operator != "?.." {
                return None;
            }
            is_null_aware_cascade(ast, access.cascade)
        } else {
            if access.implicit == NO_NODE && operator != "." && operator != "?." {
                return None;
            }
            operator == "?."
        };
        // An extension override is not a cascade target: upstream reports it
        // (`extensionOverrideWithCascade`) and resolves no section on it.
        if access.cascade != NO_NODE && self.overrides.contains_key(&access.receiver) {
            return None;
        }
        let name = ast.tokens.lexeme_string(access.name);
        if name.starts_with('_') {
            return None;
        }
        // The member, and the receiver's type when it is an expression.
        let implicit = self.implicit_this.get(&access.implicit).cloned();
        let (member, receiver_type) = match (implicit, self.overrides.get(&access.receiver)) {
            (Some(implicit), _) => {
                // `resolveUnqualified` and `ThisLookup`: the member of the
                // enclosing extension the lexical lookup found, else the
                // member of the type of `this`.
                let this_type = implicit.this_type;
                if !self.is_member_receiver(&this_type) {
                    return None;
                }
                let member = match implicit.lexical {
                    Some(element) => Member { element, substitution: Default::default(), combined: None },
                    None => {
                        let scope = ExtensionScope { extensions: self.extensions, inference_using_bounds: self.inference_using_bounds };
                        match resolve(&mut TypeSystem::new(self.store, &mut self.hierarchy), &scope, &this_type, &name) {
                            PropertyLookup::Member(member) => member,
                            _ => return None,
                        }
                    }
                };
                if self.store.fragment(self.store.element(member.element).first_fragment).is_static() {
                    return None;
                }
                (member, Some(this_type))
            }
            (None, Some(extension_override)) => {
                // `getOverrideMember`, with the type arguments
                // `resolveOverride` gives the override; a static member is
                // reported upstream.
                let extension_override = extension_override.clone();
                let argument_type = self.override_argument_type(ast, &extension_override)?;
                let type_arguments = override_type_arguments(
                    &mut TypeSystem::new(self.store, &mut self.hierarchy),
                    extension_override.extension,
                    extension_override.type_arguments.clone(),
                    &argument_type,
                    self.inference_using_bounds,
                );
                let member = override_member(self.store, extension_override.extension, &type_arguments, &name)?;
                if self.store.fragment(self.store.element(member.element).first_fragment).is_static() {
                    return None;
                }
                (member, None)
            }
            (None, None) => {
                // An integer literal cascade target has the cascade's
                // context (`double d = 1..m()` makes it a `double`), which
                // this port does not give it.
                if access.cascade != NO_NODE
                    && matches!(ast.node(un_parenthesized(ast, access.receiver)), AstNodeImpl::IntegerLiteralImpl(_))
                {
                    return None;
                }
                let mut receiver_type = self.receiver_type(ast, access.receiver)?;
                if null_aware {
                    receiver_type = promote_to_non_null(self.store, &receiver_type);
                }
                if !self.is_member_receiver(&receiver_type) {
                    return None;
                }
                let scope = ExtensionScope { extensions: self.extensions, inference_using_bounds: self.inference_using_bounds };
                let member = match resolve(&mut TypeSystem::new(self.store, &mut self.hierarchy), &scope, &receiver_type, &name) {
                    PropertyLookup::Member(member) => member,
                    _ => return None,
                };
                (member, Some(receiver_type))
            }
        };
        let kind = self.store.element(member.element).kind;
        match access.kind {
            MemberAccessKind::Invocation => {
                // `r.g(...)` of a getter is a read of the getter, whose value
                // is then called (`FunctionExpressionInvocation`, not typed).
                if kind == ElementKind::GETTER && self.is_declared_getter(&member) {
                    let type_ = member.return_type(self.store);
                    self.static_types.insert(access.name_access, type_);
                    self.accesses.insert(access.name_access, MemberAccessKind::Property);
                    return None;
                }
                if kind != ElementKind::METHOD || !self.is_declared_method(&member) {
                    return None;
                }
                if let Some(receiver_type) = &receiver_type {
                    if self.refines_numeric(&member, &name, receiver_type) {
                        return None;
                    }
                }
                self.type_arguments(ast, access.argument_list, &member);
                Some(member.return_type(self.store))
            }
            MemberAccessKind::Property => match kind {
                ElementKind::METHOD if self.is_declared_method(&member) => {
                    Some(TypeImpl::Function(std::rc::Rc::new(member.function_type(self.store))))
                }
                ElementKind::GETTER if self.is_declared_getter(&member) => Some(member.return_type(self.store)),
                _ => None,
            },
        }
    }

    /// The static type of the argument of [extension_override], when it is
    /// typed (an integer literal there has a context this port does not
    /// give it).
    fn override_argument_type(&self, ast: Ast<'_>, extension_override: &ExtensionOverride) -> Option<TypeImpl> {
        let argument = un_parenthesized(ast, extension_override.argument);
        if let AstNodeImpl::IntegerLiteralImpl(_) = ast.node(argument) {
            return None;
        }
        self.static_types.get(&argument).cloned()
    }

    /// Gives each integer literal argument (past parentheses) of an
    /// invocation of [member] the type its parameter's type as the context
    /// makes it; an argument that matches no parameter is left untyped.
    fn type_arguments(&mut self, ast: Ast<'_>, argument_list: NodeId, member: &Member) {
        let parameters = member.formal_parameters(self.store);
        let arguments = ast.node(argument_list).as_argument_list_impl().arguments2.clone();
        let mut positional = parameters.iter().filter(|p| p.kind.is_positional());
        for argument in arguments {
            let (parameter, expression) = match ast.node(argument) {
                AstNodeImpl::NamedArgumentImpl(n) => {
                    let name = ast.tokens.lexeme_string(n.name);
                    (parameters.iter().find(|p| p.is_named() && p.name.as_deref() == Some(&name)), n.argument_expression2)
                }
                _ => (positional.next(), argument),
            };
            let literal = un_parenthesized(ast, expression);
            let (Some(parameter), AstNodeImpl::IntegerLiteralImpl(_)) = (parameter, ast.node(literal)) else {
                continue;
            };
            let type_ = self.integer_literal_type(&parameter.type_.clone());
            self.static_types.insert(literal, type_);
            self.arguments.insert(literal);
        }
    }

    /// Whether [member] is a method that is not generic, with a declared
    /// return type and declared parameter types.
    fn is_declared_method(&self, member: &Member) -> bool {
        let first = self.store.element(member.element).first_fragment;
        self.store.fragment(first).type_parameters.is_empty() && !member.has_implicit_types(self.store)
    }

    /// Whether [member] is a getter with a declared return type: for the
    /// getter of a field, a field with a declared type.
    fn is_declared_getter(&self, member: &Member) -> bool {
        let element = self.store.element(member.element);
        let fragment = self.store.fragment(element.first_fragment);
        if fragment.has_flag(FragmentFlag::propertyAccessorFragment_isOriginVariable) {
            if element.variable == NO_ELEMENT {
                return false;
            }
            let variable = self.store.element(element.variable);
            !self.store.fragment(variable.first_fragment).has_flag(FragmentFlag::variableFragment_hasImplicitType)
        } else {
            !fragment.has_flag(FragmentFlag::executableFragment_hasImplicitReturnType)
        }
    }

    /// Whether `refineNumericInvocationType` refines the type of an
    /// invocation of [member] (`remainder` or `clamp` of an interface, not
    /// an extension type) on a receiver of type [target], a subtype of
    /// `num?`, from its arguments.
    fn refines_numeric(&mut self, member: &Member, name: &str, target: &TypeImpl) -> bool {
        if matches!(member.enclosing_kind(self.store), ElementKind::EXTENSION_TYPE | ElementKind::EXTENSION) || !matches!(name, "remainder" | "clamp") {
            return false;
        }
        let num = sdk_class(self.store, "dart:core", "num").expect("dart:core declares num");
        let num_question = TypeImpl::interface(num, Vec::new(), NullabilitySuffix::question);
        TypeSystem::new(self.store, &mut self.hierarchy).is_subtype_of(target, &num_question)
    }

    /// `_recordIntegerLiteralType`: `double` when `int` is not assignable to
    /// [context] and `double` is.
    fn integer_literal_type(&mut self, context: &TypeImpl) -> TypeImpl {
        let int = self.type_provider.int_type.clone();
        let double = self.type_provider.double_type.clone();
        let mut system = TypeSystem::new(self.store, &mut self.hierarchy);
        if system.is_subtype_of(&int, context) || !system.is_subtype_of(&double, context) { int } else { double }
    }
}
