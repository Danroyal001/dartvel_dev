// The arena the nodes of lib/src/dart/ast/ast.dart live in (not a mirrored
// file), and the parts of ast.dart that every node uses: `NodeListImpl`,
// `ChildEntities` and `ChildEntity`, and the generic members of
// `AstNodeImpl` (`offset`, `length`, `end`).
//
// Upstream's nodes are objects that point at each other; here a node is an
// `AstNodeImpl` in an `AstStore`, addressed by a 32-bit `NodeId`, as a token
// is a `TokenData` in a `TokenStore`. The parent pointers upstream keeps are
// not kept: nothing that builds the tree reads them.

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

use crate::src::dart::ast::ast::AstNodeImpl;

pub type NodeId = u32;

/// `null` where a node is expected.
pub const NO_NODE: NodeId = u32::MAX;

/// `NodeListImpl<E>`: the elements, in order.
pub type NodeListImpl = Vec<NodeId>;

/// `ChildEntity.value`.
#[derive(Clone, Copy, Debug)]
pub enum ChildValue<'a> {
    Token(TokenId),
    Node(NodeId),
    NodeList(&'a [NodeId]),
    TokenList(&'a [TokenId]),
}

/// `class ChildEntity`: a named child of a node.
#[derive(Clone, Copy, Debug)]
pub struct ChildEntity<'a> {
    pub name: &'static str,
    pub value: ChildValue<'a>,
}

/// `class ChildEntities`.
#[derive(Default, Debug)]
pub struct ChildEntities<'a> {
    pub entities: Vec<ChildEntity<'a>>,
}

impl<'a> ChildEntities<'a> {
    pub fn add_node(&mut self, name: &'static str, value: NodeId) {
        if value != NO_NODE {
            self.entities.push(ChildEntity {
                name,
                value: ChildValue::Node(value),
            });
        }
    }

    pub fn add_node_list(&mut self, name: &'static str, value: &'a [NodeId]) {
        self.entities.push(ChildEntity {
            name,
            value: ChildValue::NodeList(value),
        });
    }

    pub fn add_token(&mut self, name: &'static str, value: TokenId) {
        if value != NO_TOKEN {
            self.entities.push(ChildEntity {
                name,
                value: ChildValue::Token(value),
            });
        }
    }

    pub fn add_token_list(&mut self, name: &'static str, value: &'a [TokenId]) {
        self.entities.push(ChildEntity {
            name,
            value: ChildValue::TokenList(value),
        });
    }
}

/// Every node of one parse.
#[derive(Default, Debug)]
pub struct AstStore {
    pub nodes: Vec<AstNodeImpl>,
}

impl AstStore {
    pub fn new() -> AstStore {
        AstStore { nodes: Vec::new() }
    }

    /// Allocates [node]: upstream's constructor call.
    #[inline]
    pub fn add(&mut self, node: impl Into<AstNodeImpl>) -> NodeId {
        let id = self.nodes.len() as NodeId;
        self.nodes.push(node.into());
        id
    }

    #[inline(always)]
    pub fn node(&self, id: NodeId) -> &AstNodeImpl {
        &self.nodes[id as usize]
    }

    #[inline(always)]
    pub fn node_mut(&mut self, id: NodeId) -> &mut AstNodeImpl {
        &mut self.nodes[id as usize]
    }

    /// `node.beginToken`.
    pub fn begin_token(&self, id: NodeId, tokens: &TokenStore) -> TokenId {
        self.node(id).begin_token(self, tokens)
    }

    /// `node.endToken`.
    pub fn end_token(&self, id: NodeId, tokens: &TokenStore) -> TokenId {
        self.node(id).end_token(self, tokens)
    }

    /// `NodeListImpl.beginToken`: the first element's, or null.
    pub fn node_list_begin_token(&self, list: &[NodeId], tokens: &TokenStore) -> TokenId {
        match list.first() {
            Some(&first) => self.begin_token(first, tokens),
            None => NO_TOKEN,
        }
    }

    /// `NodeListImpl.endToken`: the last element's, or null.
    pub fn node_list_end_token(&self, list: &[NodeId], tokens: &TokenStore) -> TokenId {
        match list.last() {
            Some(&last) => self.end_token(last, tokens),
            None => NO_TOKEN,
        }
    }

    /// `node.offset`: `beginToken.offset`, and 0 for a compilation unit.
    pub fn offset(&self, id: NodeId, tokens: &TokenStore) -> i32 {
        if let AstNodeImpl::CompilationUnitImpl(_) = self.node(id) {
            return 0;
        }
        tokens.offset(self.begin_token(id, tokens))
    }

    /// `node.end`: `endToken.end`.
    pub fn end(&self, id: NodeId, tokens: &TokenStore) -> i32 {
        tokens.end(self.end_token(id, tokens))
    }

    /// `node.length`: `end - offset`, and the end of the last token for a
    /// compilation unit.
    pub fn length(&self, id: NodeId, tokens: &TokenStore) -> i32 {
        if let AstNodeImpl::CompilationUnitImpl(unit) = self.node(id) {
            let end_token = unit.end_token;
            return tokens.offset(end_token) + tokens.length(end_token);
        }
        self.end(id, tokens) - self.offset(id, tokens)
    }

    /// `node._childEntities2.entities`, which `namedChildEntities2` returns.
    pub fn named_child_entities2<'a>(
        &'a self,
        id: NodeId,
        tokens: &TokenStore,
    ) -> Vec<ChildEntity<'a>> {
        let mut entities = ChildEntities::default();
        self.node(id).child_entities2(self, tokens, &mut entities);
        entities.entities
    }
}
