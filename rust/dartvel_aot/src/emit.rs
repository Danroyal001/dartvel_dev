// Ours (not a ported file): the C back end. It emits only what the
// reachability analysis kept: reachable functions, one dispatcher per
// invoked selector with a case only for instantiated classes that
// implement it, and class names only when something can print one.

use std::collections::BTreeMap;
use std::fmt::Write;

use crate::ir::*;
use crate::lower::CompileError;
use crate::natives;
use crate::shake::Reach;

const RUNTIME: &str = include_str!("runtime.c");

fn mangle(selector: &str) -> String {
    let mut out = String::from("d_");
    for c in selector.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else {
            let _ = write!(out, "_{:02x}", c as u32);
        }
    }
    out
}

fn c_string(text: &str) -> String {
    let mut out = String::from("\"");
    for b in text.bytes() {
        match b {
            b'"' => out.push_str("\\\""),
            b'\\' => out.push_str("\\\\"),
            b'?' => out.push_str("\\?"),
            0x20..=0x7e => out.push(b as char),
            _ => {
                let _ = write!(out, "\\{:03o}", b);
            }
        }
    }
    out.push('"');
    out
}

struct Emitter<'p> {
    prog: &'p Program,
    reach: &'p Reach,
    arity: BTreeMap<String, usize>,
    literals: Vec<String>,
    literal_index: BTreeMap<String, usize>,
    temp: usize,
}

fn program_error(message: String) -> CompileError {
    CompileError {
        file: "<program>".into(),
        offset: 0,
        message,
    }
}

pub fn emit(prog: &Program, reach: &Reach) -> Result<String, CompileError> {
    let mut arity = BTreeMap::new();
    for s in &reach.selectors {
        let mut found: Option<(usize, FuncId)> = None;
        for &c in &reach.classes {
            if let Some(f) = prog.lookup(c, s) {
                let n = prog.funcs[f].params.len();
                if let Some((m, other)) = found
                    && m != n
                {
                    return Err(program_error(format!(
                        "unsupported: `{}` and `{}` implement `{}` with different parameter counts",
                        prog.funcs[other].name,
                        prog.funcs[f].name,
                        &s[s.find(':').unwrap() + 1..]
                    )));
                }
                found = Some((n, f));
            }
        }
        let n = match found {
            Some((n, _)) => n,
            None => reach.call_arity.get(s).copied().unwrap_or(0),
        };
        if let Some(&called) = reach.call_arity.get(s)
            && called > n
        {
            return Err(program_error(format!(
                "too many arguments to `{}`",
                &s[s.find(':').unwrap() + 1..]
            )));
        }
        arity.insert(s.clone(), n);
    }
    let mut e = Emitter {
        prog,
        reach,
        arity,
        literals: vec![],
        literal_index: BTreeMap::new(),
        temp: 0,
    };
    e.program()
}

impl<'p> Emitter<'p> {
    fn t(&mut self) -> String {
        self.temp += 1;
        format!("_t{}", self.temp)
    }

    fn literal(&mut self, text: &str) -> String {
        let index = match self.literal_index.get(text) {
            Some(&i) => i,
            None => {
                let i = self.literals.len();
                self.literals.push(text.to_string());
                self.literal_index.insert(text.to_string(), i);
                i
            }
        };
        format!("mkptr(CID_STRING, &lit{index})")
    }

    fn func_name(&self, f: FuncId) -> String {
        match &self.prog.funcs[f].body {
            Body::Native(name) => format!("n{name}"),
            _ => format!("f{f}"),
        }
    }

    fn func_arity(&self, f: FuncId) -> usize {
        let func = &self.prog.funcs[f];
        func.params.len() + usize::from(func.has_this)
    }

    fn signature(&self, name: &str, count: usize) -> String {
        let params: Vec<String> = (0..count).map(|i| format!("V l{i}")).collect();
        format!(
            "static V {name}({})",
            if params.is_empty() {
                "void".to_string()
            } else {
                params.join(", ")
            }
        )
    }

