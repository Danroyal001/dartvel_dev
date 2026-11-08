// Port of the parts of lib/src/dart/resolver/binary_expression_resolver.dart
// (`_resolveEqual`, `_resolveUserDefinable`, `_resolveRightOperand`,
// `_resolveUserDefinableType`), unary_operator_invocation_resolver.dart and
// `TypeAnalyzer.visitReceiverIndexExpression` with
// `PropertyElementResolver.resolveReceiverIndexExpression` that type an
// operator invocation: `==`, `!=`, the user-definable binary operators, unary
// `-` and `~`, and `[]` without `?`. With them, the part of
// type_property_resolver.dart (`TypePropertyResolver.resolve`) that finds an
// operator through the interface of the receiver's static type, and the
// context the operator gives an integer literal operand
// (`_recordIntegerLiteralType`).
//
// An invocation is typed only when its operands are typed (by the earlier
// slices of type_analyzer.rs, or by this one) and its operator resolves as far
// as this port resolves it: through the interface (inheritance_manager3.rs) to
// a method with declared types, or not at all because the receiver is
// `dynamic`, invalid or `Never`. Not ported, so left untyped: extensions
// (upstream looks for one when the interface has no such member, or the
// receiver may be null), extension overrides, `super` receivers, members
// with types override inference would infer, `?[]` and cascades, flow
// analysis, implicit call tear-offs and generic function instantiation of
// an index's value, and diagnostics.
//
// Contexts are `Option<TypeImpl>`: `None` when this port does not know the
// context (the invocation is somewhere the earlier slices give no context
// to), `Some(TypeImpl::Unknown)` for none (`_`).

use std::collections::{HashMap, HashSet};

use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, ChildValue, NO_NODE, NodeId};
use crate::src::dart::element::class_hierarchy::ClassHierarchy;
use crate::src::dart::element::element::{ElementId, ElementKind, ElementStore};
use crate::src::dart::element::inheritance_manager3::{Member, MethodLookup, get_method};
use crate::src::dart::element::type_algebra::{Substitution, substitute};
use crate::src::dart::resolver::applicable_extensions::{extended_type, extension_method, extension_type_parameters};
use crate::src::dart::resolver::extension_member_resolver::{ExtensionOverride, override_member, override_type_arguments};
use crate::src::dart::resolver::type_property_resolver::{ExtensionScope, PropertyLookup, resolve};
use crate::src::dart::element::r#type::TypeImpl;
use crate::src::dart::element::subtype::TypeSystem;
use crate::src::dart::element::type_provider::TypeProviderImpl;
use crate::src::dart::element::type_system::{
    is_bottom, is_dynamic_bounded, is_invalid_bounded, object_type, promote_to_non_null,
    resolve_to_bound, sdk_class,
};
use crate::src::dart::resolver::type_analyzer::{IntegerContextSite, context_site, future_value_type};
use fe_analyzer_shared::scanner::token::NO_TOKEN;

/// The binary operators a `BinaryOperatorInvocation` invokes (its
/// `binaryOperator` is not null): `==`, `!=` and the user-definable ones.
const BINARY_OPERATORS: [&str; 18] =
    ["+", "-", "*", "/", "%", "~/", "<", ">", "<=", ">=", "&", "|", "^", "<<", ">>", ">>>", "==", "!="];

/// An operator invocation this file types.
#[derive(Clone, Debug)]
pub enum Invocation {
    Binary { left: NodeId, operator: String, right: NodeId },
    Unary { operator: String, operand: NodeId },
    Index { receiver: NodeId, index: NodeId },
}

/// [node] as an operator invocation this file types.
pub fn invocation(ast: Ast<'_>, node: NodeId) -> Option<Invocation> {
    match ast.node(node) {
        AstNodeImpl::BinaryOperatorInvocationImpl(b) => {
            let operator = ast.tokens.lexeme_string(b.operator_);
            BINARY_OPERATORS.contains(&operator.as_str()).then_some(Invocation::Binary {
                left: b.left_operand,
                operator,
                right: b.right_operand,
            })
        }
        AstNodeImpl::UnaryOperatorInvocationImpl(u) => {
            let operator = ast.tokens.lexeme_string(u.operator_);
            matches!(operator.as_str(), "-" | "~").then_some(Invocation::Unary { operator, operand: u.operand })
        }
        AstNodeImpl::ReceiverIndexExpressionImpl(r) if r.question == NO_TOKEN => {
            Some(Invocation::Index { receiver: r.receiver, index: r.index })
        }
        _ => None,
    }
}

