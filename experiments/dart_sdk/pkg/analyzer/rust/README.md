# `analyzer` in Rust

A file-by-file Rust port of this package (`pkg/analyzer`), so far the part
that parses a file into a syntax tree: the AST node classes, the
`AstBuilder` listener that builds them from the parser's events, and
`parseString`; and what the tree offers once built: parent pointers, the
V2 visitors, `toSource`, `NodeLocator2` and the texts of the diagnostics;
and the start of semantic analysis: the element model built from a
library's declarations (see [The element model](#the-element-model)). Each file under `src/` ports the Dart library at the same path
under `../lib`, keeps its structure and names, and names that library in its
first line. Files that are not ports (`lib.rs`, `mod.rs`, the test harness)
say so in their first line. It follows the conventions of
`pkg/_fe_analyzer_shared/rust` (see its README), whose scanner and parser it
builds on.

## The oracle

| | Upstream | Port |
|---|---|---|
| Dump | `oracle/ast_dump.dart` | `src/bin/ast_dump.rs` |
| Input | every `.dart` file under the corpus roots | the same |
| Output | `<out>/<root>/<path>.ast` | the same, byte for byte |

Each file is read as UTF-8 and parsed with
`parseString(content: source, throwIfDiagnostics: false)`. A dump is the tree
the `AstBuilder` built (the "V2" view, what `_childEntities2` walks): every
node in pre-order as `<child name>: <runtime type> <offset>+<length>`, then
its named child entities in order, tokens as `<name>: TYPE@offset"lexeme"`
(`~` when synthetic), node and token lists as their length and then their
elements as `<name>[i]`. Values the builder computes that are not tokens (the
values of string, integer and double literals, a comment reference's
`isSynthetic`, and a doc comment's `hasNodoc`, code blocks, doc directives
and doc imports) follow the node's line as `~` lines. The parse diagnostics
end the dump, in the order reported, as
`diagnostic <uniqueName>@<offset>+<length>`.

The API oracle is the same pair of programs with `--api`, writing
`<out>/<root>/<path>.api`: what the public API returns on that tree. It
numbers the nodes in the order of the tree dump and writes the unit's
`toSource()`; then, for every node, the `AstVisitor2` method `accept2`
calls, the number of its `parent2` and its `toSource()` (quoted up to 60
code units, an FNV-1a hash of the code units beyond); the nodes that a
`RecursiveAstVisitor2`, a `UnifyingAstVisitor2` and a `SimpleAstVisitor2`
delegate of a `DelegatingAstVisitor2` visit from the unit, in order (the
recording visitors are generated on both sides); `NodeLocator2` at 32
offsets and ranges drawn from a generator seeded by the file's length; and
every diagnostic with its message and correction. Anything that throws
upstream (panics here) is written as `!throw`. The format is described at
`dumpApi` in `oracle/ast_dump.dart`.

`oracle/extract_test_inputs.dart` turns the analyzer's own AST tests (and
its parser recovery tests) into a corpus: each test file, and every string
literal in it as a file of its own, with the test's local code strings
substituted where a literal interpolates them, so the oracle checks what
those tests parse.

## Running it

The analyzer imports packages that are not in this checkout (`collection`,
`convert`, `crypto`, `glob`, `package_config`, `path`, `pub_semver`,
`source_span`, `watcher`, `yaml` and, through them, `async`, `file`,
`string_scanner`, `term_glyph` and `typed_data`): the SDK gets them through
DEPS. The test writes a package config that takes them from a pub cache, at
the versions listed in `tests/ast_oracle.rs`.

From the SDK root, with a Dart SDK at least as new as this package's
`environment: sdk:` lower bound:

```sh
DART=/path/to/dart cargo test --release -p analyzer --test ast_oracle
```

runs both oracles (`syntax_trees_are_identical_to_upstream` and
`api_results_are_identical_to_upstream`) on the inputs of the analyzer's AST
tests, `pkg/_fe_analyzer_shared/lib`, `pkg/analyzer/lib` and
`tests/language`. `AST_CORPUS` names other roots, `AST_WORK` moves the
scratch directory (default `target/ast_oracle`) and `PUB_CACHE` the pub
cache. Dumps that match are deleted; dumps that differ are kept, and the test
prints the first differing line of each.

## What is ported

| Dart (`../lib/...`) | Rust (`src/...`) |
|---|---|
| `src/dart/ast/ast.dart` (node classes) | `src/dart/ast/ast.rs` (generated, see below), `ast_store.rs` |
| `src/dart/ast/ast.g.dart` (`AstVisitor2`) | `src/dart/ast/ast_g.rs` (generated) |
| `dart/ast/visitor.dart`, `visitor.g.dart` (the V2 visitors) | `dart/ast/visitor.rs`, `visitor_g.rs` (generated) |
| `src/dart/ast/to_source_visitor.dart` | `src/dart/ast/to_source_visitor.rs` |
| `src/dart/ast/utilities.dart` (`NodeLocator2`) | `src/dart/ast/utilities.rs` |
| `dart/ast/precedence.dart` | `dart/ast/precedence.rs` |
| `src/fasta/ast_builder.dart` | `src/fasta/ast_builder.rs` |
| `src/fasta/doc_comment_builder.dart` | `src/fasta/doc_comment_builder.rs` |
| `src/fasta/error_converter.dart` | `src/fasta/error_converter.rs` |
| `src/dart/scanner/scanner.dart`, `translate_error_token.dart` | `src/dart/scanner/` |
| `src/generated/parser.dart`, `utilities_dart.dart` (`ParameterKind`) | `src/generated/` |
| `dart/analysis/utilities.dart` (`parseString`) | `dart/analysis/utilities.rs` |
| `dart/ast/doc_comment.dart` | `dart/ast/doc_comment.rs` |
| `src/dart/analysis/experiments*.dart`, `dart/analysis/features.dart` | `src/dart/analysis/`, `dart/analysis/features.rs` |
| `src/diagnostic/diagnostic.g.dart`, `diagnostic_code_values.g.dart` | `src/diagnostic/` (generated) |
| `diagnostic/diagnostic.dart`, `error/listener.dart`, `src/error/listener.dart`, `source/line_info.dart`, `dart/element/element.dart` | the parts parsing uses |

`src/` mirrors `../lib`: `src/dart/...` ports `lib/dart/...` and
`src/src/...` ports `lib/src/...`. The AstBuilder also needed
`stack_listener.dart`, `quote.dart` and `null_value.dart` of
`_fe_analyzer_shared`, and the messages need its `formatList`
(`base/errors.dart`), which are ported in that crate.

`lib/dart/ast/ast.dart` only exports the node interfaces of
`src/dart/ast/ast.dart`. Their members are read from the structs (a field
for each constructor parameter, which is what most getters return), and the
members of `AstNode` from `Ast`, the view of a parse's node and token
stores: `beginToken`, `endToken`, `offset`, `end`, `length`, `parent2`,
`root2`, `thisOrAncestorMatching2`, `namedChildEntities2`, `accept2`,
`visitChildren2`, `toSource` and an expression's `precedence`.

Not ported:

- The V1 view of the tree. Upstream builds the V2 nodes and projects the
  V1 nodes from them when they are asked for (`V1Projection`: 43 V1-only
  classes, and projections in most V2 classes); a node class that exists
  only in one view throws when visited by the other view's visitor. So
  everything that walks the V1 view waits for it: `AstVisitor`,
  `GeneralizingAstVisitor` (which has no V2 counterpart),
  `RecursiveAstVisitor`, `SimpleAstVisitor`, `ThrowingAstVisitor`,
  `UnifyingAstVisitor`, `DelegatingAstVisitor`, `BreadthFirstVisitor`
  (which has no V2 counterpart either), `NodeLocator`, `parent`, `root`
  and `childEntities`.
- `TimedAstVisitor2`, `ScopedNameFinder2` (which reads elements),
  `visitChildrenWithHooks`, `replaceChild`, `removeChild` and
  `_childContainingRange2`, and the fields resolution fills in. Upstream no
  longer has `AstComparator` or `NodeReplacer`.
- The visit methods of `ToSourceVisitor` for the classes only resolution
  builds (`ConstructorTearOffImpl`, `TypeLiteralImpl`, ...: 17 classes) do
  nothing, as no such node can be in the store.

## Conventions

The conventions of `pkg/_fe_analyzer_shared/rust` apply. In addition:

- Nodes live in an `AstStore` addressed by 32-bit `NodeId`s, as tokens
  live in a `TokenStore`; `NO_NODE` is null. `AstNodeImpl` (upstream's base
  class) is an enum with a variant per node class, holding a struct with
  the class's constructor parameters as fields; a struct larger than 24
  bytes is boxed, so that a node takes 32 bytes. `x is XImpl` is
  `is_x_impl()`, `x as XImpl` is `as_x_impl()`, and `NodeListImpl` is a
  `Vec<NodeId>`.
