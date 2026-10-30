# `analyzer` in Rust

A file-by-file Rust port of this package (`pkg/analyzer`), so far the part
that parses a file into a syntax tree: the AST node classes, the
`AstBuilder` listener that builds them from the parser's events, and
`parseString`; and what the tree offers once built: parent pointers, the
V2 visitors, `toSource`, `NodeLocator2` and the texts of the diagnostics. Each file under `src/` ports the Dart library at the same path
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