    /// Calls [callee] with [args] evaluated left to right, as Dart does;
    /// C leaves the order of a call's arguments unspecified.
    fn call(&mut self, callee: &str, args: Vec<(String, bool)>) -> String {
        if args.iter().filter(|(_, pure)| !pure).count() <= 1 {
            let list: Vec<String> = args.into_iter().map(|(a, _)| a).collect();
            return format!("{callee}({})", list.join(", "));
        }
        let mut out = String::from("({ ");
        let mut names = vec![];
        for (a, pure) in args {
            if pure {
                names.push(a);
            } else {
                let t = self.t();
                let _ = write!(out, "V {t} = {a}; ");
                names.push(t);
            }
        }
        let _ = write!(out, "{callee}({}); }})", names.join(", "));
        out
    }

    fn arg(&mut self, e: &Expr) -> (String, bool) {
        let pure = matches!(
            e,
            Expr::Int(_) | Expr::Str(_) | Expr::Bool(_) | Expr::Null | Expr::Local(_) | Expr::This
        );
        (self.expr(e), pure)
    }

    fn padded(
        &mut self,
        prefix: Vec<(String, bool)>,
        args: &[Expr],
        count: usize,
    ) -> Vec<(String, bool)> {
        let mut out = prefix;
        for a in args {
            out.push(self.arg(a));
        }
        while out.len() < count {
            out.push(("ABSENT".into(), true));
        }
        out
    }

    fn type_cond(&self, value: &str, test: &TypeTest) -> String {
        match test {
            TypeTest::Any => "1".into(),
            TypeTest::NonNull => format!("{value}.c != CID_NULL"),
            TypeTest::Null => format!("{value}.c == CID_NULL"),
            TypeTest::Class { class, nullable } => {
                if *class == self.prog.object {
                    return if *nullable {
                        "1".into()
                    } else {
                        format!("{value}.c != CID_NULL")
                    };
                }
                let mut terms: Vec<String> = self
                    .reach
                    .classes
                    .iter()
                    .filter(|&&c| self.prog.is_subclass(c, *class))
                    .map(|c| format!("{value}.c == {c}"))
                    .collect();
                if *nullable {
                    terms.push(format!("{value}.c == CID_NULL"));
                }
                if terms.is_empty() {
                    "0".into()
                } else {
                    terms.join(" || ")
                }
            }
        }
    }

