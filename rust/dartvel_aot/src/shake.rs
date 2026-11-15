// Ours (not a ported file): what of the whole program a run can reach.
//
// The program is closed: user code and the core library are all there is,
// there is no `dart:mirrors`, and nothing is looked up by name at run time.
// So a function is needed only if a reachable call can land on it:
//
// - `none` keeps everything, the way a runtime that can be asked for any
//   member by name must;
// - `calls` follows the call graph and sends each dynamic call to every
//   implementation of that name in any class (class-hierarchy analysis);
// - `types` (the default) does rapid type analysis: a dynamic call reaches
//   an implementation only in a class some reachable code instantiates,
//   and both sets grow together until neither changes.

use std::collections::{BTreeMap, BTreeSet};

use crate::ir::*;
use crate::natives::{self, Makes};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    None,
    Calls,
    Types,
}

impl Mode {
    pub fn parse(text: &str) -> Option<Mode> {
        match text {
            "none" => Some(Mode::None),
            "calls" => Some(Mode::Calls),
            "types" => Some(Mode::Types),
            _ => None,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Mode::None => "none",
            Mode::Calls => "calls",
            Mode::Types => "types",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Reach {
    pub funcs: BTreeSet<FuncId>,
    /// Classes whose instances can exist.
    pub classes: BTreeSet<ClassId>,
    /// Selectors some reachable code invokes dynamically.
    pub selectors: BTreeSet<String>,
    pub globals: BTreeSet<GlobalId>,
    /// The most arguments any reachable call site passes to each selector.
    pub call_arity: BTreeMap<String, usize>,
    /// Whether the back end must keep every function alive (`none`).
    pub keep_all: bool,
    /// Whether class names are needed at run time (the default
    /// `Object.toString` is reachable). Without it no name is emitted.
    pub class_names: bool,
}

/// What one function body refers to.
#[derive(Default)]
struct Facts {
    calls: Vec<FuncId>,
    news: Vec<(ClassId, FuncId)>,
    selectors: Vec<(String, usize)>,
    globals: Vec<GlobalId>,
    makes_string: bool,
    makes_list: bool,
    makes_map: bool,
    interpolates: bool,
}

fn expr_facts(e: &Expr, f: &mut Facts) {
    match e {
        Expr::Int(_) | Expr::Bool(_) | Expr::Null | Expr::Local(_) | Expr::This => {}
        Expr::Str(_) => f.makes_string = true,
        Expr::SetLocal(_, v)
        | Expr::Unary(_, v)
        | Expr::Not(v)
        | Expr::Is(v, _, _)
        | Expr::As(v, _) => expr_facts(v, f),
        Expr::Global(g) => f.globals.push(*g),
        Expr::SetGlobal(g, v) => {
            f.globals.push(*g);
            expr_facts(v, f);
        }
        Expr::Call(func, args) => {
            f.calls.push(*func);
            args.iter().for_each(|a| expr_facts(a, f));
        }
        Expr::New(class, ctor, args) => {
            f.news.push((*class, *ctor));
            args.iter().for_each(|a| expr_facts(a, f));
        }
        Expr::Invoke(receiver, selector, args) => {
            f.selectors.push((selector.clone(), args.len()));
            expr_facts(receiver, f);
            args.iter().for_each(|a| expr_facts(a, f));
        }
        Expr::Native(_, args) | Expr::Seq(args) => args.iter().for_each(|a| expr_facts(a, f)),
        Expr::Binary(_, a, b) | Expr::And(a, b) | Expr::Or(a, b) | Expr::Let(_, a, b) => {
            expr_facts(a, f);
            expr_facts(b, f);
        }
        Expr::Cond(a, b, c) => {
            expr_facts(a, f);
            expr_facts(b, f);
            expr_facts(c, f);
        }
        Expr::List(items) => {
            f.makes_list = true;
            items.iter().for_each(|a| expr_facts(a, f));
        }
        Expr::Map(entries) => {
            f.makes_map = true;
            for (k, v) in entries {
                expr_facts(k, f);
                expr_facts(v, f);
            }
        }
        Expr::Interp(parts) => {
            f.makes_string = true;
            f.interpolates = true;
            parts.iter().for_each(|a| expr_facts(a, f));
        }
    }
}

fn stmt_facts(s: &Stmt, f: &mut Facts) {
    match s {
        Stmt::Expr(e) => expr_facts(e, f),
        Stmt::If(c, a, b) => {
            expr_facts(c, f);
            a.iter().chain(b).for_each(|s| stmt_facts(s, f));
        }
        Stmt::While(c, body) => {
            expr_facts(c, f);
            body.iter().for_each(|s| stmt_facts(s, f));
        }
        Stmt::For(init, c, updates, body) => {
            init.iter().for_each(|s| stmt_facts(s, f));
            if let Some(c) = c {
                expr_facts(c, f);
            }
            updates.iter().for_each(|e| expr_facts(e, f));
            body.iter().for_each(|s| stmt_facts(s, f));
        }
        Stmt::Return(Some(e)) => expr_facts(e, f),
        Stmt::Return(None) | Stmt::Break | Stmt::Continue => {}
        Stmt::Block(b) => b.iter().for_each(|s| stmt_facts(s, f)),
    }
}

fn func_facts(prog: &Program, func: &Func) -> Facts {
    let mut f = Facts::default();
    for p in &func.params {
        if let Some(d) = &p.default {
            expr_facts(d, &mut f);
        }
    }
    match &func.body {
        Body::Stmts(stmts) => stmts.iter().for_each(|s| stmt_facts(s, &mut f)),
        Body::Ctor {
            field_inits,
            super_call,
            body,
        } => {
            field_inits.iter().for_each(|(_, e)| expr_facts(e, &mut f));
            if let Some((target, args)) = super_call {
                f.calls.push(*target);
                args.iter().for_each(|a| expr_facts(a, &mut f));
            }
            body.iter().for_each(|s| stmt_facts(s, &mut f));
        }
        Body::Native(name) => {
            let native =
                natives::find(name).unwrap_or_else(|| panic!("no C body for native {name}"));
            for m in native.makes {
                match m {
                    Makes::String => f.makes_string = true,
                    Makes::List => f.makes_list = true,
                }
            }
        }
        Body::Abstract | Body::FieldGet(_) | Body::FieldSet(_) => {}
    }
    let _ = prog;
    f
}

struct Analysis<'p> {
    prog: &'p Program,
    reach: Reach,
    queue: Vec<FuncId>,
}

impl<'p> Analysis<'p> {
    fn add_func(&mut self, f: FuncId) {
        if self.reach.funcs.insert(f) {
            self.queue.push(f);
        }
    }

    fn add_class(&mut self, c: ClassId) {
        if self.prog.classes[c].is_abstract || !self.reach.classes.insert(c) {
            return;
        }
        let selectors: Vec<String> = self.reach.selectors.iter().cloned().collect();
        for s in selectors {
            if let Some(f) = self.prog.lookup(c, &s) {
                self.add_func(f);
            }
        }
    }

    fn add_selector(&mut self, s: &str, args: usize) {
        let arity = self.reach.call_arity.entry(s.to_string()).or_insert(0);
        *arity = (*arity).max(args);
        if !self.reach.selectors.insert(s.to_string()) {
            return;
        }
        let classes: Vec<ClassId> = self.reach.classes.iter().copied().collect();
        for c in classes {
            if let Some(f) = self.prog.lookup(c, s) {
                self.add_func(f);
            }
        }
    }

    fn run(&mut self) {
        while let Some(id) = self.queue.pop() {
            let func = &self.prog.funcs[id];
            let facts = func_facts(self.prog, func);
            if let Body::Native(name) = &func.body
                && name == "_className"
            {
                self.reach.class_names = true;
            }
            for c in facts.calls {
                self.add_func(c);
            }
            for (class, ctor) in facts.news {
                self.add_class(class);
                self.add_func(ctor);
            }
            for g in facts.globals {
                if self.reach.globals.insert(g) {
                    self.add_func(self.prog.globals[g].init);
                }
            }
            if facts.makes_string {
                self.add_class(self.prog.string);
            }
            if facts.makes_list {
                self.add_class(self.prog.list);
            }
            if facts.makes_map {
                self.add_class(self.prog.map);
            }
            if facts.interpolates {
                self.add_selector("m:toString", 0);
            }
            for (s, n) in facts.selectors {
                self.add_selector(&s, n);
            }
        }
    }
}

pub fn analyse(prog: &Program, mode: Mode) -> Reach {
    let mut analysis = Analysis {
        prog,
        reach: Reach::default(),
        queue: vec![],
    };
    // Null, bool and int values come from every comparison, literal and
    // default, so they are always possible.
    for c in [prog.null, prog.bool_, prog.int] {
        analysis.add_class(c);
    }
    if mode != Mode::Types {
        for c in 0..prog.classes.len() {
            analysis.add_class(c);
        }
    }
    if mode == Mode::None {
        analysis.reach.keep_all = true;
        for (id, f) in prog.funcs.iter().enumerate() {
            if !matches!(f.body, Body::Abstract) {
                analysis.add_func(id);
            }
        }
        for c in &prog.classes {
            for selector in c.members.keys() {
                analysis.add_selector(selector, 0);
            }
        }
        for g in 0..prog.globals.len() {
            analysis.reach.globals.insert(g);
        }
    }
    analysis.add_func(prog.main);
    analysis.run();
    analysis.reach
}
