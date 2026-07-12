# Syntactic Location

This document proposes a new representation for syntactic location in the analyzer.

The goal is to represent structural facts about a source offset and a source selection without forcing an early policy decision.

The central idea is that one offset can have multiple syntactic properties at the same time. It can be inside some node, at the boundary of one or more other nodes, between tokens, or inside a comment. Those facts are all properties of the syntax, not of any particular feature.

This representation therefore records the facts that are true at an offset instead of collapsing the offset to one pre-chosen interpretation. That is the reason for separating token facts, comment facts, and node facts, and for allowing multiple node-boundary facts to coexist.

The intended benefit is that clients can derive their own policies from the same fact set. The analyzer should answer "what is syntactically true here?" and leave "which of these facts matters for this operation?" to the caller.

The representation in this document is intentionally fact-oriented rather than policy-oriented.

## Design Goals

- Represent structural facts for a single offset precisely.
- Build selection representation on top of two single-offset locations.
- Preserve ambiguity at boundaries instead of collapsing to a single node.
- Keep token facts, comment facts, and node facts separate.
- Make it easy for clients to derive their own policies.

## High-Level Model

Use a single `SyntacticPoint` for one offset, and a `SyntacticSelection` for a range.

```text
final class SyntacticPoint {
  final CompilationUnit unit;
  final int offset;
  final TokenPosition tokenPosition;
  final CommentPosition? commentPosition;
  final NodePosition nodePosition;
}

final class SyntacticSelection {
  final SyntacticPoint anchor;
  final SyntacticPoint focus;
}
```

`SyntacticSelection` is deliberately minimal. The important part of this design is the point representation. Selection-specific policies can be layered on top.

Here `unit` is only the shared root for the point. The interesting invariants are in `TokenPosition` and `NodePosition`, where the representation actually constrains the shape of the offset.

## Why `SyntacticPoint` Is Not A Hierarchy

A single offset can simultaneously satisfy multiple structural facts:

- it can be inside some node
- it can be at the start of some nodes
- it can be at the end of some other nodes
- it can be between sibling nodes
- it can be in a token gap and in a comment at the same time

Because these facts overlap, a top-level hierarchy would force arbitrary early choices. The top-level representation is therefore a single aggregate object.

However, some sub-dimensions really are exclusive. Token position is the best example, so it is modeled as a sealed hierarchy.

## Token Position

Token position answers the question: where is this offset relative to the main token stream?

```text
final class TokenInfo {
  final Token token;
  final AstNode introducingNode;
}

sealed class TokenPosition {}

final class InToken extends TokenPosition {
  final TokenInfo token;
}

final class InTokenGap extends TokenPosition {
  final TokenInfo? left;
  final TokenInfo? right;
}

final class AtTokenBoundary extends TokenPosition {
  final TokenInfo? left;
  final TokenInfo? right;
}
```

### Invariants

`InToken`

- The offset is strictly inside `token`.
- It is not at `token.token.offset`.
- It is not at `token.token.end`.

`InTokenGap`

- The offset is strictly outside tokens.
- If `left` is present, then `left.token.end < offset`.
- If `right` is present, then `offset < right.token.offset`.
- The offset does not touch either token.

`AtTokenBoundary`

- The offset touches the end of `left.token`, the start of `right.token`, or both.
- At least one of `left` and `right` is present.

### Examples

`foo^bar` in identifier `foobar`

- `InToken(token: TokenInfo(token: foobar, introducingNode: SimpleIdentifier(foobar)))`

`foo^+bar`

- `AtTokenBoundary(left: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)), right: TokenInfo(token: +, introducingNode: BinaryExpression))`

`foo ^ + bar`

- `InTokenGap(left: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)), right: TokenInfo(token: +, introducingNode: BinaryExpression))`

`^foo`

- `AtTokenBoundary(left: null, right: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)))`

`foo^`

- `AtTokenBoundary(left: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)), right: null)`

## Comment Position

Comment position is orthogonal to token position.

For example, an offset inside `/* comment */` between two code tokens is both:

- `InTokenGap(left, right)`
- `InComment(comment)`

This is why comment facts are not folded into `TokenPosition`.

