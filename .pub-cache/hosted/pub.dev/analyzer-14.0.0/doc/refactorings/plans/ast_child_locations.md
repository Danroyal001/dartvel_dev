# AST Child Slot Refactoring

This document explores a possible refactoring of analyzer AST ownership and structural editing. The goal is to replace ad hoc parent pointers and hand-written node replacement logic with generated child slots that know their parent, child, nullability, and edit behavior.

The proposed direction is radical but localized to the AST implementation:

```text
sealed class AstNodeImpl implements AstNode {
  ChildSlot<AstNodeImpl>? get parentSlot;
  AstNodeImpl? get parent => parentSlot?.parent;
}
```

Every child node is attached through a generated slot object. The slot becomes the authority for the parent-child relation. Replacing or removing a child is an operation on the slot that contains the child, not a visitor over every possible parent node.

## Table of Contents

- [Current Model](#current-model)
- [Problems](#problems)
  - [NodeReplacer Is A Hand-Written Parallel AST Model](#nodereplacer-is-a-hand-written-parallel-ast-model)
  - [Null Means Too Much](#null-means-too-much)
  - [Parent Links Do Not Describe The Parent Slot](#parent-links-do-not-describe-the-parent-slot)
  - [Child Lists Have Different Semantics](#child-lists-have-different-semantics)
  - [Temporary Child Stealing Is Easy To Mis-handle](#temporary-child-stealing-is-easy-to-mis-handle)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Model](#proposed-model)
  - [Parent Slot](#parent-slot)
  - [Bound Child Slots](#bound-child-slots)
  - [Required Child Slots](#required-child-slots)
  - [Optional Child Slots](#optional-child-slots)
  - [Node List Slots](#node-list-slots)
  - [Generated Node Code](#generated-node-code)
- [Structural Editing](#structural-editing)
  - [Replacement](#replacement)
  - [Removal](#removal)
  - [Captured Edits](#captured-edits)
- [Generated Child Model](#generated-child-model)
- [Compatibility Layer](#compatibility-layer)
- [Migration Plan](#migration-plan)
- [Open Questions](#open-questions)

<a name="current-model"></a>
## Current Model

Each `AstNodeImpl` stores a parent pointer:

```text
AstNode? _parent;
```

Constructors and property setters call `_becomeParentOf(child)` to update the child's parent pointer. `NodeListImpl` also updates parent pointers when list elements are assigned.

Structural replacement is centralized in `NodeReplacer`, but the implementation is a large hand-written visitor. For each parent node type, it checks each child property and assigns the replacement through the corresponding setter:

```text
if (identical(node.typeParameters, _oldNode)) {
  node.typeParameters = _newNode as TypeParameterListImpl?;
  return true;
}
```

This means the AST implementation already has generated knowledge of each child, while `NodeReplacer` maintains a second, manual copy of part of that knowledge.

<a name="problems"></a>
## Problems

<a name="nodereplacer-is-a-hand-written-parallel-ast-model"></a>
### NodeReplacer Is A Hand-Written Parallel AST Model

`NodeReplacer` has to know:

- which child properties each node type has,
- the concrete implementation type of each child,
- whether the child is required or optional,
- whether the child is stored in a `NodeList`,
- which fallback visitor should handle inherited children.

This information is already present in the AST node declarations and consumed by the AST generator. Keeping a hand-written copy makes the code fragile. Adding a new AST child or changing a child from required to optional can silently leave replacement behavior incomplete.

<a name="null-means-too-much"></a>
### Null Means Too Much

Allowing `NodeReplacer.replace(oldNode, null)` makes replacement and removal share one API. This is convenient at the call site, but it weakens the contract:

- For a required child slot, `null` is invalid.
- For an optional child slot, `null` means clear the slot.
- For a list element, `null` could mean either invalid replacement or removal from the list.

These are distinct operations and should be represented distinctly. In particular, removal from a nullable single-child slot should not imply that AST lists are resizable.

<a name="parent-links-do-not-describe-the-parent-slot"></a>
### Parent Links Do Not Describe The Parent Slot

A parent pointer answers only one question:

```text
What node owns this node?
```

Replacement needs a more precise answer:

```text
Where inside the parent is this node stored?
```

Today, answering the second question requires a visitor over the parent. This is the core design weakness. The child already knows its parent, but not the slot that makes it a child.

<a name="child-lists-have-different-semantics"></a>
### Child Lists Have Different Semantics

`NodeList` currently cannot be resized through the public list API. Replacement of an existing element is supported, but insertion and removal are not.

This is a different contract from optional single-child slots. A design that models both as "replace with nullable child" blurs an important invariant.

<a name="temporary-child-stealing-is-easy-to-mis-handle"></a>
### Temporary Child Stealing Is Easy To Mis-handle

Resolver rewrites often construct a replacement node from children of the old node. Constructing the replacement can update the children's parent pointers before the old node itself is replaced. `NodeReplacer.replace` therefore accepts an optional `parent` argument to recover the old parent.

This works, but it exposes an implementation timing issue at every rewrite site that needs it. The API should make this pattern explicit.

<a name="design-goals"></a>
## Design Goals

- Make the parent-child relation exact: parent plus child slot.
- Generate structural editing behavior from AST child metadata.
- Remove the hand-written `NodeReplacer` visitor.
- Keep replacement and removal as separate operations.
- Make required, optional, and list children have explicit edit contracts.
- Keep public AST getters and setters source-compatible where practical.
- Preserve the existing invariant that child setters update parent links.
- Make failed edits produce precise diagnostics.
- Support resolver rewrites that build replacement nodes from old children.

<a name="non-goals"></a>
## Non-Goals

- Do not redesign parser recovery or token ownership.
- Do not require public analyzer clients to use slot objects directly.
- Do not make `NodeList` resizable as part of this refactoring.
- Do not make AST edits persistent, transactional, or undoable.
- Do not preserve `NodeReplacer` as the primary implementation indefinitely.

<a name="proposed-model"></a>
## Proposed Model

<a name="parent-slot"></a>
### Parent Slot

Each `AstNodeImpl` stores the child slot that currently contains it:

```text
sealed class AstNodeImpl implements AstNode {
  ChildSlot<AstNodeImpl>? _parentSlot;

  ChildSlot<AstNodeImpl>? get parentSlot => _parentSlot;

  @override
  AstNodeImpl? get parent => _parentSlot?.parent;
}
```

A `ChildSlot` is a storage position in a parent node that holds, or can hold, one child node. The slot is a parent-side concept, but the child stores a pointer back to the slot that contains it.

```text
sealed interface class ChildSlot<C extends AstNodeImpl> {
  AstNodeImpl get parent;
  String get name;

  C? get child;

  void replace(C newChild);
}

sealed interface class RemovableChildSlot<C extends AstNodeImpl>
    implements ChildSlot<C> {
  void remove();
}
```

There are three broad slot shapes:

- a required single-child slot,
- an optional single-child slot,
- a list-element slot.

The important property is that editing starts from the old child:

```text
oldChild.parentSlot!.replace(newChild);
```

APIs that start from a child, such as `replaceWith` and `removeFromParent`, first verify that the node is still the current child of its recorded slot. The slot method itself edits the slot's current child.

No visitor is needed to rediscover where the child is stored.

<a name="bound-child-slots"></a>
### Bound Child Slots

A bound child slot is an object owned by a specific AST node instance. It is not just a static descriptor. The slot knows its parent and stores the current child.

Generated node classes expose ordinary AST getters and setters, but internally delegate to these slots.

This model intentionally spends memory on slot objects. The tradeoff is that the AST tree stores a self-describing structural model instead of requiring external visitors to reconstruct it.

<a name="required-child-slots"></a>
### Required Child Slots

A required child slot always contains a child and does not support removal:

```text
final class RequiredChildSlot<C extends AstNodeImpl>
    implements ChildSlot<C> {
  @override
  final AstNodeImpl parent;

  @override
  final String name;

  late C _child;

  RequiredChildSlot(this.parent, this.name);

  C get child => _child;

  set child(C newChild) {
    _detachOldChild();
    _child = newChild;
    newChild._parentSlot = this;
  }

  @override
  void replace(C newChild) {
    child = newChild;
  }
}
```

This makes the required-child invariant local and explicit. A failed removal is a missing capability of the slot type, not a failed cast somewhere in a visitor.

<a name="optional-child-slots"></a>
### Optional Child Slots

An optional child slot may contain no child and supports removal:

```text
final class OptionalChildSlot<C extends AstNodeImpl>
    implements ChildSlot<C>, RemovableChildSlot<C> {
  @override
  final AstNodeImpl parent;

  @override
  final String name;

  C? _child;

  OptionalChildSlot(this.parent, this.name);

  C? get child => _child;

  set child(C? newChild) {
    _detachOldChild();
    _child = newChild;
    newChild?._parentSlot = this;
  }

  @override
  void replace(C newChild) {
    child = newChild;
  }

  @override
  void remove() {
    child = null;
  }
}
```

The nullability of the child is represented in the slot type. The replacement operation remains non-null.

<a name="node-list-slots"></a>
### Node List Slots

Lists should also be attached through a generated parent-side slot. This slot represents the list-valued child property, not a specific list element:

```text
final class ChildListSlot<C extends AstNodeImpl> {
  final AstNodeImpl parent;
  final String name;
  final NodeListImpl<C> list;
}
```

Each list element receives its own slot that points to the list property and its current index:

```text
final class ListElementSlot<C extends AstNodeImpl> implements ChildSlot<C> {
  final ChildListSlot<C> listSlot;
  int index;

  @override
  AstNodeImpl get parent => listSlot.parent;

  @override
  String get name => listSlot.name;

  @override
  C get child => listSlot.list[index];

  @override
  void replace(C newChild) {
    listSlot.list[index] = newChild;
  }
}
```

`NodeListImpl.operator []=` updates the old element and new element parent slots. If list removal is not supported, `ListElementSlot` simply does not implement `RemovableChildSlot`. If a future refactoring makes some generated lists resizable, that policy can be represented by a separate removable list element slot without changing optional single-child semantics.

<a name="generated-node-code"></a>
### Generated Node Code

A generated node class keeps its public getters and setters, but stores children in slots:

```text
final class ClassTypeAliasImpl extends NamedCompilationUnitMemberImpl
    implements ClassTypeAlias {
  late final OptionalChildSlot<TypeParameterListImpl> typeParametersSlot =
      OptionalChildSlot(this, 'typeParameters');

  late final RequiredChildSlot<NamedTypeImpl> superclassSlot =
      RequiredChildSlot(this, 'superclass');

  @override
  TypeParameterListImpl? get typeParameters => typeParametersSlot.child;

  set typeParameters(TypeParameterListImpl? value) {
    typeParametersSlot.child = value;
  }

  @override
  NamedTypeImpl get superclass => superclassSlot.child;

  set superclass(NamedTypeImpl value) {
    superclassSlot.child = value;
  }
}
```

The generated constructor initializes slots instead of assigning fields directly:

```text
ClassTypeAliasImpl({
  required TypeParameterListImpl? typeParameters,
  required NamedTypeImpl superclass,
}) {
  typeParametersSlot.child = typeParameters;
  superclassSlot.child = superclass;
}
```

The concrete generated shape can be optimized, but the design invariant should stay the same: every attached child points back to the exact slot that contains it.

<a name="structural-editing"></a>
## Structural Editing

<a name="replacement"></a>
### Replacement

Replacement is non-null:

```text
extension AstNodeEdit on AstNodeImpl {
  void replaceWith(AstNodeImpl newNode) {
    var slot = parentSlot;
    if (slot == null) {
      throw ArgumentError('Node has no parent slot.');
    }
    if (!identical(slot.child, this)) {
      throw StateError('Node is not the current child of its recorded slot.');
    }
    slot.replace(newNode);
  }
}
```

This operation is valid for:

- required child slots,
- optional child slots with a current child,
- list element slots.

It is invalid when:

- the old child is detached,
- the old child is no longer the current child of its slot,
- the new child has the wrong generated slot type.

<a name="removal"></a>
### Removal

Removal is explicit:

```text
extension AstNodeEdit on AstNodeImpl {
  void removeFromParent() {
    var slot = parentSlot;
    if (slot == null) {
      throw ArgumentError('Node has no parent slot.');
    }
    if (!identical(slot.child, this)) {
      throw StateError('Node is not the current child of its recorded slot.');
    }
    if (slot is RemovableChildSlot<AstNodeImpl>) {
      slot.remove();
    } else {
      throw UnsupportedError('Cannot remove required child.');
    }
  }
}
```

Removal is valid for optional child slots. It is invalid for required child slots. It is also invalid for list element slots unless list removal is explicitly introduced as a separate generated list policy.

This avoids an API where `null` has to mean different things for different storage kinds.

<a name="captured-edits"></a>
### Captured Edits

Some rewrites build the replacement node from children of the old node. That can change child parent slots before the old node is replaced. The current workaround is to pass the old parent explicitly to `NodeReplacer.replace`.

The slot model should expose this pattern directly:

```text
final class AstEdit {
  final AstNodeImpl oldNode;
  final ChildSlot<AstNodeImpl> oldParentSlot;

  AstEdit.capture(this.oldNode) : oldParentSlot = oldNode.parentSlot!;

  void replaceWith(AstNodeImpl newNode) {
    _checkStillCurrent();
    oldParentSlot.replace(newNode);
  }

  void remove() {
    _checkStillCurrent();
    var slot = oldParentSlot;
    if (slot is RemovableChildSlot<AstNodeImpl>) {
      slot.remove();
    } else {
      throw UnsupportedError('Cannot remove required child.');
    }
  }

  void _checkStillCurrent() {
    if (!identical(oldParentSlot.child, oldNode)) {
      throw StateError('Old node is no longer the current child of its captured slot.');
    }
  }
}
```

Rewrite code would use:

```text
var edit = AstEdit.capture(node);
var replacement = buildReplacementUsingChildrenFrom(node);
edit.replaceWith(replacement);
```

The captured edit is the explicit authority for the old parent slot. This removes the need for an optional `parent` argument whose correctness depends on caller discipline.

<a name="generated-child-model"></a>
## Generated Child Model

The generated child slot model should become the single source of truth for operations that currently duplicate child metadata:

- `childEntities`
- `namedChildEntities`
- `visitChildren`
- `visitChildrenWithHooks`
- `_childContainingRange`
- `isInValueExpressionSlot`
- token linking traversal
- structural replacement
- structural removal

This does not require all of these operations to interpret a dynamic slot list at runtime. The generator can still emit direct code for performance. The important design constraint is that the generated operations should be derived from one child model, not maintained separately.

For example, a generated node could expose an internal ordered slot list:

```text
Iterable<ChildSlot> get _childSlots;
```

or the generator could emit direct implementations while using the same metadata source. The second approach is likely faster and less disruptive, but the first approach is useful as the conceptual model.

<a name="compatibility-layer"></a>
## Compatibility Layer

`NodeReplacer` can remain temporarily as a compatibility wrapper:

```text
class NodeReplacer {
  static bool replace(AstNode oldNode, AstNode newNode) {
    (oldNode as AstNodeImpl).replaceWith(newNode as AstNodeImpl);
    return true;
  }

  static bool remove(AstNode oldNode) {
    (oldNode as AstNodeImpl).removeFromParent();
    return true;
  }
}
```

The existing nullable replacement API should not be the long-term API:

```text
NodeReplacer.replace(oldNode, null)
```

If kept during migration, it should delegate to `remove` and be marked as a temporary compatibility shim. New code should call replacement and removal separately.

<a name="migration-plan"></a>
## Migration Plan

1. Add generated slot classes without changing public AST APIs.

2. Generate slots for a small set of nodes while keeping existing fields for the rest of the AST. This proves the storage model and constructor/setter shape.

3. Convert `NodeListImpl` to attach list element slots, but keep list resizing unsupported.

4. Add `AstNodeImpl.replaceWith`, `AstNodeImpl.removeFromParent`, and `AstEdit.capture`.

5. Convert resolver rewrites to use `replaceWith` or captured edits.

6. Generate child replacement/removal support for every generated node class.

7. Replace the body of `NodeReplacer` with a compatibility wrapper.

8. Remove `NodeReplacer.replace(oldNode, null)` from production call sites.

9. Delete the hand-written `NodeReplacer` visitor once tests and migration shims are no longer needed.

<a name="open-questions"></a>
## Open Questions

- Should slot objects be allocated per child property, or should we use smaller encoded parent-slot values plus generated static slot descriptors?

- Should public AST implementation classes expose `typeParametersSlot` for internal clients, or should slots remain entirely private implementation details?

- Should a child keep a direct `AstNodeImpl? parent` cache in addition to `ChildSlot<AstNodeImpl>? parentSlot` for faster parent access?

- Should assigning a child that already has a parent slot automatically detach it from the old slot, or should that be an error unless done through an explicit move operation?

- Should detached old children have their parent slot cleared during replacement? This is cleaner, but could expose existing code that expects old nodes to keep stale parent pointers after rewrites.

- Should any `NodeList` support removal, or should list edits remain outside the AST structural editing API?

- How should generated slot errors be reported so they are useful in tests while not bloating production error messages?

- How much of `childEntities`, visitor dispatch, and token linking should use runtime slot iteration versus direct generated code?
