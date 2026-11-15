// Ours (not a ported file): the whole program after name resolution, the
// form the reachability analysis and the C back end read.

use std::collections::BTreeMap;

pub type FuncId = usize;
pub type ClassId = usize;
pub type GlobalId = usize;
pub type Slot = usize;

/// What an `is` or `as` checks.
#[derive(Debug, Clone, PartialEq)]
pub enum TypeTest {
    /// `dynamic`, `Object?`: every value.
    Any,
    /// `Object`: every value but null.
    NonNull,
    /// `Null`.
    Null,
    /// A class and its subclasses, plus null when the type is nullable.
    Class { class: ClassId, nullable: bool },
}

#[derive(Debug, Clone)]
pub enum Expr {
    Int(i64),
    Str(String),
    Bool(bool),
    Null,
    Local(Slot),
    SetLocal(Slot, Box<Expr>),
    This,
    Global(GlobalId),
    SetGlobal(GlobalId, Box<Expr>),
    /// A top-level or static function, called directly.
    Call(FuncId, Vec<Expr>),
    /// Allocates an instance and runs the constructor on it.
    New(ClassId, FuncId, Vec<Expr>),
    /// A dynamic call: `m:name`, `g:name`, `s:name`, `op:[]`, `op:[]=`.
    Invoke(Box<Expr>, String, Vec<Expr>),
    /// An `external` function of the core library.
    Native(String, Vec<Expr>),
    Binary(String, Box<Expr>, Box<Expr>),
    Unary(String, Box<Expr>),
    Not(Box<Expr>),
    And(Box<Expr>, Box<Expr>),
    Or(Box<Expr>, Box<Expr>),
    Cond(Box<Expr>, Box<Expr>, Box<Expr>),
    Is(Box<Expr>, TypeTest, bool),
    As(Box<Expr>, TypeTest),
    List(Vec<Expr>),
    Map(Vec<(Expr, Expr)>),
    /// String interpolation: each part goes through `toString`.
    Interp(Vec<Expr>),
    /// Evaluates the first expression into the slot, then the second.
    Let(Slot, Box<Expr>, Box<Expr>),
    /// Evaluates each in order; the value is the last one's.
    Seq(Vec<Expr>),
}

#[derive(Debug, Clone)]
pub enum Stmt {
    Expr(Expr),
    If(Expr, Vec<Stmt>, Vec<Stmt>),
    While(Expr, Vec<Stmt>),
    For(Vec<Stmt>, Option<Expr>, Vec<Expr>, Vec<Stmt>),
    Return(Option<Expr>),
    Break,
    Continue,
    Block(Vec<Stmt>),
}

#[derive(Debug, Clone)]
pub enum Body {
    Stmts(Vec<Stmt>),
    /// Implemented in C (natives.rs) under this name.
    Native(String),
    /// Declared without a body in an abstract class.
    Abstract,
    FieldGet(Slot),
    FieldSet(Slot),
    /// A generative constructor: field initializers, then the superclass
    /// constructor, then the body, which is Dart's order.
    Ctor {
        field_inits: Vec<(Slot, Expr)>,
        super_call: Option<(FuncId, Vec<Expr>)>,
        body: Vec<Stmt>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FuncKind {
    TopLevel,
    Static,
    Method,
    Getter,
    Setter,
    Operator,
    Ctor,
    Field,
    GlobalInit,
}

#[derive(Debug, Clone)]
pub struct Func {
    /// For reports and the C comments: `Class.member` or `name`.
    pub name: String,
    pub from_prelude: bool,
    pub kind: FuncKind,
    pub class: Option<ClassId>,
    /// Slot 0 is `this` when there is one.
    pub has_this: bool,
    /// The parameters after `this`, with the default of each optional one.
    pub params: Vec<Param>,
    pub locals: usize,
    pub body: Body,
}

#[derive(Debug, Clone)]
pub struct Param {
    pub name: String,
    /// None for a required parameter.
    pub default: Option<Expr>,
}

#[derive(Debug, Clone)]
pub struct Class {
    pub name: String,
    pub from_prelude: bool,
    pub is_abstract: bool,
    pub superclass: Option<ClassId>,
    /// Every field, the superclass's first: the instance layout.
    pub fields: Vec<String>,
    /// Instance members by selector, declared in this class.
    pub members: BTreeMap<String, FuncId>,
    pub statics: BTreeMap<String, FuncId>,
    /// Constructors by name ("" is the unnamed one).
    pub ctors: BTreeMap<String, FuncId>,
}

#[derive(Debug, Clone)]
pub struct Global {
    pub name: String,
    pub init: FuncId,
}

#[derive(Debug, Clone)]
pub struct Program {
    pub classes: Vec<Class>,
    pub funcs: Vec<Func>,
    pub globals: Vec<Global>,
    pub main: FuncId,
    pub object: ClassId,
    pub null: ClassId,
    pub bool_: ClassId,
    pub int: ClassId,
    pub string: ClassId,
    pub list: ClassId,
    pub map: ClassId,
}

impl Program {
    /// The member [selector] resolves to on an instance of [class].
    pub fn lookup(&self, class: ClassId, selector: &str) -> Option<FuncId> {
        let mut current = Some(class);
        while let Some(c) = current {
            if let Some(&f) = self.classes[c].members.get(selector) {
                return match self.funcs[f].body {
                    Body::Abstract => None,
                    _ => Some(f),
                };
            }
            current = self.classes[c].superclass;
        }
        None
    }

    pub fn is_subclass(&self, class: ClassId, of: ClassId) -> bool {
        let mut current = Some(class);
        while let Some(c) = current {
            if c == of {
                return true;
            }
            current = self.classes[c].superclass;
        }
        false
    }
}
