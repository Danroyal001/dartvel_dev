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
//
// The V1 view of the tree is made of the parsed nodes and of the V1
// projection objects upstream creates when the view is read (V1Projection):
// those live in the store's `V1State`, in an arena whose nodes do not move,
// addressed by `NodeId`s from `V1_BASE` up, so that reading the view through
// a shared `Ast` can create them, as upstream's getters do. The state also
// holds each node's V1 parent (`_parent`), the projections each node caches
// (`_v1Projection`, `_methodInvocation`, ...) and the API overrides
// (`_astNodeApiOverride`).

use std::cell::{Cell, OnceCell, RefCell};
use std::collections::HashMap;

use fe_analyzer_shared::scanner::token::{NO_TOKEN, TokenId, TokenStore};

use crate::dart::ast::precedence::Precedence;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_g::AstVisitor2;
use crate::src::dart::ast::to_source_visitor::ToSourceVisitor;

pub type NodeId = u32;

/// `null` where a node is expected.
pub const NO_NODE: NodeId = u32::MAX;

/// The id of the first V1 projection object: projections are numbered from
/// here, parsed nodes from 0.
pub const V1_BASE: NodeId = 0x8000_0000;

/// A parsed node's V1 parent before anything has assigned it: the one its
/// V2 parent's constructor gave it (see `AstStore::initial_parent1`).
const UNSET: NodeId = u32::MAX - 1;

/// `enum AstNodeApi`: the views a node is in.
#[allow(non_camel_case_types)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AstNodeApi {
    /// The node exists only in the V1 AST view.
    v1,
    /// The node exists only in the V2 AST view.
    v2,
    /// The node is shared between both AST views.
    shared,
}

/// The number of chunks of the V1 arena: chunk `k` holds `2^(k + 6)`
/// nodes, so that the chunks together hold more than `V1_BASE` nodes.
const CHUNKS: usize = 26;

/// What upstream keeps in the nodes for the V1 view (see the file comment).
#[derive(Default)]
pub struct V1State {
    /// The projection objects. Chunk `k` holds the nodes from
    /// `64 * (2^k - 1)` on; a chunk, once made, never moves and a node,
    /// once set, never changes, so that a shared reference to the store can
    /// add nodes while others are borrowed (`OnceCell`).
    arena: [OnceCell<Box<[OnceCell<AstNodeImpl>]>>; CHUNKS],
    /// `_parent` of the parsed nodes (`UNSET` until assigned) and of the
    /// projection objects.
    parents: RefCell<(Vec<NodeId>, Vec<NodeId>)>,
    /// The cached projections and V1 children: `(node, slot)` to node.
    cache: RefCell<HashMap<(NodeId, u8), NodeId>>,
    /// `_astNodeApiOverride` of the nodes that have one.
    api_override: RefCell<HashMap<NodeId, AstNodeApi>>,
    /// `_parent2` of the projection objects that a mutation gave one.
    pub parents2: RefCell<HashMap<NodeId, NodeId>>,
    /// The number of projection objects.
    count: Cell<usize>,
}

impl std::fmt::Debug for V1State {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "V1State({} projections)", self.count.get())
    }
}

/// The chunk of the V1 arena holding node [index], and its place there.
#[inline]
fn chunk_of(index: usize) -> (usize, usize) {
    let k = (usize::BITS - 1 - (index / 64 + 1).leading_zeros()) as usize;
    (k, index - 64 * ((1 << k) - 1))
}

impl V1State {
    /// Allocates a projection object and returns its id.
    fn add(&self, node: AstNodeImpl) -> NodeId {
        let index = self.count.get();
        let (k, offset) = chunk_of(index);
        let chunk = self.arena[k].get_or_init(|| (0..64usize << k).map(|_| OnceCell::new()).collect());
        if chunk[offset].set(node).is_err() {
            unreachable!("a V1 arena slot is set once");
        }
        self.count.set(index + 1);
        self.parents.borrow_mut().1.push(NO_NODE);
        V1_BASE + index as NodeId
    }

    #[inline]
    fn get(&self, index: usize) -> &AstNodeImpl {
        let (k, offset) = chunk_of(index);
        self.arena[k]
            .get()
            .and_then(|chunk| chunk[offset].get())
            .expect("no such V1 projection")
    }
}

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
    /// The V1 view: projections, V1 parents and caches.
    pub v1: V1State,
}

