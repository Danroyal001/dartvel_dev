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
// override's member is not static. Not ported, so left untyped: `?.`,
// cascades, `super`, `this` and implicit `this`, static members and import
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
use crate::src::dart::element::type_system::{is_dynamic_bounded, is_invalid_bounded, resolve_to_bound, sdk_class};
use crate::src::dart::resolver::extension_member_resolver::{ExtensionOverride, override_member, override_type_arguments};
use crate::src::dart::resolver::type_property_resolver::{ExtensionScope, PropertyLookup, resolve};
use fe_analyzer_shared::scanner::token::TokenId;

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
    /// The `ParsedNameAccess` an invocation invokes; `NO_NODE` for a read.
    name_access: NodeId,
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
        AstNodeImpl::ParsedValueArgumentsImpl(v) => match ast.node(v.operand) {
            AstNodeImpl::ParsedNameAccessImpl(n) => Some(Access {
                kind: MemberAccessKind::Invocation,
                receiver: n.operand,
                operator: n.operator_,
                name: n.name,
                argument_list: v.argument_list,
                name_access: v.operand,
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
            })
        }
        AstNodeImpl::ReceiverPropertyExtractionImpl(r) => Some(Access {
            kind: MemberAccessKind::Property,
            receiver: r.receiver,
            operator: r.operator_,
            name: r.name,
            argument_list: NO_NODE,
            name_access: NO_NODE,
        }),
        _ => None,
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
        if let Some(access) = member_access(ast, node) {
            if let Some(type_) = self.type_access(ast, &access) {
                self.static_types.insert(node, type_);
                self.accesses.insert(node, access.kind);
            }
        }
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
        if ast.tokens.lexeme_string(access.operator) != "." {
            return None;
        }
        let name = ast.tokens.lexeme_string(access.name);
        if name.starts_with('_') {
            return None;
        }
        // The member, and the receiver's type when it is an expression.
        let (member, receiver_type) = match self.overrides.get(&access.receiver) {
            Some(extension_override) => {
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
            None => {
                let receiver_type = self.receiver_type(ast, access.receiver)?;
                if matches!(receiver_type, TypeImpl::Never(_) | TypeImpl::Void)
                    || is_dynamic_bounded(self.store, &receiver_type)
                    || is_invalid_bounded(self.store, &receiver_type)
                    || matches!(resolve_to_bound(self.store, &receiver_type), TypeImpl::Never(_))
                {
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
