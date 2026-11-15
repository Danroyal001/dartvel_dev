// Ours (not a ported file): resolves names in the tree the ported parser
// built and lowers it to the program in ir.rs. The core library (the
// prelude) and the user's library are two scopes: the user's sees its own
// declarations, then the prelude's public ones; the prelude sees only its
// own. Anything outside the supported subset is a compile error that names
// the construct, never a silent miscompile.

use std::collections::{BTreeMap, HashMap};

use crate::ir::*;
use crate::syntax::{Child, Node};

#[derive(Debug, Clone, PartialEq)]
pub struct CompileError {
    pub file: String,
    pub offset: i32,
    pub message: String,
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}: {}", self.file, self.offset, self.message)
    }
}

type R<T> = Result<T, CompileError>;

#[derive(Clone, Copy, Debug)]
enum Decl {
    Func(FuncId),
    Class(ClassId),
    Global(GlobalId),
}

/// The built-in classes: their values are made by the runtime, so they
/// get no constructor.
const BUILTINS: [&str; 7] = ["Object", "Null", "bool", "int", "String", "List", "Map"];

/// Operators a class may declare in this increment.
const OPERATORS: [&str; 2] = ["[]", "[]="];

struct Lib<'a> {
    unit: &'a Node,
    prelude: bool,
    file: String,
    scope: HashMap<String, Decl>,
}

/// A body still to lower, once every declaration is known.
enum Job<'a> {
    Function {
        func: FuncId,
        lib: usize,
        class: Option<ClassId>,
        params: Option<&'a Node>,
        body: &'a Node,
    },
    Ctor {
        func: FuncId,
        lib: usize,
        class: ClassId,
        node: Option<&'a Node>,
    },
    GlobalInit {
        func: FuncId,
        lib: usize,
        init: Option<&'a Node>,
    },
}

struct Lowering<'a> {
    libs: Vec<Lib<'a>>,
    prog: Program,
    jobs: Vec<Job<'a>>,
    /// Each class's field declarations with initializers: (slot, expression).
    field_inits: HashMap<ClassId, Vec<(Slot, &'a Node)>>,
    class_lib: HashMap<ClassId, usize>,
    class_nodes: HashMap<ClassId, &'a Node>,
}

fn err<T>(file: &str, node: &Node, message: impl Into<String>) -> R<T> {
    Err(CompileError {
        file: file.to_string(),
        offset: node.offset,
        message: message.into(),
    })
}

pub fn lower(prelude: &Node, user: &Node, user_file: &str) -> R<Program> {
    let empty = Program {
        classes: vec![],
        funcs: vec![],
        globals: vec![],
        main: 0,
        object: 0,
        null: 0,
        bool_: 0,
        int: 0,
        string: 0,
        list: 0,
        map: 0,
    };
    let mut lowering = Lowering {
        libs: vec![
            Lib {
                unit: prelude,
                prelude: true,
                file: "prelude.dart".into(),
                scope: HashMap::new(),
            },
            Lib {
                unit: user,
                prelude: false,
                file: user_file.into(),
                scope: HashMap::new(),
            },
        ],
        prog: empty,
        jobs: vec![],
        field_inits: HashMap::new(),
        class_lib: HashMap::new(),
        class_nodes: HashMap::new(),
    };
    lowering.declare_top_level()?;
    lowering.resolve_superclasses()?;
    lowering.declare_members()?;
    lowering.lower_bodies()?;
    let main = match lowering.libs[1].scope.get("main") {
        Some(Decl::Func(f)) => *f,
        _ => {
            return err(
                user_file,
                user,
                "the program has no top-level function `main`",
            );
        }
    };
    if !lowering.prog.funcs[main].params.is_empty() {
        return err(user_file, user, "unsupported: `main` with parameters");
    }
    lowering.prog.main = main;
    Ok(lowering.prog)
}

fn new_func(name: String, from_prelude: bool, kind: FuncKind, class: Option<ClassId>) -> Func {
    Func {
        name,
        from_prelude,
        kind,
        class,
        has_this: matches!(
            kind,
            FuncKind::Method
                | FuncKind::Getter
                | FuncKind::Setter
                | FuncKind::Operator
                | FuncKind::Ctor
                | FuncKind::Field
        ),
        params: vec![],
        locals: 0,
        body: Body::Abstract,
    }
}

impl<'a> Lowering<'a> {
    fn add_func(&mut self, func: Func) -> FuncId {
        self.prog.funcs.push(func);
        self.prog.funcs.len() - 1
    }

    fn lookup(&self, lib: usize, name: &str) -> Option<Decl> {
        if let Some(d) = self.libs[lib].scope.get(name) {
            return Some(*d);
        }
        if !self.libs[lib].prelude && !name.starts_with('_') {
            return self.libs[0].scope.get(name).copied();
        }
        None
    }

    fn declare(&mut self, lib: usize, node: &Node, name: &str, decl: Decl) -> R<()> {
        let file = self.libs[lib].file.clone();
        if self.libs[lib]
            .scope
            .insert(name.to_string(), decl)
            .is_some()
        {
            return err(&file, node, format!("`{name}` is declared twice"));
        }
        Ok(())
    }