impl AstStore {
    pub fn new() -> AstStore {
        AstStore {
            nodes: Vec::new(),
            parents: Vec::new(),
            v1: V1State::default(),
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
        if id < V1_BASE {
            &self.nodes[id as usize]
        } else {
            self.v1.get((id - V1_BASE) as usize)
        }
    }

    #[inline(always)]
    pub fn node_mut(&mut self, id: NodeId) -> &mut AstNodeImpl {
        assert!(id < V1_BASE, "A V1 projection cannot be mutated.");
        &mut self.nodes[id as usize]
    }

    /// The number of V1 projection objects created so far.
    pub fn v1_projection_count(&self) -> usize {
        self.v1.count.get()
    }

    /// `node.beginToken`.
    pub fn begin_token(&self, id: NodeId, tokens: &TokenStore) -> TokenId {
        self.node(id).begin_token_of(self, tokens, id)
    }

    /// `node.endToken`.
    pub fn end_token(&self, id: NodeId, tokens: &TokenStore) -> TokenId {
        self.node(id).end_token_of(self, tokens, id)
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

    /// `node.parent2`: `NO_NODE` when there is none (a V1 projection object
    /// has none).
    pub fn parent2(self, id: NodeId) -> NodeId {
        if id >= V1_BASE {
            return self.store.v1.parents2.borrow().get(&id).copied().unwrap_or(NO_NODE);
        }
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
        if id >= V1_BASE {
            self.check_not_v1_projection(id);
        }
        self.node(id).accept2(self, id, visitor)
    }

    /// `node.visitChildren2(visitor)`.
    #[inline]
    pub fn visit_children2<V: AstVisitor2 + ?Sized>(self, id: NodeId, visitor: &mut V) {
        if id >= V1_BASE {
            self.check_not_v1_projection(id);
        }
        self.node(id).visit_children2(self, visitor)
    }

    /// `(node as Expression).precedence`.
    pub fn precedence(self, id: NodeId) -> Precedence {
        self.node(id).precedence(self)
    }

    /// `node.toSource()`, as UTF-16 code units.
    pub fn to_source_units(self, id: NodeId) -> Vec<u16> {
        if id >= V1_BASE {
            if let Some(source) = self.v1_to_source(id) {
                return source;
            }
        }
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

// ---------------------------------------------------------------------------
// The V1 view: the members of `AstNodeImpl` that read or link it.
// ---------------------------------------------------------------------------

impl AstStore {
    /// Allocates a V1 projection object: upstream's projection constructor
    /// call. Unlike `add`, it sets no parent.
    pub fn add_v1(&self, node: impl Into<AstNodeImpl>) -> NodeId {
        self.v1.add(node.into())
    }

    /// The cached child or projection in [slot] of [node], or `NO_NODE`.
    #[inline]
    pub fn v1_cached(&self, node: NodeId, slot: u8) -> NodeId {
        self.v1
            .cache
            .borrow()
            .get(&(node, slot))
            .copied()
            .unwrap_or(NO_NODE)
    }

    pub fn set_v1_cached(&self, node: NodeId, slot: u8, value: NodeId) {
        self.v1.cache.borrow_mut().insert((node, slot), value);
    }

    /// `_astNodeApiOverride = api`.
    pub fn set_api_override(&self, node: NodeId, api: AstNodeApi) {
        self.v1.api_override.borrow_mut().insert(node, api);
    }

    pub fn api_override(&self, node: NodeId) -> Option<AstNodeApi> {
        let overrides = self.v1.api_override.borrow();
        if overrides.is_empty() {
            return None;
        }
        overrides.get(&node).copied()
    }

    /// `_parent`, as last assigned: `UNSET` for a parsed node nothing has
    /// assigned since its V2 parent's constructor.
    fn raw_parent1(&self, id: NodeId) -> NodeId {
        let parents = self.v1.parents.borrow();
        if id >= V1_BASE {
            return parents.1[(id - V1_BASE) as usize];
        }
        parents.0.get(id as usize).copied().unwrap_or(UNSET)
    }

    /// `child._parent = parent`.
    pub fn set_parent1(&self, child: NodeId, parent: NodeId) {
        let mut parents = self.v1.parents.borrow_mut();
        if child >= V1_BASE {
            parents.1[(child - V1_BASE) as usize] = parent;
        } else {
            let index = child as usize;
            if parents.0.len() <= index {
                let length = self.nodes.len().max(index + 1);
                parents.0.resize(length, UNSET);
            }
            parents.0[index] = parent;
        }
    }

}

impl<'a> Ast<'a> {
    /// `_astNodeApi`.
    pub fn api(self, id: NodeId) -> AstNodeApi {
        if let Some(api) = self.store.api_override(id) {
            return api;
        }
        self.node(id).ast_node_api(self, id)
    }

    /// `_checkV1View()`.
    pub fn check_v1_view(self, id: NodeId) {
        if self.api(id) == AstNodeApi::v2 {
            panic!(
                "StateError: {} is not in the V1 AST view.",
                self.node(id).runtime_type()
            );
        }
    }

    /// `_checkV2View()`.
    pub fn check_v2_view(self, id: NodeId) {
        if self.api(id) == AstNodeApi::v1 {
            panic!(
                "StateError: {} is not in the V2 AST view.",
                self.node(id).runtime_type()
            );
        }
    }

    /// `parent._becomeParentOf1(child)`: makes [parent] the V1 parent of
    /// [child] and returns [child].
    #[inline]
    pub fn become_parent_of1(self, parent: NodeId, child: NodeId) -> NodeId {
        if child != NO_NODE {
            self.store.set_parent1(child, parent);
        }
        child
    }

    /// `_parentInV1`.
    pub fn parent_in_v1(self, id: NodeId) -> NodeId {
        let parent = self.parent1_now(id);
        if parent != NO_NODE {
            return parent;
        }
        let source = if self.api(id) == AstNodeApi::v1 {
            self.v1_projection_source(id)
        } else {
            id
        };
        if source != NO_NODE {
            self.materialize_enclosing_tree(source);
        }
        self.parent1_now(id)
    }

    /// Fixes the V1 parent of a parsed node at the value it has now, before
    /// a mutation changes what `initial_parent1` would compute.
    pub fn freeze_parent1(self, id: NodeId) {
        if id != NO_NODE && id < V1_BASE && self.store.raw_parent1(id) == UNSET {
            let parent = self.initial_parent1(id);
            self.store.set_parent1(id, parent);
        }
    }

    /// `_parent`.
    pub fn parent1_now(self, id: NodeId) -> NodeId {
        match self.store.raw_parent1(id) {
            UNSET => self.initial_parent1(id),
            parent => parent,
        }
    }

    /// `node.parent`.
    pub fn parent(self, id: NodeId) -> NodeId {
        self.check_v1_view(id);
        self.parent_in_v1(id)
    }

    /// `node.parentInPrimaryView`.
    pub fn parent_in_primary_view(self, id: NodeId) -> NodeId {
        if self.api(id) == AstNodeApi::v1 {
            self.parent_in_v1(id)
        } else {
            self.parent2(id)
        }
    }

    /// `node.root`.
    pub fn root(self, id: NodeId) -> NodeId {
        self.check_v1_view(id);
        let mut root = id;
        let mut parent = self.parent_in_v1(root);
        while parent != NO_NODE {
            root = parent;
            parent = self.parent_in_v1(root);
        }
        root
    }

    /// `node.thisOrAncestorMatching(predicate)`.
    pub fn this_or_ancestor_matching(
        self,
        id: NodeId,
        mut predicate: impl FnMut(NodeId) -> bool,
    ) -> NodeId {
        self.check_v1_view(id);
        let mut node = id;
        while node != NO_NODE && !predicate(node) {
            node = self.parent_in_v1(node);
        }
        node
    }

    /// `node.accept(visitor)`.
    #[inline]
    pub fn accept<V: crate::src::dart::ast::ast_g::AstVisitor + ?Sized>(
        self,
        id: NodeId,
        visitor: &mut V,
    ) -> Option<V::R> {
        self.node(id).accept1(self, id, visitor)
    }

    /// `node.visitChildren(visitor)`.
    #[inline]
    pub fn visit_children<V: crate::src::dart::ast::ast_g::AstVisitor + ?Sized>(
        self,
        id: NodeId,
        visitor: &mut V,
    ) {
        self.node(id).visit_children1(self, id, visitor)
    }

    /// `node.namedChildEntities`.
    pub fn named_child_entities(self, id: NodeId) -> Vec<ChildEntity1> {
        let mut entities = ChildEntities1::default();
        self.node(id).child_entities1(self, id, &mut entities);
        entities.entities
    }

    /// `node._childContainingRange(rangeOffset, rangeEnd)`.
    pub fn child_containing_range(self, id: NodeId, range_offset: i32, range_end: i32) -> NodeId {
        self.node(id)
            .child_containing_range1(self, id, range_offset, range_end)
    }

    /// `node._childContainingRange2(rangeOffset, rangeEnd)`.
    pub fn child_containing_range2(self, id: NodeId, range_offset: i32, range_end: i32) -> NodeId {
        self.node(id)
            .child_containing_range2(self, id, range_offset, range_end)
    }

    /// `node._containsOffset(rangeOffset, rangeEnd)`.
    pub fn contains_offset(self, id: NodeId, range_offset: i32, range_end: i32) -> bool {
        let tokens = self.tokens;
        // Cache some values to avoid computing them multiple times.
        let begin_token = self.begin_token(id);
        let offset = tokens.offset(begin_token);
        let end_token = self.end_token(id);
        let end = tokens.end(end_token);
        // Handle the special insertion point cases.
        if range_offset == range_end {
            if range_offset == offset {
                let previous = tokens.previous(begin_token);
                if previous != NO_TOKEN
                    && range_offset == tokens.end(previous)
                    && tokens.is_identifier(previous)
                {
                    return false;
                }
            }
            if range_offset == end {
                let next = tokens.next(end_token);
                if next != NO_TOKEN
                    && range_offset == tokens.offset(next)
                    && tokens.is_identifier(next)
                {
                    return false;
                }
            }
        }
        // Handle the general case.
        offset <= range_offset && end >= range_end
    }

    /// `NodeListImpl._elementContainingRange(rangeOffset, rangeEnd)`: a
    /// binary search of [list].
    pub fn element_containing_range(self, list: &[NodeId], range_offset: i32, range_end: i32) -> NodeId {
        let mut left: i64 = 0;
        let mut right: i64 = list.len() as i64 - 1;
        while left <= right {
            let middle = left + (right - left) / 2;
            let candidate = list[middle as usize];
            if self.contains_offset(candidate, range_offset, range_end) {
                return candidate;
            }
            if range_end <= self.offset(candidate) {
                right = middle - 1;
            } else if self.end(candidate) <= range_offset {
                left = middle + 1;
            } else {
                return NO_NODE;
            }
        }
        NO_NODE
    }

    /// `CompilationUnit.nodeCovering(offset: offset, length: length)`.
    pub fn node_covering(self, unit: NodeId, offset: i32, length: i32) -> NodeId {
        let end = offset + length;
        if offset < 0 || end > self.end(unit) {
            return NO_NODE;
        }
        let mut previous_node = unit;
        let mut current_node = self.child_containing_range(previous_node, offset, end);
        while current_node != NO_NODE {
            previous_node = current_node;
            current_node = self.child_containing_range(previous_node, offset, end);
        }
        previous_node
    }

    /// `CompilationUnit.nodeCovering2(offset: offset, length: length)`.
    pub fn node_covering2(self, unit: NodeId, offset: i32, length: i32) -> NodeId {
        let end = offset + length;
        if offset < 0 || end > self.end(unit) {
            return NO_NODE;
        }
        let mut previous_node = unit;
        let mut current_node = self.child_containing_range2(previous_node, offset, end);
        while current_node != NO_NODE {
            previous_node = current_node;
            current_node = self.child_containing_range2(previous_node, offset, end);
        }
        previous_node
    }
}

/// `ChildEntity.value` in the V1 view, whose lists are projected.
#[derive(Clone, Debug)]
pub enum ChildValue1 {
    Token(TokenId),
    Node(NodeId),
    NodeList(Vec<NodeId>),
    TokenList(Vec<TokenId>),
}

/// `class ChildEntity` in the V1 view.
#[derive(Clone, Debug)]
pub struct ChildEntity1 {
    pub name: &'static str,
    pub value: ChildValue1,
}

/// `class ChildEntities` in the V1 view.
#[derive(Default, Debug)]
pub struct ChildEntities1 {
    pub entities: Vec<ChildEntity1>,
}

impl ChildEntities1 {
    pub fn add_node(&mut self, name: &'static str, value: NodeId) {
        if value != NO_NODE {
            self.entities.push(ChildEntity1 {
                name,
                value: ChildValue1::Node(value),
            });
        }
    }

    pub fn add_node_list(&mut self, name: &'static str, value: Vec<NodeId>) {
        self.entities.push(ChildEntity1 {
            name,
            value: ChildValue1::NodeList(value),
        });
    }

    pub fn add_token(&mut self, name: &'static str, value: TokenId) {
        if value != NO_TOKEN {
            self.entities.push(ChildEntity1 {
                name,
                value: ChildValue1::Token(value),
            });
        }
    }

    pub fn add_token_list(&mut self, name: &'static str, value: Vec<TokenId>) {
        self.entities.push(ChildEntity1 {
            name,
            value: ChildValue1::TokenList(value),
        });
    }
}
