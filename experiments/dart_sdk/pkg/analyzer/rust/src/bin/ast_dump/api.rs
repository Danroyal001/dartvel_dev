// Port of the API oracle of rust/oracle/ast_dump.dart (`dumpApi` and its
// helpers): what the public AST API returns on the tree (see that file for
// the format).

use std::collections::HashMap;
use std::fmt::Write as _;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::rc::Rc;

use analyzer::dart::analysis::utilities::parse_string;
use analyzer::dart::ast::visitor::DelegatingAstVisitor2;
use analyzer::dart::ast::visitor_g::UnifyingAstVisitor2;
use analyzer::src::dart::ast::ast_g::AstVisitor2;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue, NO_NODE, NodeId};
use analyzer::src::dart::ast::utilities::NodeLocator2;
use analyzer::unifying_ast_visitor2;

use crate::escape;
use crate::recorders::{RecursiveRecorder, SimpleRecorder};

/// `guard(f)`: the value, or `!throw` where upstream throws.
fn guard(f: impl FnOnce() -> String) -> String {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| "!throw".to_string())
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
    let result = catch_unwind(AssertUnwindSafe(|| parse_string(source, None, None)));
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
    sb
}
