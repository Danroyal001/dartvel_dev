// Port of the API oracle of rust/oracle/ast_dump.dart (`dumpApi` and its
// helpers): what the public AST API returns on the tree (see that file for
// the format).

use std::collections::HashMap;
use std::fmt::Write as _;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::rc::Rc;

use analyzer::dart::analysis::utilities::parse_string;
use std::collections::VecDeque;

use analyzer::dart::ast::visitor::{
    BreadthFirstVisitor, DelegatingAstVisitor, DelegatingAstVisitor2, breadth_first_visitor,
};
use analyzer::dart::ast::visitor_g::{
    GeneralizingAstVisitor, TimedAstVisitor, TimedAstVisitor2, UnifyingAstVisitor,
    UnifyingAstVisitor2,
};
use analyzer::src::dart::ast::ast_g::{AstVisitor, AstVisitor2};
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue, ChildValue1, NO_NODE, NodeId};
use analyzer::src::dart::ast::utilities::{NodeLocator, NodeLocator2};
use analyzer::{generalizing_ast_visitor, unifying_ast_visitor, unifying_ast_visitor2};

use crate::escape;
use crate::recorders::{GeneralizingRecorder, RecursiveRecorder, RecursiveRecorder1, SimpleRecorder, SimpleRecorder1};

/// `guard(f)`: the value, or `!throw` where upstream throws.
fn guard(f: impl FnOnce() -> String) -> String {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| "!throw".to_string())
}

/// `guardError(f)`: the value, or the error upstream throws, named. The
/// port panics with `<class>: <message>` (`TypeError` for a failed cast).
fn guard_error(f: impl FnOnce() -> String) -> String {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(value) => value,
        Err(payload) => {
            let message = payload
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_default();
            for class in ["ArgumentError", "UnsupportedError", "StateError"] {
                if let Some(rest) = message.strip_prefix(&format!("{class}: ")) {
                    let units: Vec<u16> = rest.encode_utf16().collect();
                    return format!("!{class}:{}", escape(&units));
                }
            }
            if message.starts_with("TypeError") {
                return "!TypeError".to_string();
            }
            "!throw".to_string()
        }
    }
}

fn fnv(units: &[u16]) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for &c in units {
        h ^= c as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{h:016x}")
}

fn summary(units: &[u16]) -> String {
    if units.len() <= 60 {
        format!("\"{}\"", escape(units))
    } else {
        format!("#{}:{}", units.len(), fnv(units))
    }
}

struct UnifyingRecorder<'l> {
    log: &'l mut dyn FnMut(&'static str, NodeId),
}

impl UnifyingAstVisitor2 for UnifyingRecorder<'_> {
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        (self.log)("visitNode", node);
        analyzer::dart::ast::visitor_g::unifying_ast_visitor2::visit_node(self, ast, node)
    }
}

unifying_ast_visitor2!(UnifyingRecorder<'_>, ());

struct UnifyingRecorder1<'l> {
    log: &'l mut dyn FnMut(&'static str, NodeId),
}

impl UnifyingAstVisitor for UnifyingRecorder1<'_> {
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        (self.log)("visitNode", node);
        analyzer::dart::ast::visitor_g::unifying_ast_visitor::visit_node(self, ast, node)
    }
}

unifying_ast_visitor!(UnifyingRecorder1<'_>, ());

struct BreadthFirstRecorder<'l> {
    log: &'l mut dyn FnMut(&'static str, NodeId),
    queue: VecDeque<NodeId>,
}

impl BreadthFirstVisitor for BreadthFirstRecorder<'_> {
    fn breadth_first_queue(&mut self) -> &mut VecDeque<NodeId> {
        &mut self.queue
    }
}

impl GeneralizingAstVisitor for BreadthFirstRecorder<'_> {
    fn visit_node(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        (self.log)("visitNode", node);
        breadth_first_visitor::visit_node(self, ast, node)
    }
}

