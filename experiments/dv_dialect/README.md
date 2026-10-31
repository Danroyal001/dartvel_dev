# dv_dialect: the optional-semicolon dialect

Track I of [the Dart and Flutter stack in Rust](../../docs/proposals/2026-10-29-dart-flutter-rust-stack.md):
`.dv` files are standard Dart with semicolons optional at line ends,
converted losslessly to and from standard Dart. Every tool other than the
converter only ever sees standard Dart.

```dart
import 'package:dv_dialect/dv_dialect.dart';

final dialect = toDialect(dartSource);   // removes the optional semicolons
final dart = toDart(dialect).source;     // puts them back
```

## How it stays lossless

Both directions run one decision at every line break: would a semicolon be
inserted here? `toDialect` removes a semicolon only where that decision says
it would come back, so a round trip changes nothing unless insertion wants a
semicolon where standard Dart has none. That is the only failure there can be,
and `bin/roundtrip.dart` counts it over a corpus.

Tokens come from the Dart analyzer's own scanner, so strings, comments and
operators are standard Dart's decision. The parser is used only to check
that `toDialect`'s input is valid Dart: on dialect input its error recovery
rewrites the token stream.

## The rules

A semicolon is inserted at a line break when all of these hold (Go's rule,
adapted to Dart). Each is held by a test in `test/dialect_test.dart`.

- **Where.** At the top level, or directly inside a block, a class body or a
  closure body; never inside parentheses, brackets, collection literals,
  switch expressions, enum value lists or string interpolations. A `{`
  after a postfix `!` (`x! {`), after a statement label (`outer: {`) or
  ending a constructor's initializer list (`: x = (a + 1) {`) opens a
  block, not a literal or a closure.
- **The line can end a statement.** It ends in an identifier, a literal,
  `this`/`super`/`null`/`true`/`false`, `break`/`continue`/`rethrow`, `)` of
  a call or grouping, `]`, `++`, `--` or `!`, or the `}` of a closure or
  collection. Not a control-flow header's `)` (`if (x)`), not an annotation,
  not a function type's parameter list, not `extends`/`with`/`implements`/`on`
  or a directive's `show`/`hide`, and not a type alone on its line with a name
  on the next (`late int` then `_next`), which the formatter produces.
- **The next line does not continue it.** It does not start with `.`, `..`,
  `?.`, a binary operator, `?`, `:`, `=>`, `,`, `{`, `is`, `as`, `when`,
  `show`, `hide`, a header keyword, an `if` inside a conditional import, a
  `;` (the statement already ends there), or a string literal right after a
  string (adjacent strings are one string). A directive is an `import`,
  `export` or `part` keyword followed by its URI, so a member named
  `library` or `part` is not one.
- **`return` at a line end** ends the statement only before the block's `}`,
  because the formatter wraps long returned expressions onto the next line.

A line starting with `(` or `[` begins a new statement, and `toDart` warns.
A semicolon with anything between it and the token it ends (a comment, a
line break) is never optional, because it would come back in a different
place.

## Corpus results

`dart run bin/roundtrip.dart DIR...` on 29 October 2026, at the pins in
`../upstream/`:

| Corpus | Files | Round-trip byte for byte | Semicolons optional |
|---|---|---|---|
| `dart-lang/sdk` `pkg/` (analyzer, analysis server, front end, shared front end, compiler, kernel, linter, dart2wasm, DDC, dartdev, DDS, vm), `sdk/lib`, pub, dart_style | 3,349 | 100.00% (3,349) | 97.45% (403,140 of 413,674) |
| `flutter/flutter` `packages/flutter`, `packages/flutter_tools` | 3,910 | 99.97% (3,909) | 99.19% (505,832 of 509,966) |
| `dartvel_dev` `packages/` | 2,682 | 99.96% (2,681) | 97.08% (198,397 of 204,363) |
| **All** | **9,941** | **99.98% (9,939)** | **98.17% (1,107,369 of 1,128,003)** |

The first run over `packages/` round-tripped 91.42%; each failure since was
either a rule now in the tests or is listed below.

### What still fails

2 files, both deliberate refusals; no rule gap is left in these corpora.
The proposal's freeze rule is that every failing construct becomes either a
rule or a named refusal before the rules are frozen:

- **Refusal: a line starting with `(` or `[` is a new statement.** A call
  or an index whose `(` or `[` sits at the start of the next line cannot be
  written in the dialect; `toDart` warns, and the source must join the line.
  - `(`: `flutter/packages/flutter/lib/src/material/snack_bar.dart:975`
    (`...bodyMedium!.copyWith` then `(color: ...)` on the next line).
  - `[`: `packages/dartvel_cli/test/swift_off_apple_test.dart:47`
    (`(loadYaml(...) as YamlMap)` then `['dartvel']['module']` on the next
    line).

The 36 other failures of the previous run were rule gaps, each now a test in
`test/dialect_test.dart`: a postfix `!` read as a negation (9 files), a
member named `library` read as a directive (9), labeled blocks (7), a `;`
alone on its line (6), constructor bodies after an initializer list (3) and
generic function types (2).

These three corpora are not pub.dev. The proposal freezes the rules only
when the whole of pub.dev round-trips.
