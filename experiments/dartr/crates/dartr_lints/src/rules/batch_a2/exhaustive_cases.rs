// Dart source: pkg/linter/lib/src/rules/exhaustive_cases.dart

use crate::{LinterContext, RuleVisitorRegistry};
use dartr_ast::*;
use dartr_constant::DartObjectImpl;
use dartr_diagnostics::{Diagnostic, diag};
use dartr_element::{
    ClassElement, EId, ElementFlags, ElementId, FragmentFlags, GetterElement, Tag, TypeKind,
};
use dartr_typesystem::{TypeExt, member};

pub fn register(registry: &mut RuleVisitorRegistry, _: &LinterContext<'_>) {
    registry.add(NodeKind::SwitchStatement, "exhaustive_cases", check);
}
fn check(context: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
    let Some(resolved) = context.resolved else {
        return;
    };
    let switch = &context.ast[context.ast.cast::<SwitchStatement>(node).unwrap()];
    let Some(TypeKind::Interface { element, .. }) = context
        .static_type(switch.expression)
        .map(|t| *resolved.ctx.ty(t))
    else {
        return;
    };
    // Handled in analyzer.
    let Some(class) = element.raw().cast::<ClassElement>() else {
        return;
    };
    let Some(mut constants) = as_enum_like_class(context, class) else {
        return;
    };
    let ts = crate::constants::ConstantTypeSystem(resolved.ctx);
    for &member_node in context.ast.list(switch.members) {
        // Dart: `expression.element.variableElement` of an `Identifier`, or
        // of the property name of a `PropertyAccess` or a
        // `DotShorthandPropertyAccess`, then `computeConstantValue()`.
        let expression = switch_member_expression(context, member_node.raw());
        let element = expression.and_then(|expression| {
            if let Some(prefixed) = context.ast.cast::<PrefixedIdentifier>(expression) {
                // Dart `PrefixedIdentifier.element` is `identifier.element`.
                context.element(context.ast[prefixed].identifier)
            } else if Identifier::test(context.ast.kind(expression)) {
                context.element(expression)
            } else if let Some(access) = context.ast.cast::<PropertyAccess>(expression) {
                context.element(context.ast[access].property_name)
            } else if let Some(dot) = context.ast.cast::<DotShorthandPropertyAccess>(expression) {
                context.element(context.ast[dot].property_name)
            } else {
                None
            }
        });
        let variable = element
            .map(|element| member::base_element(&resolved.ctx, element))
            .map(|element| match element.cast::<GetterElement>() {
                Some(getter) => resolved
                    .ctx
                    .get(getter)
                    .variable
                    .get()
                    .map_or(element, |variable| variable.raw()),
                None => element,
            })
            .filter(|&element| is_variable_element(element));
        if let Some(value) = variable.and_then(|variable| compute_constant_value(context, variable))
        {
            if let Some(index) = constants
                .iter()
                .position(|(candidate, _)| candidate.dart_eq(&value, &ts))
            {
                constants.remove(index);
            }
        }
        if context.ast.kind(member_node) == NodeKind::SwitchDefault {
            return;
        }
    }
    // Use the same offset as MISSING_ENUM_CONSTANT_IN_SWITCH.
    let start = context.ast.offset(node) as usize;
    let length = (context.ast.tokens.get(switch.right_parenthesis).end() - context.ast.offset(node))
        as usize;
    for (_, fields) in constants {
        let preferred = fields
            .iter()
            .copied()
            .find(|&field| !has_deprecated(context, field))
            .or_else(|| fields.first().copied());
        if let Some(name) = preferred.and_then(|field| resolved.ctx.element_name(field)) {
            context.report_offset(out, &diag::EXHAUSTIVE_CASES, start, length, &[name]);
        }
    }
}

