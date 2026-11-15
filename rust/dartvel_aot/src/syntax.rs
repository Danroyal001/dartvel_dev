// Ours (not a ported file): the tree the Rust port of `parseString` builds,
// copied into a plain owned tree so the compiler can read it by node kind
// and child name without knowing the store's layout.

use std::rc::Rc;

use analyzer::dart::analysis::utilities::parse_string;
use analyzer::src::dart::ast::ast_store::{Ast, ChildValue, NodeId};

/// One node: its kind (the analyzer's runtime type, without `Impl`), its
/// offset, and its named children in source order.
#[derive(Debug, Clone)]
pub struct Node {
    pub kind: String,
    pub offset: i32,
    pub children: Vec<(&'static str, Child)>,
}

#[derive(Debug, Clone)]
pub enum Child {
    Node(Node),
    Token(String),
    List(Vec<Node>),
    Tokens(Vec<String>),
}

impl Node {
    pub fn child(&self, name: &str) -> Option<&Child> {
        self.children.iter().find(|(n, _)| *n == name).map(|(_, c)| c)
    }
    pub fn node(&self, name: &str) -> Option<&Node> {
        match self.child(name) {
            Some(Child::Node(n)) => Some(n),
            _ => None,
        }
    }
    pub fn token(&self, name: &str) -> Option<&str> {
        match self.child(name) {
            Some(Child::Token(t)) => Some(t),
            _ => None,
        }
    }
    pub fn list(&self, name: &str) -> &[Node] {
        match self.child(name) {
            Some(Child::List(l)) => l,
            _ => &[],
        }
    }
    pub fn tokens(&self, name: &str) -> Vec<&str> {
        match self.child(name) {
            Some(Child::Tokens(l)) => l.iter().map(|s| s.as_str()).collect(),
            _ => vec![],
        }
    }
    /// Pretty-prints the tree, for `dartvel_aot dump`.
    pub fn dump(&self, depth: usize, out: &mut String) {
        out.push_str(&format!("{}{} @{}\n", "  ".repeat(depth), self.kind, self.offset));
        for (name, child) in &self.children {
            let pad = "  ".repeat(depth + 1);
            match child {
                Child::Node(n) => {
                    out.push_str(&format!("{pad}.{name}:\n"));
                    n.dump(depth + 2, out);
                }
                Child::Token(t) => out.push_str(&format!("{pad}.{name} = {t:?}\n")),
                Child::List(l) => {
                    out.push_str(&format!("{pad}.{name}: [{}]\n", l.len()));
                    for n in l {
                        n.dump(depth + 2, out);
                    }
                }
                Child::Tokens(l) => out.push_str(&format!("{pad}.{name} = {l:?}\n")),
            }
        }
    }
}

/// A syntax error the parser reported.
#[derive(Debug, Clone)]
pub struct SyntaxError {
    pub offset: i32,
    pub message: String,
}

/// Parses [source] with the ported `parseString` and copies the unit.
pub fn parse(source: &str, path: &str) -> Result<Node, Vec<SyntaxError>> {
    let units: Rc<[u16]> = source.encode_utf16().collect::<Vec<u16>>().into();
    let result = parse_string(units, None, Some(path));
    if !result.errors.is_empty() {
        return Err(result
            .errors
            .iter()
            .map(|d| SyntaxError { offset: d.offset as i32, message: d.message.to_string() })
            .collect());
    }
    let ast = Ast::new(&result.ast, &result.tokens);
    Ok(copy(ast, result.unit))
}

fn copy(ast: Ast<'_>, id: NodeId) -> Node {
    let kind = ast.node(id).runtime_type();
    let kind = kind.strip_suffix("Impl").unwrap_or(kind).to_string();
    let mut children = Vec::new();
    for entity in ast.named_child_entities2(id) {
        let child = match entity.value {
            ChildValue::Node(n) => Child::Node(copy(ast, n)),
            ChildValue::Token(t) => Child::Token(ast.tokens.lexeme_string(t)),
            ChildValue::NodeList(l) => Child::List(l.iter().map(|&n| copy(ast, n)).collect()),
            ChildValue::TokenList(l) => {
                Child::Tokens(l.iter().map(|&t| ast.tokens.lexeme_string(t)).collect())
            }
        };
        children.push((entity.name, child));
    }
    Node { kind, offset: ast.offset(id), children }
}