    fn expr(&mut self, e: &Expr) -> String {
        match e {
            Expr::Int(i) if *i == i64::MIN => "mkint(INT64_MIN)".into(),
            Expr::Int(i) => format!("mkint({i}LL)"),
            Expr::Str(s) => self.literal(s),
            Expr::Bool(b) => format!("mkbool({})", u8::from(*b)),
            Expr::Null => "NUL".into(),
            Expr::Local(s) => format!("l{s}"),
            Expr::SetLocal(s, v) => format!("(l{s} = {})", self.expr(v)),
            Expr::This => "l0".into(),
            Expr::Global(g) => format!("g{g}()"),
            Expr::SetGlobal(g, v) => format!("gset{g}({})", self.expr(v)),
            Expr::Call(f, args) => {
                let count = self.func_arity(*f);
                let list = self.padded(vec![], args, count);
                let name = self.func_name(*f);
                self.call(&name, list)
            }
            Expr::New(class, ctor, args) => {
                let fields = self.prog.classes[*class].fields.len();
                let count = self.func_arity(*ctor);
                let list = self.padded(
                    vec![(format!("dv_new({class}, {fields})"), false)],
                    args,
                    count,
                );
                self.call(&format!("f{ctor}"), list)
            }
            Expr::Invoke(receiver, selector, args) => {
                let count = self.arity[selector] + 1;
                let r = self.arg(receiver);
                let list = self.padded(vec![r], args, count);
                self.call(&mangle(selector), list)
            }
            Expr::Native(name, args) => {
                let list = self.padded(vec![], args, 0);
                self.call(&format!("n{name}"), list)
            }
            Expr::Binary(op, a, b) => {
                let a = self.arg(a);
                let b = self.arg(b);
                match op.as_str() {
                    "==" => format!("mkbool({})", self.call("dv_eq", vec![a, b])),
                    "!=" => format!("mkbool(!{})", self.call("dv_eq", vec![a, b])),
                    _ => {
                        let f = match op.as_str() {
                            "+" => "dv_add",
                            "-" => "dv_sub",
                            "*" => "dv_mul",
                            "~/" => "dv_tdiv",
                            "%" => "dv_mod",
                            "<" => "dv_lt",
                            "<=" => "dv_le",
                            ">" => "dv_gt",
                            ">=" => "dv_ge",
                            "&" => "dv_band",
                            "|" => "dv_bor",
                            "^" => "dv_bxor",
                            "<<" => "dv_shl",
                            ">>" => "dv_shr",
                            ">>>" => "dv_ushr",
                            other => unreachable!("operator {other} passed the lowering"),
                        };
                        self.call(f, vec![a, b])
                    }
                }
            }
            Expr::Unary(op, v) => format!(
                "{}({})",
                if op == "-" { "dv_neg" } else { "dv_bnot" },
                self.expr(v)
            ),
            Expr::Not(v) => format!("mkbool(!dv_truth({}))", self.expr(v)),
            Expr::And(a, b) => {
                let (a, b) = (self.expr(a), self.expr(b));
                format!("mkbool(dv_truth({a}) && dv_truth({b}))")
            }
            Expr::Or(a, b) => {
                let (a, b) = (self.expr(a), self.expr(b));
                format!("mkbool(dv_truth({a}) || dv_truth({b}))")
            }
            Expr::Cond(c, a, b) => {
                let (c, a, b) = (self.expr(c), self.expr(a), self.expr(b));
                format!("(dv_truth({c}) ? {a} : {b})")
            }
            Expr::Is(v, test, negate) => {
                let t = self.t();
                let value = self.expr(v);
                let cond = self.type_cond(&t, test);
                format!(
                    "({{ V {t} = {value}; mkbool({}({cond})); }})",
                    if *negate { "!" } else { "" }
                )
            }
            Expr::As(v, test) => {
                let t = self.t();
                let value = self.expr(v);
                let cond = self.type_cond(&t, test);
                format!("({{ V {t} = {value}; if (!({cond})) dv_cast_fail({t}); {t}; }})")
            }
            Expr::List(items) => {
                let t = self.t();
                let mut out = format!("({{ V {t} = dv_list_new({}); ", items.len());
                for item in items {
                    let v = self.expr(item);
                    let _ = write!(out, "dv_list_push({t}, {v}); ");
                }
                let _ = write!(out, "{t}; }})");
                out
            }
            Expr::Map(entries) => {
                let t = self.t();
                let mut out = format!("({{ V {t} = dv_map_new(); ");
                for (k, v) in entries {
                    let key = self.t();
                    let k = self.expr(k);
                    let v = self.expr(v);
                    let _ = write!(out, "V {key} = {k}; dv_map_set({t}, {key}, {v}); ");
                }
                let _ = write!(out, "{t}; }})");
                out
            }
            Expr::Interp(parts) => {
                if parts.is_empty() {
                    return self.literal("");
                }
                let mut out = String::from("({ ");
                let mut names = vec![];
                for p in parts {
                    let t = self.t();
                    let v = match p {
                        Expr::Str(_) => self.expr(p),
                        _ => format!("dv_tostr({})", self.expr(p)),
                    };
                    let _ = write!(out, "V {t} = {v}; ");
                    names.push(t);
                }
                let _ = write!(
                    out,
                    "dv_concatn({}, (V[]){{{}}}); }})",
                    names.len(),
                    names.join(", ")
                );
                out
            }
            Expr::Let(s, v, body) => {
                let (v, body) = (self.expr(v), self.expr(body));
                format!("({{ l{s} = {v}; {body}; }})")
            }
            Expr::Seq(items) => {
                let parts: Vec<String> = items.iter().map(|i| self.expr(i)).collect();
                format!("({})", parts.join(", "))
            }
        }
    }

    fn stmts(&mut self, stmts: &[Stmt], out: &mut String) {
        for s in stmts {
            self.stmt(s, out);
        }
    }

