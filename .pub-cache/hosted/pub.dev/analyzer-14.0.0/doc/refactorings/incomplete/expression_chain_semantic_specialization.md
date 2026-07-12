# Refactoring Expression Chains and Semantic Specialization

This document proposes a redesign of how the analyzer represents and resolves postfix expression forms: member access, null-aware access, index access, invocation continuation, expression type-argument application, dot shorthand, constructor-tearoff-like syntax, and related semantic rewrites.

The problem is not only long dotted chains such as `a.b.c.d.e`. It also includes forms such as `a?.b`, `a[b]`, `a?.[b]`, `a.b()`, `a.b<int>()`, `a.b<int>.c`, `prefix.C.named`, `C<int>.named`, `.foo`, `.foo()`, `a.b = x`, `a[b] += y`, `a.b++`, `++a.b`, and implicit-call-related specialization.

Today the analyzer AST makes early distinctions based on syntax shape and then relies on later rewriting to repair those parser-time guesses. The proposal here is to represent these postfix expression forms first with syntax-oriented forms such as `UnresolvedAccessChain`, and then perform explicit semantic specialization during resolution.

---

## 1. Current State

Today the parser and resolver do not treat postfix access and invocation syntax as one coherent syntactic family.

Instead, surface forms in this area are split early across multiple AST node kinds, including:

- `PrefixedIdentifier`
- `PropertyAccess`
- `MethodInvocation`
- `FunctionExpressionInvocation`
- `FunctionReference`
- `IndexExpression`
- `PostfixExpression`
- `DotShorthandPropertyAccess`
- `DotShorthandInvocation`
- `InstanceCreationExpression`
- `ConstructorReference`

This affects syntax such as:

- `a.b`
- `a?.b`
- `a[b]`
- `a?.[b]`
- `a.b()`
- `a.b<int>()`
- `a.b<int>.c`
- `prefix.C.named`
- `C<int>.named`
- `.foo`
- `.foo()`

One visible symptom is that the parser-side builder chooses between `PrefixedIdentifier` and `PropertyAccess` while building the AST.

Conceptually:

- `a.b` becomes `PrefixedIdentifier` if the receiver is a simple identifier and the operator is `.`
- otherwise the same surface syntax becomes `PropertyAccess`

This is structurally convenient for the parser, but semantically unstable. Later phases need to reinterpret or rewrite these nodes depending on what the chain prefix actually means:

- local variable / parameter / field / getter
- import prefix
- class / enum / extension / extension type / type alias
- constructor tearoff target
- type literal
- record value
- callable object
- extension application target
- dynamic or invalid access

More importantly, this is not just a matter of attaching elements and types to an already-correct syntax tree. The current implementation has **multiple rewrite layers** that actively change node shape after parsing.

### Rewrite layer 1: `AstRewriter`

`AstRewriter` exists specifically to repair parser-time assumptions.

It rewrites among other things:

- `InstanceCreationExpression` to `MethodInvocation` when syntax such as `a<...>.b(...)` turns out to be a function / function-type case rather than a constructor case
- `MethodInvocation` to `InstanceCreationExpression` or `ExtensionOverride` when syntax such as `C()`, `C.named()`, `p.C()`, or `p.C.named()` turns out to denote constructors or extension overrides
- `PrefixedIdentifier` to `ConstructorReference`
- `PropertyAccess` to `ConstructorReference`
- `SimpleIdentifier` / `PrefixedIdentifier` to `TypeLiteral` in value contexts

So today the parser does not merely produce unresolved syntax; it produces syntax that is expected to be structurally repaired later.

### Rewrite layer 2: `MethodInvocationResolver`

Even after `AstRewriter`, `MethodInvocationResolver` may still conclude that a `MethodInvocation` is not really a method invocation.

In particular, if the target resolves to:

- a getter
- a variable of function type
- a record field of function type
- a callable value

then `MethodInvocationResolver` rewrites the node to a `FunctionExpressionInvocation`.

To do that, it synthesizes a new function expression out of:

- `SimpleIdentifier`
- `PrefixedIdentifier`
- `PropertyAccess`
- `DotShorthandPropertyAccess`

depending on the parsed shape and context.