generalizing_ast_visitor!(BreadthFirstRecorder<'_>, ());

/// The pre-order of the V1 named child entities.
fn number_nodes1(ast: Ast<'_>, unit: NodeId) -> Vec<NodeId> {
    fn visit(ast: Ast<'_>, node: NodeId, nodes: &mut Vec<NodeId>) {
        nodes.push(node);
        for child in ast.named_child_entities(node) {
            match child.value {
                ChildValue1::Node(n) => visit(ast, n, nodes),
                ChildValue1::NodeList(list) => {
                    for n in list {
                        visit(ast, n, nodes);
                    }
                }
                _ => {}
            }
        }
    }
    let mut nodes = Vec::new();
    visit(ast, unit, &mut nodes);
    nodes
}

/// `refIn(nodes, node)`.
fn ref_in(ast: Ast<'_>, nodes: &[NodeId], node: NodeId) -> String {
    if node == NO_NODE {
        return "-".to_string();
    }
    match nodes.iter().position(|&n| n == node) {
        Some(i) => i.to_string(),
        None => format!("?{}", ast.node(node).runtime_type()),
    }
}

/// `replacementFor(nodes, i, parent, parentOf)`.
fn replacement_for(
    ast: Ast<'_>,
    nodes: &[NodeId],
    i: usize,
    parent: NodeId,
    parent_of: &dyn Fn(NodeId) -> NodeId,
) -> Option<usize> {
    let mut ancestors = Vec::new();
    let mut p = parent;
    while p != NO_NODE {
        ancestors.push(p);
        p = parent_of(p);
    }
    let in_parent = |node: NodeId| {
        let mut p = node;
        while p != NO_NODE {
            if p == parent {
                return true;
            }
            p = parent_of(p);
        }
        false
    };
    let type_ = ast.node(nodes[i]).runtime_type();
    for k in 1..nodes.len() {
        let j = (i + k) % nodes.len();
        if ast.node(nodes[j]).runtime_type() == type_
            && !ancestors.contains(&nodes[j])
            && !in_parent(nodes[j])
        {
            return Some(j);
        }
    }
    None
}

/// The visits of [run], as `visits` writes them.
fn format_visits(
    ast: Ast<'_>,
    index: &HashMap<NodeId, usize>,
    dispatch: &[String],
    run: &mut dyn FnMut(&mut dyn FnMut(&'static str, NodeId)),
) -> String {
    let mut entries: Vec<String> = Vec::new();
    let mut run_range: Option<(usize, usize)> = None;
    fn flush(entries: &mut Vec<String>, run_range: &mut Option<(usize, usize)>) {
        if let Some((start, end)) = run_range.take() {
            entries.push(if start == end {
                format!("{start}")
            } else {
                format!("{start}-{end}")
            });
        }
    }
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        run(&mut |visit, node| {
            let i = index.get(&node).copied();
            if let Some(i) = i {
                if visit == "visitNode" || visit == dispatch[i] {
                    if let Some((_, end)) = run_range.as_mut() {
                        if *end + 1 == i {
                            *end = i;
                            return;
                        }
                    }
                    flush(&mut entries, &mut run_range);
                    run_range = Some((i, i));
                    return;
                }
            }
            flush(&mut entries, &mut run_range);
            let what = match i {
                Some(i) => i.to_string(),
                None => format!("?{}", ast.node(node).runtime_type()),
            };
            entries.push(format!("{what}:{visit}"));
        });
    }));
    if outcome.is_err() {
        flush(&mut entries, &mut run_range);
        entries.push("!throw".to_string());
    }
    flush(&mut entries, &mut run_range);
    entries.join(" ")
}

/// The pre-order of the named child entities.
fn number_nodes(ast: Ast<'_>, unit: NodeId) -> Vec<NodeId> {
    fn visit(ast: Ast<'_>, node: NodeId, nodes: &mut Vec<NodeId>) {
        nodes.push(node);
        for child in ast.named_child_entities2(node) {
            match child.value {
                ChildValue::Node(n) => visit(ast, n, nodes),
                ChildValue::NodeList(list) => {
                    for &n in list {
                        visit(ast, n, nodes);
                    }
                }
                _ => {}
            }
        }
    }
    let mut nodes = Vec::new();
    visit(ast, unit, &mut nodes);
    nodes
}

