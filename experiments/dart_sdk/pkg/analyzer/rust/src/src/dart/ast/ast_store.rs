// The arena the nodes of lib/src/dart/ast/ast.dart live in (not a mirrored
// file), and the parts of ast.dart that every node uses: `NodeListImpl`,
// `ChildEntities` and `ChildEntity`, and the members every `AstNodeImpl`
// has (`offset`, `length`, `end`, `parent2`, `accept2`, `visitChildren2`,
// `toSource`, ...), which `Ast` provides.
//
// Upstream's nodes are objects that point at each other; here a node is an
// `AstNodeImpl` in an `AstStore`, addressed by a 32-bit `NodeId`, as a token
// is a `TokenData` in a `TokenStore`. The store keeps each node's V2 parent
// (`_parent2`), which a node's constructor sets on its children upstream:
// `AstStore::add` sets it on the children the generated
// `for_each_child_node` names. An `Ast` is the two stores together, the
// view through which the public API (`AstNode`) is read.

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

use crate::dart::ast::precedence::Precedence;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_g::AstVisitor2;
use crate::src::dart::ast::to_source_visitor::ToSourceVisitor;

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
    /// `_parent2` of each node, `NO_NODE` when it has none.
    pub parents: Vec<NodeId>,
}

impl AstStore {
    pub fn new() -> AstStore {
        AstStore {
            nodes: Vec::new(),
            parents: Vec::new(),
        }
    }

    /// Allocates [node]: upstream's constructor call.
    #[inline]
    pub fn add(&mut self, node: impl Into<AstNodeImpl>) -> NodeId {
        let id = self.nodes.len() as NodeId;
        let node = node.into();
        // The constructor's `_becomeParentOf2(child)`.
        let parents = &mut self.parents;
        node.for_each_child_node(&mut |child| {
            if child != NO_NODE {
                parents[child as usize] = id;
            }
        });
        self.nodes.push(node);
        self.parents.push(NO_NODE);
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

impl AstStore {
    /// The heap bytes of the nodes' own lists (node and token lists, literal
    /// values), which [nodes] does not hold inline.
    pub fn list_heap_bytes(&self) -> usize {
        let mut bytes = 0;
        for node in &self.nodes {
            let mut entities = ChildEntities::default();
            node.child_entities2(self, &TokenStore::default(), &mut entities);
            for entity in entities.entities {
                match entity.value {
                    ChildValue::NodeList(l) => bytes += l.len() * 4,
                    ChildValue::TokenList(l) => bytes += l.len() * 4,
                    _ => {}
                }
            }
        }
        bytes
    }
}

impl AstStore {
    /// A setter's `_becomeParentOf2(child)`: makes [parent] the parent of
    /// [child].
    pub fn become_parent_of2(&mut self, parent: NodeId, child: NodeId) {
        if child != NO_NODE {
            self.parents[child as usize] = parent;
        }
    }
}

/// The tree of one parse: its nodes and the tokens they hold. The members
/// of `AstNode` that read a node take its id.
#[derive(Clone, Copy)]
pub struct Ast<'a> {
    pub store: &'a AstStore,
    pub tokens: &'a TokenStore,
}

impl<'a> Ast<'a> {
    pub fn new(store: &'a AstStore, tokens: &'a TokenStore) -> Ast<'a> {
        Ast { store, tokens }
    }

    #[inline(always)]
    pub fn node(self, id: NodeId) -> &'a AstNodeImpl {
        self.store.node(id)
    }

    /// `node.beginToken`.
    pub fn begin_token(self, id: NodeId) -> TokenId {
        self.store.begin_token(id, self.tokens)
    }

    /// `node.endToken`.
    pub fn end_token(self, id: NodeId) -> TokenId {
        self.store.end_token(id, self.tokens)
    }

    /// `node.offset`.
    pub fn offset(self, id: NodeId) -> i32 {
        self.store.offset(id, self.tokens)
    }

    /// `node.end`.
    pub fn end(self, id: NodeId) -> i32 {
        self.store.end(id, self.tokens)
    }

    /// `node.length`.
    pub fn length(self, id: NodeId) -> i32 {
        self.store.length(id, self.tokens)
    }

    /// `node.parent2`: `NO_NODE` when there is none.
    pub fn parent2(self, id: NodeId) -> NodeId {
        self.store.parents[id as usize]
    }

    /// `node.root2`.
    pub fn root2(self, id: NodeId) -> NodeId {
        let mut root = id;
        let mut parent = self.parent2(root);
        while parent != NO_NODE {
            root = parent;
            parent = self.parent2(root);
        }
        root
    }

    /// `node.thisOrAncestorMatching2(predicate)`.
    pub fn this_or_ancestor_matching2(
        self,
        id: NodeId,
        mut predicate: impl FnMut(NodeId) -> bool,
    ) -> NodeId {
        let mut node = id;
        while node != NO_NODE && !predicate(node) {
            node = self.parent2(node);
        }
        node
    }

    /// `node.namedChildEntities2`.
    pub fn named_child_entities2(self, id: NodeId) -> Vec<ChildEntity<'a>> {
        self.store.named_child_entities2(id, self.tokens)
    }

    /// `node.accept2(visitor)`.
    #[inline]
    pub fn accept2<V: AstVisitor2 + ?Sized>(self, id: NodeId, visitor: &mut V) -> Option<V::R> {
        self.node(id).accept2(self, id, visitor)
    }

    /// `node.visitChildren2(visitor)`.
    #[inline]
    pub fn visit_children2<V: AstVisitor2 + ?Sized>(self, id: NodeId, visitor: &mut V) {
        self.node(id).visit_children2(self, visitor)
    }

    /// `(node as Expression).precedence`.
    pub fn precedence(self, id: NodeId) -> Precedence {
        self.node(id).precedence(self)
    }

    /// `node.toSource()`, as UTF-16 code units.
    pub fn to_source_units(self, id: NodeId) -> Vec<u16> {
        let mut buffer = Vec::new();
        self.accept2(id, &mut ToSourceVisitor::new(&mut buffer));
        buffer
    }

    /// `node.toSource()` (and `toString()`).
    pub fn to_source(self, id: NodeId) -> String {
        String::from_utf16_lossy(&self.to_source_units(id))
    }

    /// `_visitCommentAndAnnotations2(visitor)` of an annotated node: the
    /// comment and the annotations, in source order.
    pub fn visit_comment_and_annotations2<V: AstVisitor2 + ?Sized>(
        self,
        documentation_comment: NodeId,
        metadata: &[NodeId],
        visitor: &mut V,
    ) {
        // _commentIsBeforeAnnotations()
        if documentation_comment == NO_NODE
            || metadata.is_empty()
            || self.offset(documentation_comment) < self.offset(metadata[0])
        {
            if documentation_comment != NO_NODE {
                self.accept2(documentation_comment, visitor);
            }
            for &annotation in metadata {
                self.accept2(annotation, visitor);
            }
        } else {
            // sortedCommentAndAnnotations
            let comment = [documentation_comment];
            for node in self.sorted_by_offset(&[&comment, metadata]) {
                self.accept2(node, visitor);
            }
        }
    }

    /// The nodes of [lists], concatenated and sorted by
    /// `AstNode.LEXICAL_ORDER`.
    pub fn sorted_by_offset(self, lists: &[&[NodeId]]) -> Vec<NodeId> {
        let mut nodes: Vec<NodeId> = lists.iter().flat_map(|l| l.iter().copied()).collect();
        nodes.sort_by_key(|&n| self.offset(n));
        nodes
    }
}