```text
final class CommentInfo {
  final Token token;
  final Token anchorToken;
  final AstNode? anchorNode;
}

sealed class CommentPosition {}

final class InComment extends CommentPosition {
  final CommentInfo comment;
}

final class AtCommentBoundary extends CommentPosition {
  final CommentInfo comment;
  final bool atStart;
  final bool atEnd;
}
```

### Invariants

`InComment`

- The offset is strictly inside `comment.token`.
- It is not at the start or end of `comment.token`.
- `comment.anchorToken` is the neighboring non-comment token that the comment is anchored to in the token stream.

`AtCommentBoundary`

- The offset is at the start of `comment.token`, the end of `comment.token`, or both.
- At least one of `atStart` and `atEnd` is `true`.

There is intentionally no `InCommentGap`. The design does not currently model a separate token stream inside comments.

## Node Position

Node position answers the question: where is this offset relative to AST nodes?

Unlike token position, node facts overlap heavily, so `NodePosition` is an aggregate.

```text
final class NodePosition {
  final AstNode strictlyContainingNode;
  final List<AstNode> startingNodes;
  final List<AstNode> endingNodes;
  final List<AstNode> leftNodes;
  final List<AstNode> rightNodes;
}
```

All lists are ordered from innermost to outermost.

More precisely, if two nodes appear in the same list and one is a descendant of the other, the descendant comes first.

The reason `leftNodes` and `rightNodes` exist at all is that many interesting caret positions are in real gaps, such as whitespace between statements or expressions. At such offsets, `startingNodes` and `endingNodes` are both empty, but clients still often need nearest node structure on the left or right. These lists make such gap positions first-class instead of forcing every client to rediscover the nearest neighboring node frontiers from the AST.

### Meaning Of Each Field

`strictlyContainingNode`

- Usually, the innermost node whose interior strictly contains the offset.
- This is open-interval containment: `node.offset < offset < node.end`.
- If no non-`CompilationUnit` node strictly contains the offset, this falls back to the `CompilationUnit`.

`startingNodes`

- Nodes whose `node.offset == offset`.
- Ordered from innermost to outermost among the nodes that start at this offset.

`endingNodes`

- Nodes whose `node.end == offset`.
- Ordered from innermost to outermost among the nodes that end at this offset.

`leftNodes`

- Let `leftEnd` be the greatest offset less than the point offset such that some node ends at `leftEnd`.
- `leftNodes` contains all nodes with `node.end == leftEnd`.
- Ordered from innermost to outermost among the nodes that end at `leftEnd`.
- These nodes are strictly to the left of the point, not touching it.

`rightNodes`

- Let `rightStart` be the least offset greater than the point offset such that some node starts at `rightStart`.
- `rightNodes` contains all nodes with `node.offset == rightStart`.
- Ordered from innermost to outermost among the nodes that start at `rightStart`.
- These nodes are strictly to the right of the point, not touching it.

### Invariants

- `leftNodes` and `endingNodes` are disjoint.
- `rightNodes` and `startingNodes` are disjoint.
- `strictlyContainingNode` is always present.
- `strictlyContainingNode` can coexist with any of the lists.
- `startingNodes` and `endingNodes` can both be non-empty at the same offset.
- `leftNodes` is non-empty only when `endingNodes` is empty.
- `rightNodes` is non-empty only when `startingNodes` is empty.
- `leftNodes` is non-empty only when there is a real gap between the point and the nearest node-ending frontier on the left.
- `rightNodes` is non-empty only when there is a real gap between the point and the nearest node-starting frontier on the right.

### Examples

Inside identifier:

```text
var x = fo^o;
```

- `tokenPosition = InToken(token: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)))`
- `strictlyContainingNode = SimpleIdentifier(foo)`
- `startingNodes = []`
- `endingNodes = []`
- `leftNodes = []`
- `rightNodes = []`

At identifier start:

```text
var x = ^foo;
```

- `tokenPosition = AtTokenBoundary(left: null, right: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)))`
- `strictlyContainingNode = VariableDeclaration(x = foo)`
- `startingNodes = [SimpleIdentifier(foo)]`
- `endingNodes = []`
- `leftNodes = []`
- `rightNodes = []`

At identifier end:

```text
var x = foo^;
```