- The store keeps every node's `parent2` beside the nodes. Upstream's
  constructors make a node the parent of their children
  (`_becomeParentOf2`); `AstStore::add` does it for the fields the
  generated `for_each_child_node` names, which `generate_ast.dart`
  translates from each constructor's body (`invalidNodes`, for one, is not
  a child). Where the AstBuilder sets a field upstream does it through a
  setter, which sets the parent; the port calls `become_parent_of2`.
- `ast.rs` is generated by `oracle/generate_ast.dart`, which reads
  `ast.dart` with the analyzer, as upstream generates the `@generated`
  members of each class: the fields, `beginToken`, `endToken`,
  `_childEntities2`, `accept2`, `visitChildren2`, `precedence` and the
  children a constructor adopts, translated from upstream's bodies; the
  few written by hand upstream are translated by hand in the generator.
  Members of node classes that the AstBuilder needs and that are written
  by hand upstream follow the "Written by hand" line at the end of
  `ast.rs`, which the generator keeps. Only the classes the AstBuilder and
  the DocCommentBuilder construct are generated: run it with
  `../lib/src/fasta/ast_builder.dart` and `doc_comment_builder.dart` after
  the two paths.
- A visitor class `XAstVisitor2<R>` is a trait `XAstVisitor2: AstVisitor2`
  whose methods default to upstream's bodies, which are also the functions
  of a module `x_ast_visitor2` so that an override can call the method it
  overrides (`super.visitBlock(node)` is
  `recursive_ast_visitor2::visit_block(self, ast, node)`). A type
  implementing it becomes an `AstVisitor2` with the macro of the same name
  (`recursive_ast_visitor2!(Counter, ())`). A visit method takes the `Ast`
  and the node's id and returns `Option<R>`. `oracle/generate_visitors.dart`
  generates them, and the recording visitors of the API oracle, from
  `ast.g.dart` and `visitor.g.dart`.
- `toSource` writes UTF-16 code units, as a Dart string holds them.
- `oracle/generate_codes.dart` (with `dart:mirrors`) writes the analyzer's
  diagnostic codes, with the templates of their messages, and the parser
  codes' `sharedCode` and `pseudoSharedCode`;
  `oracle/generate_experiments.dart` writes the feature table. Run them
  again when the messages or experiments change.
- The AstBuilder's stack holds `Value`s (a variant for each kind of object
  upstream pushes), and a cast is a `pop_*` helper that panics where the
  cast would throw.
- A parser listener may change the token store (`&mut TokenStore`), which
  the AstBuilder needs for `parser.rewriter`. A doc import is parsed by a
  nested parser and builder that borrow the file's token store, node store
  and diagnostic reporter for the time of the parse; the tokens scanned for
  a comment reference or a doc import are appended to the file's store.
- A parser `Message` carries its `arguments` map with each value as the
  string it prints as, which is what the analyzer formats its messages
  from (`formatList`); a `Diagnostic` holds the formatted message and
  correction, and two diagnostics are equal when their codes, offsets,
  lengths and messages are, as upstream.

## Tests

`tests/ast_oracle.rs` runs both oracles. `tests/utilities_test.rs` ports
`NodeLocator2Test` of `test/src/dart/ast/utilities_test.dart`, whose
name-end cases the oracle's random offsets rarely reach.
`tests/visitor_test.rs` tests what the oracle does not see:
`ThrowingAstVisitor2`'s exception, the order in which
`DelegatingAstVisitor2` calls its delegates, and an override stopping a
`RecursiveAstVisitor2`. The other AST tests upstream check `toSource`,
parents and locations of the code they parse, which the oracle checks on
their inputs.

Each check was seen to fail on a broken port: the API oracle on
`pkg/analyzer/lib` when a `toSource` method dropped a space (94 of 449
files), when `AstStore::add` set no parents (449) or a builder setter did
not (29), when a binary operator lost its precedence (273),
`RecursiveAstVisitor2.visitBlock` did not descend (381), or `NodeLocator2`
compared offsets with `<` for `<=` (326); on `tests/language`, when
`formatList` dropped its arguments (181 of 4563) or the converter passed
the wrong one (96). The unit tests fail when `NodeLocator2` ignores name
ends, `DelegatingAstVisitor2` visits the children before the delegates, or
`ThrowingAstVisitor2` names the wrong method.

## Results

Measured 2026-11-05 on an 8-core AMD EPYC host shared with other work,
Dart 3.13.4, rustc 1.99.0, by `../../_fe_analyzer_shared/rust/tool/measure_rows.sh`:
11 processes a side, Dart AOT and Rust alternating, user-space instructions
from `perf stat`, peak RSS from `/usr/bin/time` (method and the scanner and
parser rows in `pkg/_fe_analyzer_shared/rust/README.md`, Measurements).
Dart AOT is `oracle/ast_dump.dart` built with `dart compile exe`.