pub fn dump_api(source: Rc<[u16]>) -> String {
    let length = source.len() as i64;
    let result = catch_unwind(AssertUnwindSafe(|| parse_string(source.clone(), None, None)));
    let Ok(result) = result else {
        return "crash\n".to_string();
    };
    let ast = Ast::new(&result.ast, &result.tokens);
    let unit = result.unit;
    let mut sb = String::new();
    let nodes = number_nodes(ast, unit);
    let index: HashMap<NodeId, usize> = nodes.iter().enumerate().map(|(i, &n)| (n, i)).collect();
    let reference = |node: NodeId| -> String {
        if node == NO_NODE {
            return "-".to_string();
        }
        match index.get(&node) {
            Some(i) => i.to_string(),
            None => format!("?{}", ast.node(node).runtime_type()),
        }
    };

    let source_text = guard(|| format!("\"{}\"", escape(&ast.to_source_units(unit))));
    let _ = writeln!(sb, "toSource {source_text}");
    let mut dispatch: Vec<String> = Vec::new();
    for (i, &node) in nodes.iter().enumerate() {
        let v = guard(|| {
            let mut name = "-";
            ast.accept2(node, &mut SimpleRecorder { log: &mut |visit, _| name = visit });
            name.to_string()
        });
        let p = guard(|| reference(ast.parent2(node)));
        let s = guard(|| summary(&ast.to_source_units(node)));
        let _ = writeln!(
            sb,
            "node {i} {} v={v} p={p} s={s}",
            ast.node(node).runtime_type()
        );
        dispatch.push(v);
    }

    let visits = |run: &mut dyn FnMut(&mut dyn FnMut(&'static str, NodeId))| -> String {
        let mut entries: Vec<String> = Vec::new();
        let mut run_range: Option<(usize, usize)> = None;
        fn flush(entries: &mut Vec<String>, run_range: &mut Option<(usize, usize)>) {
            if let Some((start, end)) = run_range.take() {
                entries.push(if start == end {
                    format!("{start}")
                } else {
                    format!("{start}-{end}")
                });
            }
        }
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            run(&mut |visit, node| {
                let i = index.get(&node).copied();
                if let Some(i) = i {
                    if visit == "visitNode" || visit == dispatch[i] {
                        if let Some((_, end)) = run_range.as_mut() {
                            if *end + 1 == i {
                                *end = i;
                                return;
                            }
                        }
                        flush(&mut entries, &mut run_range);
                        run_range = Some((i, i));
                        return;
                    }
                }
                flush(&mut entries, &mut run_range);
                let what = match i {
                    Some(i) => i.to_string(),
                    None => format!("?{}", ast.node(node).runtime_type()),
                };
                entries.push(format!("{what}:{visit}"));
            });
        }));
        if outcome.is_err() {
            flush(&mut entries, &mut run_range);
            entries.push("!throw".to_string());
        }
        flush(&mut entries, &mut run_range);
        entries.join(" ")
    };

    let recursive = visits(&mut |log| {
        ast.accept2(unit, &mut RecursiveRecorder { log });
    });
    let _ = writeln!(sb, "recursive {recursive}");
    let unifying = visits(&mut |log| {
        ast.accept2(unit, &mut UnifyingRecorder { log });
    });
    let _ = writeln!(sb, "unifying {unifying}");
    let delegating = visits(&mut |log| {
        let mut delegate = SimpleRecorder { log };
        let delegates: Vec<&mut dyn AstVisitor2<R = ()>> = vec![&mut delegate];
        ast.accept2(unit, &mut DelegatingAstVisitor2::new(delegates));
    });
    let _ = writeln!(sb, "delegating {delegating}");

    let mut seed = length;
    let mut next = || {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        seed
    };
    for k in 0..32 {
        let a = next() % (length + 1);
        let b = if k < 16 { a } else { a + next() % 40 };
        let found = guard(|| {
            reference(NodeLocator2::new(a as i32, Some(b as i32)).search_within(ast, unit))
        });
        let _ = writeln!(sb, "locate {a}-{b} {found}");
    }

    for diagnostic in &result.errors {
        let message: Vec<u16> = diagnostic.message.encode_utf16().collect();
        let correction = match &diagnostic.correction_message {
            None => "-".to_string(),
            Some(c) => format!("\"{}\"", escape(&c.encode_utf16().collect::<Vec<u16>>())),
        };
        let _ = writeln!(
            sb,
            "diagnostic {}@{}+{} \"{}\" {correction}",
            diagnostic.diagnostic_code.unique_name,
            diagnostic.offset,
            diagnostic.length,
            escape(&message)
        );
    }

    seed = length;
    let mut next = || {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        seed
    };
    for k in 0..32 {
        let a = next() % (length + 1);
        let b = if k < 16 { a } else { a + next() % 40 };
        let found = guard(|| reference(ast.node_covering2(unit, a as i32, (b - a) as i32)));
        let _ = writeln!(sb, "cover {a}-{b} {found}");
    }
    let timed2 = visits(&mut |log| {
        let mut base = RecursiveRecorder { log };
        ast.accept2(unit, &mut TimedAstVisitor2::new(&mut base, None));
    });
    let _ = writeln!(sb, "timed2 {timed2}");

    // Mutations, each on a fresh parse.
    for _ in 0..4 {
        let mut fresh = parse_string(source.clone(), None, None);
        let fresh_nodes = number_nodes(Ast::new(&fresh.ast, &fresh.tokens), fresh.unit);
        let i = (next() % nodes.len() as i64) as usize;
        let node = fresh_nodes[i];
        let parent = Ast::new(&fresh.ast, &fresh.tokens).parent2(node);
        if parent == NO_NODE {
            let _ = writeln!(sb, "replace {i} -");
            continue;
        }
        let j = {
            let ast = Ast::new(&fresh.ast, &fresh.tokens);
            replacement_for(ast, &fresh_nodes, i, parent, &|n| ast.parent2(n))
        };
        let Some(j) = j else {
            let _ = writeln!(sb, "replace {i} -");
            continue;
        };
        let other = fresh_nodes[j];
        let r = guard_error(|| {
            fresh.ast.replace_child(&fresh.tokens, parent, node, other);
            let ast = Ast::new(&fresh.ast, &fresh.tokens);
            format!(
                "{} {} {}",
                summary(&ast.to_source_units(parent)),
                guard(|| ref_in(ast, &fresh_nodes, ast.parent2(other))),
                guard(|| ref_in(ast, &fresh_nodes, ast.parent2(node)))
            )
        });
        let _ = writeln!(sb, "replace {i} {j} {r}");
    }
    for _ in 0..4 {
        let mut fresh = parse_string(source.clone(), None, None);
        let fresh_nodes = number_nodes(Ast::new(&fresh.ast, &fresh.tokens), fresh.unit);
        let i = (next() % nodes.len() as i64) as usize;
        let node = fresh_nodes[i];
        let parent = Ast::new(&fresh.ast, &fresh.tokens).parent2(node);
        if parent == NO_NODE {
            let _ = writeln!(sb, "remove {i} -");
            continue;
        }
        let r = guard_error(|| {
            fresh.ast.remove_child(&fresh.tokens, parent, node);
            summary(&Ast::new(&fresh.ast, &fresh.tokens).to_source_units(parent))
        });
        let _ = writeln!(sb, "remove {i} {r}");
    }

    dump_api1(&mut sb, &source, ast, unit, &index);
    sb
}

