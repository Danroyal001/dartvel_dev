# Reference Identity Refactoring

This document explores a possible refactoring of analyzer summary references.
The goal is to keep the stable identity properties of `Reference` while removing
the current reliance on arbitrary string paths such as:

```text
package:test/a.dart::@class::A::@method::foo
package:test/a.dart::@class::A::@def::1
```

The current representation is effective, but it makes implementation details
such as kind container names and duplicate declaration containers visible to
callers. This makes the model harder to reason about, especially for duplicate
declarations.

## Table of Contents

- [Current Model](#current-model)
- [Problems](#problems)
  - [String Path Encoding Leaks](#string-path-encoding-leaks)
  - [Duplicate Declarations Are Onerous](#duplicate-declarations-are-onerous)
  - [The Tree Looks More General Than It Is](#the-tree-looks-more-general-than-it-is)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Model](#proposed-model)
  - [Reference](#reference)
  - [Kinds](#kinds)
  - [Reference Names](#reference-names)
  - [Reference Name Allocation](#reference-name-allocation)
- [Canonicalization](#canonicalization)
- [Performance Considerations](#performance-considerations)
- [Serialization](#serialization)
- [Formal Parameters And Type Parameters](#formal-parameters-and-type-parameters)
- [Library Fragments](#library-fragments)
- [Import Prefixes](#import-prefixes)
- [Debug Representation](#debug-representation)
- [Migration Plan](#migration-plan)
- [Open Questions](#open-questions)

## Current Model

`Reference` is currently a prefix tree. Each node has:

- a parent reference,
- a string name,
- optional children,
- an optional element,
- temporary serialization state.

The tree is used for more than diagnostics:

- It provides stable cross-bundle identity using library URI, kind strings, and
  declaration names.
- It lets summary readers reconstruct canonical references from serialized
  parent/name rows.
- It supports lazy loading by walking from a member reference to the enclosing
  declaration and loading that declaration's members.
- It gives synthesized elements, such as inherited interface members, a stable
  cache key.

The important property is not the printable path itself. The important property
is that unrelated edits do not perturb the identity of existing declarations.
For example, if a reused bundle references `package:test/a.dart::@class::A2`,
adding a new class `A1` to that library must not change the identity of `A2`.

## Problems

### String Path Encoding Leaks

Callers construct references with string segments such as `@class`, `@method`,
`@getter`, and `@setter`. These strings are really kind tags, not user names.
Using them as tree nodes exposes the storage encoding at every call site.

### Duplicate Declarations Are Onerous

Duplicate declarations are represented by inserting an intermediate `@def`
container:

```text
@class::A::@def::0
@class::A::@def::1
```

This means:

- `Reference.name` is not always the declaration name.
- Callers sometimes need `elementName`.
- Walking to the enclosing declaration requires skipping fake containers.
- Tests and diagnostics expose an implementation detail as if it were identity.

### The Tree Looks More General Than It Is

Most declaration references have only two semantic layers inside a library:

```text
library -> top-level declaration -> member declaration
```

The arbitrary-depth tree mostly exists because kind tags and duplicate
containers are represented as normal nodes.

## Design Goals

- Preserve stable, name-based identity for normal operation and incremental
  reuse.
- Keep references usable without requiring library manifests.
- Keep lazy loading simple.
- Hide duplicate declaration mechanics behind typed APIs.
- Avoid putting formal parameters and type parameters into durable reference
  identity.
- Keep a path-like debug representation available for tests and diagnostics.

## Non-Goals

- Do not make library manifests mandatory for reference identity.
- Do not replace references with purely opaque per-bundle integers.
- Do not redesign fine-grained requirements in this refactoring.
- Do not change public element identity semantics.

## Proposed Model

Use a typed `Reference` hierarchy instead of arbitrary string path segments.

The conceptual identity for declarations is:

```text
libraryUri
topLevelKind + topLevelReferenceName
memberKind + memberReferenceName
```

`referenceName` is an internal identity string. It is usually the declaration
name, but source-order declaration building may generate a different string for
unnamed or duplicate declarations. The reference store consumes these strings;
it does not allocate them.

For prefixes, if they remain in the reference model temporarily, a separate
shape is needed because prefix elements are tied to a library fragment/import
context:

```text
libraryUri
fragmentUri
prefixReferenceName
```

### Reference

`Reference` remains the runtime handle stored on elements. Instead of storing a
separate `ReferenceKey` object, make the kind-specific identity part of the
reference object itself.

```text
sealed class Reference {
  ElementImpl? element;

  /// The enclosing declaration used for lazy loading, or `null` for references
  /// that cannot trigger member loading.
  Reference? get enclosingDeclaration;
}

final class LibraryReference extends Reference {
  final Uri uri;

  LibraryReference(this.uri);

  @override
  Reference? get enclosingDeclaration => null;
}

sealed class TopLevelReference extends Reference {
  LibraryReference get library;
  String get referenceName;

  /// Compact tag used for enum-indexed storage and serialization.
  TopLevelReferenceKind get topLevelKind;

  @override
  Reference? get enclosingDeclaration => library;
}

sealed class InstanceReference extends TopLevelReference {
  /// Lazily created member storage for this instance declaration.
  List<Map<String, MemberReference>?>? _membersByKind;
}

sealed class InterfaceReference extends InstanceReference {}

final class ClassReference extends InterfaceReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  ClassReference({required this.library, required this.referenceName});

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.class_;
}

final class EnumReference extends InterfaceReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  EnumReference({required this.library, required this.referenceName});

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.enum_;
}

final class MixinReference extends InterfaceReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  MixinReference({required this.library, required this.referenceName});

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.mixin_;
}

final class ExtensionTypeReference extends InterfaceReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  ExtensionTypeReference({required this.library, required this.referenceName});

  @override
  TopLevelReferenceKind get topLevelKind =>
      TopLevelReferenceKind.extensionType;
}

final class ExtensionReference extends InstanceReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  ExtensionReference({required this.library, required this.referenceName});

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.extension_;
}

final class TypeAliasReference extends TopLevelReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  TypeAliasReference({required this.library, required this.referenceName});

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.typeAlias;
}

final class TopLevelFunctionReference extends TopLevelReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  TopLevelFunctionReference({
    required this.library,
    required this.referenceName,
  });

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.function;
}

final class TopLevelVariableReference extends TopLevelReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  TopLevelVariableReference({
    required this.library,
    required this.referenceName,
  });

  @override
  TopLevelReferenceKind get topLevelKind =>
      TopLevelReferenceKind.topLevelVariable;
}

final class TopLevelGetterReference extends TopLevelReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  TopLevelGetterReference({
    required this.library,
    required this.referenceName,
  });

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.getter;
}

final class TopLevelSetterReference extends TopLevelReference {
  @override
  final LibraryReference library;

  @override
  final String referenceName;

  TopLevelSetterReference({
    required this.library,
    required this.referenceName,
  });

  @override
  TopLevelReferenceKind get topLevelKind => TopLevelReferenceKind.setter;
}

sealed class MemberReference extends Reference {
  InstanceReference get enclosing;
  String get referenceName;

  /// Compact tag used for enum-indexed storage and serialization.
  MemberReferenceKind get memberKind;

  @override
  Reference? get enclosingDeclaration => enclosing;
}

final class ConstructorReference extends MemberReference {
  @override
  final InterfaceReference enclosing;

  @override
  final String referenceName;

  ConstructorReference({required this.enclosing, required this.referenceName});

  @override
  MemberReferenceKind get memberKind => MemberReferenceKind.constructor;
}

final class FieldReference extends MemberReference {
  @override
  final InstanceReference enclosing;

  @override
  final String referenceName;

  FieldReference({required this.enclosing, required this.referenceName});

  @override
  MemberReferenceKind get memberKind => MemberReferenceKind.field;
}

final class GetterReference extends MemberReference {
  @override
  final InstanceReference enclosing;

  @override
  final String referenceName;

  GetterReference({required this.enclosing, required this.referenceName});

  @override
  MemberReferenceKind get memberKind => MemberReferenceKind.getter;
}

final class SetterReference extends MemberReference {
  @override
  final InstanceReference enclosing;

  @override
  final String referenceName;

  SetterReference({required this.enclosing, required this.referenceName});

  @override
  MemberReferenceKind get memberKind => MemberReferenceKind.setter;
}

final class MethodReference extends MemberReference {
  @override
  final InstanceReference enclosing;

  @override
  final String referenceName;

  MethodReference({required this.enclosing, required this.referenceName});

  @override
  MemberReferenceKind get memberKind => MemberReferenceKind.method;
}

/// Transitional if prefixes remain in reference serialization.
final class PrefixReference extends Reference {
  final LibraryReference library;
  final Uri fragmentUri;
  final String referenceName;

  PrefixReference({
    required this.library,
    required this.fragmentUri,
    required this.referenceName,
  });

  @override
  Reference? get enclosingDeclaration => library;
}

final class SpecialReference extends Reference {
  final SpecialReferenceKind kind;

  SpecialReference(this.kind);

  @override
  Reference? get enclosingDeclaration => null;
}
```

The hierarchy keeps impossible states out of the model and avoids allocating a
separate key object for each reference. Serialization and debug printing can use
exhaustive `switch` statements over the subclasses.

The hierarchy mirrors the element model at the level that matters for
references. `InstanceReference` covers declarations that can contain members.
`InterfaceReference` is narrower and can be used for constructors. The kind
enums still exist because they are useful as compact tags for list indexing and
binary serialization; they are not the whole type model.

The tradeoff is migration and dispatch cost: current code assumes a single
`Reference` class with `parent` and `name` fields. A hierarchy introduces more
subclass checks or pattern matches in generic code. This should be comparable
to the current string/kind checks, but it should be measured if reference-heavy
paths regress.

### Kinds

```text
enum TopLevelReferenceKind {
  class_,
  enum_,
  extension_,
  extensionType,
  mixin_,
  typeAlias,
  function,
  getter,
  setter,
  topLevelVariable,
}

enum MemberReferenceKind {
  constructor,
  field,
  getter,
  setter,
  method,
}

enum SpecialReferenceKind {
  dynamic_,
  never_,
}
```

### Reference Names

Use raw `String` keys for names. This keeps the hot storage path cheap and
matches the current implementation.

The string is a `referenceName`, not necessarily the user-visible declaration
name. The source-order declaration builder owns the policy for generating these
names:

- named non-duplicate declarations usually use the declaration name unchanged;
- unnamed declarations use a deterministic generated name;
- duplicate declarations use a deterministic generated suffix.

This allocation must be local to the library or enclosing declaration traversal.
Do not move it to a static/global `Reference` allocator; that would make
reference identity depend on unrelated library build order and would make tests
less stable.

For example, a library-local allocator might produce:

```text
class A        -> A
duplicate A    -> A#1
unnamed ext #0 -> #0
unnamed ext #1 -> #1
```

The exact spelling is a compatibility choice. The important invariant is that
generated names cannot collide with user declaration names for the same kind and
container. Callers that need a user-visible name should use the element or
fragment name, not `referenceName`.

### Reference Name Allocation

Reference name allocation should be explicit and local to declaration traversal.
The reference store should not invent names; it should only canonicalize the
names it is given.

Reference name uniqueness is scoped by parent reference and kind:

```text
(parentReference, kind, baseName) -> next duplicate index
(parentReference) -> next unnamed index
```

For top-level declarations, the parent is the library reference. For members,
the parent is the enclosing class, enum, mixin, extension, or extension type
reference. This matters because duplicate member names are independent in
different enclosing declarations.

One possible shape:

```text
final class ReferenceNameAllocator {
  final Map<Reference, _ParentReferenceNames> _byParent = Map.identity();

  String declareTopLevel({
    required LibraryReference library,
    required TopLevelReferenceKind kind,
    required String? name,
  }) {
    return (_byParent[library] ??= _ParentReferenceNames(
      kindCount: TopLevelReferenceKind.values.length,
    )).declare(kindIndex: kind.index, name: name);
  }

  String declareMember({
    required InstanceReference enclosing,
    required MemberReferenceKind kind,
    required String? name,
  }) {
    return (_byParent[enclosing] ??= _ParentReferenceNames(
      kindCount: MemberReferenceKind.values.length,
    )).declare(kindIndex: kind.index, name: name);
  }
}

final class _ParentReferenceNames {
  final List<Map<String, int>?> _nextDuplicateIndexByKind;
  int _nextUnnamedIndex = 0;

  _ParentReferenceNames({required int kindCount})
    : _nextDuplicateIndexByKind = List.filled(kindCount, null);

  String declare({
    required int kindIndex,
    required String? name,
  }) {
    var baseName = name ?? _unnamedName(_nextUnnamedIndex++);
    var byName = _nextDuplicateIndexByKind[kindIndex] ??= {};
    var duplicateIndex = byName[baseName] ?? 0;
    byName[baseName] = duplicateIndex + 1;

    if (duplicateIndex == 0) {
      return baseName;
    }
    return _duplicateName(baseName, duplicateIndex);
  }

  String _unnamedName(int index) => '#$index';

  String _duplicateName(String baseName, int index) => '$baseName#$index';
}
```

The allocator is intentionally not static. Static/global counters would make
reference names depend on unrelated libraries and build order, which would make
tests and serialized references less stable.

## Canonicalization

The current `parent.getChild(name)` operation should be replaced with typed
lookup operations. The store owns canonical references.

```text
final class ReferenceStore {
  final Map<Uri, LibraryReferenceData> _libraries = {};

  LibraryReference library(Uri uri) {
    return (_libraries[uri] ??= LibraryReferenceData(uri)).reference;
  }

  TopLevelReference declareTopLevel({
    required LibraryReference library,
    required TopLevelReferenceKind kind,
    required String referenceName,
  }) {
    return _dataFor(library).declareTopLevel(
      kind: kind,
      referenceName: referenceName,
    );
  }

  TopLevelReference topLevel({
    required LibraryReference library,
    required TopLevelReferenceKind kind,
    required String referenceName,
  }) {
    return _dataFor(library).topLevel(
      kind: kind,
      referenceName: referenceName,
    );
  }

  MemberReference declareMember({
    required InstanceReference enclosing,
    required MemberReferenceKind kind,
    required String referenceName,
  }) {
    return enclosing.declareMember(
      kind: kind,
      referenceName: referenceName,
    );
  }

  MemberReference member({
    required InstanceReference enclosing,
    required MemberReferenceKind kind,
    required String referenceName,
  }) {
    return enclosing.member(
      kind: kind,
      referenceName: referenceName,
    );
  }
}
```

Duplicate and unnamed declaration handling happens before the store is called.
The store maps already-normalized `referenceName` strings to `Reference`
objects. This keeps storage simple: one map entry points directly to one
reference.

```text
final class LibraryReferenceData {
  final LibraryReference reference;
  final List<Map<String, TopLevelReference>?> _topLevelsByKind;

  TopLevelReference declareTopLevel({
    required TopLevelReferenceKind kind,
    required String referenceName,
  }) {
    var byName = _topLevelMap(kind);
    var existing = byName[referenceName];

    if (existing == null) {
      var result = _createTopLevel(kind, referenceName);
      byName[referenceName] = result;
      return result;
    }

    throw StateError('Duplicate reference name: $kind $referenceName');
  }

  TopLevelReference topLevel({
    required TopLevelReferenceKind kind,
    required String referenceName,
  }) {
    var byName = _topLevelMap(kind);
    return byName[referenceName] ??= _createTopLevel(kind, referenceName);
  }

  Map<String, TopLevelReference> _topLevelMap(TopLevelReferenceKind kind) {
    return _topLevelsByKind[kind.index] ??= {};
  }
}
```

Member-reference storage uses the same shape under each enclosing declaration.
Every `InstanceReference` owns a lazily created member table:

```text
// Methods on InstanceReference.
extension InstanceReferenceMembers on InstanceReference {
  MemberReference declareMember({
    required MemberReferenceKind kind,
    required String referenceName,
  }) {
    var byName = _memberMap(kind);
    var existing = byName[referenceName];

    if (existing == null) {
      var result = _createMember(kind, referenceName);
      byName[referenceName] = result;
      return result;
    }

    throw StateError('Duplicate member reference name: $kind $referenceName');
  }

  MemberReference member({
    required MemberReferenceKind kind,
    required String referenceName,
  }) {
    var byName = _memberMap(kind);
    return byName[referenceName] ??= _createMember(kind, referenceName);
  }

  Map<String, MemberReference> _memberMap(MemberReferenceKind kind) {
    var byKind = _membersByKind ??= List.filled(
      MemberReferenceKind.values.length,
      null,
    );
    return byKind[kind.index] ??= {};
  }
}
```

For example:

```text
libraryData._topLevelsByKind[class_]["A"] -> Reference(class A)

classA._membersByKind[method]["foo"] -> Reference(A.foo)
classA._membersByKind[getter]["bar"] -> Reference(A.bar getter)
```

When building from source, `ElementBuilder` declares a member under the enclosing
declaration:

```text
referenceStore.declareMember(
  enclosing: classElement.reference,
  kind: MemberReferenceKind.method,
  referenceName: referenceNameFor(fragment.name),
);
```

When reading a bundle, the member row names its parent reference:

```text
var container = referenceOfIndex(row.parentIndex);
container as InstanceReference;
return container.member(
  kind: row.memberKind,
  referenceName: row.referenceName,
);
```

## Performance Considerations

The typed reference hierarchy and helper APIs describe the conceptual model.
They should not force allocation of additional composite key objects in hot
paths.

The current string-tree implementation is reasonably efficient:

- it uses strings as map keys,
- it lazily allocates child maps instead of building composite key objects,
- it reconstructs each serialized reference index at most once per bundle
  reader.

The proposed model should preserve these properties. In particular, storage
should not use composite lookup keys that allocate for every lookup. The hot
storage layout should be indexed first by enum kind, then by raw string
`referenceName`:

```text
final class LibraryReferenceData {
  final List<Map<String, TopLevelReference>?> _topLevelsByKind;

  Map<String, TopLevelReference> _topLevelMap(TopLevelReferenceKind kind) {
    return _topLevelsByKind[kind.index] ??= {};
  }
}
```

With this shape, a top-level lookup hashes only the `referenceName`, and a
member lookup does the same under the enclosing declaration. The value is a
direct `TopLevelReference` or `MemberReference`.

This should compare well with the current tree:

```text
current member path:
  library -> @class -> A -> @method -> foo

typed member lookup:
  library -> (class, A) -> (method, foo)
```

The typed model removes kind-container references such as `@class` and
`@method`, so there are fewer reference objects and fewer lookup steps. The
main risk is replacing string-tree walking with object-heavy key hashing; the
implementation should avoid that.

Unnamed and duplicate declarations should be handled by deterministic
`referenceName` allocation before lookup. This keeps the map key as a raw
`String`, avoiding wrapper allocation and custom hashing.

## Serialization

The bundle can still use a dense reference table, but table rows should describe
typed references rather than parent/name string segments.

```text
enum _SerializedReferenceTag {
  root,
  library,
  topLevel,
  member,
  prefix,
  special,
}

final class SerializedReferenceRow {
  final _SerializedReferenceTag tag;
  final int parentIndex;
  final int kind;
  final int nameIndex;
  final int uriIndex;
}
```

Examples:

```text
library package:test/a.dart
  tag = library
  uri = package:test/a.dart

class A
  tag = topLevel
  parent = library
  kind = class
  referenceName = A

method A.foo
  tag = member
  parent = class A
  kind = method
  referenceName = foo

duplicate class A
  tag = topLevel
  parent = library
  kind = class
  referenceName = A#1

prefix p in a fragment
  tag = prefix
  parent = library
  fragmentUri = package:test/a.dart
  referenceName = p
```

Reading a reference becomes a typed canonicalization operation:

```text
Reference referenceOfIndex(int index) {
  var row = rows[index];

  return switch (row.tag) {
    _SerializedReferenceTag.library => store.library(row.uri),
    _SerializedReferenceTag.topLevel => store.topLevel(
      library: referenceOfIndex(row.parentIndex) as LibraryReference,
      kind: row.topLevelKind,
      referenceName: row.referenceName,
    ),
    _SerializedReferenceTag.member => store.member(
      enclosing: referenceOfIndex(row.parentIndex) as InstanceReference,
      kind: row.memberKind,
      referenceName: row.referenceName,
    ),
    _SerializedReferenceTag.prefix => store.prefix(
      library: referenceOfIndex(row.parentIndex) as LibraryReference,
      fragmentUri: row.fragmentUri,
      referenceName: row.referenceName,
    ),
    _SerializedReferenceTag.special => store.special(row.specialKind),
    _SerializedReferenceTag.root => store.root,
  };
}
```

## Formal Parameters And Type Parameters

Formal parameters should not be durable `Reference` objects. This matches the
current implementation.

When a formal parameter element is serialized as an element reference, it is
encoded as:

```text
enclosing executable element + parameter index
```

Type parameters are also local to the currently serialized scope. They should
continue to use local indexing rather than durable reference identity.

The `@formalParameter` paths seen in element text tests are fabricated by test
printers for readability and are not part of the actual `Reference` tree.

## Library Fragments

Library fragment URIs should not be part of ordinary declaration identity.
Top-level declarations from parts are still declarations of the library, so the
stable identity is:

```text
libraryUri + topLevelKind + topLevelReferenceName
```

The current exception is `PrefixElementImpl`. Prefix identity is tied to the
fragment/import context, so prefixes need their own key shape:

```text
libraryUri + fragmentUri + prefixReferenceName
```

If prefixes are later moved to an import-table based representation, they could
be removed from the general reference model.

## Import Prefixes

Import prefixes probably do not need durable `Reference` identity.

A prefix is local to the library fragment/import context that declares it. It is
not exported, cannot be referenced from another library, and is not a declaration
target in the same sense as a class, getter, setter, or method. External bundles
should not need to preserve a stable cross-library reference to a prefix.

The current reference path for prefixes serves local reconstruction and sharing:

```text
libraryUri + @fragment + fragmentUri + @prefix2 + prefixName
```

This gives multiple import directives with the same prefix in the same fragment
the same `PrefixElementImpl`, and it lets serialized AST nodes such as
`ImportPrefixReference` reuse generic element serialization. That is useful, but
it is not the same requirement as durable declaration identity.

The important invariant is local object identity:

```text
node.element == import.prefix?.element
```

Scopes, search, indexing, and resolvers can rely on this identity without the
prefix element being represented by a global declaration reference.

A cleaner model would give prefixes a library-local or fragment-local identity,
for example:

```text
library fragment + prefix referenceName
```

or:

```text
library fragment + prefix table index
```

With such a model, AST serialization would need a prefix-specific encoding
instead of routing prefix elements through generic `ElementImpl` reference
serialization:

```text
ElementTag.prefix
  fragment index
  prefix index
```

This would let declaration `Reference` focus on externally stable declaration
identity, while prefixes remain a local scope construct.

## Debug Representation

The printable form should become a diagnostic view, not the storage model.
For compatibility during migration, it can initially print something close to
the current format:

```text
package:test/a.dart::@class::A
package:test/a.dart::@class::A::@method::foo
package:test/a.dart::@class::A#1
```

The duplicate marker should not be a fake child path. A compact suffix such as
`#1` makes it clearer that the generated reference name is part of declaration
identity, while the element or fragment still owns the user-visible name.

## Migration Plan

1. Introduce typed enums for top-level and member reference kinds.
2. Add typed construction APIs while keeping the existing tree storage.
   Existing calls such as `getChild('@method').addChild(name)` should move to
   APIs such as `declareMember(kind: method, name: name)`.
3. Move duplicate and unnamed declaration naming behind deterministic,
   source-order reference-name allocation.
4. Update `elementName`, `isSetter`, `isPrefix`, and `parentNotContainer`
   call sites to use typed properties.
5. Change bundle reference rows from parent/name strings to typed rows.
6. Move prefix elements to a local prefix table or prefix-specific serialized
   identity, instead of using declaration references.
7. Replace the internal storage with enum-indexed maps keyed by raw
   `String referenceName`.
8. Update element text printers to use the new debug representation.

The early steps reduce API complexity without committing to the final storage
format. The later steps can be done once callers no longer depend on path
segments.

## Open Questions

- What generated-name spelling should be used for unnamed and duplicate
  declarations, and how much test/bundle churn is acceptable?
- Should `dynamic` and `Never` be represented as special references, or as
  synthetic top-level declarations in `dart:core`?
- Should prefixes be keyed by fragment URI and name, or by a compact prefix
  table index?
- How much backward compatibility is needed for existing element text tests?
- Can writer-local serialization indexes be removed from `Reference` at the
  same time, using an identity map in the bundle writer instead?