- `tokenPosition = AtTokenBoundary(left: TokenInfo(token: foo, introducingNode: SimpleIdentifier(foo)), right: TokenInfo(token: ;, introducingNode: TopLevelVariableDeclaration))`
- `strictlyContainingNode = VariableDeclaration(x = foo)`
- `startingNodes = []`
- `endingNodes = [SimpleIdentifier(foo)]`
- `leftNodes = []`
- `rightNodes = []`

In whitespace between expression children:

```text
var x = a ^ + b;
```

- `tokenPosition = InTokenGap(left: TokenInfo(token: a, introducingNode: SimpleIdentifier(a)), right: TokenInfo(token: +, introducingNode: BinaryExpression))`
- `strictlyContainingNode = BinaryExpression(a + b)`
- `startingNodes = []`
- `endingNodes = []`
- `leftNodes = [SimpleIdentifier(a)]`
- `rightNodes = [SimpleIdentifier(b)]`

Between two statements with a real gap:

```text
void f() {
  a();
  ^
  b();
}
```

- `tokenPosition = InTokenGap(left: TokenInfo(token: ;, introducingNode: ExpressionStatement(a())), right: TokenInfo(token: b, introducingNode: SimpleIdentifier(b)))`
- `strictlyContainingNode = Block`
- `startingNodes = []`
- `endingNodes = []`
- `leftNodes = [ExpressionStatement(a())]`
- `rightNodes = [SimpleIdentifier(b), MethodInvocation(b()), ExpressionStatement(b())]`

At the start of a statement inside a block:

```text
void f() {
  ^a();
}
```

- `tokenPosition = AtTokenBoundary(left: null, right: TokenInfo(token: a, introducingNode: SimpleIdentifier(a)))`
- `strictlyContainingNode = Block`
- `startingNodes = [SimpleIdentifier(a), MethodInvocation(a()), ExpressionStatement(a())]`
- `endingNodes = []`
- `leftNodes = []`
- `rightNodes = []`

At the end of a statement inside a block:

```text
void f() {
  a();^
}
```

- `tokenPosition = AtTokenBoundary(left: TokenInfo(token: ;, introducingNode: ExpressionStatement(a())), right: null)`
- `strictlyContainingNode = Block`
- `startingNodes = []`
- `endingNodes = [ExpressionStatement(a())]`
- `leftNodes = []`
- `rightNodes = []`

Between two adjacent statements with no gap:

```text
void f() { a();^b(); }
```

- `tokenPosition = AtTokenBoundary(left: TokenInfo(token: ;, introducingNode: ExpressionStatement(a())), right: TokenInfo(token: b, introducingNode: SimpleIdentifier(b)))`
- `strictlyContainingNode = Block`
- `startingNodes = [SimpleIdentifier(b), MethodInvocation(b()), ExpressionStatement(b())]`
- `endingNodes = [ExpressionStatement(a())]`
- `leftNodes = []`
- `rightNodes = []`

Between two adjacent top-level declarations:

```text
class A {}^class B {}
```

- `tokenPosition = AtTokenBoundary(left: TokenInfo(token: }, introducingNode: ClassDeclaration(A)), right: TokenInfo(token: class, introducingNode: ClassDeclaration(B)))`
- `strictlyContainingNode = CompilationUnit`
- `startingNodes = [ClassDeclaration(B)]`
- `endingNodes = [ClassDeclaration(A)]`
- `leftNodes = []`
- `rightNodes = []`

Between declaration name and parameter list:

```text
void f^() {}
```

- `tokenPosition = AtTokenBoundary(left: TokenInfo(token: f, introducingNode: FunctionDeclaration), right: TokenInfo(token: (, introducingNode: FormalParameterList))`
- `strictlyContainingNode = FunctionDeclaration`
- `startingNodes = [FormalParameterList, FunctionExpression]`
- `endingNodes = []`
- `leftNodes = []`
- `rightNodes = []`

Higher-level policies can prefer the enclosing `FunctionDeclaration`, but that choice should not be baked into `NodePosition`.

In a token gap after a node but before punctuation:

```text
f(a ^, b);
```

