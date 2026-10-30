// Dart source: pkg/linter/lib/src/rules/join_return_with_assignment.dart

// Dart `canonicalElementsFromIdentifiersAreEqual` (`util/dart_type_utilities.dart`).
use crate::rules::batch_b::util::canonical_elements_from_identifiers_are_equal;
use crate::{LinterContext, RuleVisitorRegistry};
use dartr_ast::*;
use dartr_diagnostics::{Diagnostic, diag};

pub fn register(registry: &mut RuleVisitorRegistry) {
    registry.add_block("join_return_with_assignment", check);
}

fn unparenthesized(ctx: &LinterContext<'_>, mut node: NodeId) -> NodeId {
    while let Some(p) = ctx.ast.cast::<ParenthesizedExpression>(node) {
        node = ctx.ast[p].expression.raw();
    }
    node
}

fn assignment_target(ctx: &LinterContext<'_>, statement: NodeId) -> Option<NodeId> {
    let statement = ctx.ast.cast::<ExpressionStatement>(statement)?;
    let expression = unparenthesized(ctx, ctx.ast[statement].expression.raw());
    match ctx.ast.kind(expression) {
        NodeKind::AssignmentExpression => Some(
            ctx.ast[Id::<AssignmentExpression>::from_raw(expression)]
                .left_hand_side
                .raw(),
        ),
        NodeKind::PostfixExpression => Some(
            ctx.ast[Id::<PostfixExpression>::from_raw(expression)]
                .operand
                .raw(),
        ),
        NodeKind::PrefixExpression => Some(
            ctx.ast[Id::<PrefixExpression>::from_raw(expression)]
                .operand
                .raw(),
        ),
        _ => None,
    }
}

fn return_expression(ctx: &LinterContext<'_>, statement: NodeId) -> Option<NodeId> {
    ctx.ast
        .cast::<ReturnStatement>(statement)
        .and_then(|r| ctx.ast[r].expression.map(Id::raw))
}

fn check(ctx: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
    let statements = ctx
        .ast
        .list(ctx.ast[Id::<Block>::from_raw(node)].statements);
    if statements.len() < 2 {
        return;
    }
    let Some(last) = return_expression(ctx, statements[statements.len() - 1].raw()) else {
        return;
    };
    let second_statement = statements[statements.len() - 2].raw();
    let Some(second) = assignment_target(ctx, second_statement) else {
        return;
    };
    let third = statements
        .get(statements.len().wrapping_sub(3))
        .and_then(|s| assignment_target(ctx, s.raw()));
    if !canonical_elements_from_identifiers_are_equal(ctx, Some(second), third)
        && canonical_elements_from_identifiers_are_equal(ctx, Some(last), Some(second))
    {
        ctx.report_node(
            out,
            &diag::JOIN_RETURN_WITH_ASSIGNMENT,
            second_statement,
            &[],
        );
    }
}
