// Dart source: pkg/linter/lib/src/rules/prefer_collection_literals.dart
use crate::{LinterContext, RuleVisitorRegistry};
use dartr_ast::*;
use dartr_diagnostics::{Diagnostic, diag};
use dartr_typesystem::TypeExt;

use crate::rules::batch_a2::avoid_types_on_closure_parameters::approximate_context_type;

pub fn register(registry: &mut RuleVisitorRegistry) {
    registry.add_instance_creation_expression("prefer_collection_literals", check);
    registry.add_method_invocation("prefer_collection_literals", check);
}

fn name<'a>(ctx: &'a LinterContext<'_>, id: Id<SimpleIdentifier>) -> &'a str {
    ctx.ast.tokens.lexeme(ctx.ast[id].token)
}

fn is_collection_type(
    resolved: crate::ResolvedLintContext<'_>,
    ty: dartr_element::TypeId,
    name: &str,
) -> bool {
    resolved.ctx.interface_element(ty).is_some_and(|element| {
        resolved.ctx.element_name(element.raw()) == Some(name)
            && resolved.ctx.element_library_name(element.raw()) == Some("dart.collection")
    })
}

fn check(ctx: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
    match ctx.ast.kind(node) {
        NodeKind::MethodInvocation => {
            let n = &ctx.ast[Id::<MethodInvocation>::from_raw(node)];
            if name(ctx, n.method_name) == "toSet"
                && n.target
                    .is_some_and(|t| ctx.ast.kind(t) == NodeKind::ListLiteral)
            {
                ctx.report_node(out, &diag::PREFER_COLLECTION_LITERALS, node, &[]);
            }
        }
        NodeKind::InstanceCreationExpression => {
            let n = &ctx.ast[Id::<InstanceCreationExpression>::from_raw(node)];
            let Some(resolved) = ctx.resolved else {
                return;
            };
            if ctx
                .element(ctx.ast[n.constructor_name].type_.raw())
                .is_some_and(|element| {
                    dartr_typesystem::member::base_element(&resolved.ctx, element).kind()
                        == dartr_element::ElementKind::TypeAlias
                })
            {
                return;
            }
            let Some(ty) = ctx.static_type(node) else {
                return;
            };
            let is_hash_map = is_collection_type(resolved, ty, "LinkedHashMap");
            let is_hash_set = is_collection_type(resolved, ty, "LinkedHashSet");
            let constructor = &ctx.ast[n.constructor_name];
            let constructor_name = constructor.name.map(|id| name(ctx, id));
            let args = ctx.ast.list(ctx.ast[n.argument_list].arguments);
            // Dart: `approximateContextType is InvalidType` returns, and a
            // context type that is the same collection class allows the call.
            let allowed_by_context = |class_name: &str| {
                let context_type = approximate_context_type(ctx, node);
                context_type.is_some_and(|context_type| {
                    matches!(
                        resolved.ctx.ty(context_type),
                        dartr_element::TypeKind::Invalid
                    ) || is_collection_type(resolved, context_type, class_name)
                })
            };
            // Maps.
            if is_hash_map && allowed_by_context("LinkedHashMap") {
                return;
            }
            if resolved.ctx.is_dart_core_map(ty) || is_hash_map {
                if constructor_name.is_none() && args.is_empty() {
                    ctx.report_node(out, &diag::PREFER_COLLECTION_LITERALS, node, &[]);
                }
                return;
            }
            // Sets.
            if is_hash_set && allowed_by_context("LinkedHashSet") {
                return;
            }
            if resolved.ctx.is_dart_core_set(ty) || is_hash_set {
                match constructor_name {
                    // Allow `LinkedHashSet(equals: (a, b) => false, hashCode: (o) => 13)`.
                    None => {
                        if args.is_empty() {
                            ctx.report_node(out, &diag::PREFER_COLLECTION_LITERALS, node, &[]);
                        }
                    }
                    Some("from" | "of") => {
                        if args.len() == 1 && ctx.ast.kind(args[0]) == NodeKind::ListLiteral {
                            ctx.report_node(out, &diag::PREFER_COLLECTION_LITERALS, node, &[]);
                        }
                    }
                    Some(_) => {}
                }
            }
        }
        _ => {}
    }
}