This means the current system has both:

- a pre-resolution rewrite layer (`AstRewriter`)
- and a resolution-time semantic rewrite layer (`MethodInvocationResolver`)

which is a strong signal that the parsed expression forms do not line up with the semantic categories the rest of the analyzer needs.

As a result, downstream code pays a constant complexity tax:

- duplicated handling of `PrefixedIdentifier` and `PropertyAccess`
- parent-shape checks to recover intent
- AST rewrites during resolution
- special bookkeeping to preserve diagnostics and flow information across rewrites

---

## 2. Design Goal

The parser should describe syntax, not semantics.

For expression chains, the parser should stop deciding whether a dotted suffix is:

- a name qualified by an import prefix, such as `prefix.C`
- an instance member access on a value, such as `a.b`
- a static member access on a type-denoting prefix, such as `C.m`
- a constructor tearoff, such as `C.named`
- more postfix syntax that continues from a type-denoting prefix, such as `C<int>.named` or `prefix.C<int>.named`

Instead, it should build a single syntax-first representation of a postfix access chain, and resolution should classify it once. This classification must cover not only read-like interpretations, but also whether the chain is being used as an assignment target, a compound-assignment target, or an update target.

---

## 3. Scope

This proposal is specifically about **expression postfix chains**.

It does **not** require unifying all dotted syntax in the language.

There are two distinct syntactic families:

### Name-only qualified syntax

Examples:

- directive names
- some comment-reference forms
- other grammar productions that are purely qualified names

For these, a plain qualified-name structure remains sufficient.

### Expression postfix chains

Examples:

- `a.b.c`
- `a?.b.c`
- `a.b<int>.c`
- `a.b(x).c`
- `a[b].c`
- `prefix.C.named`
- `C<int>.named`
- `super.a.b`

These are the forms this document targets.

### Existing expression classes that are not intended to be changed

This refactoring is **not** intended to restructure the general `Expression` hierarchy. It is focused on postfix access and invocation syntax only.

In particular, the following existing expression classes are intended to remain structurally as they are:

- `AdjacentStrings`
- `AnonymousMethodInvocation`
- `AsExpression`
- `AssignmentExpression`
- `AwaitExpression`
- `BinaryExpression`
- `BooleanLiteral`
- `CascadeExpression`
- `ConditionalExpression`
- `DoubleLiteral`
- `FunctionExpression`
- `IntegerLiteral`
- `IsExpression`
- `ListLiteral`
- `NamedExpression`
- `NullLiteral`
- `ParenthesizedExpression`
- `PatternAssignment`
- `PrefixExpression`
- `RecordLiteral`
- `RethrowExpression`
- `SetOrMapLiteral`
- `SimpleStringLiteral`
- `StringInterpolation`
- `SuperExpression`
- `SwitchExpression`
- `SymbolLiteral`
- `ThisExpression`
- `ThrowExpression`

These nodes may still appear inside or around an access chain, for example as a `GeneralExpressionHead`, but they are not themselves the target of this refactoring.

### Existing expression classes in the affected area

The current expression classes most directly in scope are:

- `PrefixedIdentifier`
- `PropertyAccess`
- `MethodInvocation`
- `FunctionExpressionInvocation`
- `FunctionReference`
- `IndexExpression`
- `PostfixExpression`
- `DotShorthandPropertyAccess`
- `DotShorthandInvocation`

These are the parser / resolver shapes that currently overlap or are repaired by rewriting, and they are the main candidates to be replaced or have their parser-time role significantly reduced.

### Existing semantic endpoint nodes that likely remain

Some existing expression classes should likely survive, but with a clearer role as semantic specialization endpoints rather than as parser guesses.

These include:

- `ImplicitCallReference`
- `InstanceCreationExpression`
- `ConstructorReference`
- `TypeLiteral`
- `ExtensionOverride`
- `DotShorthandConstructorInvocation`

So the boundary is not simply "old nodes go away" versus "old nodes stay". The more accurate split is:

- ordinary expressions stay ordinary
- ambiguous postfix-chain syntax is replaced by `UnresolvedAccessChain`
- semantic endpoint nodes remain, but are produced later and more intentionally

