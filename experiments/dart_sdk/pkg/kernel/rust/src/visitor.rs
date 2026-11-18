// Port of the traversal of lib/visitor.dart (`RecursiveVisitor`) and of the
// `visitChildren` methods of lib/src/ast/*.dart: the children of each node,
// in the order upstream visits them.
//
// Upstream's visitors are classes with one method per node kind; here
// `children` lists a node's immediate children in `visitChildren` order and
// a visitor walks them itself, so that it can act before and after a node's
// children as an upstream override does.
use crate::ast::*;

#[derive(Debug, Clone, Copy)]
pub enum Node<'a> {
    Expression(&'a Expression),
    Statement(&'a Statement),
    Initializer(&'a Initializer),
    /// A `Variable` declaration (parameter, local, catch variable...).
    Variable(&'a Variable),
    FunctionNode(&'a FunctionNode),
    DartType(&'a DartType),
    TypeParameter(&'a TypeParameter),
    Pattern(&'a Pattern),
    NamedPattern(&'a NamedPattern),
    MapPatternEntry(&'a MapPatternEntry),
    Catch(&'a Catch),
    SwitchCase(&'a SwitchCase),
    PatternSwitchCase(&'a PatternSwitchCase),
    PatternGuard(&'a PatternGuard),
    SwitchExpressionCase(&'a SwitchExpressionCase),
}

fn ty<'a>(out: &mut Vec<Node<'a>>, t: &'a DartType) {
    out.push(Node::DartType(t));
}

fn expr<'a>(out: &mut Vec<Node<'a>>, e: &'a Expression) {
    out.push(Node::Expression(e));
}

fn args<'a>(out: &mut Vec<Node<'a>>, a: &'a Arguments) {
    for t in &a.types {
        ty(out, t);
    }
    for e in &a.positional {
        expr(out, e);
    }
    for n in &a.named {
        expr(out, &n.value);
    }
}

fn exprs<'a>(out: &mut Vec<Node<'a>>, list: &'a [Expression]) {
    for e in list {
        expr(out, e);
    }
}

/// The children of [node], in upstream's `visitChildren` order.
pub fn children(node: Node<'_>) -> Vec<Node<'_>> {
    let mut out = Vec::new();
    match node {
        Node::Expression(e) => expressionChildren(e, &mut out),
        Node::Statement(s) => statementChildren(s, &mut out),
        Node::Initializer(i) => match i {
            Initializer::Invalid { .. } => {}
            Initializer::Field { value, .. } => expr(&mut out, value),
            Initializer::Super { arguments, .. } | Initializer::Redirecting { arguments, .. } => {
                args(&mut out, arguments)
            }
            Initializer::Local { variable, .. } => out.push(Node::Variable(variable)),
            Initializer::Assert { statement, .. } => out.push(Node::Statement(statement)),
        },
        Node::Variable(v) => {
            exprs(&mut out, &v.annotations);
            ty(&mut out, &v.r#type);
            if let Some(i) = &v.initializer {
                expr(&mut out, i);
            }
        }
        Node::FunctionNode(f) => {
            for p in &f.typeParameters {
                out.push(Node::TypeParameter(p));
            }
            for p in &f.positionalParameters {
                out.push(Node::Variable(p));
            }
            for p in &f.namedParameters {
                out.push(Node::Variable(p));
            }
            ty(&mut out, &f.returnType);
            if let Some(t) = &f.emittedValueType {
                ty(&mut out, t);
            }
            if let Some(target) = &f.redirectingFactoryTarget {
                if let Some(types) = &target.typeArguments {
                    for t in types {
                        ty(&mut out, t);
                    }
                }
            }
            if let Some(b) = &f.body {
                out.push(Node::Statement(b));
            }
        }
        Node::DartType(t) => match t {
            DartType::Interface { typeArguments, .. } | DartType::Typedef { typeArguments, .. } => {
                for a in typeArguments {
                    ty(&mut out, a);
                }
            }
            DartType::Function(f) => {
                for p in &f.typeParameters {
                    out.push(Node::TypeParameter(p));
                }
                for p in &f.positionalParameters {
                    ty(&mut out, p);
                }
                for n in &f.namedParameters {
                    ty(&mut out, &n.r#type);
                }
                ty(&mut out, &f.returnType);
            }
            DartType::Record(r) => {
                for p in &r.positional {
                    ty(&mut out, p);
                }
                for n in &r.named {
                    ty(&mut out, &n.r#type);
                }
            }
            DartType::Intersection { left, right } => {
                ty(&mut out, left);
                ty(&mut out, right);
            }
            DartType::Extension { typeArguments, .. } => {
                for a in typeArguments {
                    ty(&mut out, a);
                }
            }
            DartType::FutureOr { typeArgument, .. } => ty(&mut out, typeArgument),
            _ => {}
        },
        Node::TypeParameter(p) => {
            exprs(&mut out, &p.annotations);
            ty(&mut out, &p.bound);
            ty(&mut out, &p.defaultType);
        }
        Node::Pattern(p) => patternChildren(p, &mut out),
        Node::NamedPattern(n) => out.push(Node::Pattern(&n.pattern)),
        Node::MapPatternEntry(e) => {
            if let MapPatternEntry::Entry { key, value, .. } = e {
                expr(&mut out, key);
                out.push(Node::Pattern(value));
            }
        }
        Node::Catch(c) => {
            ty(&mut out, &c.guard);
            if let Some(v) = &c.exception {
                out.push(Node::Variable(v));
            }
            if let Some(v) = &c.stackTrace {
                out.push(Node::Variable(v));
            }
            out.push(Node::Statement(&c.body));
        }
        Node::SwitchCase(c) => {
            exprs(&mut out, &c.expressions);
            out.push(Node::Statement(&c.body));
        }
        Node::PatternSwitchCase(c) => {
            for g in &c.patternGuards {
                out.push(Node::PatternGuard(g));
            }
            out.push(Node::Statement(&c.body));
        }
        Node::PatternGuard(g) => {
            out.push(Node::Pattern(&g.pattern));
            if let Some(e) = &g.guard {
                expr(&mut out, e);
            }
        }
        Node::SwitchExpressionCase(c) => {
            out.push(Node::PatternGuard(&c.patternGuard));
            expr(&mut out, &c.expression);
        }
    }
    out
}

fn expressionChildren<'a>(e: &'a Expression, out: &mut Vec<Node<'a>>) {
    use Expression::*;
    match e {
        Invalid { expression, .. } => {
            if let Some(x) = expression {
                expr(out, x);
            }
        }
        VariableGet { promotedType, .. } => {
            if let Some(t) = promotedType {
                ty(out, t);
            }
        }
        VariableSet { value, .. } => expr(out, value),
        SuperPropertyGet { receiver, .. } => expr(out, receiver),
        SuperPropertySet { receiver, value, .. } => {
            expr(out, receiver);
            expr(out, value);
        }
        InstanceGet { receiver, resultType, .. } | InstanceTearOff { receiver, resultType, .. } => {
            expr(out, receiver);
            ty(out, resultType);
        }
        RecordIndexGet { receiver, receiverType, .. } | RecordNameGet { receiver, receiverType, .. } => {
            expr(out, receiver);
            ty(out, receiverType);
        }
        InstanceSet { receiver, value, .. } | DynamicSet { receiver, value, .. } => {
            expr(out, receiver);
            expr(out, value);
        }
        DynamicGet { receiver, .. } | FunctionTearOff { receiver, .. } => expr(out, receiver),
        StaticGet { .. }
        | StaticTearOff { .. }
        | ConstructorTearOff { .. }
        | RedirectingFactoryTearOff { .. }
        | StringLiteral { .. }
        | IntLiteral { .. }
        | DoubleLiteral { .. }
        | BoolLiteral { .. }
        | NullLiteral { .. }
        | SymbolLiteral { .. }
        | ThisExpression { .. }
        | Rethrow { .. }
        | LoadLibrary { .. }
        | CheckLibraryIsLoaded { .. } => {}
        TypedefTearOff { structuralParameters, expression, typeArguments, .. } => {
            for p in structuralParameters {
                out.push(Node::TypeParameter(p));
            }
            expr(out, expression);
            for t in typeArguments {
                ty(out, t);
            }
        }
        StaticSet { value, .. } => expr(out, value),
        InstanceInvocation { receiver, arguments, functionType, .. } => {
            expr(out, receiver);
            args(out, arguments);
            ty(out, functionType);
        }
        InstanceGetterInvocation { receiver, arguments, functionType, .. } => {
            expr(out, receiver);
            args(out, arguments);
            ty(out, functionType);
        }
        DynamicInvocation { receiver, arguments, .. } => {
            expr(out, receiver);
            args(out, arguments);
        }
        FunctionInvocation { receiver, arguments, functionType, .. } => {
            expr(out, receiver);
            args(out, arguments);
            ty(out, functionType);
        }
        LocalFunctionInvocation { arguments, functionType, .. } => {
            args(out, arguments);
            ty(out, functionType);
        }
        EqualsNull { expression, .. } => expr(out, expression),
        EqualsCall { left, right, functionType, .. } => {
            expr(out, left);
            expr(out, right);
            ty(out, functionType);
        }
        SuperMethodInvocation { receiver, arguments, .. } => {
            expr(out, receiver);
            args(out, arguments);
        }
        StaticInvocation { arguments, .. } | ConstructorInvocation { arguments, .. } => args(out, arguments),
        RedirectingFactoryInvocation { expression, .. } => expr(out, expression),
        Not { operand, .. } | NullCheck { operand, .. } => expr(out, operand),
        LogicalExpression { left, right, .. } => {
            expr(out, left);
            expr(out, right);
        }
        ConditionalExpression { condition, then, otherwise, staticType, .. } => {
            expr(out, condition);
            expr(out, then);
            expr(out, otherwise);
            if let Some(t) = staticType {
                ty(out, t);
            }
        }
        StringConcatenation { expressions, .. } => exprs(out, expressions),
        ListConcatenation { typeArgument, lists, .. } => {
            ty(out, typeArgument);
            exprs(out, lists);
        }
        SetConcatenation { typeArgument, sets, .. } => {
            ty(out, typeArgument);
            exprs(out, sets);
        }
        MapConcatenation { keyType, valueType, maps, .. } => {
            ty(out, keyType);
            ty(out, valueType);
            exprs(out, maps);
        }
        InstanceCreation { typeArguments, fieldValues, asserts, unusedArguments, .. } => {
            for t in typeArguments {
                ty(out, t);
            }
            for (_, v) in fieldValues {
                expr(out, v);
            }
            for s in asserts {
                out.push(Node::Statement(s));
            }
            exprs(out, unusedArguments);
        }
        FileUriExpression { expression, .. } => expr(out, expression),
        IsExpression { operand, r#type, .. } | AsExpression { operand, r#type, .. } => {
            expr(out, operand);
            ty(out, r#type);
        }
        TypeLiteral { r#type, .. } => ty(out, r#type),
        Throw { expression, .. } => expr(out, expression),
        ListLiteral { typeArgument, expressions, .. } | SetLiteral { typeArgument, expressions, .. } => {
            ty(out, typeArgument);
            exprs(out, expressions);
        }
        MapLiteral { keyType, valueType, entries, .. } => {
            ty(out, keyType);
            ty(out, valueType);
            for entry in entries {
                expr(out, &entry.key);
                expr(out, &entry.value);
            }
        }
        RecordLiteral { positional, named, recordType, .. } => {
            exprs(out, positional);
            for n in named {
                expr(out, &n.value);
            }
            ty(out, recordType);
        }
        AwaitExpression { operand, runtimeCheckType, .. } => {
            expr(out, operand);
            if let Some(t) = runtimeCheckType {
                ty(out, t);
            }
        }
        FunctionExpression { function, .. } => out.push(Node::FunctionNode(function)),
        Let { variable, body, .. } => {
            out.push(Node::Variable(variable));
            expr(out, body);
        }
        BlockExpression { body, value, .. } => {
            for s in body {
                out.push(Node::Statement(s));
            }
            expr(out, value);
        }
        Instantiation { expression, typeArguments, .. } => {
            expr(out, expression);
            for t in typeArguments {
                ty(out, t);
            }
        }
        ConstantExpression { r#type, .. } | FileUriConstantExpression { r#type, .. } => ty(out, r#type),
        SwitchExpression { expression, cases, .. } => {
            expr(out, expression);
            for c in cases {
                out.push(Node::SwitchExpressionCase(c));
            }
        }
        PatternAssignment { pattern, expression, .. } => {
            out.push(Node::Pattern(pattern));
            expr(out, expression);
        }
    }
}

fn statementChildren<'a>(s: &'a Statement, out: &mut Vec<Node<'a>>) {
    use Statement::*;
    match s {
        Expression(e) => expr(out, e),
        Block { statements, .. } | AssertBlock { statements } => {
            for s in statements {
                out.push(Node::Statement(s));
            }
        }
        Empty | Break { .. } | ContinueSwitch { .. } => {}
        Assert { condition, message, .. } => {
            expr(out, condition);
            if let Some(m) = message {
                expr(out, m);
            }
        }
        Labeled { body, .. } => out.push(Node::Statement(body)),
        While { condition, body, .. } => {
            expr(out, condition);
            out.push(Node::Statement(body));
        }
        Do { body, condition, .. } => {
            out.push(Node::Statement(body));
            expr(out, condition);
        }
        For { variables, condition, updates, body, .. } => {
            for v in variables {
                out.push(Node::Variable(&v.variable));
            }
            if let Some(c) = condition {
                expr(out, c);
            }
            exprs(out, updates);
            out.push(Node::Statement(body));
        }
        ForIn { variable, iterable, body, .. } => {
            out.push(Node::Variable(variable));
            expr(out, iterable);
            out.push(Node::Statement(body));
        }
        Switch { expression, cases, .. } => {
            expr(out, expression);
            for c in cases {
                out.push(Node::SwitchCase(c));
            }
        }
        If { condition, then, otherwise, .. } => {
            expr(out, condition);
            out.push(Node::Statement(then));
            if let Some(o) = otherwise {
                out.push(Node::Statement(o));
            }
        }
        Return { expression, .. } => {
            if let Some(e) = expression {
                expr(out, e);
            }
        }
        TryCatch { body, catches, .. } => {
            out.push(Node::Statement(body));
            for c in catches {
                out.push(Node::Catch(c));
            }
        }
        TryFinally { body, finalizer, .. } => {
            out.push(Node::Statement(body));
            out.push(Node::Statement(finalizer));
        }
        Yield { expression, .. } => expr(out, expression),
        VariableStatement { declaration, .. } => out.push(Node::Variable(&declaration.variable)),
        FunctionDeclaration { variable, function, .. } => {
            out.push(Node::Variable(variable));
            out.push(Node::FunctionNode(function));
        }
        IfCase { expression, patternGuard, then, otherwise, .. } => {
            expr(out, expression);
            out.push(Node::PatternGuard(patternGuard));
            out.push(Node::Statement(then));
            if let Some(o) = otherwise {
                out.push(Node::Statement(o));
            }
        }
        PatternVariableDeclaration { pattern, initializer, .. } => {
            out.push(Node::Pattern(pattern));
            expr(out, initializer);
        }
        PatternSwitch { expression, cases, .. } => {
            expr(out, expression);
            for c in cases {
                out.push(Node::PatternSwitchCase(c));
            }
        }
    }
}

fn patternChildren<'a>(p: &'a Pattern, out: &mut Vec<Node<'a>>) {
    use Pattern::*;
    match p {
        And { left, right, .. } | Or { left, right, .. } => {
            out.push(Node::Pattern(left));
            out.push(Node::Pattern(right));
        }
        AssignedVariable { .. } | Wildcard { .. } => {}
        Cast { pattern, r#type, .. } => {
            out.push(Node::Pattern(pattern));
            ty(out, r#type);
        }
        Constant { expression, .. } => expr(out, expression),
        Invalid { invalidExpression, declaredVariables, .. } => {
            expr(out, invalidExpression);
            for v in declaredVariables {
                out.push(Node::Variable(v));
            }
        }
        List { typeArgument, patterns, .. } => {
            if let Some(t) = typeArgument {
                ty(out, t);
            }
            for p in patterns {
                out.push(Node::Pattern(p));
            }
        }
        Map { keyType, valueType, entries, .. } => {
            if let Some(t) = keyType {
                ty(out, t);
            }
            if let Some(t) = valueType {
                ty(out, t);
            }
            for e in entries {
                out.push(Node::MapPatternEntry(e));
            }
        }
        Named(n) => out.push(Node::Pattern(&n.pattern)),
        NullAssert { pattern, .. } | NullCheck { pattern, .. } => out.push(Node::Pattern(pattern)),
        Object { requiredType, fields, .. } => {
            ty(out, requiredType);
            for f in fields {
                out.push(Node::NamedPattern(f));
            }
        }
        Record { patterns, .. } => {
            for p in patterns {
                out.push(Node::Pattern(p));
            }
        }
        Relational { expression, .. } => expr(out, expression),
        Rest { subPattern, .. } => {
            if let Some(p) = subPattern {
                out.push(Node::Pattern(p));
            }
        }
        Variable { r#type, variable, .. } => {
            if let Some(t) = r#type {
                ty(out, t);
            }
            out.push(Node::Variable(variable));
        }
    }
}

/// Visits every descendant of [node] before its own children (a
/// `RecursiveVisitor` that overrides nothing but `defaultNode`).
pub fn visitDescendants<'a>(node: Node<'a>, f: &mut dyn FnMut(Node<'a>)) {
    for child in children(node) {
        f(child);
        visitDescendants(child, f);
    }
}

pub fn visitStatementChildren<'a>(statement: &'a Statement, f: &mut dyn FnMut(Node<'a>)) {
    f(Node::Statement(statement));
    visitDescendants(Node::Statement(statement), f);
}

pub fn visitExpressionChildren<'a>(expression: &'a Expression, f: &mut dyn FnMut(Node<'a>)) {
    visitDescendants(Node::Expression(expression), f);
}