Both oracles match on the default corpus (5152 files, 28,328,001 bytes,
and 2221 inputs of the analyzer's AST tests). The tree oracle also matches
on corpora the port was not written against: `pkg/front_end/
parser_testcases` (905 files, mostly recovery), `pkg/front_end/testcases`
(4029), `tests/lib` and `tests/corelib` (1590), the other `tests/`
directories (2182), `pkg/analysis_server/lib`, `pkg/linter/lib`,
`pkg/front_end/lib` and `sdk/lib` (1910), and the tests of `pkg/analyzer`,
`pkg/analysis_server` and `pkg/linter` (2377): 12,993 more files, no
differences. The API oracle matches on `pkg/compiler/lib` (278 files),
`pkg/front_end/parser_testcases`, `pkg/front_end/testcases` and every
`tests/` directory but `language` (3772): 8984 more files, no differences.

`--bench=N` parses the corpus N times (`parseString`: scanning and building
the tree; the sources are read once, before) and drops each result.
`--retain` parses it once and keeps every result, printing the resident set
size before and after: the memory the parsed corpus (tokens, tree and
diagnostics) takes, with only the sources loaded before. `--api --bench=N`
parses the corpus once and times `toSource` of every unit N times
(177,688,640 code units a round).

Fastest round is the fastest of the 11 processes, median round the median
of their medians; instructions (the whole process) and peak RSS are
medians.

| `parseString`, 10 rounds | Instructions | Fastest round | Median round | Peak RSS |
|---|---|---|---|---|
| Dart AOT | 84.38 G | 2620.6 ms | 3638.9 ms | 126.4 MiB |
| Rust | **56.42 G** | **1545.4 ms** | **1858.5 ms** | **93.2 MiB** |

| `toSource` of every unit, 10 rounds | Instructions | Fastest round | Median round | Peak RSS |
|---|---|---|---|---|
| Dart AOT | 45.04 G | 871.3 ms | 1152.3 ms | 698.6 MiB |
| Rust | **16.42 G** | **268.7 ms** | **370.5 ms** | **485.0 MiB** |

The peak of the `toSource` runs is the parsed corpus they hold. Dart's peak
RSS on `parseString` ranged 125.0–260.5 MiB across its processes; Rust's
varied by under 1.5% on every row.

| Whole corpus kept (`--retain`) | Instructions | Sources loaded | After parsing | Parsed corpus | Peak RSS |
|---|---|---|---|---|---|
| Dart AOT | 21.48 G | 78.8 MiB | 641.0 MiB | 562.1 MiB | 640.4 MiB |
| Rust | **7.88 G** | **59.2 MiB** | **483.0 MiB** | **423.8 MiB** | **482.7 MiB** |

The Rust corpus is 3,845,602 nodes at 32 bytes each (165.7 MiB of node
store, lists included, plus the boxed large nodes), their parents (4 bytes
each, 14.7 MiB) and 5,201,677 tokens at 28 bytes each (246.7 MiB of token
store with its spare capacity). On 2026-10-30, when `TokenData` took 92
bytes, the token store was 458.0 MiB and the parsed corpus 536.9 MiB against
Dart's 518.4 MiB; the 28-byte token (`43e9c5127` in the scanner port) is
what turned that loss into a win.

Earlier measurements (2026-10-30, 4-core Xeon, Dart 3.13.3, rustc 1.97.0,
one process each): `parseString` 1179.2 / 1363.5 ms, 120.3 MiB (Dart AOT)
against 669.0 / 803.2 ms, 92.4 MiB (Rust); `toSource` 446.6 / 475.1 ms,
646.4 MiB against 151.2 / 176.8 ms, 597.2 MiB.

## The element model

### Slice boundary

Upstream builds elements while linking a library cycle
(`summary2/link.dart`, `Linker._buildOutlines`). The port covers the steps
up to and including the export scopes, and the synthetic constructors,
which need nothing more:

1. `LibraryBuilder.build`: the library element (its name from the
   `library` directive) and the defining unit's fragment.
2. `_computeLibraryScopes`: `buildElements` (the directives of every unit,
   following `part` directives into the parts they include;
   `FragmentBuilder`, a fragment for every declaration; `ElementBuilder`,
   which joins fragments into elements and creates the variables, getters
   and setters a field, a variable or an accessor induces; `dynamic` and
   `Never` in `dart:core`), then `_buildExportScopes`.
3. `_buildClassSyntheticConstructors` and `_buildEnumSyntheticConstructors`.
4. `_resolveTypes`: the scopes type annotations are resolved in
   (`dart/element/scope.dart`), `ReferenceResolver`, the type builders
   (`named_type_builder.dart`, function and record type builders),
   `TypeAliasSelfReferenceFinder`, `DefaultTypesBuilder` and
   `TypesBuilder` (declared types, supertypes, mixins and interfaces,
   mixin inference through `matchSupertypeConstraints`,
   `breakInterfaceCycles`, `buildEnumChildren`), with the type system they
   need: subtyping, NORM, NNBD_TOP_MERGE, the class hierarchy, least and
   greatest closures, upper and lower bounds, the type constraint gatherer
   and `GenericInferrer`.
5. `_performTopLevelInference`, the part representation types need (see
   `summary2/top_level_inference.rs`): an untyped declaring formal
   parameter with no default value gets `Object?`, a variable with nothing
   to infer from `dynamic`. Inference from an initializer or a default
   value (`AstResolver`) and override inference (`InstanceMemberInferrer`)
   are not ported; the oracle writes those types as `implicit`, and
   override inference never changes an extension type's field.
6. `buildExtensionTypes`: representation types that depend on each other
   become `InvalidType` (the erasure of an acyclic representation is not
   computed; nothing reads it yet).

and, from `dart/resolver/scope.dart`, the namespace of each import. The
files, their URIs and their kinds (library or part, `part of` checks) come
from `dart/analysis/file_state.dart`, with the SDK's library map read from
its `libraries.dart` (`dart/sdk/sdk.dart`) and the package config
(`context/packages.dart`), as `AnalysisContextCollection` sets them up.

The steps between `_resolveTypes` and `buildExtensionTypes` that the
declared types do not read (`_computeHasNonFinalField`, constant fields,
field formals, field promotability, `SuperConstructorResolver`) and every
step after it are not ported (see [Not ported yet](#not-ported-yet)).

### The oracle

| | Upstream | Port |
|---|---|---|
| Dump | `oracle/element_dump.dart` | `src/bin/element_dump/main.rs` |
| Input | every library among the `.dart` files under the corpus roots | the same |
| Output | `<out>/<root>/<path>.elements` | the same, byte for byte |

The oracle asks the analyzer's own API for each file's library
(`AnalysisContextCollectionImpl`, then `session.getLibraryByUri` of the
file's URI: the library is linked from declarations, bodies are not
resolved) and writes: the library's URI, name and name range; each unit
with its imports, exports and part includes (keyword offset, the runtime
class of the `DirectiveUri` and what it names, combinators with offsets,
an import's prefix, and the names in an import's namespace); every
element by kind (`<ElementKind> <name>`), each of its fragments with its
unit, `firstTokenOffset`, `nameOffset` and the flags `flagsForTesting`
reports set, and its children (type parameters, fields, getters, setters,
constructors, methods, formal parameters with their kind, field/super
formal class, private name and default value); and the export namespace.
A name in a namespace is followed by the kind, library and offsets of the
element it names. Flags computed later (`isPromotable`), the constructors
of mixin applications (which need supertypes) and the default values super
formal parameters inherit (which need the super constructor) are left out.

`--types` adds the declared types (`getDisplayString()` of bounds,
supertypes, mixins, interfaces, superclass constraints, extended and
aliased types, return types and variable and parameter types; `implicit`
where inference decides), and each extension type's `representationType`,
which is the one inferred type the dump reads (`element.representation.type`
after linking: what top-level inference and `buildExtensionTypes` leave).
`declared_types_are_identical_to_upstream` compares them.

### Running it

```sh
DART=/path/to/dart cargo test --release -p analyzer --test element_oracle
```

`tests/element_oracle.rs` writes a package config (this checkout's
`_fe_analyzer_shared`, `analyzer` and `meta`, and the analyzer's
dependencies from the pub cache, as `tests/ast_oracle.rs` does), lays out
an SDK directory whose `lib` is this checkout's `sdk/lib` and whose
`version` comes from `tools/VERSION`, and runs both programs on
`pkg/_fe_analyzer_shared/lib` and `pkg/analyzer/lib`. `ELEMENT_CORPUS`
names other roots and `ELEMENT_WORK` moves the scratch directory (default
`target/element_oracle`).

### What is ported

| Dart (`../lib/...`) | Rust (`src/...`) |
|---|---|
| `src/dart/element/element.dart` (the element and fragment classes, flags) | `src/dart/element/element.rs` |
| `src/summary2/element_builder.dart` (`FragmentBuilder`, `ElementBuilder`) | `src/summary2/element_builder.rs` |
| `src/summary2/library_builder.dart` (`build`, `buildElements`, directives, export scope, synthetic constructors) | `src/summary2/library_builder.rs` |
| `src/summary2/link.dart` (the steps above) | `src/summary2/link.rs` |
| `src/summary2/export.dart`, `combinator.dart` | `src/summary2/export.rs` |
| `src/summary2/not_serializable_nodes.dart` | `src/summary2/not_serializable_nodes.rs` |
| `src/dart/ast/invokes_super_self.dart` | `src/dart/ast/invokes_super_self.rs` |
| `src/dart/resolver/scope.dart` (`Namespace`, `NamespaceBuilder`) | `src/dart/resolver/scope.rs` |
| `src/dart/analysis/file_state.dart` (files, URIs, unlinked directives, kinds) | `src/dart/analysis/file_state.rs` |
| `src/dart/sdk/sdk.dart`, `src/generated/sdk.dart` (library map) | `src/dart/sdk/sdk.rs` |
| `src/context/packages.dart` | `src/context/packages.rs` |
| `src/utilities/uri_cache.dart`, `_fe_analyzer_shared`'s `resolve_relative_uri.dart` (with `dart:core`'s `Uri.resolveUri`) | `src/utilities/uri_cache.rs` |
| `src/dart/element/type.dart`, `display_string_builder.dart`, `type_algebra.dart` (substitution) | `src/dart/element/type.rs`, `display_string_builder.rs`, `type_algebra.rs` |
| `src/dart/element/scope.dart` | `src/dart/element/scope.rs` |
| `src/summary2/reference_resolver.dart`, `type_builder.dart`, `named_type_builder.dart`, `function_type_builder.dart`, `record_type_builder.dart` | `src/summary2/reference_resolver.rs`, `type_builder.rs` |
| `src/summary2/type_alias.dart`, `variance_builder.dart`, `default_types_builder.dart`, `types_builder.dart`, `interface_cycles.dart` | `src/summary2/` (same names) |
| `src/summary2/top_level_inference.dart` (`TopLevelInference`, `_InitializerInference`; see above for what is not ported) | `src/summary2/top_level_inference.rs` |
| `src/summary2/extension_type.dart` (`buildExtensionTypes`, but the erasure) | `src/summary2/extension_type.rs` |
| `src/dart/element/subtype.dart`, `normalize.dart`, `top_merge.dart`, `class_hierarchy.dart`, `least_greatest_closure.dart`, `least_upper_bound.dart`, `greatest_lower_bound.dart`, `type_schema_elimination.dart`, `type_constraint_gatherer.dart`, `generic_inferrer.dart`, parts of `type_system.dart` | `src/dart/element/` (same names) |
| `_fe_analyzer_shared`'s `util/dependency_walker.dart`, `Variance` | `src/fe_analyzer_shared/` |

### Conventions

- Fragments and elements live in an `ElementStore` addressed by 32-bit
  ids (`NO_FRAGMENT`, `NO_ELEMENT` are null), as nodes live in an
  `AstStore`. A fragment class is a `FragmentKind`, an element class an
  `ElementKind`; `LibraryElementImpl` and `LibraryFragmentImpl` (a unit)
  are separate tables. The `_FragmentStorageFlag` bits are the bits of
  `FragmentImpl::flags`, named as `flagsForTesting` names them; the three
  getters upstream overrides (field and super formal parameters are final,
  top-level variables static) are applied where the flags are read.
- The reference tree (`summary2/reference.dart`) gives elements stable
  names in summaries; with no summaries, an export entry's reference is the
  element id it names.
- A fragment gets its offsets from its node when it is created. Upstream
  writes them to the informative data and `InformativeDataApplier` pairs
  each fragment with its node again; the numbers are the same. A default
  value is kept as its source (`defaultValueCode`), as a summary keeps it:
  the marker `_notSerializableExpression` when it is not serializable.
- The linker links what the inputs import or export, transitively, in one
  set of builders, instead of one library cycle after another; export
  scopes come out the same. The parse trees are dropped once a library's
  elements are built.
- Upstream keys a file's unlinked data by its content, not its URI
  (`_unlinkedKey`), so a copy of `dart:core`'s defining file read after
  `dart:core` is taken for `dart:core` and gets no implicit import of it.
  The port does the same (`FileSystemState.unlinked_is_dart_core`), and
  `element_dump` asks for one corpus file at a time, as the oracle does,
  so that files are read in the same order.
- A file is read as UTF-8 without a leading byte order mark. No variable
  is declared, so a configuration (`if (dart.library.io)`) never selects
  its URI, as with the analyzer's default `DeclaredVariables`.

### Tests

`tests/element_oracle.rs` runs the oracle. `tests/element_builder_test.rs`
tests what the oracle's corpus rarely reaches, on files it writes, with an
SDK of its own holding a two-class `dart:core` (so the tests run under
Miri): relative URIs with dot segments and `dart:` parts, the package
config's JSON escapes, an ambiguous export keeping the first element, a
name exported twice, `show` and `hide` applied to setters, accessors of
one name sharing a variable unless repeated, a part of another library and
a part included twice. The type algorithms have tests of their own
(`subtype_test.rs`, `normalize_test.rs`, `bounds_test.rs`,
`closure_test.rs`, `constraint_gatherer_test.rs`,
`generic_inferrer_test.rs`, `promoted_test.rs`, `type_display_test.rs`,
`scope_test.rs`, on the hand-built SDK of `tests/common`).
`tests/top_level_inference_test.rs` checks the representation types of
extension types against what upstream's `element_dump.dart --types` writes
for the same declarations: `Object?` for an untyped declaring parameter,
`InvalidType` for a recovery representation field, for an untyped
representation that `breakInterfaceCycles` reads before inference, and for
representations that depend on each other (with their declaring formal
parameters). Not memoizing the `InvalidType` the `type` getter gives fails
two of its four tests, and the oracle on `tests/language` reported the
declaring parameters (19 rows in 4 libraries) before they were ported;
the representation cycles are in no corpus file, and were found by
comparing the two dumps on a file of such declarations.

Each check was seen to fail on a broken port: with `Combinator.matches`
comparing setter names with their `=`, `ExportScope.export` replacing an
ambiguous entry, `_handleTopLevelGetterFragment` not resetting the
variable of a repeated getter, and `isPartOf` accepting any library name,
four of the six unit tests fail, and the oracle reports 19 of the 567
libraries of its default corpus. While porting, the oracle found the
default values super formal parameters inherit (6 libraries), values that
are not serializable, the language version deciding private named
parameters, the byte order mark (tests/language) and the content-keyed
unlinked data (sdk/lib).

### Results

Measured 2026-10-30 on a 4-core Intel Xeon at 2.10 GHz, Dart 3.13.3, rustc
1.97.0 (rustc 1.101.0-nightly for Miri and coverage).

The element oracle matches on the default corpus (`pkg/_fe_analyzer_shared/lib`
and `pkg/analyzer/lib`: 567 libraries) and on corpora the port was not
written against: `sdk/lib` (216 libraries, the SDK's own files as `file:`
libraries), `pkg/linter/lib`, `pkg/kernel/lib`, `pkg/front_end/lib` and
`pkg/analysis_server/lib` (1454), `pkg/compiler/lib` and `tests/language`
(4784), and `tests/lib`, `tests/corelib`, `tests/ffi` and
`tests/standalone` (2312): 9333 libraries, no differences. (The linking
of each of them also links the `dart:` libraries they import.)
The declared types (`--types`) match too, re-measured 2026-11-03 with Dart
3.13.4 and rustc 1.99.0: 0 differences on the default corpus (567
libraries) and 0 on the held-out roots `tests/language`, `sdk/lib`,
`pkg/front_end/lib`, `pkg/linter/lib` and `pkg/kernel/lib` (5371
libraries, where 19 representation types in 4 libraries differed before
top-level inference was ported); the element oracle stays at 0 on both.
The other held-out roots above were not re-run with `--types`.
`pkg/front_end/testcases` and `parser_testcases` cannot be used: their
`analysis_options.yaml` excludes them, so the oracle finds no context for
them.

`--bench=N` links the default corpus N times, each round from nothing
(files read and parsed again). The Dart round is a new
`AnalysisContextCollectionImpl` and `getLibraryByUri` for every file, the
entry point the analyzer offers: it does more than the port (it also
resolves types, infers, evaluates and writes and reads summaries), so the
comparison favours the port; there is no smaller upstream entry point
that stops after the export scopes.

| Linking the default corpus | Fastest round | Median round | Peak RSS |
|---|---|---|---|
| Dart AOT (5 rounds) | 6458.6 ms | 7535.4 ms | 572.9 MiB |
| Rust (10 rounds) | 687.2 ms | 832.8 ms | 233.6 MiB |

| Cold start (median of 7 runs) | Dart AOT | Rust |
|---|---|---|
| No input | 13 ms | 4 ms |
| A library of 3 files (and `dart:core`, `dart:async`, ... it links) | 557 ms | 93 ms |

| Binary | Unstripped | Stripped |
|---|---|---|
| Dart AOT (`dart compile exe`) | 17,891,328 bytes | (stripping drops the appended snapshot; the executable no longer runs) |
| Rust `element_dump` | 3,107,840 bytes | 2,494,336 bytes |

### Safety

- The crate is `#![forbid(unsafe_code)]`, as are both binaries.
- **Miri** (`MIRIFLAGS=-Zmiri-disable-isolation cargo +nightly miri test
  --test element_builder_test`): the six tests pass with no undefined
  behaviour reported.
- **Coverage** (`-C instrument-coverage -Zcoverage-options=branch`, the
  unit tests and `element_dump` on the default corpus, `sdk/lib`,
  `tests/language` and a small library with every kind of declaration,
  merged; the files of this section only): **90.1% of lines** (2670 of
  2962), **78.4% of branches** (508 of 648), 92.4% of functions. Fully or
  nearly covered: `scope.rs`, `export.rs`, `link.rs`, `library_builder.rs`,
  `invokes_super_self.rs`, `file_state.rs`. The least covered are what
  only augmentations reach (the fragment chains of `element_builder.rs`:
  89.9% of its lines, 73.1% of its branches) and the
  `not_serializable_nodes.rs` visits other than function expressions
  (60%).

### Not ported yet

In the order linking needs them:

- Of `_resolveTypes`: `simply_bounded.dart` (no row of the oracle's
  corpora needs it yet), and the alias
  information of types (`preferTypeAlias` display).
- Of top-level inference: inference from initializers and default values
  (`AstResolver`, which is the resolver of expressions), dependency cycles
  between them, and override inference (`InstanceMemberInferrer`); the
  erasure of representation types (`ExtensionTypeErasure`).
- The other steps: `_computeHasNonFinalField`, constant fields without a
  const constructor, field formals and constructors, field promotability,
  `SuperConstructorResolver`, constant initializers and default values
  (with what super formal parameters inherit), metadata and `@Since`, and
  the flags they set.
- Augmentations beyond chains of fragments that declare the same formal
  and type parameters (`_linkFormalParameters` and `_linkTypeParameters`
  growing the chains with `isOriginOtherFragmentOfEnclosing` parameters),
  and moving an augmentation's enum `values`; the corpora have no
  augmentation that reaches them.
- Language versions from the package config (`languageVersion`): every
  library is parsed at the latest version unless it has a `// @dart`
  comment; doc imports, documentation comments, code ranges and the
  reference tree and summaries (`bundle_writer.dart`, `bundle_reader.dart`).

## Body resolution (in progress)

`oracle/body_dump.dart` asks the real upstream analyzer for
`getResolvedUnit`, then records every V1 expression's static type and every
identifier's resolved element (kind, library URI, declaration offset and
name). `--literals` selects seven context-independent literal kinds:
boolean, double, null, simple strings, adjacent strings, interpolated strings
and symbols. Integers need downward inference (an integer literal may have
static type `double`) and are outside this first slice.

`--operators` selects the expressions whose operator fixes their type
whatever their operands resolve to: `is` and `is!` (`IsExpression`), `!`,
`&&` and `||` (`bool`: upstream's `LogicalNotResolver` and
`_resolveLogicalExpression`), `throw` and `rethrow` (`Never`, the type
provider's `bottomType`), and parentheses whose `unParenthesized` expression
is one of those or a `--literals` literal (the enclosed type).

`src/dart/resolver/type_analyzer.rs` records those slices' types, using
the linked SDK classes through the narrow `src/dart/element/type_provider.rs`.
It does not resolve identifiers other than the `--identifiers` reads, infer
locals or other calls, type integer literals outside the `--integers` sites,
the operands of `--user-operators` invocations and the arguments of
`--members` invocations, type operator invocations or member accesses
outside those selections, perform flow analysis, report diagnostics or rewrite
the AST; those expressions get no type rather than a guessed one, including a
parenthesized one. `body_dump` requires `--literals`, `--operators`,
`--integers`, `--identifiers`, `--user-operators` or `--members` and
refuses full mode rather than presenting missing resolution as a full result.
The full upstream dump is available as a reference for the next slices.

From the SDK root, using the same setup and environment variables as the
element oracle:

```sh
DART=/path/to/dart cargo test --release -p analyzer --test body_oracle -- --nocapture
ELEMENT_CORPUS=pkg/analyzer/rust/tests/body_corpus \
  DART=/path/to/dart cargo test --release -p analyzer --test body_oracle -- --nocapture
```

The test requires nonempty expression output, compares every byte and keeps
mismatches under `ELEMENT_WORK/body-literals` (default
`target/element_oracle/body-literals`). Before implementation the fixture
produced 37 upstream rows and all 3 files differed from Rust's empty output.
The expanded fixture matches all 43 rows across 4 files, including directive
URIs, parts, annotations, defaults, unreachable literals and conditional
imports/exports. Conditional-directive children deliberately remain untyped,
matching upstream's `visitConfiguration`; the default corpus exposed two
differences before that fix. The default corpus now matches 41,283 rows across
589 files (265.66 seconds, 2026-11-06). The held-out roots `tests/language`,
`sdk/lib`, `pkg/front_end/lib`, `pkg/linter/lib` and `pkg/kernel/lib` also
match: 146,712 rows across 5,730 files, zero differences (548.06 seconds).
This is not body-resolution parity or a completed performance gate.

`operator_typed_expressions_match_upstream` runs `--operators` the same way
(mismatches under `ELEMENT_WORK/body-operators`). The fixture
`tests/body_corpus/operators.dart` (operands resolved and unresolved,
initializers, asserts, guards, collection elements, catch clauses, dead
code) produced 52 upstream rows that all differed (`type=-`, same selection)
before the analyzer typed them; it now matches, as does the literal test on
the enlarged fixture (57 rows, 5 files). Measured 2026-11-08: the default
corpus matches 13,036 rows across 589 files (145 seconds), and the held-out
roots above 52,170 rows across 5,730 files (397 seconds), zero differences.

`--integers` selects integer literals whose context type upstream takes from
a declared type annotation, or which have none. Past a `-` whose operand the
literal is (`UnaryOperatorInvocationResolver` passes its context on) and
parentheses, the literal is an expression statement or an interpolation (no
context: `int`); the initializer of a variable declared with a type; the
default value of an optional, typed formal parameter (no function-typed
suffix) of a function, method, constructor, local function or function
expression; a returned expression (`return` or `=>`) of a function, method,
getter, operator or local function declared with a return type, not a
generator; or an element of a list or set literal with one type argument, or
a key or value of a map literal with two, also inside `if` and `for`
elements. Both sides read the selection on the V2 tree (`parent2`); the
port's is `is_declared_context_integer`. `_recordIntegerLiteralType` makes
the literal `double` when `int` is not assignable to the context and
`double` is, which for these contexts is exactly `double`, or `FutureOr<S>`
for such an `S`, at any nullability; in an `async` body the context is
`FutureOr<futureValueType(R)>` (`BodyInferenceContext`), so `Future<double>`
and `FutureOr<double>` return types give `double` and `double` itself gives
`int`.

With `--integers`, `body_dump` links each file's library (the file, the
library its `part of` URI names when that library includes it, or else the
part as a library of its own, as upstream's `kind.library ?? kind.asLibrary`:
`Linker::unit_of_file`) and the analyzer
resolves each annotation where it is written, as `TypeNameResolver` does:
through the unit's `LibraryFragmentScope` (so an explicit `dart:core` import
removes the implicit one, and prefixes work), the type parameter and instance
scopes of the enclosing class, mixin, enum, extension or extension type (a
member named like a type hides it, as upstream's `InstanceScope` does), and
the type parameters, formal parameters, local variables, local functions and
catch parameters of the enclosing executables, which name no type. An alias
is expanded with its type arguments, or the defaults of its type parameters
when it has none. The analyzer only classifies an annotation (`double`,
`Future<S>`, `FutureOr<S>`, other, unknown); it does not build the type.
Without the library (`TypeAnalyzer::new`) an annotated site stays untyped
rather than `int`.

Limits: integer literals in every other context (arguments, operands,
assignments, inferred or inherited declaration types, closures' inferred
return types, untyped collection literals, record fields, switch
expressions, ...) are not selected and get no type. A part with a `part of`
name directive is analyzed against the library that includes it
(`PartOfNameFileKind.library`, added with the `--identifiers` slice: of the
known libraries of that name, after reading the part's directory when none
is known, the one with the smallest path that includes the part).

The fixtures `tests/body_corpus/integers.dart` (with a part),
`integers_prefixed_core.dart` (which imports `dart:core` with a prefix) and
`integers_orphan_part.dart` (a part its library does not include) cover each
site, aliases (generic, bounded, raw, ignoring their argument),
`FutureOr` and `Future` at both nullabilities, `async` and `sync*` bodies,
shadowing by type parameters, members, parameters and locals, and sites
outside the selection: 102 upstream rows, which all differed (`type=-`, same
selection) before the analyzer typed them, and now match. The held-out
`sdk/lib` found the orphan parts (104 of its files, `part of "dart:io"` and
the like, which the SDK's own libraries include from elsewhere); the
fixture's orphan part reproduced it before `asLibrary` was ported. Measured
2026-11-08: the default corpus matches 1,096 rows across 589 files (141
seconds), and the held-out roots above 10,879 rows across 5,730 files
(380 seconds), zero differences. The literal and operator tests still match
on the default corpus and on the enlarged fixture (72 and 53 rows, 9 files).

`--identifiers` selects reads of declared variables: a local variable of a
declaration with a type annotation, a for-in loop variable with one, or a
regular formal parameter with a type annotation or a function-typed suffix
(not a field or super formal parameter), read by an unqualified name outside
documentation comments. Its row adds the declaration's element kind
(`LOCAL_VARIABLE` or `PARAMETER`) and name offset after the type, so the
selection checks name resolution as well as the type. Flow analysis may
promote a variable, and is not ported, so a variable is left out entirely
when any read of it can promote it, or when it is written or initialized and
its declared type is not non-nullable (`int? x = 1;` promotes `x` to `int`
upstream; a default value does not promote). A read can promote when, past
enclosing parentheses, the token after it is `!`, `?.`, `?..`, `is`, `as`,
`==` or `!=`, `?` followed by `[`, or `)` followed by `?.` or `?..` (the
argument of an extension override); when the token before it is `==`, `!=` or
`?` (a null-aware element); when it is an argument of `identical`; or when it
is the scrutinee of a switch, an `if`-`case`, a pattern
variable declaration or a pattern assignment. Writes are assignments,
compound assignments, `++` and `--`, for-in loops over a name, assigned
variable patterns, initializers and for-in loop variables. Both sides decide
this the same way (the oracle's `DeclaredVariableReads` on the resolved V2
tree, the port's `TypeAnalyzer` on the parsed one); it is deliberately
conservative, a selection rather than flow analysis.

For it the analyzer resolves names in the local scopes `ScopeAnalyzer` and
`ScopeContext` build: a block declares all of its local variables, local
functions and pattern variables for the whole block (`_defineLocalElements`),
as does a branch or loop body that is not a block; a loop's declared
variables are in scope in the whole loop, a for-in variable after its
iterable; formal parameters are in scope in the body (`FormalParameterScope`,
without field and super formal parameters) and, all of them, in a
constructor's initializers (`ConstructorInitializerScope`); type parameters
of executables and function types; catch parameters; the pattern variables
of an `if`-`case` in its guard and then branch, of a switch expression case,
of a switch statement case in its guard, and of a case group, joined, in the
group's statements. With wildcard variables `_` declares nothing. The
first declaration of a name in a scope wins, and untyped variables, local
functions, type parameters and catch and pattern variables hide what they
shadow. The integer slice's annotations now resolve in the same scopes,
which corrects the two limits it had (pattern variables did not hide names;
a local hid a name only from its declaration on); its oracle results did not
change. A declared type is the linked element's type for the formal
parameters of declarations, and otherwise built from the annotation where it
is written (`NamedTypeResolver`: an interface type with its type arguments,
the defaults of its type parameters when there are none, `InvalidType` for
each when their number is wrong, or for a type parameter given arguments; an alias instantiated; a type parameter,
`dynamic`, `Never`, `void`; else `InvalidType`; function, generic function
and record types, and function-typed suffixes). Type parameters declared in
bodies become elements of the linked store, so the analyzer now takes the
store mutably. The parse-time V1 projection gives the called name of `f()` a
`MethodInvocation` whose `methodName` has no origin, where upstream's
resolver rewrites the call of a variable into a
`FunctionExpressionInvocation`; `body_dump` maps that name to the parsed name
it was projected from (`called_name_source`). The oracle selects a V1
identifier only when its offset and length are the read's: upstream's
projection of an anonymous method puts a synthetic identifier at a read's
offset. Primary constructors' parameters are in the initializer scope in
their initializers and in the initializers of instance fields that are not
late, and in the `PrimaryParameterScope` in their body, which leaves out
declaring (`var` or `final`) parameters: there the name is the field.

The held-out roots found what the default corpus did not: the extension
override, null-aware element and `identical` positions, annotations, the
synthetic identifiers, primary constructors, `part of` name parts (6 files,
which were not analyzed at all), `InvalidType` for a wrong number of type
arguments, and raw types whose defaults need the variance of a typedef's
type parameters. That variance was not computed by the linker, so a
contravariant occurrence (`Function(X)` through `typedef F<X> =
Function(X)`) stayed `dynamic` where `DefaultTypesBuilder` puts `Never`;
`src/summary2/variance_builder.rs` now ports `VarianceBuilder`, which runs
before the default types as upstream's does (and also gives class, enum and
mixin type parameters the variance an `in`, `out` or `inout` keyword states).
The fixture reproduces each of them.

Limits: reads of untyped or inferred variables (`var`, `final x = ...`,
untyped and initializing parameters), of pattern and catch variables, of
fields and top-level variables, and every variable flow analysis might
promote are not selected and get no type; class type parameters are not made
`InvalidType` in static members; an annotation's name is not a selected read
(upstream gives its identifier no static type).

The fixture `tests/body_corpus/identifiers.dart` covers parameters of
functions, methods, constructors (body and initializer list), setters,
operators, local functions and function expressions, optional and named
parameters, function-typed suffixes, generic methods and local functions,
aliases, a prefixed import, records, `Function`, `dynamic`, unresolved types,
loop variables, closures, calls of variables (also `f().g`), shadowing by
blocks, untyped locals, local functions, type parameters, catch and pattern
variables, wildcards, references before a declaration in an inner block, and
each promoting position and write, and what the held-out roots found (a
named library and its `part of` name part, a raw type through a
contravariant typedef, a wrong number of type arguments, `identical`, a
null-aware map key, an extension override, an annotation, a primary
constructor with a declaring parameter): 73 upstream rows in 3 files. The
first 64 matched once names were resolved; the held-out cases differed (the
part's reads missing, `dynamic` for `Never` and for `InvalidType`, declared
types where upstream promotes, the declaring parameter selected in the body)
until fixed. The default corpus first differed in 4 files, all calls of a variable
followed by a member (`keyOf1(a).compareTo(...)`), whose projection gives the
inner call the whole chain as its origin; the fixture now has that shape.
Measured 2026-11-08: the default corpus matches 50,276 rows across 589 files
(141 seconds), and the held-out roots above 108,816 rows across 5,730
files (337 seconds), zero differences. The literal, operator and integer
tests still match on the default corpus (41,283, 13,036 and 1,096 rows), and
the element oracle, with `VarianceBuilder` and `part of` name parts, still
matches its default corpus (567 libraries, elements and declared types).

`--user-operators` selects operator invocations: `==` and `!=`, the
user-definable binary operators (`BinaryOperatorInvocation` with a
`binaryOperator`), unary `-` and `~` (`UnaryOperatorInvocation`) and `[]`
without `?` (`ReceiverIndexExpression`), whose receiver and argument are
known and whose operator resolves as far as the port resolves it. Past
parentheses, a known operand is a `--literals` literal, an `--operators`
expression, an `--identifiers` read, a selected invocation, or an integer
literal whose context type is known: as a receiver it has none; as an
argument it has the operator's parameter type (`==` and `!=` give none),
which `refineNumericInvocationContext` replaces for `+`, `-`, `*` and `%` on
a receiver whose type is a subtype of `num?` by `int`, `double` or `num`
from the invocation's own context, which must then be known in turn; an
operand of unary minus has the minus's context; and the declared contexts
of `--integers` (expression statements, interpolations, typed variables,
typed defaults, returns of typed functions, explicitly typed collection
elements) are known. The operator resolves when the interface of the
receiver's static type has a method of that name with declared return and
parameter types, or when the receiver is `dynamic`, invalid or `Never`
(`dynamic`, `InvalidType` and `Never` results, by upstream's rules for each
kind). A receiver that may be null (but for `==` and `!=`, which make it
non-nullable for the lookup) and a member the interface does not have are
left out: there upstream looks for an extension, which is not ported. The
selection also writes the integer literals that are operands of a selected
invocation (past parentheses) and parentheses around either. Both sides
decide it the same way, the oracle's `OperatorInvocations` from the
resolved tree, the port from what it types, so a lookup that finds a
member upstream does not, or the reverse, shows as a row missing on one
side.

`src/dart/resolver/binary_expression_resolver.rs` types them after every
other expression of the earlier slices (an operand may be a read):
`_resolveEqual` (`==` is `bool`, or `Never` on a `Never` receiver; `!=` is
the return type of the `==` method found on the receiver made non-nullable,
`Object`'s when the interface has none), `_resolveUserDefinable` with
`_resolveRightOperand` and `_resolveUserDefinableType` (the method's return
type, refined by `refineBinaryExpressionType`: `int + int` is `int`, a
`double` on either side makes `double`, otherwise `num`), unary operators
(`UnaryOperatorInvocationResolver`: `dynamic`, invalid and `Never` operands
are themselves, another receiver bounded by `dynamic` or `Never` finds no
method and is `InvalidType`), and index expressions
(`resolveReceiverIndexExpression`: the method's return type, `InvalidType`
on `void` or when the method does not take one parameter). The integer
literal operands get `_recordIntegerLiteralType` in their context (an
`async` return's context is `FutureOr<futureValueType(R)>`). Members are
found by `src/dart/element/inheritance_manager3.rs`, a port of what
`getMember3` returns for a method: declared, else the class chain (the
superclass with each mixin over it) and the other superinterfaces, merged
into one member when their signatures agree and otherwise the most specific
one, with the receiver's type arguments substituted. `type_system.rs` adds
`resolveToBound`, `isDynamicBounded` and `isInvalidBounded`.

Limits (extensions were added by the extension slice below): `super`
receivers, members whose types override inference would infer (an operator without a declared
return or parameter type, which upstream infers from what it overrides),
combined member signatures where no candidate is most specific, `?[]`,
cascades, compound assignments and increments, implicit call tear-offs and
generic function instantiation of an operator's value, integer literals in
other contexts (call arguments, untyped variables, closures' inferred return
types), and every invocation an operand of which is not typed. The
identifiers slice leaves out every variable read next to `==` or `!=` (they
can promote), so equality with a variable operand is not selected. The
`--members` slice below reuses the lookup, and the extension slice extends
both.

The fixture `tests/body_corpus/user_operators.dart` covers each operator on
`int`, `double`, `num` and `String`, literal and parenthesized operands,
chains, the numeric refinements of results and argument contexts (declared
`double`, `num`, `int`, `Object`, `dynamic`, `FutureOr<double>` and nullable
contexts, `async`, collection, default, getter and field sites, unknown
contexts), user classes, generic classes and a subclass of an instantiation,
an inherited member, a mixin's, the most specific of two interface members,
enums, extension types (with and without `implements`), members with
implicit types, `dynamic`, `Never`, `void`, nullable and type parameter
receivers (bounded by `num`, a class, `dynamic`, `Never`, a nullable type,
unbounded), function and record receivers, extension operators and
`null` and `throw` operands: with the other fixtures, 416 upstream rows across 13 files, which match. Unit
tests in `type_analyzer_test.rs` (on a hand-built `dart:core` with
operators) failed before the port typed invocations (all `-`), but the one
that checks what must stay untyped. Measured 2026-11-08: the default corpus
matches 1,359 rows across 589 files (246 seconds), and the held-out roots
13,605 rows across 5,730 files (429 seconds), zero differences. The
literal, operator, integer and identifier tests still match on the default
corpus (41,283, 13,036, 1,096 and 50,276 rows) and on the held-out roots
(146,712, 52,170, 10,879 and 108,816 rows).

`--members` selects member accesses on a typed receiver: method invocations
`r.m(...)` (`ReceiverMethodInvocation`, without type arguments) and property
reads `r.p` (`ReceiverPropertyExtraction`: a getter, a field's getter or a
method torn off) whose operator is `.` and whose name is not private, whose
receiver is known and whose receiver's static type is not nullable and has an
interface type as its bound, and which resolve through that interface. Past
parentheses, a known receiver is what `--user-operators` knows (a literal, an
`--operators` expression, an `--identifiers` read, a selected operator
invocation), a selected member access, or an integer literal (no context:
`int`). An invocation must resolve to a method that is not generic and has a
declared return type and declared parameter types (when its type is invalid,
because the return type does not resolve, upstream's resolution is invalid
with that method as the recovery, and it is still selected), other than
`remainder` and `clamp` on a subtype of `num?`, whose type
`refineNumericInvocationType` refines from the arguments; a read must resolve
to a getter with a declared return type (for a field's getter, a field with a
declared type) or to such a method. The V1 rows are `MethodInvocation`,
`PrefixedIdentifier` and `PropertyAccess`. The selection also writes the
integer literals that are arguments of a selected invocation (past
parentheses, positional or named) and match a parameter, whose type is
`_recordIntegerLiteralType` with the parameter's type as the context. Both
sides decide it the same way, the oracle's `MemberAccesses` from upstream's
resolution and the port from what it types.

`src/dart/resolver/method_invocation_resolver.rs` types them after the
operator invocations (a receiver may be one; the operator invocations do not
take a member access as an operand, so the earlier selection is unchanged).
The parser builds a read as a `ParsedNameAccess` when its receiver is a name
or a name access, and as a `ReceiverPropertyExtraction` when it is a literal,
parenthesized, `this` or an index expression; an invocation is a
`ParsedValueArguments` whose operand is a `ParsedNameAccess`. The member is
found by `get_member` in `inheritance_manager3.rs`, which now looks up getters
as well as methods (a method and a getter of one name in two superinterfaces
are a conflict, left unresolved), merges a mixin's member as
`_getInterfaceClass` does (a member the mixin declares replaces the member so
far, one its interface inherits is merged with it, the most specific
winning; before, any member of the mixin's interface replaced it, which the
default corpus found: `MethodElementImpl.formalParameters`), and combines
valid overrides of different types into their top merge (`_topMerge`, which
the held-out extension type tests found). The type is the method's return
type, the getter's type or the method's function type, substituted with the
receiver's type arguments. An invocation of a getter (`r.g()`) is a read of
the getter, whose value is called: upstream's resolver rewrites it into a
`FunctionExpressionInvocation` whose function is the read, so the read is
typed and written as a `PrefixedIdentifier` or `PropertyAccess` (the parse-time
projection here keeps the `MethodInvocation`; `body_dump` writes the read's
row in its place), and the call is not typed. `body_dump` finds the member
accesses of a V1 projection by offset and length, since the projection of
`a.f().g()` gives the inner invocation the whole chain as its origin.

Limits (as extended by the extension and `this` slices below): `?.`, nullable
receivers that neither `Object` nor an extension serves, cascades, `super`,
`this` where it is not known, static members and import prefixes, `dynamic`,
`Never`, invalid and `void` receivers, `call` of functions and record
fields, private names (a private field may be promoted by flow analysis,
and a private name is looked up per library, which `get_member` does not
port), generic methods and explicit type arguments, members whose types
override or top-level inference would infer, the call of a getter's value,
`remainder` and `clamp` on numbers, implicit call tear-offs and generic
function instantiation, integer literals in other argument positions (past a
unary minus, inside other expressions), and every access whose receiver is
not typed.

The fixture `tests/body_corpus/members.dart` covers methods, getters, fields
and tear-offs on user classes, a subclass, generic classes and a subclass of
an instantiation, a mixin, the most specific of two interface members,
enums, extension types (with and without `implements`), `String`, `int`,
`double`, `num`, `List`, `Map` and `Object` members, chains, literal,
parenthesized, operator and member access receivers, type parameter
receivers, each argument context (positional, optional, named, extra,
parenthesized; `double`, `double?`, `num`, `int`, `Object`, `dynamic`,
`FutureOr<double>` and substituted type parameters), and each limit above,
with what the corpora found: a mixin's inherited member, top-merged combined
signatures, an unresolved return type and invoked getters. Before the port
typed member accesses it produced 230 upstream rows and none on the Rust
side; with those cases added it has 247 rows, which match. Unit tests in
`type_analyzer_test.rs` (on a hand-built `dart:core` with members) failed
before the port typed them (all `-`), but the one that checks what must stay
untyped. Measured 2026-11-08: the default corpus matches 18,467 rows across
589 files (184 seconds), and the held-out roots 29,691 rows across 5,730
files (326 seconds), zero differences. Before the mixin fix the default
corpus differed in 4 files; the held-out roots differed in 53 (3 combined
signatures, 50 invocations whose return type does not resolve). The earlier tests still match on the fixture (154, 77, 130, 416
and 418 rows), the default corpus (41,283, 13,036, 1,096, 50,276 and 1,359
rows) and the held-out roots (146,712, 52,170, 10,879, 108,816 and 13,605 rows).

Extension members widen `--members` and `--user-operators` rather than
adding a flag: an extension member is a member access or an operator
invocation like any other. A member access is now selected on any known
receiver whose static type is not `dynamic`, invalid, `void` or `Never` (nor
bounded by them), or on an explicit extension override `E(x)`, `E<T>(x)` or
`p.E(x)` with one positional argument that is known, when the member it
resolves to is one the port's lookup finds: of the overriding extension; of
an applicable extension; of `Object` when the receiver may be null or its
bound is not an interface type; else of the interface; and not static. An
operator invocation's receiver may now be nullable when the operator is an
extension's, and may be an override with a known argument (not of `==` or
`!=`). Upstream decides the member, so both sides still decide the selection
independently: a lookup that differs shows as a missing or extra row.

`src/dart/resolver/type_property_resolver.rs` ports `TypePropertyResolver.resolve`
for a read: `dynamic` and invalid receivers have only `Object`'s members; a
receiver that may be null finds `Object`'s member, else an extension's; any
other finds its bound's interface member, stopping there when the interface
has a setter of the name (`has_setter` in `inheritance_manager3.rs`, which
is what `getMember3(Name('$name='))` answers, `[]=` for `[]`) or for `call`
of `Function`, then, but for a function's `call`, `Never` and a record
field, the most specific applicable extension, then `Object`.
`src/dart/resolver/extension_member_resolver.rs` ports `findExtension`
(`_chooseMostSpecific`, `_isMoreSpecific`: a non-platform extension beats a
platform one, then the instantiated extended types, then the
instantiate-to-bounds ones), `getOverrideMember` and the type arguments
`resolveOverride` gives an override (written, `dynamic` for each when their
number is wrong, or inferred by `chooseFinalTypes` from the argument);
`src/dart/resolver/applicable_extensions.rs` ports `havingMemberWithBaseName`
(an instance field's getter and setter, then a method, as two candidates;
`[]` and `[]=` for `[]`) and `applicableTo` (fresh copies of the type
parameters inferred from the receiver with `GenericInferrer.constrainArgument`,
newly ported, then a subtype check). `Scopes::accessible_extensions` gives
`LibraryFragmentScope.accessibleExtensions`: the library's extensions
(unnamed and private too), those of the imports without a prefix, of each
prefix, and of the enclosing file, with `PrefixScope` now keeping its
extensions. `TypeAnalyzer` records an override where `_visitScopeInvocation`
makes one: a call whose name (or prefixed name) finds an extension in scope.
Through an override, a binary or unary operator has the extension's method
unsubstituted (upstream's `extension.getMethod`, so `-BoxedList(ints)` is
`T`), and `[]` the substituted one (`getOverrideMember`); extension members
are never refined numerically. `body_dump` writes the read `r.p` of a
record-typed receiver as a `PropertyAccess`, as `V1Projection` projects it
(`_usesPrefixedIdentifier`), which record receivers now reach.

Limits: static extension members, private names, `?.` and cascades through
extensions, explicit type arguments that do not resolve, overrides with
other than one positional argument, `==` through an override, generic
extension methods, extension members with implicit types, the receiver
context of an override (an integer literal argument stays untyped), and
every access whose receiver or override argument is not typed.

The fixture `tests/body_corpus/extensions.dart` (with
`extensions_library.dart` and `extensions_part.dart`) covers extensions
declared in the library, in a part, imported, imported with a prefix,
hidden, unnamed in another library, private; generic extensions (on
`List<T>`, `Map<A, B>`, bounded `N extends num`, `T extends Shape`), the
SDK's (`EnumName`, `IterableExtensions`, `FutureExtensions`); the most
specific of several (subclass, `int` over `num`, `List` over `Iterable`),
ambiguity, a setter-only extension, an interface setter or member of the
name; nullable receivers with `Object` members and extensions on nullable
types; function and record receivers (a record field wins); operators a
class lacks, on nullable receivers, generic ones; explicit overrides with
inferred, written and wrong-count type arguments, prefixed, inapplicable,
static, missing, null-aware, cascaded, with two arguments, shadowed by a
local, and operators through them; and contexts of integer arguments.
Before the port resolved extensions, the fixtures produced 389 upstream member
rows (3 files differing) and 490 operator rows (2 files differing, the
existing `user_operators.dart` among them); with the cases added they have
409 member rows and 496 operator rows, which match. Unit tests in `type_analyzer_test.rs` (implicit
application, overrides, operators, rejected lookups, accessible extensions
with an import, a prefix, `hide`, unnamed and private extensions and a
platform extension) failed before the port (all `-`, but the last's two
extension-free reads). Measured 2026-11-09: the default corpus matches 19,879
member rows (was 18,467) and 1,359 operator rows across 589 files (173
seconds for both), and the held-out roots 30,615 member rows (was 29,691) and
13,690 operator rows (was 13,605) across 5,730 files (470 seconds), zero
differences. The literal, operator, integer and identifier tests still match
on the fixture (180, 78, 147 and 623 rows), the default corpus (41,283,
13,036, 1,096 and 50,276 rows) and the held-out roots (146,712, 52,170,
10,879 and 108,816 rows).
Two existing unit tests changed: `member_accesses_resolution_does_not_reach_are_left_untyped`
read `s.ext` of `extension on String` and expected it untyped, and
`operators_resolution_does_not_reach_are_left_untyped` did the same for
`s - s`; both now resolve upstream's way, so the extensions in those tests
are `on int` (inapplicable to `String`), keeping the tests' intent: an
extension member upstream does not find stays untyped.

`this` and implicit `this` receivers widen `--members` and
`--user-operators` the same way. `this` is known in the body of an instance
method, getter, setter or operator, of a generative constructor or of a
primary constructor's body (closures inside included), where it has the
type of `this` of the enclosing declaration (`thisType`: a class, mixin,
enum or extension type with its own type parameters as arguments, an
extension's extended type); field and constructor initializers, defaults,
metadata, factories and static members are left out. Flow analysis may
promote `this`, so a member is left out entirely when any `this` in its body
is in a position that can promote it, decided by the tokens as for a
variable read (`this == other` in `operator ==`, `this is T`, a switch on
`this`). A known `this` is a receiver like any other: `this.p`,
`this.m(...)`, `this + x`, `-this`, `this[i]`, also parenthesized, and
`--members` writes the `this` receivers of selected accesses
(`ThisExpression` rows), `--user-operators` the `this` operands of selected
invocations. `--members` also selects implicit `this` accesses: an
unqualified invocation `m(...)` (`UnqualifiedFunctionInvocation`, V1
`MethodInvocation`) or read `p` (`UnqualifiedNameExpression`, V1
`SimpleIdentifier`, also as the receiver of an invoked getter's call) where
`this` is known, whose name is not private, whose member is found and
declared as for an explicit receiver (the type of `this` as the receiver
type), and whose integer arguments get their parameter's type. Operator
invocations still take no member access as an operand, so `count + 1` with
an implicit `count` is not selected.

`TypeAnalyzer` keeps the type of `this` while it visits a member's body
(`member_body`, `promotes_this`) and records each `ParsedUnqualifiedName`
that no local declares as an implicit `this` access when the lexical lookup
finds nothing (an instance member of an enclosing class ends it with
nothing, `InstanceScope.lookup`; then `ThisLookup` resolves it on the type
of `this`), or finds an instance member of the enclosing extension
(`ExtensionScope`, which is that member, unsubstituted); a read past an
instance setter of the extension is looked up on `this`
(`LexicalLookup.resolveGetter`) but an invocation is not (`resolveUnqualified`:
such a setter ends the lookup); a name with type arguments is an
instantiation and is left out. `MemberResolver` types those like explicit
accesses (`TypePropertyResolver.resolve` with no receiver), so an implicit
member of an applicable extension, `Object`'s members on a nullable extended
type and inherited and substituted members (`first` is `int` in a subclass
of `Box<int>`) follow.

Limits: `this` where it is not known (initializers, `late` field
initializers, static members, where flow analysis may promote it), implicit
accesses with type arguments, private names, static members, operators with
an implicit `this` operand, `?.` and cascades on `this`, `super`, and
everything the explicit member accesses leave out.

The fixture `tests/body_corpus/this_receivers.dart` covers explicit and
implicit accesses in methods, getters, operators, constructor bodies,
closures and local functions; inherited, generic, substituted, mixin, enum
(`index`, and `name` of `EnumName`), extension type and extension members
(the extension's own, another applicable extension's, the extended type's,
on nullable, generic, `int`, `dynamic` and `Future` types, a setter-only and
a static extension member); invoked getters, tear-offs, integer arguments;
operators on `this`; and what stays out: initializers, a factory, a static
method, defaults, shadowing locals and parameters, top-level names, private,
static, generic and implicitly typed members, unresolved names, cascades,
`?.`, and members where `this` is promoted. Before the port typed `this`,
`--members` on the fixtures produced 598 upstream rows with 8 of 18 files
differing (implicit reads in every earlier fixture with a class, and the new
one); they now match, as do 538 `--user-operators` rows. The
`--user-operators` oracle was not run before the port changed (its new rows
are the `this` operands, which the port did not type before). Unit tests in
`type_analyzer_test.rs` (`this` in each kind of declaration, implicit
accesses, and what must stay untyped) failed before the port (all `-`, the
last because the query helper could not find its nodes, then for a read of
a declared parameter the test itself got wrong; it now reads an untyped
parameter). Measured 2026-11-09: the default corpus matches 51,626 member
rows (was 19,879) and 1,402 operator rows (was 1,359) across 589 files, and
the held-out roots 93,449 member rows (was 30,615) and
14,229 operator rows (was 13,690) across 5,730 files, zero
differences. The literal, operator, integer and identifier tests still match
on the fixture (187, 80, 159 and 632 rows), the default corpus (41,283,
13,036, 1,096 and 50,276 rows) and the held-out roots (146,712, 52,170, 10,879 and 108,816 rows).
No existing unit test changed; the unit-test query helper now accepts a
marked part (`‹this›.a1`) to name a node inside a longer, unique snippet.

`tests/type_analyzer_test.rs` runs the analyzer on a hand-built `dart:core`
(so it can run under Miri, not yet done): the literal and operator types,
integer literals with no context (`int`), with declared contexts (aliases,
`FutureOr`, `async` returns, defaults, collection type arguments, shadowed
names, a prefixed `dart:core`; these link the test code as a library with a
hand-built `dart:async`), and untyped when analyzed without their library;
reads of declared variables (parameters and locals of each kind, generic,
function, record and alias types, `InvalidType`, `dynamic`), the declaration
a name finds (block-wide locals, untyped variables, local functions, type
parameters, catch and pattern variables and wildcards), and that variables
flow analysis may promote stay untyped (the silent failure: their declared
type); and that `==`, unary minus, integer arguments, unresolved identifiers
and parentheses around them stay untyped. The four integer tests with expected
types failed before the analyzer typed integer literals; the three
variable-read tests failed before it resolved names (all reads `-`). Typing an unknown parenthesized
expression `bool` fails that last test.
The member access tests cover method, getter, field and tear-off types
(substituted, inherited, on literal, parenthesized and chained receivers),
integer argument contexts, invoked getters, a mixin's inherited member, a
top-merged combined signature, and what must stay untyped (null-aware and
nullable receivers, extension members, private names, generic methods,
implicit member types, `dynamic` and unresolved receivers, `remainder`,
explicit type arguments, static members); the first two failed before the
port typed member accesses (all `-`), the last passes by design.

`tests/oracle_comparison.rs` checks that missing empty dumps count as
differences, extra dumps fail, and identical empty/nonempty dumps match. Its
missing-empty case failed before the shared comparator was fixed. Missing
output must never be mistaken for an empty expression selection.

### Literal output-pipeline measurements

Measured 2026-11-06 on a shared AMD EPYC host, Dart 3.13.4 AOT and rustc
1.99.0 release, using the existing
`../../_fe_analyzer_shared/rust/tool/measure.sh`: 11 alternating processes
per side on the four-file fixture, 43 output rows. Each process loads the
SDK, parses, analyzes and writes its dumps. Both output directories match
byte for byte, as does output from the separately stripped Rust executable.
[Raw runs](measurements/body-literals-2026-11-06.runs) retain all samples.

| Fixture output pipeline | Dart AOT | Rust |
|---|---:|---:|
| Fastest process | 822.97 ms | 170.86 ms |
| Median process | 964.09 ms | 197.01 ms |
| Median peak RSS | 102,452 KiB | 33,656 KiB |
| Maximum peak RSS | 103,744 KiB | 33,716 KiB |
| Executable bytes | 17,931,560 | 3,510,552 |
| Stripped executable bytes | unmeasured | 2,936,992 |

The upstream entry point also resolves everything beyond the selected
literals, so the comparison favors Rust. These are output-pipeline
measurements, not isolated visitor timings or proof of full resolver
performance. Wall-time CV was 46.1% for Dart and 17.4% for Rust. Instruction
counts were unavailable (`perf_event_paranoid=4`); the empty `ins=` fields
in the raw log mean unmeasured, not zero. Comparable clean compile times
and full-resolver cold start remain unmeasured. The upstream AOT compile
alone took 78.73 seconds and 574,136 KiB peak RSS; the Rust rebuild was
incremental and included multiple binaries, so it is not comparable.

Reproduce after the oracle has created its SDK and package configuration,
from the SDK root (`DART` names the installed Dart executable):

```sh
body_work="$PWD/target/element_oracle/body-literals"
body_fixture="$PWD/pkg/analyzer/rust/tests/body_corpus"
"$DART" compile exe --packages="$body_work/package_config.json" \
  pkg/analyzer/rust/oracle/body_dump.dart -o target/body-oracle-aot
OUT=target/measure/body-literals bash pkg/_fe_analyzer_shared/rust/tool/measure.sh \
  11 body-literals \
  "target/body-oracle-aot --sdk $body_work/sdk --packages $body_work/package_config.json --literals --out target/body-bench-dart $body_fixture" \
  "target/release/body_dump --sdk $body_work/sdk --packages $body_work/package_config.json --literals --out target/body-bench-rust $body_fixture"
diff -qr target/body-bench-dart target/body-bench-rust
```

The analyzer crate and body dump forbid unsafe code. The three comparator
tests pass under Miri (`MIRIFLAGS=-Zmiri-disable-isolation cargo +nightly
miri test -p analyzer --test oracle_comparison`); that run covers the
comparator, not body-resolution paths. Body-resolution coverage and Miri
evidence remain incomplete.
