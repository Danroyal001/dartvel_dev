// Dart source: pkg/linter/lib/src/rules/no_default_cases.dart
use crate::{LinterContext, RuleVisitorRegistry};
use dartr_ast::*;
use dartr_diagnostics::{Diagnostic, diag};
use dartr_element::{ClassElement, TypeKind};
pub fn register(registry: &mut RuleVisitorRegistry) {
    registry.add_switch_statement("no_default_cases", check);
}

/// Dart `InterfaceElementExtension.isEnumLikeClass` (linter `extensions.dart`).
fn is_enum_like(ctx: &LinterContext<'_>, class: dartr_element::EId<ClassElement>) -> bool {
    crate::rules::batch_a2::exhaustive_cases::as_enum_like_class(ctx, class).is_some()
}

fn check(ctx: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
    let n = &ctx.ast[Id::<SwitchStatement>::from_raw(node)];
    let Some(r) = ctx.resolved else {
        return;
    };
    let Some(t) = ctx.static_type(n.expression) else {
        return;
    };
    let TypeKind::Interface { element, .. } = *r.ctx.ty(t) else {
        return;
    };
    if element.raw().kind() != dartr_element::ElementKind::Enum
        && !element
            .cast::<ClassElement>()
            .is_some_and(|class| is_enum_like(ctx, class))
    {
        return;
    }
    if let Some(default) = ctx
        .ast
        .list(n.members)
        .iter()
        .find(|m| ctx.ast.kind(**m) == NodeKind::SwitchDefault)
    {
        ctx.report_node(out, &diag::NO_DEFAULT_CASES, *default, &[]);
    }
}