/// The V1 view of [unit] (see `dumpApi1` in ast_dump.dart).
fn dump_api1(sb: &mut String, source: &Rc<[u16]>, ast: Ast<'_>, unit: NodeId, index2: &HashMap<NodeId, usize>) {
    let Ok(nodes) = catch_unwind(AssertUnwindSafe(|| number_nodes1(ast, unit))) else {
        let _ = writeln!(sb, "v1 !throw");
        return;
    };
    let index: HashMap<NodeId, usize> = nodes.iter().enumerate().map(|(i, &n)| (n, i)).collect();
    let reference = |node: NodeId| -> String {
        if node == NO_NODE {
            return "-".to_string();
        }
        match index.get(&node) {
            Some(i) => i.to_string(),
            None => format!("?{}", ast.node(node).runtime_type()),
        }
    };
    let mut dispatch: Vec<String> = Vec::new();
    for (i, &node) in nodes.iter().enumerate() {
        let v = guard(|| {
            let mut name = "-";
            ast.accept(node, &mut SimpleRecorder1 { log: &mut |visit, _| name = visit });
            name.to_string()
        });
        dispatch.push(v.clone());
        let p = guard(|| reference(ast.parent(node)));
        let r = guard(|| reference(ast.root(node)));
        let w = match index2.get(&node) {
            Some(i) => i.to_string(),
            None => "-".to_string(),
        };
        let s = guard(|| summary(&ast.to_source_units(node)));
        let c = guard(|| {
            let mut entities: Vec<String> = Vec::new();
            for child in ast.named_child_entities(node) {
                match child.value {
                    ChildValue1::Token(t) => entities.push(format!("{}@{}", child.name, ast.tokens.offset(t))),
                    ChildValue1::Node(n) => entities.push(format!("{}#{}", child.name, reference(n))),
                    ChildValue1::NodeList(list) => {
                        entities.push(format!("{}[{}]", child.name, list.len()));
                        for n in list {
                            entities.push(format!("#{}", reference(n)));
                        }
                    }
                    ChildValue1::TokenList(list) => {
                        entities.push(format!("{}[{}]", child.name, list.len()));
                        for t in list {
                            entities.push(format!("@{}", ast.tokens.offset(t)));
                        }
                    }
                }
            }
            entities.join(",")
        });
        let range = guard(|| format!("{}+{}", ast.offset(node), ast.length(node)));
        let _ = writeln!(
            sb,
            "v1node {i} {} {range} v={v} p={p} r={r} w={w} s={s} c={c}",
            ast.node(node).runtime_type()
        );
    }

    let visits = |run: &mut dyn FnMut(&mut dyn FnMut(&'static str, NodeId))| -> String {
        format_visits(ast, &index, &dispatch, run)
    };
    let recursive = visits(&mut |log| {
        ast.accept(unit, &mut RecursiveRecorder1 { log });
    });
    let _ = writeln!(sb, "v1recursive {recursive}");
    let generalizing = visits(&mut |log| {
        ast.accept(unit, &mut GeneralizingRecorder { log });
    });
    let _ = writeln!(sb, "v1generalizing {generalizing}");
    let unifying = visits(&mut |log| {
        ast.accept(unit, &mut UnifyingRecorder1 { log });
    });
    let _ = writeln!(sb, "v1unifying {unifying}");
    let delegating = visits(&mut |log| {
        let mut delegate = SimpleRecorder1 { log };
        let delegates: Vec<&mut dyn AstVisitor<R = ()>> = vec![&mut delegate];
        ast.accept(unit, &mut DelegatingAstVisitor::new(delegates));
    });
    let _ = writeln!(sb, "v1delegating {delegating}");
    let breadth = visits(&mut |log| {
        let mut visitor = BreadthFirstRecorder {
            log,
            queue: VecDeque::new(),
        };
        breadth_first_visitor::visit_all_nodes(&mut visitor, ast, unit);
    });
    let _ = writeln!(sb, "v1breadth {breadth}");
    let timed = visits(&mut |log| {
        let mut base = RecursiveRecorder1 { log };
        ast.accept(unit, &mut TimedAstVisitor::new(&mut base, None));
    });
    let _ = writeln!(sb, "v1timed {timed}");

    let length = source.len() as i64;
    let mut seed = length;
    let mut next = || {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        seed
    };
    for k in 0..32 {
        let a = next() % (length + 1);
        let b = if k < 16 { a } else { a + next() % 40 };
        let found = guard(|| reference(NodeLocator::new(a as i32, Some(b as i32)).search_within(ast, unit)));
        let covering = guard(|| reference(ast.node_covering(unit, a as i32, (b - a) as i32)));
        let _ = writeln!(sb, "v1locate {a}-{b} {found}");
        let _ = writeln!(sb, "v1cover {a}-{b} {covering}");
    }

    for _ in 0..4 {
        let mut fresh = parse_string(source.clone(), None, None);
        let fresh_nodes = number_nodes1(Ast::new(&fresh.ast, &fresh.tokens), fresh.unit);
        let i = (next() % nodes.len() as i64) as usize;
        let node = fresh_nodes[i];
        let parent = guard_node(|| Ast::new(&fresh.ast, &fresh.tokens).parent(node));
        if parent == NO_NODE {
            let _ = writeln!(sb, "v1replace {i} -");
            continue;
        }
        let j = {
            let ast = Ast::new(&fresh.ast, &fresh.tokens);
            replacement_for(ast, &fresh_nodes, i, parent, &|n| ast.parent(n))
        };
        let Some(j) = j else {
            let _ = writeln!(sb, "v1replace {i} -");
            continue;
        };
        let other = fresh_nodes[j];
        let r = guard_error(|| {
            fresh.ast.replace_child(&fresh.tokens, parent, node, other);
            let ast = Ast::new(&fresh.ast, &fresh.tokens);
            format!(
                "{} {} {}",
                summary(&ast.to_source_units(parent)),
                guard(|| ref_in(ast, &fresh_nodes, ast.parent(other))),
                guard(|| ref_in(ast, &fresh_nodes, ast.parent(node)))
            )
        });
        let _ = writeln!(sb, "v1replace {i} {j} {r}");
    }
}

/// [f]'s node, or `NO_NODE` where it panics.
fn guard_node(f: impl FnOnce() -> NodeId) -> NodeId {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(NO_NODE)
}
