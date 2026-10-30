// Dart source: pkg/linter/lib/src/rules/avoid_catches_without_on_clauses.dart

use super::helpers::descendants;
use crate::{LinterContext, RuleVisitorRegistry};
use dartr_ast::{CatchClause, Id, InstanceCreationExpression, MethodInvocation, NodeId, NodeKind};
use dartr_diagnostics::{Diagnostic, diag};
use dartr_element::{AnyElement, EId, ElementId, InterfaceElement, TypeKind};
use dartr_typesystem::TypeExt;

pub fn register(registry: &mut RuleVisitorRegistry, _: &LinterContext<'_>) {
    registry.add(
        NodeKind::CatchClause,
        "avoid_catches_without_on_clauses",
        check,
    );
}

fn check(c: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
    let n = &c.ast[Id::<CatchClause>::from_raw(node)];
    if n.on_keyword.is_some() {
        return;
    }
    let Some(parameter) = n.exception_parameter.and_then(|p| c.declared_element(p)) else {
        return;
    };
    let mut visitor = ValidUseVisitor {
        c,
        caught_exception: parameter,
        has_valid_use: false,
        can_rethrow: true,
    };
    visitor.visit(n.body.raw());
    if visitor.has_valid_use {
        return;
    }
    if let Some(catch) = n.catch_keyword {
        c.report_token(out, &diag::AVOID_CATCHES_WITHOUT_ON_CLAUSES, catch, &[]);
    }
}

/// Dart `_CaughtExceptionUseVisitor`: whether a `SimpleIdentifier` under
/// [root] (or [root] itself) refers to [caught_exception].
fn exception_was_used(c: &LinterContext<'_>, root: NodeId, caught_exception: ElementId) -> bool {
    descendants(c.ast, root)
        .into_iter()
        .chain(std::iter::once(root))
        .any(|used| {
            c.ast.kind(used) == NodeKind::SimpleIdentifier
                && c.element(used)
                    .is_some_and(|e| super::helpers::base_element(c, e) == Some(caught_exception))
        })
}

/// Dart `_ValidUseVisitor`, a `RecursiveAstVisitor`: nodes are visited in
/// order and nothing stops the walk early. `visitRethrowExpression`
/// assigns `hasValidUse = _canRethrow`, so a `rethrow` after the first
/// nested catch clause (which clears `_canRethrow` for good) undoes an
/// earlier valid use.
struct ValidUseVisitor<'c, 'a> {
    c: &'c LinterContext<'a>,
    caught_exception: ElementId,
    has_valid_use: bool,
    can_rethrow: bool,
}

impl ValidUseVisitor<'_, '_> {
    fn visit(&mut self, node: NodeId) {
        let c = self.c;
        match c.ast.kind(node) {
            NodeKind::CatchClause => {
                self.can_rethrow = false;
            }
            NodeKind::FunctionExpressionInvocation => {
                if self.is_never(node) {
                    let arguments = c.ast
                        [Id::<dartr_ast::FunctionExpressionInvocation>::from_raw(node)]
                    .argument_list
                    .raw();
                    self.check_use_in_argument(arguments);
                    // Dart returns without visiting the children.
                    return;
                }
            }
            NodeKind::InstanceCreationExpression => {
                let creation = &c.ast[Id::<InstanceCreationExpression>::from_raw(node)];
                let constructor = &c.ast[creation.constructor_name];
                let is_future_error = constructor.name.is_some_and(|name| {
                    c.ast.tokens.lexeme(c.ast[name].token) == "error"
                        && c.static_type(node).is_some_and(|ty| {
                            c.resolved.is_some_and(|r| r.ctx.is_dart_async_future(ty))
                        })
                });
                if is_future_error {
                    self.check_use_in_argument(creation.argument_list.raw());
                }
            }
            NodeKind::MethodInvocation => {
                let invocation = &c.ast[Id::<MethodInvocation>::from_raw(node)];
                let name = c.ast.tokens.lexeme(c.ast[invocation.method_name].token);
                let real_target = invocation.target.or_else(|| {
                    super::helpers::ancestor(c.ast, node, NodeKind::CascadeExpression).map(
                        |cascade| {
                            c.ast[Id::<dartr_ast::CascadeExpression>::from_raw(cascade)].target
                        },
                    )
                });
                if self.is_never(node) {
                    self.check_use_in_argument(invocation.argument_list.raw());
                } else if name == "reportError" {
                    let is_flutter_error = real_target.is_some_and(|target| {
                        let (Some(r), Some(element)) = (
                            c.resolved,
                            c.element(target)
                                .and_then(|element| super::helpers::base_element(c, element)),
                        ) else {
                            return false;
                        };
                        matches!(r.ctx.any(element), AnyElement::Class(_))
                            && r.ctx.element_name(element) == Some("FlutterError")
                    });
                    if is_flutter_error {
                        self.check_use_in_argument(invocation.argument_list.raw());
                    }
                } else if name == "completeError" {
                    let is_completer = real_target.is_some_and(|target| {
                        let (Some(r), Some(ty)) = (c.resolved, c.static_type(target)) else {
                            return false;
                        };
                        r.ctx.library_by_uri("dart:async").is_some_and(|library| {
                            r.ctx.get(library).classes.iter().copied().any(|class| {
                                r.ctx.element_name(class.raw()) == Some("Completer")
                                    && extends_class(c, ty, class.upcast())
                            })
                        })
                    });
                    if is_completer {
                        self.check_use_in_argument(invocation.argument_list.raw());
                    }
                }
            }
            NodeKind::RethrowExpression => {
                self.has_valid_use = self.can_rethrow;
            }
            NodeKind::ThrowExpression => {
                if exception_was_used(c, node, self.caught_exception) {
                    self.has_valid_use = true;
                }
            }
            _ => {}
        }
        for child in c.ast.children(node) {
            self.visit(child);
        }
    }

    fn is_never(&self, node: NodeId) -> bool {
        self.c.static_type(node).is_some_and(|ty| {
            self.c
                .resolved
                .is_some_and(|r| matches!(r.ctx.ty(ty), TypeKind::Never(_)))
        })
    }

    fn check_use_in_argument(&mut self, arguments: NodeId) {
        if exception_was_used(self.c, arguments, self.caught_exception) {
            self.has_valid_use = true;
        }
    }
}

fn extends_class(
    c: &LinterContext<'_>,
    ty: dartr_element::TypeId,
    base: EId<InterfaceElement>,
) -> bool {
    let Some(r) = c.resolved else { return false };
    let Some(mut current) = r.ctx.interface_element(ty) else {
        return false;
    };
    let mut visited = indexmap::IndexSet::new();
    loop {
        if current == base {
            return true;
        }
        if !visited.insert(current) {
            return false;
        }
        let Some(supertype) = r.ctx.interface(current).supertype.get() else {
            return false;
        };
        let Some(next) = r.ctx.interface_element(supertype) else {
            return false;
        };
        current = next;
    }
}