    fn declare_top_level(&mut self) -> R<()> {
        for lib in 0..self.libs.len() {
            let unit = self.libs[lib].unit;
            let file = self.libs[lib].file.clone();
            let prelude = self.libs[lib].prelude;
            for directive in unit.list("directives") {
                let uri = directive
                    .node("uri")
                    .and_then(|u| u.token("literal"))
                    .unwrap_or("");
                let uri = uri.trim_matches(|c| c == '\'' || c == '"');
                if directive.kind != "ImportDirective"
                    || !(uri == "dart:convert" || uri == "dart:core")
                {
                    return err(
                        &file,
                        directive,
                        format!(
                            "unsupported directive: only `import 'dart:convert';` and `import 'dart:core';` are understood, not {uri:?}"
                        ),
                    );
                }
                if directive.token("prefixName").is_some()
                    || !directive.list("combinators").is_empty()
                {
                    return err(
                        &file,
                        directive,
                        "unsupported: import prefixes and show/hide",
                    );
                }
            }
            for decl in unit.list("declarations2") {
                match decl.kind.as_str() {
                    "ClassDeclaration2" => {
                        let name = decl
                            .node("namePart")
                            .and_then(|n| n.token("typeName"))
                            .unwrap_or("")
                            .to_string();
                        for clause in ["withClause", "implementsClause"] {
                            if decl.node(clause).is_some() {
                                return err(
                                    &file,
                                    decl,
                                    format!("unsupported: `{name}` uses with/implements"),
                                );
                            }
                        }
                        let id = self.prog.classes.len();
                        self.prog.classes.push(Class {
                            name: name.clone(),
                            from_prelude: prelude,
                            is_abstract: decl.token("abstractKeyword").is_some(),
                            superclass: None,
                            fields: vec![],
                            members: BTreeMap::new(),
                            statics: BTreeMap::new(),
                            ctors: BTreeMap::new(),
                        });
                        self.class_lib.insert(id, lib);
                        self.class_nodes.insert(id, decl);
                        self.declare(lib, decl, &name, Decl::Class(id))?;
                        if prelude {
                            match name.as_str() {
                                "Object" => self.prog.object = id,
                                "Null" => self.prog.null = id,
                                "bool" => self.prog.bool_ = id,
                                "int" => self.prog.int = id,
                                "String" => self.prog.string = id,
                                "List" => self.prog.list = id,
                                "Map" => self.prog.map = id,
                                _ => {}
                            }
                        }
                    }
                    "TopLevelFunctionDeclaration" => {
                        let name = decl.token("name").unwrap_or("").to_string();
                        if decl.token("propertyKeyword").is_some()
                            || decl.token("getKeyword").is_some()
                            || decl.token("setKeyword").is_some()
                        {
                            return err(&file, decl, "unsupported: top-level getters and setters");
                        }
                        let id = self.add_func(new_func(
                            name.clone(),
                            prelude,
                            FuncKind::TopLevel,
                            None,
                        ));
                        self.declare(lib, decl, &name, Decl::Func(id))?;
                        if decl.token("externalKeyword").is_some() {
                            if !prelude {
                                return err(&file, decl, "unsupported: external functions");
                            }
                            self.prog.funcs[id].body = Body::Native(name.clone());
                            self.set_params_only(id, lib, decl.node("formalParameters"))?;
                        } else {
                            let body = decl.node("body").expect("function body");
                            self.jobs.push(Job::Function {
                                func: id,
                                lib,
                                class: None,
                                params: decl.node("formalParameters"),
                                body,
                            });
                        }
                    }
                    "TopLevelVariablesDeclaration" => {
                        let list = decl
                            .node("variables")
                            .map(|v| v.list("variables"))
                            .unwrap_or(decl.list("variables"));
                        let keyword = decl.token("constFinalOrVarKeyword").unwrap_or("");
                        if decl.token("lateKeyword").is_some() || keyword == "const" {
                            return err(
                                &file,
                                decl,
                                "unsupported: late and const top-level variables",
                            );
                        }
                        for variable in list {
                            let name = variable.token("name").unwrap_or("").to_string();
                            let init = self.add_func(new_func(
                                name.clone(),
                                prelude,
                                FuncKind::GlobalInit,
                                None,
                            ));
                            let id = self.prog.globals.len();
                            self.prog.globals.push(Global {
                                name: name.clone(),
                                init,
                            });
                            self.declare(lib, variable, &name, Decl::Global(id))?;
                            self.jobs.push(Job::GlobalInit {
                                func: init,
                                lib,
                                init: variable.node("initializer"),
                            });
                        }
                    }
                    other => return err(&file, decl, format!("unsupported declaration: {other}")),
                }
            }
        }
        Ok(())
    }

    fn resolve_superclasses(&mut self) -> R<()> {
        for class in 0..self.prog.classes.len() {
            let lib = self.class_lib[&class];
            let node = self.class_nodes[&class];
            let file = self.libs[lib].file.clone();
            let superclass = match node
                .node("extendsClause")
                .and_then(|e| e.node("superclass"))
            {
                Some(named) => {
                    let name = named.token("name").unwrap_or("");
                    match self.lookup(lib, name) {
                        Some(Decl::Class(c)) if !BUILTINS.contains(&name) || name == "Object" => {
                            Some(c)
                        }
                        Some(Decl::Class(_)) => {
                            return err(
                                &file,
                                named,
                                format!("unsupported: extending the built-in class `{name}`"),
                            );
                        }
                        _ => return err(&file, named, format!("unknown class `{name}`")),
                    }
                }
                None if class == self.prog.object => None,
                None => Some(self.prog.object),
            };
            self.prog.classes[class].superclass = superclass;
        }
        // Reject cycles before anything walks the chain.
        for class in 0..self.prog.classes.len() {
            let mut seen = 0;
            let mut current = self.prog.classes[class].superclass;
            while let Some(c) = current {
                seen += 1;
                if seen > self.prog.classes.len() {
                    let file = self.libs[self.class_lib[&class]].file.clone();
                    return err(
                        &file,
                        self.class_nodes[&class],
                        "the class hierarchy has a cycle",
                    );
                }
                current = self.prog.classes[c].superclass;
            }
        }
        Ok(())
    }

    fn layout(&mut self, class: ClassId, done: &mut Vec<bool>) -> R<()> {
        if done[class] {
            return Ok(());
        }
        let mut fields = vec![];
        if let Some(s) = self.prog.classes[class].superclass {
            self.layout(s, done)?;
            fields = self.prog.classes[s].fields.clone();
        }
        let node = self.class_nodes[&class];
        let file = self.libs[self.class_lib[&class]].file.clone();
        let mut inits = vec![];
        for member in members_of(node) {
            if member.kind != "FieldsDeclaration" {
                continue;
            }
            if member.token("staticKeyword").is_some() {
                return err(&file, member, "unsupported: static fields");
            }
            if member.token("lateKeyword").is_some() || member.token("externalKeyword").is_some() {
                return err(&file, member, "unsupported: late or external fields");
            }
            for field in member.list("fields") {
                let name = field.token("name").unwrap_or("").to_string();
                if fields.contains(&name) {
                    return err(
                        &file,
                        field,
                        format!("unsupported: field `{name}` shadows an inherited field"),
                    );
                }
                fields.push(name);
                if let Some(init) = field.node("initializer") {
                    inits.push((fields.len() - 1, init));
                }
            }
        }
        self.prog.classes[class].fields = fields;
        self.field_inits.insert(class, inits);
        done[class] = true;
        Ok(())
    }