/// Dart `VariableElement`: the elements whose `computeConstantValue()`
/// the rule reads.
fn is_variable_element(element: ElementId) -> bool {
    matches!(
        element.tag(),
        Tag::Field
            | Tag::TopLevelVariable
            | Tag::LocalVariable
            | Tag::FormalParameter
            | Tag::FieldFormalParameter
            | Tag::SuperFormalParameter
    )
}

/// Dart `VariableElement.computeConstantValue()`: through the analyzer's
/// constant engine when the driver gives element access (any library),
/// otherwise from the initializer in the analyzed library.
fn compute_constant_value(
    context: &LinterContext<'_>,
    variable: ElementId,
) -> Option<DartObjectImpl> {
    if let Some(metadata) = context.resolved.and_then(|r| r.metadata) {
        return metadata.element_constant_value(variable);
    }
    let (declaration_context, declaration) = declaration_context(context, variable)?;
    declaration_context
        .ast
        .cast::<VariableDeclaration>(declaration)
        .and_then(|variable| declaration_context.ast[variable].initializer)
        .and_then(|expression| declaration_context.constant_value(expression))
}

/// Dart `element.metadata.hasDeprecated`.
fn has_deprecated(context: &LinterContext<'_>, element: ElementId) -> bool {
    if let Some(metadata) = context.resolved.and_then(|r| r.metadata) {
        return metadata.annotations(element).into_iter().any(|annotation| {
            metadata
                .annotation_element(annotation)
                .is_some_and(|annotation_element| {
                    super::super::batch_b::util::is_deprecated_annotation_element(
                        context,
                        annotation_element,
                    )
                })
        });
    }
    declaration_context(context, element).is_some_and(|(declaration_context, declaration)| {
        variable_is_deprecated(&declaration_context, declaration)
    })
}

/// Dart `InterfaceElementExtension.asEnumLikeClass` (linter
/// `extensions.dart`): the values of the static const fields of [class]
/// whose type is the class, each with the fields that have it, in field
/// order (`EnumLikeClassDescription.enumConstants`); `None` when [class] is
/// not enum-like.
pub(crate) fn as_enum_like_class(
    context: &LinterContext<'_>,
    class: EId<ClassElement>,
) -> Option<Vec<(DartObjectImpl, Vec<ElementId>)>> {
    let resolved = context.resolved?;
    let ctx = &resolved.ctx;
    let element = class.upcast();
    // Must be concrete.
    if ctx
        .get(class)
        .flags
        .has(ElementFlags::CLASS_ELEMENT_IS_ABSTRACT)
    {
        return None;
    }
    // With only private non-factory constructors.
    let interface = ctx.interface(element);
    for &constructor in &interface.constructors {
        let data = ctx.get(constructor);
        let name = data.name.map(|n| ctx.name_str(n)).unwrap_or("");
        let factory = ctx
            .fragment_data(data.first_fragment)
            .is_some_and(|f| f.flags.has(FragmentFlags::CONSTRUCTOR_FRAGMENT_IS_FACTORY));
        if !name.starts_with('_') || factory {
            return None;
        }
    }
    let this_type = ctx.interface_this_type(element);
    let ts = crate::constants::ConstantTypeSystem(*ctx);
    // And 2 or more static const fields whose type is the enclosing class.
    let mut enum_constant_count = 0;
    let mut enum_constants: Vec<(DartObjectImpl, Vec<ElementId>)> = vec![];
    for &field in &interface.fields {
        let data = ctx.get(field);
        let Some(fragment) = ctx.fragment_data(data.first_fragment) else {
            continue;
        };
        // Ensure static const.
        if fragment
            .flags
            .has(FragmentFlags::PROPERTY_INDUCING_FRAGMENT_IS_ORIGIN_GETTER_SETTER)
            || !fragment
                .flags
                .has(FragmentFlags::VARIABLE_FRAGMENT_IS_CONST)
            || !fragment
                .flags
                .has(FragmentFlags::VARIABLE_FRAGMENT_IS_STATIC)
        {
            continue;
        }
        // Check for type equality (Dart `field.type != type`).
        let field_type = member::type_(ctx, dartr_element::ElemRef::Base(field.raw()));
        if !dartr_typesystem::equality::dart_eq(ctx, field_type, this_type) {
            continue;
        }
        let Some(value) = compute_constant_value(context, field.raw()) else {
            continue;
        };
        enum_constant_count += 1;
        match enum_constants
            .iter_mut()
            .find(|(candidate, _)| candidate.dart_eq(&value, &ts))
        {
            Some((_, fields)) => fields.push(field.raw()),
            None => enum_constants.push((value, vec![field.raw()])),
        }
    }
    if enum_constant_count < 2 {
        return None;
    }
    // And no subclasses in the defining library
    // (`_hasSubclassInDefiningCompilationUnit`: `superclass` types compared
    // with `==`).
    if let Some(library) = ctx.get(class).library {
        for &other in &ctx.get(library).classes {
            let mut class_type = Some(ctx.interface_this_type(other.upcast()));
            loop {
                class_type = class_type.and_then(|ty| ctx.superclass(ty));
                let Some(ty) = class_type else {
                    break;
                };
                if dartr_typesystem::equality::dart_eq(ctx, ty, this_type) {
                    return None;
                }
                if ctx.is_dart_core_object(ty) {
                    break;
                }
            }
        }
    }
    Some(enum_constants)
}

