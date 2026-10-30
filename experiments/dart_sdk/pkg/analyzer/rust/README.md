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

Measured 2026-10-30 on a 4-core Intel Xeon at 2.10 GHz, Dart 3.13.3, rustc
1.97.0. Dart AOT is `oracle/ast_dump.dart` built with `dart compile exe`.

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

| `parseString`, 10 rounds | Fastest round | Median round | Peak RSS |
|---|---|---|---|
| Dart AOT | 1179.2 ms | 1363.5 ms | 120.3 MiB |
| Rust | 669.0 ms | 803.2 ms | 92.4 MiB |

| `toSource` of every unit, 10 rounds | Fastest round | Median round | Peak RSS |
|---|---|---|---|
| Dart AOT | 446.6 ms | 475.1 ms | 646.4 MiB |
| Rust | 151.2 ms | 176.8 ms | 597.2 MiB |

The peak of the `toSource` runs is the parsed corpus they hold.

| Whole corpus kept (`--retain`) | Sources loaded | After parsing | Parsed corpus |
|---|---|---|---|
| Dart AOT | 75.4 MiB | 593.8 MiB | 518.4 MiB |
| Rust | 58.8 MiB | 595.7 MiB | 536.9 MiB |

The Rust corpus is 3,845,602 nodes at 32 bytes each (165.7 MiB of node
store, lists included, plus the boxed large nodes), their parents (4 bytes
each, 14.7 MiB, which took the parsed corpus past Dart's) and 5,201,677
tokens, whose store (`TokenData` is 92 bytes, from the scanner port) takes
458.0 MiB: the tokens, not the tree, dominate the parsed corpus.

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

and, from `dart/resolver/scope.dart`, the namespace of each import. The
files, their URIs and their kinds (library or part, `part of` checks) come
from `dart/analysis/file_state.dart`, with the SDK's library map read from
its `libraries.dart` (`dart/sdk/sdk.dart`) and the package config
(`context/packages.dart`), as `AnalysisContextCollection` sets them up.

The boundary is the next step, `_resolveTypes`: nothing about types is
ported (see [Not ported yet](#not-ported-yet)).

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
where inference decides). The Rust binary does not port it yet and exits
with status 70, so `declared_types_are_identical_to_upstream` fails, by
design, until it is.

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
a part included twice.

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

- **Declared types** (`--types`): `_resolveTypes`, i.e. the `DartType`
  classes of `dart/element/type.dart` (interface, function, record, type
  parameter, `dynamic`, `void`, `Never`, invalid; nullability and alias
  info), `display_string_builder.dart`, the library and declaration scopes
  of `dart/element/scope.dart`, `summary2/reference_resolver.dart` and
  `named_type_builder.dart` (with type aliases and import prefixes),
  `types_builder.dart` (function types, supertypes, mixin inference),
  `default_types_builder.dart` and `simply_bounded.dart` (instantiation to
  bounds of raw types), `variance_builder.dart`, `type_alias.dart`, the
  `TypeProvider`, and `buildEnumChildren` (`Enum` supertype, `values`
  type). This is also what the fragments of type annotations wait for:
  `GenericFunctionType` fragments and the formal parameters of
  function-typed formal parameters, which `FragmentBuilder` skips.
- The steps after it: field formals and constructors, top-level and
  instance member inference, constant initializers and default values
  (with what super formal parameters inherit), metadata and `@Since`,
  field promotability, and the flags they set.
- Augmentations beyond chains of fragments that declare the same formal
  and type parameters (`_linkFormalParameters` and `_linkTypeParameters`
  growing the chains with `isOriginOtherFragmentOfEnclosing` parameters),
  and moving an augmentation's enum `values`; the corpora have no
  augmentation that reaches them.
- Language versions from the package config (`languageVersion`): every
  library is parsed at the latest version unless it has a `// @dart`
  comment; doc imports, documentation comments, code ranges and the
  reference tree and summaries (`bundle_writer.dart`, `bundle_reader.dart`).
