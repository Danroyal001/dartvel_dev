// Port of lib/transformations/type_flow/summary.dart: the statements of a
// summary, their text and their simplification, and `Summary`.
//
// Upstream's statements are objects that point at each other; here they
// live in their summary's arena and refer to each other by index
// (`StmtId`), and a `TypeExpr` is a type or a statement. Equality of
// statements is identity, as upstream's. `apply` (evaluating a summary
// during the analysis) is not ported yet.
use kernel::ast::{CnId, DartType};
use kernel::src::printer::AstPrinter;

use super::Env;
use super::calls::{Args, Selector};
use super::types::*;

pub type StmtId = usize;

/// `TypeExpr`: a type or a statement.
#[derive(Debug, Clone)]
pub enum TypeExpr {
    Type(Type),
    Stmt(StmtId),
}

impl PartialEq for TypeExpr {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (TypeExpr::Type(a), TypeExpr::Type(b)) => a == b,
            (TypeExpr::Stmt(a), TypeExpr::Stmt(b)) => a == b,
            _ => false,
        }
    }
}

impl TypeExpr {
    pub fn ty(t: Type) -> Self {
        TypeExpr::Type(t)
    }
    pub fn empty() -> Self {
        TypeExpr::Type(Type::Empty)
    }
    pub fn isEmpty(&self) -> bool {
        matches!(self, TypeExpr::Type(Type::Empty))
    }
    pub fn asType(&self) -> Option<&Type> {
        match self {
            TypeExpr::Type(t) => Some(t),
            _ => None,
        }
    }
    pub fn asStmt(&self) -> Option<StmtId> {
        match self {
            TypeExpr::Stmt(s) => Some(*s),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnaryOp {
    Move,
    IsNull,
    IsEmpty,
    Not,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOp {
    And,
    Or,
}

#[derive(Debug, Clone)]
pub enum StatementKind {
    Parameter { name: String, staticTypeForNarrowing: Option<Type>, defaultValue: Option<Type> },
    Narrow { arg: TypeExpr, type_: Type },
    /// `NarrowNotNull`, a `Narrow` to `anyInstanceType`.
    NarrowNotNull { arg: TypeExpr },
    Join { name: Option<String>, staticType: DartType, values: Vec<TypeExpr> },
    Use { arg: TypeExpr },
    Call { selector: Selector, args: Args, staticResultType: Option<Type>, isInstanceCreation: bool, isResultUsed: bool },
    Extract { arg: TypeExpr, referenceClass: CnId, paramIndex: usize, nullability: u8 },
    ApplyNullability { arg: TypeExpr, nullability: u8 },
    CreateConcreteType { cls: std::rc::Rc<TFClass>, flattenedTypeArgs: Vec<TypeExpr> },
    CreateRecordType { cls: std::rc::Rc<TFClass>, fieldTypes: Vec<TypeExpr> },
    CreateRuntimeType { klass: CnId, nullability: u8, flattenedTypeArgs: Vec<TypeExpr> },
    /// `TypeCheck`; [nodeText] is `nodeToText(node)`, [isParameterCheck]
    /// whether the node is a parameter.
    TypeCheck { arg: TypeExpr, type_: TypeExpr, nodeText: String, staticType: Type },
    Unary { op: UnaryOp, arg: TypeExpr },
    Binary { op: BinaryOp, arg1: TypeExpr, arg2: TypeExpr },
    ReadVariable { variable: String },
    WriteVariable { variable: String, arg: TypeExpr },
}

#[derive(Debug, Clone)]
pub struct Statement {
    pub index: i64,
    pub condition: Option<TypeExpr>,
    pub kind: StatementKind,
}

impl Statement {
    pub fn new(kind: StatementKind) -> Self {
        Statement { index: -1, condition: None, kind }
    }

    /// `is Narrow` (a `NarrowNotNull` is one) and its `arg` and `type`.
    pub fn asNarrow(&self) -> Option<(&TypeExpr, Type)> {
        match &self.kind {
            StatementKind::Narrow { arg, type_ } => Some((arg, type_.clone())),
            StatementKind::NarrowNotNull { arg } => Some((arg, anyInstanceType)),
            _ => None,
        }
    }
}

/// `Summary`, with the arena its statements live in.
#[derive(Debug, Clone)]
pub struct Summary {
    pub arena: Vec<Statement>,
    pub statements: Vec<StmtId>,
    pub result: TypeExpr,
    pub parameterCount: usize,
    pub positionalParameterCount: usize,
    pub requiredParameterCount: usize,
}

impl Summary {
    pub fn new(parameterCount: usize, positionalParameterCount: usize, requiredParameterCount: usize) -> Self {
        Summary {
            arena: Vec::new(),
            statements: Vec::new(),
            result: TypeExpr::empty(),
            parameterCount,
            positionalParameterCount,
            requiredParameterCount,
        }
    }

    /// A statement that is not (yet) part of the summary.
    pub fn alloc(&mut self, statement: Statement) -> StmtId {
        self.arena.push(statement);
        self.arena.len() - 1
    }

    /// `add`: a new statement, appended.
    pub fn addNew(&mut self, statement: Statement) -> StmtId {
        let id = self.alloc(statement);
        self.add(id);
        id
    }

    /// `add`: appends [id] and numbers it.
    pub fn add(&mut self, id: StmtId) -> StmtId {
        self.arena[id].index = self.statements.len() as i64;
        self.statements.push(id);
        id
    }

    pub fn reset(&mut self) {
        self.statements.clear();
    }

    pub fn st(&self, id: StmtId) -> &Statement {
        &self.arena[id]
    }

    pub fn stMut(&mut self, id: StmtId) -> &mut Statement {
        &mut self.arena[id]
    }

    /// `label`.
    pub fn label(&self, id: StmtId) -> String {
        let s = &self.arena[id];
        match &s.kind {
            StatementKind::Parameter { name, .. } => format!("%{name}"),
            StatementKind::Join { name: Some(n), .. } => n.clone(),
            _ => format!("t{}", s.index),
        }
    }

    pub fn exprText(&self, e: &TypeExpr, env: &Env) -> String {
        match e {
            TypeExpr::Type(t) => t.toText(env),
            TypeExpr::Stmt(s) => self.label(*s),
        }
    }

    fn list(&self, list: &[TypeExpr], env: &Env) -> String {
        list.iter().map(|e| self.exprText(e, env)).collect::<Vec<_>>().join(", ")
    }

    fn argsText(&self, args: &Args, env: &Env) -> String {
        let mut buf = String::from("(");
        let positional = args.positionalCount();
        for i in 0..positional {
            if i != 0 {
                buf.push_str(", ");
            }
            buf.push_str(&self.exprText(&args.values[i], env));
        }
        for (i, name) in args.names.iter().enumerate() {
            if positional + i != 0 {
                buf.push_str(", ");
            }
            buf.push_str(name);
            buf.push_str(": ");
            buf.push_str(&self.exprText(&args.values[positional + i], env));
        }
        buf.push(')');
        buf
    }

    /// `dump`.
    pub fn dump(&self, id: StmtId, env: &Env) -> String {
        let s = &self.arena[id];
        let label = self.label(id);
        let cond = match &s.condition {
            Some(c) => format!(" {{{}}}", self.exprText(c, env)),
            None => String::new(),
        };
        let suffix = |n: u8| if n == kernel::core_types::Nullability::nullable { "?" } else { "" };
        match &s.kind {
            StatementKind::Parameter { staticTypeForNarrowing, .. } => {
                let mut text = format!("{label} = _Parameter #{}", s.index);
                if let Some(t) = staticTypeForNarrowing {
                    text.push_str(&format!(" [{}]", t.toText(env)));
                }
                text + &cond
            }
            StatementKind::Narrow { arg, type_ } => {
                format!("{label} = _Narrow ({} to {}){cond}", self.exprText(arg, env), type_.toText(env))
            }
            StatementKind::NarrowNotNull { arg } => {
                format!("{label} = _Narrow ({} to {}){cond}", self.exprText(arg, env), anyInstanceType.toText(env))
            }
            StatementKind::Join { staticType, values, .. } => {
                let mut p = AstPrinter::new(env.index, None);
                p.writeType(staticType);
                format!("{label} = _Join [{}] ({}){cond}", p.getText(), self.list(values, env))
            }
            StatementKind::Use { arg } => format!("{label} = _Use ({}){cond}", self.exprText(arg, env)),
            StatementKind::Call { selector, args, isResultUsed, .. } => format!(
                "{label}{} = _Call {} {}{cond}",
                if *isResultUsed { "*" } else { "" },
                selector.toText(env),
                self.argsText(args, env)
            ),
            StatementKind::Extract { arg, referenceClass, paramIndex, nullability } => format!(
                "{label} = _Extract ({}[{}/{paramIndex}]{}){cond}",
                self.exprText(arg, env),
                AstPrinter::new(env.index, None).className(*referenceClass),
                suffix(*nullability)
            ),
            StatementKind::ApplyNullability { arg, nullability } => {
                format!("{label} = _ApplyNullability ({}, {}){cond}", self.exprText(arg, env), suffix(*nullability))
            }
            StatementKind::CreateConcreteType { cls, flattenedTypeArgs } => {
                let n = env.index.class(cls.classNode).map(|c| c.typeParameters.len()).unwrap_or(0);
                format!(
                    "{label} = _CreateConcreteType ({} @ ({})){cond}",
                    cls.toText(env),
                    self.list(&flattenedTypeArgs[..n.min(flattenedTypeArgs.len())], env)
                )
            }
            StatementKind::CreateRecordType { cls, fieldTypes } => {
                format!("{label} = _CreateRecordType ({} @ [{}]){cond}", cls.toText(env), self.list(fieldTypes, env))
            }
            StatementKind::CreateRuntimeType { klass, nullability, flattenedTypeArgs } => {
                let n = env.index.class(*klass).map(|c| c.typeParameters.len()).unwrap_or(0);
                format!(
                    "{label} = _CreateRuntimeType ({} @ ({}){}){cond}",
                    AstPrinter::new(env.index, None).className(*klass),
                    self.list(&flattenedTypeArgs[..n.min(flattenedTypeArgs.len())], env),
                    suffix(*nullability)
                )
            }
            StatementKind::TypeCheck { arg, type_, nodeText, .. } => format!(
                "{label} = _TypeCheck ({} against {}) (for {nodeText}){cond}",
                self.exprText(arg, env),
                self.exprText(type_, env)
            ),
            StatementKind::Unary { op, arg } => format!("{label} = {:?} ({}){cond}", op, self.exprText(arg, env)),
            StatementKind::Binary { op, arg1, arg2 } => {
                format!("{label} = {:?} ({}, {}){cond}", op, self.exprText(arg1, env), self.exprText(arg2, env))
            }
            StatementKind::ReadVariable { variable } => format!("{label} = read {variable}{cond}"),
            StatementKind::WriteVariable { variable, arg } => format!("write {variable} = {}{cond}", self.exprText(arg, env)),
        }
    }

    /// `toString`.
    pub fn toText(&self, env: &Env) -> String {
        let lines: Vec<String> = self.statements.iter().map(|&s| self.dump(s, env)).collect();
        format!("{}\nRESULT: {}", lines.join("\n"), self.exprText(&self.result, env))
    }
}
