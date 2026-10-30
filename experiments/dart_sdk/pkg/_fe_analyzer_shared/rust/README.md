# `_fe_analyzer_shared` in Rust

A file-by-file Rust port of this package (`pkg/_fe_analyzer_shared`), so far
the scanner and the parser. Each file under `src/` ports the Dart library at
the same path under `../lib/src`, keeps its structure and names, and names
that library in its first line. Files that are not ports (`lib.rs`, `mod.rs`,
the test harnesses) say so in their first line.

## The oracle

The port is checked against the upstream Dart code it ports, which stays in
this checkout as the oracle:

| | Upstream | Port |
|---|---|---|
| Dump | `oracle/scanner_dump.dart` | `src/bin/scanner_dump.rs` |
| Input | every `.dart` file under the corpus roots | the same |
| Output | `<out>/<root>/<path>.tokens` | the same, byte for byte |

and for the parser:

| | Upstream | Port |
|---|---|---|
| Dump | `oracle/parser_dump.dart` | `src/bin/parser_dump/main.rs` |
| Listener | `oracle/parser_trace_listener.dart` | `src/bin/parser_dump/trace_listener.rs` |
| Input | every `.dart` file under the corpus roots | the same |
| Output | `<out>/<root>/<path>.trace` | the same, byte for byte |

A dump lists every token in stream order (error tokens included, where the
scanner puts them) with its type, runtime class, offset, length, lexeme or
error code and arguments, language version, group end and synthetic flag;
each token's preceding comments come before it, and the line starts end the
file. `--scanner=utf8` runs `scan(bytes)` (the `Utf8BytesScanner`) and
`--scanner=string` runs `scanString(source)` (the `StringScanner`), both with
comments and the default configuration.

`oracle/extract_test_inputs.dart` turns the scanner's own tests into a
corpus: each test file, plus the value of every uninterpolated string literal
in it, as a file of its own.

A parser trace is every listener event, in order, one line each: the
event's name and each argument. A token is `TYPE@offset"lexeme"`, plus `~`
when synthetic; an error token is `!code@offset`, and `handleErrorToken`
also logs its assertion message; a message is `Code"problem""correction"`;
null is `-`; enums print as Dart's `toString`. A file that makes the
parser throw ends its trace with a `crash` line. Each file is scanned with
`scan(bytes)` (comments included) and parsed by `Parser.parseUnit` with
`DefaultExperimentalFeatures`, so the parser's error codes and offsets are
in the trace as `handleRecoverableError` events.

Both tracing listeners are generated from the upstream `Listener` by
`oracle/generate_parser_trace.dart`, which reflects on it with
`dart:mirrors`; run it again when `listener.dart` changes.

The Dart programs import only `dart:` libraries and this package's own, and
run with `oracle/package_config.json`, so they need no `pub get`.

## Running it

From the SDK root, with a Dart SDK at least as new as this package's
`environment: sdk:` lower bound:

```sh
DART=/path/to/dart cargo test --release --test scanner_oracle
```

compares both scanners on the default corpus: the scanner tests' inputs,
`pkg/_fe_analyzer_shared/lib` and `pkg/analyzer/lib`. `SCANNER_CORPUS=a:b:c`
names other roots; `SCANNER_WORK` moves the scratch directory (default
`target/scanner_oracle`). Both resolve relative paths against the SDK root,
where the oracle runs, so the two dumps always read the same files. Dumps that match are deleted; dumps that differ are
kept there, and the test prints the first differing line of each.

```sh
DART=/path/to/dart cargo test --release --test parser_oracle
```

compares the parser on `pkg/_fe_analyzer_shared/lib`, `pkg/analyzer/lib`
and `tests/language`; `PARSER_CORPUS` and `PARSER_WORK` (default
`target/parser_oracle`) work as the scanner's variables do.

Speed: `scanner_dump.dart --bench=N` and `scanner_dump --bench=N` scan the
corpus N times in memory and print the fastest and median round.
`parser_dump.dart --bench=N` and `parser_dump --bench=N` scan the corpus
before each round and time only parsing it, with a listener that ignores
every event.

## Porting conventions

- Dart's `$X` character constants are `C_X`; `$$` is `C_DOLLAR` and `$_` is
  `C_UNDERSCORE`. Other names keep their Dart spelling where Rust allows it
  (constants and enum values) and become snake case otherwise.
- Tokens live in an arena (`TokenStore`) addressed by 32-bit `TokenId`s;
  `NO_TOKEN` is `null`. A Dart getter on `Token` is a `TokenStore` method
  that takes the token's id. A token's Dart class is its `TokenRuntimeType`,
  and getters a class overrides dispatch on it.
- A lexeme is a range of the source until something reads it, which is what
  upstream's lazy substrings do; the canonicalizer's cache is identity only
  and has no counterpart.
- An abstract Dart class with subclasses becomes a generic struct over a
  trait holding the abstract members (`AbstractScanner<S: ScannerSubclass>`).
- Where upstream throws, the port panics with the same message.
- A Dart class hierarchy that the parser picks among at run time becomes
  one type with a kind or an enum (`IdentifierContext`, `TypeInfo`,
  `LiteralEntryInfo`, `ParserKind` for `ClassMemberParser` and
  `TopLevelParser`); a subclass that only overrides listener events becomes
  a `ForwardingListener` with recovery state.
- The parser owns the `TokenStore` and the listener (`Box<dyn Listener>`),
  and every listener event takes the store first. Code that splits `>>` or
  inserts synthetic tokens takes `&mut TokenStore`.
- Behaviour that looks like an upstream slip is ported as is and marked with
  a comment, never fixed: the oracle would report the fix as a difference.

## Baseline

Measured 2026-10-30 on a 4-core Intel Xeon at 2.10 GHz, Dart 3.13.3, rustc
1.97.0, on the default corpus (1178 files, 12,790,695 bytes, 1,545,787
tokens), 20 rounds in one process, comments included. Dart AOT is
`scanner_dump.dart` built with `dart compile exe`; peak RSS is the whole
process, which holds the corpus in memory.

| Scanner | Implementation | Fastest round | Median round | Peak RSS |
|---|---|---|---|---|
| `scan` (UTF-8) | Dart AOT | 94.6 ms | 100.0 ms | 71.5 MiB |
| `scan` (UTF-8) | Dart JIT | 92.0 ms | 107.2 ms | 260.3 MiB |
| `scan` (UTF-8) | Rust | 48.5 ms | 50.8 ms | 28.6 MiB |
| `scanString` | Dart AOT | 101.7 ms | 109.8 ms | 86.7 MiB |
| `scanString` | Dart JIT | 98.2 ms | 113.5 ms | 279.9 MiB |
| `scanString` | Rust | 49.1 ms | 51.9 ms | 53.3 MiB |

The parser, measured the same day on its default corpus (5152 files,
28,328,001 bytes), 20 rounds in one process. Each round scans every file
first and times only `parseUnit` with a listener that ignores every event.
Peak RSS is sampled from `/proc` every 50 ms and is dominated by the token
streams of the whole corpus, which both programs hold before parsing. The
median of the Dart AOT run moved between 346 and 400 ms across runs.

| Parser | Implementation | Fastest round | Median round | Peak RSS |
|---|---|---|---|---|
| `parseUnit` | Dart AOT | 312.4 ms | 400.2 ms | 496.5 MiB |
| `parseUnit` | Dart JIT | 399.6 ms | 457.1 ms | 981.6 MiB |
| `parseUnit` | Rust | 164.0 ms | 186.4 ms | 494.3 MiB |
