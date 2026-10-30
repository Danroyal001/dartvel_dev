# `analyzer` in Rust

A file-by-file Rust port of this package (`pkg/analyzer`), so far the part
that parses a file into a syntax tree: the AST node classes, the
`AstBuilder` listener that builds them from the parser's events, and
`parseString`. Each file under `src/` ports the Dart library at the same path
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

compares the trees on `pkg/_fe_analyzer_shared/lib`, `pkg/analyzer/lib` and
`tests/language`. `AST_CORPUS` names other roots, `AST_WORK` moves the
scratch directory (default `target/ast_oracle`) and `PUB_CACHE` the pub
cache. Dumps that match are deleted; dumps that differ are kept, and the test
prints the first differing line of each.