    fn declare_members(&mut self) -> R<()> {
        let mut done = vec![false; self.prog.classes.len()];
        for class in 0..self.prog.classes.len() {
            self.layout(class, &mut done)?;
        }
        for class in 0..self.prog.classes.len() {
            let lib = self.class_lib[&class];
            let node = self.class_nodes[&class];
            let file = self.libs[lib].file.clone();
            let prelude = self.libs[lib].prelude;
            let class_name = self.prog.classes[class].name.clone();
            let mut has_ctor = false;
            for member in members_of(node) {
                let name = member.token("name").unwrap_or("").to_string();
                let is_static = member.token("staticKeyword").is_some();
                if member.token("externalKeyword").is_some() {
                    return err(&file, member, "unsupported: external members");
                }
                match member.kind.as_str() {
                    "FieldsDeclaration" => {
                        let final_ = matches!(
                            member.token("constFinalOrVarKeyword"),
                            Some("final") | Some("const")
                        );
                        for field in member.list("fields") {
                            let fname = field.token("name").unwrap_or("").to_string();
                            let slot = self.prog.classes[class]
                                .fields
                                .iter()
                                .position(|f| *f == fname)
                                .unwrap();
                            let mut getter = new_func(
                                format!("{class_name}.{fname}"),
                                prelude,
                                FuncKind::Field,
                                Some(class),
                            );
                            getter.body = Body::FieldGet(slot);
                            getter.locals = 1;
                            let g = self.add_func(getter);
                            self.add_member(class, &file, field, format!("g:{fname}"), g)?;
                            if !final_ {
                                let mut setter = new_func(
                                    format!("{class_name}.{fname}="),
                                    prelude,
                                    FuncKind::Field,
                                    Some(class),
                                );
                                setter.body = Body::FieldSet(slot);
                                setter.params = vec![Param {
                                    name: "value".into(),
                                    default: None,
                                }];
                                setter.locals = 2;
                                let s = self.add_func(setter);
                                self.add_member(class, &file, field, format!("s:{fname}"), s)?;
                            }
                        }
                    }
                    "MethodDeclaration2"
                    | "GetterDeclaration"
                    | "SetterDeclaration"
                    | "OperatorDeclaration" => {
                        let (kind, selector, display) = match member.kind.as_str() {
                            "MethodDeclaration2" if is_static => {
                                (FuncKind::Static, name.clone(), name.clone())
                            }
                            "MethodDeclaration2" => {
                                (FuncKind::Method, format!("m:{name}"), name.clone())
                            }
                            "GetterDeclaration" => {
                                (FuncKind::Getter, format!("g:{name}"), name.clone())
                            }
                            "SetterDeclaration" => {
                                (FuncKind::Setter, format!("s:{name}"), format!("{name}="))
                            }
                            _ => {
                                let op = member.token("operator").unwrap_or("").to_string();
                                if !OPERATORS.contains(&op.as_str()) {
                                    return err(
                                        &file,
                                        member,
                                        format!("unsupported: declaring `operator {op}`"),
                                    );
                                }
                                (
                                    FuncKind::Operator,
                                    format!("op:{op}"),
                                    format!("operator {op}"),
                                )
                            }
                        };
                        if is_static && kind != FuncKind::Static {
                            return err(&file, member, "unsupported: static getters and setters");
                        }
                        let id = self.add_func(new_func(
                            format!("{class_name}.{display}"),
                            prelude,
                            kind,
                            Some(class),
                        ));
                        let body = member.node("body").expect("member body");
                        if body.kind == "EmptyFunctionBody" {
                            if !self.prog.classes[class].is_abstract {
                                return err(
                                    &file,
                                    member,
                                    format!(
                                        "`{class_name}.{display}` has no body in a class that is not abstract"
                                    ),
                                );
                            }
                            self.set_params_only(id, lib, member.node("formalParameters"))?;
                        } else {
                            self.jobs.push(Job::Function {
                                func: id,
                                lib,
                                class: Some(class),
                                params: member.node("formalParameters"),
                                body,
                            });
                        }
                        if kind == FuncKind::Static {
                            self.prog.classes[class].statics.insert(selector, id);
                        } else {
                            self.add_member(class, &file, member, selector, id)?;
                        }
                    }
                    "ConstructorDeclaration2" => {
                        if member.token("factoryKeyword").is_some()
                            || member.token("constKeyword").is_some()
                        {
                            return err(
                                &file,
                                member,
                                "unsupported: factory and const constructors",
                            );
                        }
                        has_ctor = true;
                        let id = self.add_func(new_func(
                            if name.is_empty() {
                                class_name.clone()
                            } else {
                                format!("{class_name}.{name}")
                            },
                            prelude,
                            FuncKind::Ctor,
                            Some(class),
                        ));
                        self.prog.classes[class].ctors.insert(name.clone(), id);
                        self.jobs.push(Job::Ctor {
                            func: id,
                            lib,
                            class,
                            node: Some(member),
                        });
                    }
                    other => {
                        return err(&file, member, format!("unsupported class member: {other}"));
                    }
                }
            }
            if !has_ctor && !(prelude && BUILTINS.contains(&class_name.as_str())) {
                let id = self.add_func(new_func(
                    class_name.clone(),
                    prelude,
                    FuncKind::Ctor,
                    Some(class),
                ));
                self.prog.classes[class].ctors.insert(String::new(), id);
                self.jobs.push(Job::Ctor {
                    func: id,
                    lib,
                    class,
                    node: None,
                });
            }
        }
        Ok(())
    }

    fn add_member(
        &mut self,
        class: ClassId,
        file: &str,
        node: &Node,
        selector: String,
        id: FuncId,
    ) -> R<()> {
        if self.prog.classes[class]
            .members
            .insert(selector.clone(), id)
            .is_some()
        {
            return err(
                file,
                node,
                format!(
                    "`{}` declares `{}` twice",
                    self.prog.classes[class].name,
                    &selector[selector.find(':').unwrap() + 1..]
                ),
            );
        }
        Ok(())
    }

    /// Records the parameters of a function that has no Dart body.
    fn set_params_only(&mut self, func: FuncId, lib: usize, params: Option<&'a Node>) -> R<()> {
        let has_this = self.prog.funcs[func].has_this;
        let mut fx = Fx::new(self, lib, None, has_this);
        let lowered = fx.params(params, &mut vec![])?;
        let locals = fx.next;
        self.prog.funcs[func].params = lowered;
        self.prog.funcs[func].locals = locals;
        Ok(())
    }

    fn lower_bodies(&mut self) -> R<()> {
        let jobs = std::mem::take(&mut self.jobs);
        for job in jobs {
            match job {
                Job::Function {
                    func,
                    lib,
                    class,
                    params,
                    body,
                } => {
                    let has_this = self.prog.funcs[func].has_this;
                    let mut fx = Fx::new(self, lib, class, has_this);
                    let lowered_params = fx.params(params, &mut vec![])?;
                    let stmts = fx.function_body(body)?;
                    let locals = fx.next;
                    let f = &mut self.prog.funcs[func];
                    f.params = lowered_params;
                    f.body = Body::Stmts(stmts);
                    f.locals = locals;
                }
                Job::GlobalInit { func, lib, init } => {
                    let mut fx = Fx::new(self, lib, None, false);
                    let value = match init {
                        Some(e) => fx.expr(e)?,
                        None => Expr::Null,
                    };
                    let locals = fx.next;
                    let f = &mut self.prog.funcs[func];
                    f.body = Body::Stmts(vec![Stmt::Return(Some(value))]);
                    f.locals = locals;
                }
                Job::Ctor {
                    func,
                    lib,
                    class,
                    node,
                } => self.lower_ctor(func, lib, class, node)?,
            }
        }
        Ok(())
    }