---

## 4. New Design

Introduce a syntax-first node:

```text
abstract final class UnresolvedAccessChain implements Expression {
  ChainHead get head;
  NodeList<ChainSegment> get segments;
}
```

The node represents one expression head followed by an ordered list of postfix selectors / applications.

### `ChainHead`

`ChainHead` is the root syntax before the first postfix step.

Suggested head kinds:

- `IdentifierHead`
- `ThisHead`
- `SuperHead`
- `DotShorthandHead`
- `ParenthesizedHead`
- `GeneralExpressionHead`

`GeneralExpressionHead` is the escape hatch for cases where the base is already an ordinary expression, for example:

- `(a + b).c`
- `foo().bar`
- `[1, 2].length`
- `({a: 0}).a`

### `ChainSegment`

Suggested segment kinds:

- `PropertySegment`
  - `.name`
  - `?.name`
- `IndexSegment`
  - `[index]`
  - `?.[index]`
- `TypeArgumentSegment`
  - `<T>`
- `InvocationSegment`
  - `(arguments)`
- `PostfixSegment`
  - `++`
  - `--`

This is intentionally syntactic. These segment kinds do not imply runtime or resolution behavior.

---

## 5. Core Invariants

`UnresolvedAccessChain` should obey a small set of strict invariants.

### Purely syntactic

The chain carries no semantic classification.

In particular, it does not encode whether any segment denotes:

- an instance property read
- a static member access
- an import-prefix lookup
- a constructor tearoff
- a type literal
- an error

### Ordered left-to-right structure

Evaluation and classification proceed from `head` through `segments` in source order.

Each segment attaches to the immediately preceding prefix of the chain.

### No bare identifiers

A bare identifier such as `a` remains a normal identifier node.

`UnresolvedAccessChain` is used only when there is at least one postfix segment.

### Null-aware is segment-local

Null-aware behavior is introduced by the segment that carries `?.`, not by the chain as a whole.

Example:

```text
a?.b.c
```

is represented as:

- head: `a`
- segments:
  - `?.b`
  - `.c`

### Type arguments are explicit syntax

Expression type arguments are represented by `TypeArgumentSegment`.

Example:

```text
C<int>.named
```

is represented as:

- head: `C`
- segments:
  - `<int>`
  - `.named`

Resolution later decides whether this means a constructor tearoff, a static access, or something invalid.

### Postfix `++` / `--` are terminal

`PostfixSegment` must be the final segment of the chain.

### Invocation is composable

`InvocationSegment` may appear after a property, index, or type-argument segment.

Example:

```text
a.b<int>(x)[y]
```

is represented as:

- head: `a`
- segments:
  - `.b`
  - `<int>`
  - `(x)`
  - `[y]`

### Assignability comes from semantic specialization plus use context

The syntax chain itself does not decide whether it is assignable.

For example, forms such as `a.b = x`, `a[b] += y`, `a.b++`, and `++a.b` all use the same underlying chain syntax, but resolution must determine whether the final prefix denotes:

- a writable property
- a writable index operator
- a read-only getter
- a namespace-qualified member
- a type-denoting prefix
- an invalid target

This is another reason not to bake semantic meaning into the parser representation.

---

## 6. Examples

### `a.b.c`

```text
head: IdentifierHead(a)
segments:
  .b
  .c
```

### `a?.b.c<int>(x)[y]`

```text
head: IdentifierHead(a)
segments:
  ?.b
  .c
  <int>
  (x)
  [y]
```

### `prefix.C.named`

```text
head: IdentifierHead(prefix)
segments:
  .C
  .named
```

### `super.a.b`

```text
head: SuperHead(super)
segments:
  .a
  .b
```

### Dot shorthand

```text
.zero
```

can be represented either as:

- a dedicated `DotShorthandHead` with ordinary following segments, or
- a separate dot-shorthand-specific syntax node family

This document does not require choosing between these two immediately.

---

## 7. Cascades

Cascades should remain outside `UnresolvedAccessChain`.

A cascade is not just another postfix segment; it changes receiver propagation and evaluation rules.

So the structure should remain conceptually:

```text
abstract final class CascadeExpression implements Expression {
  Expression get target;
  NodeList<CascadeSection> get sections;
}
```

where each section is chain-like but uses an implicit receiver.

This keeps ordinary access chains simple and prevents cascade-specific rules from contaminating non-cascade syntax.

---

## 8. Resolution / Semantic Specialization Model

Parsing builds one `UnresolvedAccessChain`.

Resolution then walks the chain prefix-by-prefix and classifies each step using scope lookup and type information.

Potential semantic outcomes include:

- instance property get / set
- static member access
- import-prefix qualified lookup
- constructor tearoff
- method invocation
- function-expression invocation
- index get / set
- compound-assignment target classification
- prefix / postfix update target classification
- type literal
- error recovery form

The important point is that this semantic classification happens **after** parsing, not during parsing.

This is similar in spirit to front_end using an internal syntax-oriented representation first, and only later producing semantically precise forms.

The contrast with the current analyzer state is important:

- today, semantic repair is split across parser output, `AstRewriter`, and resolver-specific rewrites such as `MethodInvocationResolver`
- in the proposed design, the parser would produce one syntax-first access chain, and a single explicit semantic-specialization step during resolution would classify it into semantic forms

This is intended to replace ad hoc shape repair with one first-class semantic specialization step.

---

## 9. Semantic Node Naming

The syntax-only form should be marked explicitly as unusual.

That means:

- syntax-first parser-only nodes use `Unresolved...`
- semantic nodes use the plain operation names

So:

- `UnresolvedAccessChain`
- `UnresolvedAccessHead`
- `UnresolvedAccessSegment`

The intent is:

- unresolved syntax is the exceptional state and should say so
- the normal rewritten / semantic AST should own the simple names

This matches existing analyzer practice better than prefixing every semantic node with `Resolved...`.

It also aligns with kernel/front_end, where the semantically precise forms have simple operation-oriented names.

---

## 11. Why `head + list` Instead of `head + next`

The syntax node should use:

```text
head + ordered list of segments
```

not:

```text
head + next segment + next segment + ...
```

Reasons:

1. Parsing naturally discovers segments left-to-right.
2. Long chains stay shallow instead of becoming deeply nested.
3. Most later analyses want the whole chain anyway.
4. Null-aware positions, type-argument attachment, and invocation boundaries are easier to inspect when the chain is one flat ordered structure.
5. Semantic specialization can split the chain into semantic pieces without rebuilding a large parent-linked recursive shape.

---

## 12. Migration Strategy

This should be staged.

### Stage 1: Introduce syntax-only chain internally

Add `UnresolvedAccessChain` as an internal AST representation for expression chains, but keep the existing public APIs stable where possible.

### Stage 2: Parse chains without semantic branching

Update the parser-side builder so that forms currently split between `PrefixedIdentifier`, `PropertyAccess`, `MethodInvocation`, and `FunctionReference` in expression-chain positions are first recorded as `UnresolvedAccessChain`.

### Stage 3: Perform semantic specialization during resolution

Introduce one normalization / semantic-specialization step that translates `UnresolvedAccessChain` into semantically precise resolved forms.

### Stage 4: Migrate downstream consumers

Move resolution, flow analysis, constant evaluation, and related logic to rely on the semantically specialized forms instead of parsed node shape.

---

## 13. Open Questions

1. Should dot shorthand be modeled as a dedicated chain head, or remain a separate syntax family?
2. Should expression type-argument application remain a distinct segment, or be folded into the following invocation / property segment?
3. How much of this should become public API versus remaining internal?
4. Should some name-only dotted forms also move to a more uniform qualified name representation, or is it better to keep that orthogonal?
5. Which of the semantic classes above should exist immediately, and which should begin life as temporary semantic-specialization artifacts during migration?

---

## 14. Summary

The core design decision is simple:

- parsing should produce a syntax-first postfix chain
- resolution should assign semantics later

`UnresolvedAccessChain` is the proposed syntax node for expression chains.

Its purpose is to eliminate parser-time semantic branching, remove the `PrefixedIdentifier` vs `PropertyAccess` split from syntax, and make later semantic specialization a single explicit phase rather than a collection of ad hoc rewrites spread across the resolver.