- `tokenPosition = InTokenGap(left: TokenInfo(token: a, introducingNode: SimpleIdentifier(a)), right: TokenInfo(token: ,, introducingNode: ArgumentList))`
- `strictlyContainingNode = ArgumentList`
- `startingNodes = []`
- `endingNodes = []`
- `leftNodes = [SimpleIdentifier(a)]`
- `rightNodes = [SimpleIdentifier(b)]`

In a token gap after punctuation but before a node:

```text
f(a, ^ b);
```

- `tokenPosition = InTokenGap(left: TokenInfo(token: ,, introducingNode: ArgumentList), right: TokenInfo(token: b, introducingNode: SimpleIdentifier(b)))`
- `strictlyContainingNode = ArgumentList`
- `startingNodes = []`
- `endingNodes = []`
- `leftNodes = [SimpleIdentifier(a)]`
- `rightNodes = [SimpleIdentifier(b)]`

At the end of a function declaration, with several `endingNodes`:

```text
f() {}^
```

- `tokenPosition = AtTokenBoundary(left: TokenInfo(token: }, introducingNode: Block), right: null)`
- `strictlyContainingNode = CompilationUnit`
- `startingNodes = []`
- `endingNodes = [Block, BlockFunctionBody, FunctionExpression, FunctionDeclaration]`
- `leftNodes = []`
- `rightNodes = []`

In a gap after a function declaration, with several `leftNodes`:

```text
f() {}

^
g() {}
```

- `tokenPosition = InTokenGap(left: TokenInfo(token: }, introducingNode: Block), right: TokenInfo(token: g, introducingNode: FunctionDeclaration))`
- `strictlyContainingNode = CompilationUnit`
- `startingNodes = []`
- `endingNodes = []`
- `leftNodes = [Block, BlockFunctionBody, FunctionExpression, FunctionDeclaration]`
- `rightNodes = [FunctionDeclaration]`

## Why `NodePosition` Does Not Use `InNode` / `AtNodeBoundary`

For nodes, the facts do not partition the space cleanly.

At one offset, a point can simultaneously be:

- inside a block
- at the end of one statement
- at the start of another statement

This is why node position is modeled as overlapping facts rather than as a sealed hierarchy.

## Selection

Selection should be modeled in terms of points.

```text
final class SyntacticSelection {
  final SyntacticPoint anchor;
  final SyntacticPoint focus;
}
```

Selections can then define higher-level operations in terms of those two points:

- covering node
- nearest common ancestor
- left-biased or right-biased interpretation of endpoints
- expansion to enclosing structure

This design keeps point representation and selection policy separate.

## Covering Node

The smallest node fully covering a selection can be derived from the two point locations, but only after endpoint interpretation policy is chosen.

For many policies, the covering node will be the lowest common ancestor of:

- the node interpretation chosen for the anchor point
- the node interpretation chosen for the focus point

However, this document deliberately does not bake a single covering-node policy into the point representation.

## Derived Convenience APIs

Clients will likely want convenience getters derived from the structural facts, for example:

```text
extension NodePositionConvenience on NodePosition {
  AstNode? get nearestStartingNode =>
      startingNodes.isEmpty ? null : startingNodes.first;

  AstNode? get nearestEndingNode =>
      endingNodes.isEmpty ? null : endingNodes.first;

  AstNode? get nearestLeftNode =>
      leftNodes.isEmpty ? null : leftNodes.first;

  AstNode? get nearestRightNode =>
      rightNodes.isEmpty ? null : rightNodes.first;
}
```

These are conveniences only. The underlying representation should preserve the full fact set.

## Open Questions

- Should `SyntacticSelection` also expose normalized `start`/`end` convenience getters in addition to `anchor`/`focus`?
- Should `NodePosition` include additional facts for nodes whose full range is exactly equal on both sides of the point?
- How should synthetic and recovery nodes be represented?
- Should there be specialized facts for declaration names that do not have dedicated AST nodes?
- Which node lists should include zero-length synthetic nodes, if any?

## Summary

This design uses:

- a single `SyntacticPoint` as the fact bundle for one offset
- `TokenPosition` as a sealed hierarchy
- `CommentPosition` as an orthogonal optional fact
- `NodePosition` as an aggregate of overlapping structural facts
- `SyntacticSelection` as a thin wrapper around two points

The main principle is to preserve structure first and defer client policy until later.