fn declaration_context<'a>(
    context: &LinterContext<'a>,
    element: dartr_element::ElementId,
) -> Option<(LinterContext<'a>, NodeId)> {
    for unit in std::iter::once(*context).chain(
        (0..context.resolved_units.len())
            .filter(|&index| index != context.current_unit)
            .filter_map(|index| context.resolved_unit(index)),
    ) {
        if let Some(node) = (0..unit.ast.node_count())
            .map(NodeId::from_index)
            .find(|&node| unit.declared_element(node) == Some(element))
        {
            return Some((unit, node));
        }
    }
    None
}

fn unparenthesized_expression(context: &LinterContext<'_>, mut node: NodeId) -> NodeId {
    while let Some(parenthesized) = context.ast.cast::<ParenthesizedExpression>(node) {
        node = context.ast[parenthesized].expression.raw();
    }
    node
}

fn unparenthesized_pattern(context: &LinterContext<'_>, mut node: NodeId) -> NodeId {
    while let Some(parenthesized) = context.ast.cast::<ParenthesizedPattern>(node) {
        node = context.ast[parenthesized].pattern.raw();
    }
    node
}

fn switch_member_expression(context: &LinterContext<'_>, member: NodeId) -> Option<NodeId> {
    if let Some(case) = context.ast.cast::<SwitchCase>(member) {
        return Some(unparenthesized_expression(
            context,
            context.ast[case].expression.raw(),
        ));
    }
    let pattern_case = context.ast.cast::<SwitchPatternCase>(member)?;
    let pattern = unparenthesized_pattern(
        context,
        context.ast[context.ast[pattern_case].guarded_pattern]
            .pattern
            .raw(),
    );
    let constant = context.ast.cast::<ConstantPattern>(pattern)?;
    Some(unparenthesized_expression(
        context,
        context.ast[constant].expression.raw(),
    ))
}

fn variable_is_deprecated(context: &LinterContext<'_>, variable: NodeId) -> bool {
    let declaration = &context.ast[context.ast.cast::<VariableDeclaration>(variable).unwrap()];
    if super::deprecated_consistency::has_deprecated(context, declaration.metadata) {
        return true;
    }
    context
        .ast
        .parent(variable)
        .and_then(|parent| context.ast.cast::<VariableDeclarationList>(parent))
        .and_then(|list| context.ast.parent(list.raw()))
        .and_then(|parent| context.ast.cast::<FieldDeclaration>(parent))
        .is_some_and(|field| {
            super::deprecated_consistency::has_deprecated(context, context.ast[field].metadata)
        })
}