    fn lower_ctor(
        &mut self,
        func: FuncId,
        lib: usize,
        class: ClassId,
        node: Option<&'a Node>,
    ) -> R<()> {
        let file = self.libs[lib].file.clone();
        let decl_inits = self.field_inits.get(&class).cloned().unwrap_or_default();
        let superclass = self.prog.classes[class].superclass;
        let mut fx = Fx::new(self, lib, Some(class), true);
        let mut field_inits = vec![];
        // Field declarations' initializers see neither parameters nor `this`.
        for (slot, init) in decl_inits {
            field_inits.push((slot, fx.expr(init)?));
        }
        let mut this_params = vec![];
        let params = fx.params(
            node.and_then(|n| n.node("formalParameters")),
            &mut this_params,
        )?;
        for (field_name, slot_of_param, at) in &this_params {
            match fx.lowering.prog.classes[class]
                .fields
                .iter()
                .position(|f| f == field_name)
            {
                Some(field_slot) => field_inits.push((field_slot, Expr::Local(*slot_of_param))),
                None => return err(&file, at, format!("`this.{field_name}` names no field")),
            }
        }
        let mut super_call = None;
        let mut super_seen = false;
        if let Some(n) = node {
            for init in n.list("initializers") {
                match init.kind.as_str() {
                    "SuperConstructorInvocation" => {
                        super_seen = true;
                        let ctor_name = init
                            .token("constructorName")
                            .or(init.node("constructorName").and_then(|c| c.token("name")))
                            .unwrap_or("");
                        let Some(s) = superclass else {
                            return err(&file, init, "no superclass");
                        };
                        let Some(&target) = fx.lowering.prog.classes[s].ctors.get(ctor_name) else {
                            return err(
                                &file,
                                init,
                                format!("the superclass has no constructor `{ctor_name}`"),
                            );
                        };
                        let args = fx.arguments(init.node("argumentList"))?;
                        super_call = Some((target, args));
                    }
                    "ConstructorFieldInitializer" => {
                        let field_name = init.token("fieldName").unwrap_or("").to_string();
                        let value = fx.expr(
                            init.node("expression")
                                .or(init.node("expression2"))
                                .expect("initializer value"),
                        )?;
                        match fx.lowering.prog.classes[class]
                            .fields
                            .iter()
                            .position(|f| *f == field_name)
                        {
                            Some(slot) => field_inits.push((slot, value)),
                            None => {
                                return err(&file, init, format!("`{field_name}` names no field"));
                            }
                        }
                    }
                    other => {
                        return err(
                            &file,
                            init,
                            format!("unsupported constructor initializer: {other}"),
                        );
                    }
                }
            }
        }
        if !super_seen
            && let Some(s) = superclass
            && s != fx.lowering.prog.object
        {
            match fx.lowering.prog.classes[s].ctors.get("") {
                Some(&target) => super_call = Some((target, vec![])),
                None => {
                    let at = node.unwrap_or(fx.lowering.class_nodes[&class]);
                    return err(
                        &file,
                        at,
                        "the superclass has no unnamed constructor to call",
                    );
                }
            }
        }
        // `this.x` parameters are not in scope in the body: `x` is the field.
        for (name, _, _) in &this_params {
            fx.unbind(name);
        }
        let body = match node.and_then(|n| n.node("body")) {
            Some(b) => fx.function_body(b)?,
            None => vec![],
        };
        let locals = fx.next;
        let f = &mut self.prog.funcs[func];
        f.params = params;
        f.locals = locals;
        f.body = Body::Ctor {
            field_inits,
            super_call,
            body,
        };
        Ok(())
    }
}

fn members_of(class: &Node) -> &[Node] {
    class.node("body").map(|b| b.list("members")).unwrap_or(&[])
}

/// The lowering of one function body: its scopes and its slots.
struct Fx<'l, 'a> {
    lowering: &'l Lowering<'a>,
    lib: usize,
    class: Option<ClassId>,
    has_this: bool,
    scopes: Vec<HashMap<String, Slot>>,
    next: Slot,
}

impl<'l, 'a> Fx<'l, 'a> {
    fn new(lowering: &'l Lowering<'a>, lib: usize, class: Option<ClassId>, has_this: bool) -> Self {
        Fx {
            lowering,
            lib,
            class,
            has_this,
            scopes: vec![HashMap::new()],
            next: if has_this { 1 } else { 0 },
        }
    }

    fn file(&self) -> &str {
        &self.lowering.libs[self.lib].file
    }

    fn fail<T>(&self, node: &Node, message: impl Into<String>) -> R<T> {
        err(self.file(), node, message)
    }

    fn slot(&mut self) -> Slot {
        self.next += 1;
        self.next - 1
    }

    fn bind(&mut self, name: &str) -> Slot {
        let slot = self.slot();
        self.scopes
            .last_mut()
            .unwrap()
            .insert(name.to_string(), slot);
        slot
    }

    fn unbind(&mut self, name: &str) {
        for scope in self.scopes.iter_mut() {
            scope.remove(name);
        }
    }

    fn local(&self, name: &str) -> Option<Slot> {
        self.scopes.iter().rev().find_map(|s| s.get(name).copied())
    }

    /// Whether the enclosing class (or a superclass) declares [selector].
    fn member(&self, selector: &str) -> bool {
        if !self.has_this {
            return false;
        }
        let Some(class) = self.class else {
            return false;
        };
        let prog = &self.lowering.prog;
        let mut current = Some(class);
        while let Some(c) = current {
            if prog.classes[c].members.contains_key(selector) {
                return true;
            }
            current = prog.classes[c].superclass;
        }
        false
    }

    fn static_member(&self, name: &str) -> Option<FuncId> {
        self.class
            .and_then(|c| self.lowering.prog.classes[c].statics.get(name).copied())
    }