impl Invocation {
    fn is_operand(&self, node: NodeId) -> bool {
        match *self {
            Invocation::Binary { left, right, .. } => node == left || node == right,
            Invocation::Unary { operand, .. } => node == operand,
            Invocation::Index { receiver, index } => node == receiver || node == index,
        }
    }
}

pub struct OperatorResolver<'s> {
    pub store: &'s mut ElementStore,
    pub hierarchy: ClassHierarchy,
    pub type_provider: &'s TypeProviderImpl,
    pub static_types: &'s mut HashMap<NodeId, TypeImpl>,
    pub annotation_types: &'s HashMap<NodeId, TypeImpl>,
    pub invocations: &'s mut HashSet<NodeId>,
    /// The extensions accessible in the file.
    pub extensions: &'s [ElementId],
    /// The explicit extension overrides of the file, by node.
    pub overrides: &'s HashMap<NodeId, ExtensionOverride>,
    pub inference_using_bounds: bool,
}

/// How an operator resolved: to a method, to none (the type then follows
/// from the receiver), or beyond what is ported.
enum Resolved {
    Method(Member),
    NoMethod,
    Unresolved,
}

impl OperatorResolver<'_> {
    /// Types the operator invocations under [node] (outside configurations
    /// and comments), each with the context its position gives.
    pub fn resolve(&mut self, ast: Ast<'_>, node: NodeId) {
        if matches!(ast.node(node), AstNodeImpl::ConfigurationImpl(_) | AstNodeImpl::CommentImpl(_)) {
            return;
        }
        if self.is_top(ast, node) {
            let context = self.position_context(ast, node);
            self.type_expression(ast, node, context);
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
    }

    /// Whether [node] is an invocation or parentheses that no enclosing
    /// invocation or parentheses types as its operand.
    fn is_top(&self, ast: Ast<'_>, node: NodeId) -> bool {
        if invocation(ast, node).is_none() && !matches!(ast.node(node), AstNodeImpl::ParenthesizedExpressionImpl(_)) {
            return false;
        }
        let parent = ast.parent2(node);
        if parent == NO_NODE || matches!(ast.node(parent), AstNodeImpl::ParenthesizedExpressionImpl(_)) {
            return parent == NO_NODE;
        }
        !invocation(ast, parent).is_some_and(|i| i.is_operand(node))
    }

    /// The context of [node] where an enclosing invocation does not give it
    /// one: an expression statement or interpolation gives none, a declared
    /// type annotation gives its type (`FutureOr<futureValueType(R)>` for a
    /// returned expression of an `async` body), and elsewhere it is not known.
    fn position_context(&mut self, ast: Ast<'_>, node: NodeId) -> Option<TypeImpl> {
        match context_site(ast, node)? {
            IntegerContextSite::None => Some(TypeImpl::Unknown),
            IntegerContextSite::Annotation(annotation) => self.annotation_types.get(&annotation).cloned(),
            IntegerContextSite::Return { annotation, is_async } => {
                let declared = self.annotation_types.get(&annotation).cloned()?;
                if is_async {
                    let value = future_value_type(self.store, &declared);
                    let future_or = sdk_class(self.store, "dart:async", "FutureOr")?;
                    Some(TypeImpl::interface(future_or, vec![value], NullabilitySuffix::none))
                } else {
                    Some(declared)
                }
            }
        }
    }

    /// The static type of [node] in the context [context], typing the
    /// operator invocations, parentheses and integer literals of its operand
    /// chain; `None` when it is not typed.
    fn type_expression(&mut self, ast: Ast<'_>, node: NodeId, context: Option<TypeImpl>) -> Option<TypeImpl> {
        let type_ = match ast.node(node) {
            AstNodeImpl::ParenthesizedExpressionImpl(p) => self.type_expression(ast, p.expression2, context)?,
            AstNodeImpl::IntegerLiteralImpl(_) => {
                if let Some(type_) = self.static_types.get(&node) {
                    return Some(type_.clone());
                }
                self.integer_literal_type(&context?)
            }
            _ => match invocation(ast, node) {
                Some(invocation) => {
                    let type_ = self.type_invocation(ast, invocation, context)?;
                    self.invocations.insert(node);
                    type_
                }
                None => return self.static_types.get(&node).cloned(),
            },
        };
        self.static_types.insert(node, type_.clone());
        Some(type_)
    }

    fn type_invocation(&mut self, ast: Ast<'_>, invocation: Invocation, context: Option<TypeImpl>) -> Option<TypeImpl> {
        match invocation {
            Invocation::Binary { left, operator, right } => match self.overrides.get(&left).cloned() {
                Some(extension_override) => self.type_binary_override(ast, &extension_override, &operator, right),
                None => self.type_binary(ast, left, &operator, right, context),
            },
            Invocation::Unary { operator, operand } => {
                if let Some(extension_override) = self.overrides.get(&operand).cloned() {
                    // `extension.getMethod(...)`, whose return type is not
                    // substituted.
                    self.override_type_arguments(ast, &extension_override)?;
                    let name = if operator == "-" { "unary-" } else { "~" };
                    let member = self.override_operator(&extension_override, name)?;
                    return Some(member.return_type(self.store));
                }
                // `UnaryOperatorInvocationResolver.resolve`: unary minus
                // passes its context to an integer literal operand.
                let operand_context =
                    if operator == "-" && matches!(ast.node(operand), AstNodeImpl::IntegerLiteralImpl(_)) {
                        context
                    } else {
                        Some(TypeImpl::Unknown)
                    };
                let operand_type = self.type_expression(ast, operand, operand_context)?;
                self.unary_type(&operator, &operand_type)
            }
            Invocation::Index { receiver, index } => {
                let resolution = match self.overrides.get(&receiver).cloned() {
                    Some(extension_override) => self.override_index_resolution(ast, &extension_override),
                    None => match self.type_expression(ast, receiver, Some(TypeImpl::Unknown)) {
                        Some(receiver_type) => self.index_resolution(&receiver_type),
                        None => None,
                    },
                };
                let Some((type_, index_context)) = resolution else {
                    self.type_expression(ast, index, None);
                    return None;
                };
                self.type_expression(ast, index, Some(index_context))?;
                Some(type_)
            }
        }
    }

    /// `_resolveUserDefinableElement`, `_resolveRightOperand` and
    /// `_resolveUserDefinableType` for an extension override operand: the
    /// extension's method unsubstituted, its parameter type as the right
    /// operand's context, no numeric refinement, and `Never` when the
    /// override's extended type is. `==` and `!=` find no method in an
    /// extension, which is not typed here.
    fn type_binary_override(
        &mut self,
        ast: Ast<'_>,
        extension_override: &ExtensionOverride,
        operator: &str,
        right: NodeId,
    ) -> Option<TypeImpl> {
        let member = match self.override_type_arguments(ast, extension_override) {
            Some(type_arguments) if operator != "==" && operator != "!=" => {
                self.override_operator(extension_override, operator).map(|member| (member, type_arguments))
            }
            _ => None,
        };
        let Some((member, type_arguments)) = member else {
            self.type_expression(ast, right, None);
            return None;
        };
        let right_context = member.parameter_types(self.store).into_iter().next().unwrap_or(TypeImpl::Unknown);
        self.type_expression(ast, right, Some(right_context))?;
        let substitution = Substitution::from_pairs(
            extension_type_parameters(self.store, extension_override.extension),
            type_arguments,
        );
        let declared = extended_type(self.store, extension_override.extension);
        if is_never(&substitute(self.store, &substitution, &declared)) {
            return Some(TypeImpl::Never(NullabilitySuffix::none));
        }
        Some(member.return_type(self.store))
    }

    /// `resolveReceiverIndexExpression` for an extension override receiver:
    /// `getOverrideMember(receiver, '[]')`, substituted, when it is an
    /// instance method with declared types.
    fn override_index_resolution(
        &mut self,
        ast: Ast<'_>,
        extension_override: &ExtensionOverride,
    ) -> Option<(TypeImpl, TypeImpl)> {
        let type_arguments = self.override_type_arguments(ast, extension_override)?;
        let member = override_member(self.store, extension_override.extension, &type_arguments, "[]")?;
        let fragment = self.store.fragment(self.store.element(member.element).first_fragment);
        if fragment.is_static() || member.has_implicit_types(self.store) {
            return None;
        }
        let parameters = member.parameter_types(self.store);
        let context = parameters.first().cloned().unwrap_or(TypeImpl::Unknown);
        let type_ = if parameters.len() == 1 { member.return_type(self.store) } else { TypeImpl::Invalid };
        Some((type_, context))
    }

    /// `BinaryExpressionResolver.resolveBinaryOperatorInvocation`.
    fn type_binary(
        &mut self,
        ast: Ast<'_>,
        left: NodeId,
        operator: &str,
        right: NodeId,
        context: Option<TypeImpl>,
    ) -> Option<TypeImpl> {
        let Some(left_type) = self.type_expression(ast, left, Some(TypeImpl::Unknown)) else {
            self.type_expression(ast, right, None);
            return None;
        };
        let left_bound = resolve_to_bound(self.store, &left_type);
        let never = TypeImpl::Never(NullabilitySuffix::none);
        if operator == "==" || operator == "!=" {
            // `_resolveEqual`: the right operand has no context, and the
            // receiver's type is made non-nullable for the lookup (after
            // the `Never` check).
            let element = if is_never(&left_type) {
                None
            } else {
                let promoted = promote_to_non_null(self.store, &left_type);
                match self.equality_method(&promoted) {
                    Some(member) => Some(member),
                    None => {
                        self.type_expression(ast, right, None);
                        return None;
                    }
                }
            };
            self.type_expression(ast, right, Some(TypeImpl::Unknown))?;
            // `_resolveUserDefinableType`.
            if is_never(&left_bound) {
                return Some(never);
            }
            if operator == "==" {
                return Some(self.type_provider.bool_type.clone());
            }
            return Some(match element {
                Some(member) => {
                    if has_implicit_return_type(self.store, &member) {
                        return None;
                    }
                    member.return_type(self.store)
                }
                None if matches!(left_bound, TypeImpl::Dynamic) => TypeImpl::Dynamic,
                None => TypeImpl::Invalid,
            });
        }
        // `_resolveUserDefinableElement`.
        let resolved = if is_never(&left_type) {
            Resolved::NoMethod
        } else {
            self.resolve_method(&left_type, operator)
        };
        let element = match resolved {
            Resolved::Method(member) => Some(member),
            Resolved::NoMethod => None,
            Resolved::Unresolved => {
                self.type_expression(ast, right, None);
                return None;
            }
        };
        // `_resolveRightOperand`.
        let right_context = match &element {
            Some(member) => {
                let parameter = member.parameter_types(self.store).into_iter().next();
                match parameter {
                    Some(_) if self.refines_numeric(member, &left_type) => {
                        context.map(|context| self.refined_context(&left_type, &context))
                    }
                    Some(parameter) => Some(parameter),
                    None => Some(TypeImpl::Unknown),
                }
            }
            None => Some(TypeImpl::Unknown),
        };
        let right_type = self.type_expression(ast, right, right_context)?;
        // `_resolveUserDefinableType`.
        if is_never(&left_bound) {
            return Some(never);
        }
        let current = match &element {
            Some(member) => member.return_type(self.store),
            None if matches!(left_bound, TypeImpl::Dynamic) => TypeImpl::Dynamic,
            None => TypeImpl::Invalid,
        };
        Some(match &element {
            Some(member) if self.refines_numeric(member, &left_bound) => {
                self.refined_type(&left_bound, &right_type)
            }
            _ => current,
        })
    }

    /// The `==` method `TypePropertyResolver.resolve` finds for the
    /// non-nullable [receiver]: `Object`'s where the interface has none
    /// (an extension cannot declare `==`); `None` when ambiguous.
    fn equality_method(&mut self, receiver: &TypeImpl) -> Option<Member> {
        let object = object_type(self.store, NullabilitySuffix::none);
        let receiver = if is_dynamic_bounded(self.store, receiver) || is_invalid_bounded(self.store, receiver) {
            object.clone()
        } else {
            resolve_to_bound(self.store, receiver)
        };
        let lookup = |this: &mut Self, type_: &TypeImpl| match type_.as_interface() {
            Some(i) => {
                let i = i.clone();
                get_method(&mut TypeSystem::new(this.store, &mut this.hierarchy), &i, "==")
            }
            None => MethodLookup::NotFound,
        };
        match lookup(self, &receiver) {
            MethodLookup::Found(member) => Some(member),
            MethodLookup::Ambiguous => None,
            MethodLookup::NotFound => match lookup(self, &object) {
                MethodLookup::Found(member) => Some(member),
                _ => None,
            },
        }
    }

    /// `TypePropertyResolver.resolve` of the operator [name] on [receiver],
    /// as far as it is ported: the interface's method, else an applicable
    /// extension's.
    fn resolve_method(&mut self, receiver: &TypeImpl, name: &str) -> Resolved {
        if is_dynamic_bounded(self.store, receiver) || is_invalid_bounded(self.store, receiver) {
            // Only `Object`'s members, and it has no operator but `==`.
            return Resolved::NoMethod;
        }
        let scope = ExtensionScope { extensions: self.extensions, inference_using_bounds: self.inference_using_bounds };
        match resolve(&mut TypeSystem::new(self.store, &mut self.hierarchy), &scope, receiver, name) {
            PropertyLookup::Member(member)
                if self.store.element(member.element).kind == ElementKind::METHOD
                    && !member.has_implicit_types(self.store) =>
            {
                Resolved::Method(member)
            }
            PropertyLookup::Never | PropertyLookup::DynamicBounded => Resolved::NoMethod,
            _ => Resolved::Unresolved,
        }
    }

    /// The method `extension.getMethod(name)` of the extension [extension_override]
    /// names, unsubstituted (as upstream's binary and unary operator
    /// resolution reads it), when it is an instance method with declared
    /// types.
    fn override_operator(&self, extension_override: &ExtensionOverride, name: &str) -> Option<Member> {
        let element = extension_method(self.store, extension_override.extension, name)?;
        let member = Member { element, substitution: Substitution::from_pairs(Vec::new(), Vec::new()), combined: None };
        let fragment = self.store.fragment(self.store.element(element).first_fragment);
        (!fragment.is_static() && !member.has_implicit_types(self.store)).then_some(member)
    }

    /// The type arguments `resolveOverride` gives [extension_override], whose
    /// argument is typed first (with no context known: an integer literal
    /// there stays untyped); `None` when the argument is not typed.
    fn override_type_arguments(&mut self, ast: Ast<'_>, extension_override: &ExtensionOverride) -> Option<Vec<TypeImpl>> {
        let argument_type = self.type_expression(ast, extension_override.argument, None)?;
        Some(override_type_arguments(
            &mut TypeSystem::new(self.store, &mut self.hierarchy),
            extension_override.extension,
            extension_override.type_arguments.clone(),
            &argument_type,
            self.inference_using_bounds,
        ))
    }

    /// `UnaryOperatorInvocationResolver.resolve`.
    fn unary_type(&mut self, operator: &str, operand: &TypeImpl) -> Option<TypeImpl> {
        match operand {
            TypeImpl::Dynamic => return Some(TypeImpl::Dynamic),
            TypeImpl::Invalid => return Some(TypeImpl::Invalid),
            _ if is_never(operand) => return Some(TypeImpl::Never(NullabilitySuffix::none)),
            _ => {}
        }
        let name = if operator == "-" { "unary-" } else { "~" };
        match self.resolve_method(operand, name) {
            Resolved::Method(member) => Some(member.return_type(self.store)),
            Resolved::NoMethod => Some(TypeImpl::Invalid),
            Resolved::Unresolved => None,
        }
    }

    /// `resolveReceiverIndexExpression`: the type of the index expression
    /// and the context of its index, `None` when unresolved.
    fn index_resolution(&mut self, receiver: &TypeImpl) -> Option<(TypeImpl, TypeImpl)> {
        let bound = resolve_to_bound(self.store, receiver);
        match &bound {
            _ if is_never(&bound) => return Some((TypeImpl::Never(NullabilitySuffix::none), TypeImpl::Unknown)),
            TypeImpl::Dynamic => return Some((TypeImpl::Dynamic, TypeImpl::Unknown)),
            TypeImpl::Void | TypeImpl::Invalid => return Some((TypeImpl::Invalid, TypeImpl::Unknown)),
            _ => {}
        }
        match self.resolve_method(&bound, "[]") {
            Resolved::Method(member) => {
                let parameters = member.parameter_types(self.store);
                let context = parameters.first().cloned().unwrap_or(TypeImpl::Unknown);
                let type_ = if parameters.len() == 1 { member.return_type(self.store) } else { TypeImpl::Invalid };
                Some((type_, context))
            }
            Resolved::NoMethod => Some((TypeImpl::Invalid, TypeImpl::Unknown)),
            Resolved::Unresolved => None,
        }
    }

    fn subtype(&mut self, a: &TypeImpl, b: &TypeImpl) -> bool {
        TypeSystem::new(self.store, &mut self.hierarchy).is_subtype_of(a, b)
    }

    fn core_type(&self, name: &str, suffix: NullabilitySuffix) -> TypeImpl {
        let class = sdk_class(self.store, "dart:core", name).unwrap_or_else(|| panic!("dart:core declares {name}"));
        TypeImpl::interface(class, Vec::new(), suffix)
    }

    /// Whether the numeric rules of `refineNumericInvocationContext` and
    /// `refineNumericInvocationType` apply to [member] invoked on a receiver
    /// of type [target]: `+`, `-`, `*` or `%` of an interface (not an
    /// extension type) on a subtype of `num?`.
    fn refines_numeric(&mut self, member: &Member, target: &TypeImpl) -> bool {
        let name = self.store.element(member.element).name.clone();
        if matches!(member.enclosing_kind(self.store), ElementKind::EXTENSION_TYPE | ElementKind::EXTENSION)
            || !matches!(name.as_deref(), Some("+" | "-" | "*" | "%"))
        {
            return false;
        }
        let num_question = self.core_type("num", NullabilitySuffix::question);
        self.subtype(target, &num_question)
    }

    /// `_refineNumericInvocationContextNullSafe` for a receiver of type
    /// [target] in the context [context].
    fn refined_context(&mut self, target: &TypeImpl, context: &TypeImpl) -> TypeImpl {
        let num = self.core_type("num", NullabilitySuffix::none);
        let int = self.core_type("int", NullabilitySuffix::none);
        let double = self.core_type("double", NullabilitySuffix::none);
        let num_in_context = self.subtype(&num, context);
        let int_question = self.core_type("int", NullabilitySuffix::question);
        if self.subtype(&int, context) && !num_in_context && self.subtype(target, &int_question) {
            return int;
        }
        let double_question = self.core_type("double", NullabilitySuffix::question);
        if self.subtype(&double, context) && !num_in_context && !self.subtype(target, &double_question) {
            return double;
        }
        num
    }

    /// `_refineNumericInvocationTypeNullSafe` for a receiver of type
    /// [target] and an argument of type [argument].
    fn refined_type(&mut self, target: &TypeImpl, argument: &TypeImpl) -> TypeImpl {
        let double = self.core_type("double", NullabilitySuffix::none);
        let double_question = self.core_type("double", NullabilitySuffix::question);
        if self.subtype(target, &double_question) {
            return double;
        }
        let argument_is_bottom = is_bottom(self.store, argument);
        if !argument_is_bottom && self.subtype(argument, &double_question) {
            return double;
        }
        let int_question = self.core_type("int", NullabilitySuffix::question);
        if !argument_is_bottom && self.subtype(target, &int_question) && self.subtype(argument, &int_question) {
            return self.core_type("int", NullabilitySuffix::none);
        }
        self.core_type("num", NullabilitySuffix::none)
    }

    /// `_recordIntegerLiteralType`: `double` when `int` is not assignable to
    /// [context] and `double` is.
    fn integer_literal_type(&mut self, context: &TypeImpl) -> TypeImpl {
        let int = self.type_provider.int_type.clone();
        let double = self.type_provider.double_type.clone();
        if self.subtype(&int, context) || !self.subtype(&double, context) { int } else { double }
    }
}

/// `identical(type, NeverTypeImpl.instance)`: the non-nullable `Never`.
fn is_never(type_: &TypeImpl) -> bool {
    matches!(type_, TypeImpl::Never(NullabilitySuffix::none))
}

fn has_implicit_return_type(store: &ElementStore, member: &Member) -> bool {
    use crate::src::dart::element::element::FragmentFlag;
    store
        .fragment(store.element(member.element).first_fragment)
        .has_flag(FragmentFlag::executableFragment_hasImplicitReturnType)
}
