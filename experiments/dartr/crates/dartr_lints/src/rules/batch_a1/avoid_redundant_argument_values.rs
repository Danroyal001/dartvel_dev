// Dart source: pkg/linter/lib/src/rules/avoid_redundant_argument_values.dart

use crate::{LinterContext, RuleVisitorRegistry};
use dartr_ast::{
    ArgumentList, Id, InstanceCreationExpression, MethodInvocation, NamedArgument, NodeId, NodeKind,
};
use dartr_diagnostics::{Diagnostic, diag};
use dartr_element::{ConstructorElement, EId, ElemRef, FormalParameterElement};
use dartr_typesystem::{TypeExt, member};
use indexmap::IndexSet;

pub fn register(registry: &mut RuleVisitorRegistry, _: &LinterContext<'_>) {
    registry.add(
        NodeKind::ArgumentList,
        "avoid_redundant_argument_values",
        check,
    );
}

fn check(c: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
    let (Some(r), Some(ts)) = (c.resolved, c.constant_type_system()) else {
        return;
    };
    let arguments = c
        .ast
        .list_raw(c.ast[Id::<ArgumentList>::from_raw(node)].arguments);
    if arguments.is_empty() {
        return;
    }
    if c.ast.parent(node).is_none_or(|parent| {
        !matches!(
            c.ast.kind(parent),
            NodeKind::Annotation
                | NodeKind::EnumConstantArguments
                | NodeKind::FunctionExpressionInvocation
                | NodeKind::InstanceCreationExpression
                | NodeKind::MethodInvocation
        )
    }) {
        return;
    }
    let redirected = match redirected_parameters(c, node) {
        Ok(parameters) => parameters,
        Err(()) => return,
    };
    let mut positional_indices = vec![None; arguments.len()];
    let mut positional = 0;
    for (index, argument) in arguments.iter().enumerate() {
        if c.ast.kind(*argument) != NodeKind::NamedArgument {
            positional_indices[index] = Some(positional);
            positional += 1;
        }
    }
    for (index, argument) in arguments.iter().enumerate().rev() {
        let expression = c
            .ast
            .cast::<NamedArgument>(*argument)
            .map_or(*argument, |named| c.ast[named].argument_expression.raw());
        let parameter = redirected.as_ref().and_then(|parameters| {
            if let Some(named) = c.ast.cast::<NamedArgument>(*argument) {
                let name = c.ast.tokens.lexeme(c.ast[named].name);
                parameters.iter().copied().find(|parameter| {
                    r.ctx.get(*parameter).kind.is_named()
                        && r.ctx.element_name(parameter.raw()) == Some(name)
                })
            } else {
                let index = positional_indices[index]?;
                parameters
                    .iter()
                    .copied()
                    .filter(|parameter| r.ctx.get(*parameter).kind.is_positional())
                    .nth(index)
            }
        });
        let parameter = parameter
            .map(|parameter| ElemRef::Base(parameter.raw()))
            .or_else(|| c.corresponding_parameter(*argument));
        let Some(parameter) = parameter else {
            continue;
        };
        let base = member::base_element(&r.ctx, parameter);
        let Some(formal) = base.cast::<FormalParameterElement>() else {
            continue;
        };
        let kind = r
            .ctx
            .get(EId::<FormalParameterElement>::from_raw(formal.raw()))
            .kind;
        if kind == dartr_ast::ParameterKind::NamedRequired
            || kind == dartr_ast::ParameterKind::Required
        {
            continue;
        }
        // Dart `param.metadata.hasRequired`.
        if c.has_package_meta_getter(formal.raw(), "required")
            || c.has_constructor_annotation(formal.raw(), "meta", "Required")
        {
            continue;
        }
        // The function type that declares a parameter: the type of an
        // executable, or of a `GenericFunctionTypeElement` (the parameters
        // of a function type written in source, e.g. in the return type of
        // a local function), which is not an executable and has no
        // `ExecutableElement.type`.
        let enclosing_function_type = |owner: dartr_element::ElementId| {
            if owner.is::<dartr_element::ExecutableElement>() {
                Some(member::type_(&r.ctx, ElemRef::Base(owner)))
            } else if let Some(function_type) =
                owner.cast::<dartr_element::GenericFunctionTypeElement>()
            {
                r.ctx.get(function_type).type_.get()
            } else {
                None
            }
        };
        // The parameters of a function type that substitution or LUB/GLB
        // changed are synthetic copies
        // (`FormalParameterElementMixinExtension.copyWith`) whose
        // `computeConstantValue()` is `null`.
        // `_TypeSubstitutor.visitFunctionType` (type_algebra.dart) returns
        // the function type itself, with its own parameters, when the
        // substitution was not used (`useCounter == before`): only a
        // reference to one of the substituted type parameters of the
        // enclosing interface or extension copies the parameters. The
        // function's own type parameters are fresh in an inner environment
        // and do not count.
        let is_substituted_generic_member = |executable: dartr_element::ElementId| {
            let Some(owner) = r.ctx.element_data(executable).and_then(|d| d.enclosing) else {
                return false;
            };
            let substituted: &[EId<dartr_element::TypeParameterElement>] =
                if let Some(i) = owner.cast::<dartr_element::InterfaceElement>() {
                    r.ctx.interface_type_parameters(i)
                } else if let Some(e) = owner.cast::<dartr_element::ExtensionElement>() {
                    &r.ctx.get(e).type_params
                } else {
                    &[]
                };
            !substituted.is_empty()
                && enclosing_function_type(executable)
                    .is_some_and(|ty| references_type_parameter(&r.ctx, ty, substituted))
        };
        let synthetic = redirected.is_none()
            && r.ctx
                .element_data(base)
                .and_then(|d| d.enclosing)
                .is_some_and(|executable| {
                    c.ast.parent(node).is_some_and(|parent| {
                        if let Some(invocation) = c.ast.cast::<MethodInvocation>(parent) {
                            // An implicit `this` invocation finds an interface
                            // member through the scope as a member of
                            // `thisType` (the identity substitution, which
                            // `_TypeSubstitutor` counts as a use), and an
                            // extension member as declared.
                            (c.ast[invocation].target.is_some()
                                || c.ast[invocation].operator.is_some_and(|op| {
                                    matches!(c.ast.tokens.lexeme(op), ".." | "?..")
                                })
                                || r.ctx
                                    .element_data(executable)
                                    .and_then(|d| d.enclosing)
                                    .is_some_and(|owner| {
                                        owner.is::<dartr_element::InterfaceElement>()
                                    }))
                                && is_substituted_generic_member(executable)
                        } else if let Some(invocation) =
                            c.ast
                                .cast::<dartr_ast::FunctionExpressionInvocation>(parent)
                        {
                            if is_substituted_generic_member(executable) {
                                true
                            } else if c.element(invocation).is_none() {
                                let fn_ty = c.static_type(c.ast[invocation].function).map(|t| {
                                    dartr_typesystem::TypeSystem::new(r.ctx).resolve_to_bound(t)
                                });
                                if let Some(fn_ty) = fn_ty
                                    && let Some(exec_ty) = enclosing_function_type(executable)
                                    && let (
                                        dartr_element::TypeKind::Function(fn_f),
                                        dartr_element::TypeKind::Function(exec_f),
                                    ) = (r.ctx.ty(fn_ty), r.ctx.ty(exec_ty))
                                {
                                    r.ctx.list(fn_f.type_params).len()
                                        == r.ctx.list(exec_f.type_params).len()
                                        && r.ctx.with_nullability(
                                            fn_ty,
                                            dartr_element::Nullability::None,
                                        ) != r.ctx.with_nullability(
                                            exec_ty,
                                            dartr_element::Nullability::None,
                                        )
                                } else {
                                    false
                                }
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                    })
                });
        if synthetic {
            if kind == dartr_ast::ParameterKind::Positional {
                break;
            }
            continue;
        }
        if let Some(value) = c.constant_value(expression)
            && value.has_known_value()
            && let Some(default) = c.default_value(parameter)
            && default.has_known_value()
            && value.dart_eq(&default, &ts)
        {
            c.report_node(out, &diag::AVOID_REDUNDANT_ARGUMENT_VALUES, expression, &[]);
        }
        if kind == dartr_ast::ParameterKind::Positional {
            break;
        }
    }
}

fn redirected_parameters(
    c: &LinterContext<'_>,
    argument_list: NodeId,
) -> Result<Option<Vec<EId<FormalParameterElement>>>, ()> {
    let Some(r) = c.resolved else { return Ok(None) };
    let Some(creation) = c
        .ast
        .parent(argument_list)
        .and_then(|parent| c.ast.cast::<InstanceCreationExpression>(parent))
    else {
        return Ok(None);
    };
    let Some(mut constructor) = c
        .element(c.ast[creation].constructor_name)
        .and_then(|element| member::base_element(&r.ctx, element).cast::<ConstructorElement>())
    else {
        return Ok(None);
    };
    if !dartr_link::dump::is_factory(&r.ctx, constructor.raw()) {
        return Ok(None);
    }
    let Some(mut redirected) = r.ctx.get(constructor).redirected_constructor.get() else {
        return Ok(None);
    };
    let mut visited = IndexSet::new();
    visited.insert(constructor.raw());
    loop {
        let base = member::base_element(&r.ctx, redirected);
        let Some(next) = base.cast::<ConstructorElement>() else {
            return Ok(None);
        };
        if !visited.insert(next.raw()) {
            return Err(());
        }
        constructor = next;
        let Some(further) = r.ctx.get(constructor).redirected_constructor.get() else {
            break;
        };
        redirected = further;
    }
    Ok(Some(r.ctx.get(constructor).formal_params.clone()))
}

/// Whether [ty] references one of [params] (`_TypeSubstitutor.getSubstitute`
/// finding a mapping, which increments `useCounter`). Type alias arguments
/// are not visited, as the substitutor maps the aliased type itself.
fn references_type_parameter(
    ctx: &dartr_element::Ctx<'_>,
    ty: dartr_element::TypeId,
    params: &[EId<dartr_element::TypeParameterElement>],
) -> bool {
    use dartr_element::TypeKind;
    match *ctx.ty(ty) {
        TypeKind::TypeParameter {
            param,
            promoted_bound,
            ..
        } => {
            params.contains(&param)
                || promoted_bound.is_some_and(|b| references_type_parameter(ctx, b, params))
        }
        TypeKind::Interface { args, .. } => ctx
            .list(args)
            .iter()
            .any(|&a| references_type_parameter(ctx, a, params)),
        TypeKind::Function(f) => {
            references_type_parameter(ctx, f.ret, params)
                || ctx.list(f.type_params).iter().any(|&tp| {
                    ctx.get(tp)
                        .bound
                        .get()
                        .is_some_and(|b| references_type_parameter(ctx, b, params))
                })
                || ctx
                    .list(f.params)
                    .iter()
                    .any(|p| references_type_parameter(ctx, p.ty, params))
        }
        TypeKind::Record {
            positional, named, ..
        } => {
            ctx.list(positional)
                .iter()
                .any(|&t| references_type_parameter(ctx, t, params))
                || ctx
                    .list(named)
                    .iter()
                    .any(|n| references_type_parameter(ctx, n.ty, params))
        }
        _ => false,
    }
}