    fn stmt(&mut self, s: &Stmt, out: &mut String) {
        match s {
            Stmt::Expr(e) => {
                let e = self.expr(e);
                let _ = writeln!(out, "  {e};");
            }
            Stmt::If(c, a, b) => {
                let c = self.expr(c);
                let _ = writeln!(out, "  if (dv_truth({c})) {{");
                self.stmts(a, out);
                out.push_str("  } else {\n");
                self.stmts(b, out);
                out.push_str("  }\n");
            }
            Stmt::While(c, body) => {
                let c = self.expr(c);
                let _ = writeln!(out, "  while (dv_truth({c})) {{");
                self.stmts(body, out);
                out.push_str("  }\n");
            }
            Stmt::For(init, c, updates, body) => {
                out.push_str("  {\n");
                self.stmts(init, out);
                let c = match c {
                    Some(c) => format!("dv_truth({})", self.expr(c)),
                    None => String::new(),
                };
                let u: Vec<String> = updates
                    .iter()
                    .map(|u| format!("(void){}", self.expr(u)))
                    .collect();
                let _ = writeln!(out, "  for (; {c}; {}) {{", u.join(", "));
                self.stmts(body, out);
                out.push_str("  }\n  }\n");
            }
            Stmt::Return(Some(e)) => {
                let e = self.expr(e);
                let _ = writeln!(out, "  return {e};");
            }
            Stmt::Return(None) => out.push_str("  return NUL;\n"),
            Stmt::Break => out.push_str("  break;\n"),
            Stmt::Continue => out.push_str("  continue;\n"),
            Stmt::Block(b) => {
                out.push_str("  {\n");
                self.stmts(b, out);
                out.push_str("  }\n");
            }
        }
    }

    fn function(&mut self, id: FuncId, out: &mut String) {
        let func = &self.prog.funcs[id];
        let count = self.func_arity(id);
        if let Body::Native(name) = &func.body {
            let native =
                natives::find(name).unwrap_or_else(|| panic!("no C body for native {name}"));
            let params: Vec<String> = (0..count).map(|i| format!("V a{i}")).collect();
            let params = if params.is_empty() {
                "void".to_string()
            } else {
                params.join(", ")
            };
            let _ = writeln!(out, "static V n{name}({params}) {{\n  {}\n}}", native.body);
            return;
        }
        let _ = writeln!(
            out,
            "/* {} */\n{} {{",
            func.name,
            self.signature(&format!("f{id}"), count)
        );
        for slot in count..func.locals.max(count) {
            let _ = writeln!(out, "  V l{slot} = NUL;");
        }
        let offset = usize::from(func.has_this);
        for (i, p) in func.params.iter().enumerate() {
            if let Some(d) = &p.default {
                let d = self.expr(d);
                let _ = writeln!(out, "  if (l{0}.c == C_ABSENT) l{0} = {d};", i + offset);
            }
        }
        match &func.body {
            Body::Stmts(stmts) => self.stmts(stmts, out),
            Body::FieldGet(slot) => {
                let _ = writeln!(out, "  return F(l0)[{slot}];");
            }
            Body::FieldSet(slot) => {
                let _ = writeln!(out, "  F(l0)[{slot}] = l1;\n  return l1;");
            }
            Body::Ctor {
                field_inits,
                super_call,
                body,
            } => {
                for (slot, e) in field_inits {
                    let e = self.expr(e);
                    let _ = writeln!(out, "  F(l0)[{slot}] = {e};");
                }
                if let Some((target, args)) = super_call {
                    let count = self.func_arity(*target);
                    let list = self.padded(vec![("l0".into(), true)], args, count);
                    let call = self.call(&format!("f{target}"), list);
                    let _ = writeln!(out, "  {call};");
                }
                self.stmts(body, out);
                out.push_str("  return l0;\n");
            }
            Body::Native(_) | Body::Abstract => unreachable!(),
        }
        out.push_str("  return NUL;\n}\n");
    }