    /// Binds the parameters; `this.x` ones are reported in [this_params].
    fn params(
        &mut self,
        list: Option<&'a Node>,
        this_params: &mut Vec<(String, Slot, &'a Node)>,
    ) -> R<Vec<Param>> {
        let Some(list) = list else { return Ok(vec![]) };
        let mut out = vec![];
        let mut all: Vec<(&'a Node, bool)> = list
            .list("requiredPositionalFormalParameters")
            .iter()
            .map(|p| (p, false))
            .collect();
        if let Some(delimited) = list.node("delimitedFormalParameters") {
            if delimited.token("leftDelimiter") != Some("[") {
                return self.fail(delimited, "unsupported: named parameters");
            }
            all.extend(delimited.list("formalParameters").iter().map(|p| (p, true)));
        }
        for (param, optional) in all {
            let name = param.token("name").unwrap_or("").to_string();
            match param.kind.as_str() {
                "RegularFormalParameter" | "FieldFormalParameter" => {}
                other => return self.fail(param, format!("unsupported parameter: {other}")),
            }
            if param.node("functionTypedSuffix").is_some() {
                return self.fail(param, "unsupported: function-typed parameters");
            }
            let default = if optional {
                Some(match param.node("defaultClause") {
                    Some(clause) => {
                        let value = clause
                            .node("value")
                            .or(clause.node("defaultValue"))
                            .or_else(|| first_node(clause));
                        match value {
                            Some(v) => self.expr(v)?,
                            None => Expr::Null,
                        }
                    }
                    None => Expr::Null,
                })
            } else {
                None
            };
            let slot = self.bind(&name);
            if param.kind == "FieldFormalParameter" {
                this_params.push((name.clone(), slot, param));
            }
            out.push(Param { name, default });
        }
        Ok(out)
    }

    fn function_body(&mut self, body: &'a Node) -> R<Vec<Stmt>> {
        if body.token("keyword").is_some() || body.token("star").is_some() {
            return self.fail(body, "unsupported: async and generator functions");
        }
        match body.kind.as_str() {
            "BlockFunctionBody" => self.block(body.node("block").expect("block")),
            "ExpressionFunctionBody" => Ok(vec![Stmt::Return(Some(
                self.expr(body.node("expression2").expect("expression"))?,
            ))]),
            "EmptyFunctionBody" => Ok(vec![]),
            other => self.fail(body, format!("unsupported function body: {other}")),
        }
    }

    fn block(&mut self, block: &'a Node) -> R<Vec<Stmt>> {
        self.scopes.push(HashMap::new());
        let mut out = vec![];
        for statement in block.list("statements2") {
            out.push(self.stmt(statement)?);
        }
        self.scopes.pop();
        Ok(out)
    }

    /// A statement in a scope of its own (a branch or loop body).
    fn scoped(&mut self, statement: &'a Node) -> R<Vec<Stmt>> {
        self.scopes.push(HashMap::new());
        let out = self.stmt(statement)?;
        self.scopes.pop();
        Ok(match out {
            Stmt::Block(v) => v,
            s => vec![s],
        })
    }

    fn locals_decl(&mut self, decl: &'a Node) -> R<Vec<Stmt>> {
        if decl.token("lateKeyword").is_some() {
            return self.fail(decl, "unsupported: late variables");
        }
        let mut out = vec![];
        for variable in decl.list("variables") {
            let value = match variable.node("initializer") {
                Some(e) => self.expr(e)?,
                None => Expr::Null,
            };
            // Bound after the initializer, which cannot see the variable.
            let slot = self.bind(variable.token("name").unwrap_or(""));
            out.push(Stmt::Expr(Expr::SetLocal(slot, Box::new(value))));
        }
        Ok(out)
    }

    fn stmt(&mut self, s: &'a Node) -> R<Stmt> {
        Ok(match s.kind.as_str() {
            "Block" => Stmt::Block(self.block(s)?),
            "ExpressionStatement" => {
                Stmt::Expr(self.expr(s.node("expression2").expect("expression"))?)
            }
            "EmptyStatement" => Stmt::Block(vec![]),
            "LocalVariablesDeclarationStatement" => {
                Stmt::Block(self.locals_decl(s.node("declaration").expect("declaration"))?)
            }
            "IfStatement" => {
                if s.node("caseClause").is_some() {
                    return self.fail(s, "unsupported: if-case");
                }
                let condition = self.expr(s.node("expression2").expect("condition"))?;
                let then = self.scoped(s.node("thenStatement2").expect("then"))?;
                let otherwise = match s.node("elseStatement2") {
                    Some(e) => self.scoped(e)?,
                    None => vec![],
                };
                Stmt::If(condition, then, otherwise)
            }
            "WhileStatement" => {
                let condition = self.expr(s.node("condition2").expect("condition"))?;
                Stmt::While(condition, self.scoped(s.node("body2").expect("body"))?)
            }
            "ForStatement" => {
                if s.token("awaitKeyword").is_some() {
                    return self.fail(s, "unsupported: await for");
                }
                let parts = s.node("forLoopParts").expect("loop parts");
                self.scopes.push(HashMap::new());
                let result = match parts.kind.as_str() {
                    "ForPartsWithDeclarations" | "ForPartsWithExpression" => {
                        let init = match parts.kind.as_str() {
                            "ForPartsWithDeclarations" => {
                                self.locals_decl(parts.node("variables2").expect("variables"))?
                            }
                            _ => match parts
                                .node("initialization2")
                                .or(parts.node("initialization"))
                            {
                                Some(e) => vec![Stmt::Expr(self.expr(e)?)],
                                None => vec![],
                            },
                        };
                        let condition = match parts.node("condition2") {
                            Some(c) => Some(self.expr(c)?),
                            None => None,
                        };
                        let mut updates = vec![];
                        for u in parts.list("updaters2") {
                            updates.push(self.expr(u)?);
                        }
                        let body = self.scoped(s.node("body2").expect("body"))?;
                        Stmt::For(init, condition, updates, body)
                    }
                    "ForEachPartsWithDeclaration" => {
                        let iterable = self.expr(parts.node("iterable2").expect("iterable"))?;
                        let iterator = self.slot();
                        let name = parts
                            .node("loopVariable")
                            .and_then(|v| v.token("name"))
                            .unwrap_or("");
                        let variable = self.bind(name);
                        let mut body = vec![Stmt::Expr(Expr::SetLocal(
                            variable,
                            Box::new(Expr::Invoke(
                                Box::new(Expr::Local(iterator)),
                                "g:current".into(),
                                vec![],
                            )),
                        ))];
                        body.extend(self.scoped(s.node("body2").expect("body"))?);
                        Stmt::Block(vec![
                            Stmt::Expr(Expr::SetLocal(
                                iterator,
                                Box::new(Expr::Invoke(
                                    Box::new(iterable),
                                    "g:iterator".into(),
                                    vec![],
                                )),
                            )),
                            Stmt::While(
                                Expr::Invoke(
                                    Box::new(Expr::Local(iterator)),
                                    "m:moveNext".into(),
                                    vec![],
                                ),
                                body,
                            ),
                        ])
                    }
                    other => return self.fail(parts, format!("unsupported for loop: {other}")),
                };
                self.scopes.pop();
                result
            }
            "ReturnStatement" => Stmt::Return(match s.node("expression2") {
                Some(e) => Some(self.expr(e)?),
                None => None,
            }),
            "BreakStatement" | "ContinueStatement" => {
                if s.token("label").is_some() || s.node("label").is_some() {
                    return self.fail(s, "unsupported: labelled break and continue");
                }
                if s.kind == "BreakStatement" {
                    Stmt::Break
                } else {
                    Stmt::Continue
                }
            }
            other => return self.fail(s, format!("unsupported statement: {other}")),
        })
    }

    fn arguments(&mut self, list: Option<&'a Node>) -> R<Vec<Expr>> {
        let mut out = vec![];
        if let Some(list) = list {
            for a in list.list("arguments2") {
                if a.kind == "NamedArgument" || a.kind.starts_with("Named") {
                    return self.fail(a, "unsupported: named arguments");
                }
                out.push(self.expr(a)?);
            }
        }
        Ok(out)
    }

    /// The class an identifier names, when no local or member hides it.
    fn class_named(&self, node: &Node) -> Option<ClassId> {
        if node.kind != "ParsedUnqualifiedName" {
            return None;
        }
        let name = node.token("name")?;
        if self.local(name).is_some()
            || self.member(&format!("g:{name}"))
            || self.member(&format!("m:{name}"))
        {
            return None;
        }
        match self.lowering.lookup(self.lib, name) {
            Some(Decl::Class(c)) => Some(c),
            _ => None,
        }
    }

    fn new_instance(&mut self, at: &Node, class: ClassId, ctor: &str, args: Vec<Expr>) -> R<Expr> {
        let c = &self.lowering.prog.classes[class];
        if c.is_abstract {
            return self.fail(
                at,
                format!("abstract class `{}` cannot be instantiated", c.name),
            );
        }
        match c.ctors.get(ctor) {
            Some(&f) => Ok(Expr::New(class, f, args)),
            None => self.fail(
                at,
                format!(
                    "unsupported: `{}` has no constructor `{ctor}` dartvel_aot can call",
                    c.name
                ),
            ),
        }
    }

    fn call(&mut self, call: &'a Node) -> R<Expr> {
        let operand = call.node("operand").expect("callee");
        if call.node("typeArguments").is_some() {
            // Type arguments are erased in this increment.
        }
        let args = self.arguments(call.node("argumentList"))?;
        match operand.kind.as_str() {
            "ParsedUnqualifiedName" => {
                let name = operand.token("name").unwrap_or("");
                if self.local(name).is_some() {
                    return self.fail(operand, "unsupported: calling a function value");
                }
                if self.member(&format!("m:{name}")) {
                    return Ok(Expr::Invoke(
                        Box::new(Expr::This),
                        format!("m:{name}"),
                        args,
                    ));
                }
                if let Some(f) = self.static_member(name) {
                    return Ok(Expr::Call(f, args));
                }
                match self.lowering.lookup(self.lib, name) {
                    Some(Decl::Func(f)) => Ok(Expr::Call(f, args)),
                    Some(Decl::Class(c)) => self.new_instance(operand, c, "", args),
                    Some(Decl::Global(_)) => {
                        self.fail(operand, "unsupported: calling a function value")
                    }
                    None => self.fail(operand, format!("unknown function `{name}`")),
                }
            }
            "ParsedNameAccess" => {
                let target = operand.node("operand").expect("receiver");
                let name = operand.token("name").unwrap_or("");
                if operand.token("operator") != Some(".") {
                    return self.fail(operand, "unsupported: `?.` and cascades");
                }
                if let Some(class) = self.class_named(target) {
                    if let Some(&f) = self.lowering.prog.classes[class].statics.get(name) {
                        return Ok(Expr::Call(f, args));
                    }
                    return self.new_instance(operand, class, name, args);
                }
                if target.kind == "SuperExpression" {
                    return self.fail(target, "unsupported: super calls");
                }
                let receiver = self.expr(target)?;
                Ok(Expr::Invoke(Box::new(receiver), format!("m:{name}"), args))
            }
            other => self.fail(operand, format!("unsupported callee: {other}")),
        }
    }

    fn type_test(&self, ty: &Node, for_is: bool) -> R<TypeTest> {
        if ty.kind != "NamedType" {
            return self.fail(ty, format!("unsupported type: {}", ty.kind));
        }
        let name = ty.token("name").unwrap_or("");
        let nullable = ty.token("question").is_some();
        if for_is && ty.node("typeArguments").is_some() {
            return self.fail(
                ty,
                "unsupported: `is` with type arguments (types are erased in this increment)",
            );
        }
        Ok(match name {
            "dynamic" => TypeTest::Any,
            "Object" if nullable => TypeTest::Any,
            "Object" => TypeTest::NonNull,
            "Null" => TypeTest::Null,
            "num" => TypeTest::Class {
                class: self.lowering.prog.int,
                nullable,
            },
            _ => match self.lowering.lookup(self.lib, name) {
                Some(Decl::Class(c)) => TypeTest::Class { class: c, nullable },
                _ => return self.fail(ty, format!("unsupported type `{name}`")),
            },
        })
    }

    fn expr(&mut self, e: &'a Node) -> R<Expr> {
        Ok(match e.kind.as_str() {
            "IntegerLiteral" => {
                let text = e.token("literal").unwrap_or("").replace('_', "");
                let value = if let Some(hex) = text.strip_prefix("0x").or(text.strip_prefix("0X")) {
                    u64::from_str_radix(hex, 16).map(|v| v as i64).ok()
                } else {
                    text.parse::<i64>().ok()
                };
                match value {
                    Some(v) => Expr::Int(v),
                    None => {
                        return self
                            .fail(e, format!("integer literal {text} does not fit in 64 bits"));
                    }
                }
            }
            "DoubleLiteral" => return self.fail(e, "unsupported: double (not in this increment)"),
            "BooleanLiteral" => Expr::Bool(e.token("literal") == Some("true")),
            "NullLiteral" => Expr::Null,
            "ThisExpression" => {
                if !self.has_this {
                    return self.fail(e, "`this` outside an instance member");
                }
                Expr::This
            }
            "SimpleStringLiteral" => {
                Expr::Str(self.string_literal(e, e.token("literal").unwrap_or(""))?)
            }
            "AdjacentStrings" => {
                let mut parts = vec![];
                for s in e.list("strings") {
                    parts.push(self.expr(s)?);
                }
                Expr::Interp(parts)
            }
            "StringInterpolation" => self.interpolation(e)?,
            "ParenthesizedExpression" => self.expr(e.node("expression2").expect("expression"))?,
            "ParsedUnqualifiedName" => {
                let name = e.token("name").unwrap_or("");
                if let Some(slot) = self.local(name) {
                    Expr::Local(slot)
                } else if self.member(&format!("g:{name}")) {
                    Expr::Invoke(Box::new(Expr::This), format!("g:{name}"), vec![])
                } else {
                    match self.lowering.lookup(self.lib, name) {
                        Some(Decl::Global(g)) => Expr::Global(g),
                        Some(_) => return self.fail(e, format!("unsupported: `{name}` used as a value (tear-offs and type literals)")),
                        None => return self.fail(e, format!("unknown name `{name}`")),
                    }
                }
            }
            "ParsedNameAccess" => {
                let target = e.node("operand").expect("receiver");
                let name = e.token("name").unwrap_or("");
                if e.token("operator") != Some(".") {
                    return self.fail(e, "unsupported: `?.` and cascades");
                }
                if self.class_named(target).is_some() {
                    return self.fail(e, "unsupported: static getters and tear-offs");
                }
                Expr::Invoke(Box::new(self.expr(target)?), format!("g:{name}"), vec![])
            }
            "ParsedValueArguments" => self.call(e)?,
            "ReceiverIndexExpression" => {
                if e.token("question").is_some() {
                    return self.fail(e, "unsupported: `?[`");
                }
                let receiver = self.expr(e.node("receiver").expect("receiver"))?;
                let index = self.expr(e.node("index").expect("index"))?;
                Expr::Invoke(Box::new(receiver), "op:[]".into(), vec![index])
            }
            "BinaryOperatorInvocation" => {
                let op = e.token("operator").unwrap_or("").to_string();
                const OPS: [&str; 17] = [
                    "+", "-", "*", "~/", "%", "==", "!=", "<", "<=", ">", ">=", "&", "|", "^",
                    "<<", ">>", ">>>",
                ];
                if !OPS.contains(&op.as_str()) {
                    return self.fail(e, format!("unsupported operator `{op}`"));
                }
                let left = self.expr(e.node("leftOperand").expect("left"))?;
                let right = self.expr(e.node("rightOperand").expect("right"))?;
                Expr::Binary(op, Box::new(left), Box::new(right))
            }
            "UnaryOperatorInvocation" => {
                let op = e.token("operator").unwrap_or("").to_string();
                if op != "-" && op != "~" {
                    return self.fail(e, format!("unsupported operator `{op}`"));
                }
                let operand = e.node("operand").expect("operand");
                if op == "-" && operand.kind == "IntegerLiteral" {
                    let text = operand.token("literal").unwrap_or("").replace('_', "");
                    if text == "9223372036854775808" {
                        return Ok(Expr::Int(i64::MIN));
                    }
                }
                Expr::Unary(op, Box::new(self.expr(operand)?))
            }
            "LogicalNot" => Expr::Not(Box::new(self.expr(e.node("operand").expect("operand"))?)),
            "LogicalAnd" | "LogicalOr" => {
                let left = Box::new(self.expr(e.node("leftOperand").expect("left"))?);
                let right = Box::new(self.expr(e.node("rightOperand").expect("right"))?);
                if e.kind == "LogicalAnd" {
                    Expr::And(left, right)
                } else {
                    Expr::Or(left, right)
                }
            }
            "ConditionalExpression" => Expr::Cond(
                Box::new(self.expr(e.node("condition2").expect("condition"))?),
                Box::new(self.expr(e.node("thenExpression2").expect("then"))?),
                Box::new(self.expr(e.node("elseExpression2").expect("else"))?),
            ),
            "IfNull" => {
                let left = self.expr(e.node("leftOperand").expect("left"))?;
                let right = self.expr(e.node("rightOperand").expect("right"))?;
                let t = self.slot();
                Expr::Let(
                    t,
                    Box::new(left),
                    Box::new(Expr::Cond(
                        Box::new(Expr::Binary(
                            "==".into(),
                            Box::new(Expr::Local(t)),
                            Box::new(Expr::Null),
                        )),
                        Box::new(right),
                        Box::new(Expr::Local(t)),
                    )),
                )
            }
            "IsExpression" => {
                let value = self.expr(e.node("expression2").expect("operand"))?;
                let test = self.type_test(e.node("type").expect("type"), true)?;
                Expr::Is(Box::new(value), test, e.token("notOperator").is_some())
            }
            "AsExpression" => {
                let value = self.expr(e.node("expression2").expect("operand"))?;
                let test = self.type_test(e.node("type").expect("type"), false)?;
                Expr::As(Box::new(value), test)
            }
            "ListLiteral" => {
                if e.token("constKeyword").is_some() {
                    return self.fail(e, "unsupported: const collections");
                }
                let mut items = vec![];
                for item in e.list("elements2") {
                    if !is_expression(item) {
                        return self.fail(
                            item,
                            format!("unsupported collection element: {}", item.kind),
                        );
                    }
                    items.push(self.expr(item)?);
                }
                Expr::List(items)
            }
            "SetOrMapLiteral" => {
                if e.token("constKeyword").is_some() {
                    return self.fail(e, "unsupported: const collections");
                }
                let type_args = e
                    .node("typeArguments")
                    .map(|t| t.list("arguments").len())
                    .unwrap_or(2);
                let elements = e.list("elements2");
                if type_args == 1 || elements.iter().any(|x| x.kind != "MapLiteralEntry") {
                    return self.fail(e, "unsupported: set literals and collection if/for/spread");
                }
                let mut entries = vec![];
                for entry in elements {
                    let key = self.expr(entry.node("key2").expect("key"))?;
                    let value = self.expr(entry.node("value2").expect("value"))?;
                    entries.push((key, value));
                }
                Expr::Map(entries)
            }
            "DirectAssignment" | "CompoundAssignment" => self.assignment(e)?,
            "IncrementOrDecrementExpression" => {
                let target = e.node("target").expect("target");
                let delta = if e.token("operator") == Some("++") {
                    "+"
                } else {
                    "-"
                };
                let prefix = e.children.iter().position(|(n, _)| *n == "operator")
                    < e.children.iter().position(|(n, _)| *n == "target");
                let place = self.place(target)?;
                if prefix {
                    let value =
                        Expr::Binary(delta.into(), Box::new(place.read()), Box::new(Expr::Int(1)));
                    place.wrap(self.write(&place, value))
                } else {
                    let old = self.slot();
                    let value = Expr::Binary(
                        delta.into(),
                        Box::new(Expr::Local(old)),
                        Box::new(Expr::Int(1)),
                    );
                    let write = self.write(&place, value);
                    place.wrap(Expr::Let(
                        old,
                        Box::new(place.read()),
                        Box::new(Expr::Seq(vec![write, Expr::Local(old)])),
                    ))
                }
            }
            other => return self.fail(e, format!("unsupported expression: {other}")),
        })
    }

    fn assignment(&mut self, e: &'a Node) -> R<Expr> {
        let op = e.token("operator").unwrap_or("=").to_string();
        let place = self.place(e.node("target").expect("target"))?;
        let value = self.expr(e.node("value").expect("value"))?;
        let result = if op == "=" {
            self.write(&place, value)
        } else if op == "??=" {
            let current = self.slot();
            let write = self.write(&place, value);
            Expr::Let(
                current,
                Box::new(place.read()),
                Box::new(Expr::Cond(
                    Box::new(Expr::Binary(
                        "==".into(),
                        Box::new(Expr::Local(current)),
                        Box::new(Expr::Null),
                    )),
                    Box::new(write),
                    Box::new(Expr::Local(current)),
                )),
            )
        } else {
            let binary = op.trim_end_matches('=').to_string();
            const OPS: [&str; 11] = ["+", "-", "*", "~/", "%", "&", "|", "^", "<<", ">>", ">>>"];
            if !OPS.contains(&binary.as_str()) {
                return self.fail(e, format!("unsupported operator `{op}`"));
            }
            let combined = Expr::Binary(binary, Box::new(place.read()), Box::new(value));
            self.write(&place, combined)
        };
        Ok(place.wrap(result))
    }

    fn place(&mut self, target: &'a Node) -> R<Place> {
        Ok(match target.kind.as_str() {
            "UnqualifiedNameAssignmentTarget" => {
                let name = target.token("name").unwrap_or("");
                if let Some(slot) = self.local(name) {
                    Place::Local(slot)
                } else if self.member(&format!("s:{name}")) {
                    Place::Member(None, name.to_string())
                } else {
                    match self.lowering.lookup(self.lib, name) {
                        Some(Decl::Global(g)) => Place::Global(g),
                        _ => return self.fail(target, format!("`{name}` cannot be assigned")),
                    }
                }
            }
            "ParsedNameAccessAssignmentTarget" => {
                if target.token("operator") != Some(".") {
                    return self.fail(target, "unsupported: `?.` and cascades");
                }
                let receiver = self.expr(target.node("operand").expect("receiver"))?;
                let slot = self.slot();
                Place::Member(
                    Some((slot, receiver)),
                    target.token("name").unwrap_or("").to_string(),
                )
            }
            "ReceiverIndexAssignmentTarget" => {
                let receiver = self.expr(target.node("receiver").expect("receiver"))?;
                let index = self.expr(target.node("index").expect("index"))?;
                let (r, i) = (self.slot(), self.slot());
                Place::Index(r, receiver, i, index)
            }
            other => return self.fail(target, format!("unsupported assignment target: {other}")),
        })
    }

    /// Writes [value] to [place]; the expression's value is [value].
    fn write(&mut self, place: &Place, value: Expr) -> Expr {
        match place {
            Place::Local(slot) => Expr::SetLocal(*slot, Box::new(value)),
            Place::Global(g) => Expr::SetGlobal(*g, Box::new(value)),
            Place::Member(receiver, name) => {
                let r = match receiver {
                    Some((slot, _)) => Expr::Local(*slot),
                    None => Expr::This,
                };
                let t = self.slot();
                Expr::Let(
                    t,
                    Box::new(value),
                    Box::new(Expr::Seq(vec![
                        Expr::Invoke(Box::new(r), format!("s:{name}"), vec![Expr::Local(t)]),
                        Expr::Local(t),
                    ])),
                )
            }
            Place::Index(r, _, i, _) => {
                let t = self.slot();
                Expr::Let(
                    t,
                    Box::new(value),
                    Box::new(Expr::Seq(vec![
                        Expr::Invoke(
                            Box::new(Expr::Local(*r)),
                            "op:[]=".into(),
                            vec![Expr::Local(*i), Expr::Local(t)],
                        ),
                        Expr::Local(t),
                    ])),
                )
            }
        }
    }

    fn interpolation(&mut self, e: &'a Node) -> R<Expr> {
        let elements = e.list("elements");
        let first = elements
            .first()
            .and_then(|x| x.token("contents"))
            .unwrap_or("");
        let quote = string_opening(first);
        let mut parts = vec![];
        let count = elements.len();
        for (index, element) in elements.iter().enumerate() {
            match element.kind.as_str() {
                "InterpolationString" => {
                    let mut text = element.token("contents").unwrap_or("");
                    if index == 0 {
                        text = &text[quote.len()..];
                    }
                    if index == count - 1 {
                        let closing = quote.trim_start_matches(['r', 'R']);
                        text = &text[..text.len() - closing.len()];
                    }
                    let raw = quote.starts_with(['r', 'R']);
                    let value = self.unescape(element, text, raw)?;
                    if !value.is_empty() {
                        parts.push(Expr::Str(value));
                    }
                }
                "InterpolationExpression" => {
                    parts.push(self.expr(element.node("expression2").expect("expression"))?)
                }
                other => {
                    return self.fail(
                        element,
                        format!("unsupported interpolation element: {other}"),
                    );
                }
            }
        }
        Ok(Expr::Interp(parts))
    }

    fn string_literal(&self, at: &Node, lexeme: &str) -> R<String> {
        let quote = string_opening(lexeme);
        let closing = quote.trim_start_matches(['r', 'R']);
        let inner = &lexeme[quote.len()..lexeme.len() - closing.len()];
        self.unescape(at, inner, quote.starts_with(['r', 'R']))
    }

    fn unescape(&self, at: &Node, text: &str, raw: bool) -> R<String> {
        let mut out = String::new();
        let mut chars = text.chars().peekable();
        while let Some(c) = chars.next() {
            if c != '\\' || raw {
                out.push(c);
                continue;
            }
            let Some(e) = chars.next() else { break };
            match e {
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                'b' => out.push('\u{8}'),
                'f' => out.push('\u{c}'),
                'v' => out.push('\u{b}'),
                'x' => {
                    let hex: String = (0..2).filter_map(|_| chars.next()).collect();
                    out.push(
                        char::from_u32(u32::from_str_radix(&hex, 16).unwrap_or(0)).unwrap_or('\0'),
                    );
                }
                'u' => {
                    let hex: String = if chars.peek() == Some(&'{') {
                        chars.next();
                        chars.by_ref().take_while(|&c| c != '}').collect()
                    } else {
                        (0..4).filter_map(|_| chars.next()).collect()
                    };
                    out.push(
                        char::from_u32(u32::from_str_radix(&hex, 16).unwrap_or(0)).unwrap_or('\0'),
                    );
                }
                '\n' => {}
                other => out.push(other),
            }
        }
        if !out.is_ascii() {
            return self.fail(at, "unsupported: non-ASCII strings (not in this increment)");
        }
        Ok(out)
    }
}

/// `r'''`, `"""`, `'`, `r"`...: how a string literal opens.
fn string_opening(lexeme: &str) -> String {
    let raw = lexeme.starts_with(['r', 'R']);
    let rest = if raw { &lexeme[1..] } else { lexeme };
    let quote = if rest.starts_with("'''") || rest.starts_with("\"\"\"") {
        &rest[..3]
    } else {
        &rest[..1.min(rest.len())]
    };
    format!("{}{quote}", if raw { &lexeme[..1] } else { "" })
}

fn first_node(node: &Node) -> Option<&Node> {
    node.children.iter().find_map(|(_, c)| match c {
        Child::Node(n) => Some(n),
        _ => None,
    })
}

fn is_expression(node: &Node) -> bool {
    !matches!(
        node.kind.as_str(),
        "SpreadElement" | "IfElement" | "ForElement" | "NullAwareElement" | "MapLiteralEntry"
    )
}

/// An assignable place, with its receiver and index evaluated once.
enum Place {
    Local(Slot),
    Global(GlobalId),
    /// A setter on a receiver (kept in the slot) or on `this`.
    Member(Option<(Slot, Expr)>, String),
    Index(Slot, Expr, Slot, Expr),
}

impl Place {
    fn read(&self) -> Expr {
        match self {
            Place::Local(s) => Expr::Local(*s),
            Place::Global(g) => Expr::Global(*g),
            Place::Member(Some((slot, _)), name) => {
                Expr::Invoke(Box::new(Expr::Local(*slot)), format!("g:{name}"), vec![])
            }
            Place::Member(None, name) => {
                Expr::Invoke(Box::new(Expr::This), format!("g:{name}"), vec![])
            }
            Place::Index(r, _, i, _) => Expr::Invoke(
                Box::new(Expr::Local(*r)),
                "op:[]".into(),
                vec![Expr::Local(*i)],
            ),
        }
    }

    /// Evaluates the receiver and index before [inner].
    fn wrap(&self, inner: Expr) -> Expr {
        match self {
            Place::Member(Some((slot, receiver)), _) => {
                Expr::Let(*slot, Box::new(receiver.clone()), Box::new(inner))
            }
            Place::Index(r, receiver, i, index) => Expr::Let(
                *r,
                Box::new(receiver.clone()),
                Box::new(Expr::Let(*i, Box::new(index.clone()), Box::new(inner))),
            ),
            _ => inner,
        }
    }
}