    fn program(&mut self) -> Result<String, CompileError> {
        let prog = self.prog;
        let reach = self.reach;
        let funcs: Vec<FuncId> = reach
            .funcs
            .iter()
            .copied()
            .filter(|&f| !matches!(prog.funcs[f].body, Body::Abstract))
            .collect();

        let mut functions = String::new();
        for &f in &funcs {
            self.function(f, &mut functions);
        }

        let mut dispatchers = String::new();
        for s in &reach.selectors {
            let n = self.arity[s];
            let name = mangle(s);
            let mut targets: BTreeMap<FuncId, Vec<ClassId>> = BTreeMap::new();
            for &c in &reach.classes {
                if let Some(f) = prog.lookup(c, s) {
                    targets.entry(f).or_default().push(c);
                }
            }
            let _ = writeln!(
                dispatchers,
                "{} {{\n  switch (l0.c) {{",
                self.signature(&name, n + 1)
            );
            let args: Vec<String> = (0..=n).map(|i| format!("l{i}")).collect();
            for (f, classes) in targets {
                for c in classes {
                    let _ = write!(dispatchers, "  case {c}:");
                }
                let callee = self.func_name(f);
                let _ = writeln!(dispatchers, " return {callee}({});", args.join(", "));
            }
            let display = &s[s.find(':').unwrap() + 1..];
            let _ = writeln!(
                dispatchers,
                "  default: return dv_nsm({}, l0);\n  }}\n}}",
                c_string(display)
            );
        }

        let mut out = String::new();
        let _ = writeln!(
            out,
            "/* Generated by dartvel_aot. */\n#define CID_NULL {}\n#define CID_BOOL {}\n#define CID_INT {}\n#define CID_STRING {}\n#define CID_LIST {}\n#define CID_MAP {}",
            prog.null, prog.bool_, prog.int, prog.string, prog.list, prog.map
        );
        out.push_str(RUNTIME);
        out.push_str("\n/* Declarations. */\n");
        for &f in &funcs {
            let name = self.func_name(f);
            let _ = writeln!(out, "{};", self.signature(&name, self.func_arity(f)));
        }
        for s in &reach.selectors {
            let _ = writeln!(out, "{};", self.signature(&mangle(s), self.arity[s] + 1));
        }
        for &g in &reach.globals {
            let _ = writeln!(out, "static V g{g}(void);\nstatic V gset{g}(V value);");
        }
        if reach.selectors.contains("m:toString") {
            let _ = writeln!(
                out,
                "static V dv_tostr(V v) {{ return v.c == CID_STRING ? v : {}(v); }}",
                mangle("m:toString")
            );
        }
        if reach.class_names {
            let mut names = String::new();
            for &c in &reach.classes {
                let _ = writeln!(names, "  [{c}] = {},", c_string(&prog.classes[c].name));
            }
            let _ = writeln!(out, "static const char *const dv_names[] = {{\n{names}}};");
        }
        for (i, text) in self.literals.iter().enumerate() {
            let _ = writeln!(
                out,
                "static struct {{ int64_t n; char s[{}]; }} lit{i} = {{{}, {}}};",
                text.len() + 1,
                text.len(),
                c_string(text)
            );
        }
        for &g in &reach.globals {
            let init = prog.globals[g].init;
            let _ = writeln!(
                out,
                "static V gv{g}; static int gi{g};\nstatic V g{g}(void) {{ if (!gi{g}) {{ gi{g} = 1; gv{g} = f{init}(); }} return gv{g}; }}\nstatic V gset{g}(V value) {{ gi{g} = 1; gv{g} = value; return value; }}"
            );
        }
        out.push_str(&dispatchers);
        out.push_str(&functions);
        if reach.keep_all {
            let mut names: Vec<String> = funcs
                .iter()
                .map(|&f| format!("(void *){}", self.func_name(f)))
                .collect();
            names.extend(
                reach
                    .selectors
                    .iter()
                    .map(|s| format!("(void *){}", mangle(s))),
            );
            names.extend(reach.globals.iter().map(|g| format!("(void *)g{g}")));
            let _ = writeln!(
                out,
                "__attribute__((used)) static void *const dv_keep[] = {{\n  {}\n}};",
                names.join(",\n  ")
            );
        }
        let _ = writeln!(
            out,
            "int main(void) {{\n  f{}();\n  fflush(stdout);\n  return 0;\n}}",
            prog.main
        );
        Ok(out)
    }
}
