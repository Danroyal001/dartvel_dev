# `_fe_analyzer_shared` in Rust

A file-by-file Rust port of this package (`pkg/_fe_analyzer_shared`), started
with the scanner. Each file under `src/` ports the Dart library at the same
path under `../lib/src`, keeps its structure and names, and names that
library in its first line. Files that are not ports (`lib.rs`, `mod.rs`, the
test harness) say so in their first line.

## The oracle

The port is checked against the upstream Dart code it ports, which stays in
this checkout as the oracle:

| | Upstream | Port |
|---|---|---|
| Dump | `oracle/scanner_dump.dart` | `src/bin/scanner_dump.rs` |
| Input | every `.dart` file under the corpus roots | the same |
| Output | `<out>/<root>/<path>.tokens` | the same, byte for byte |

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

Both Dart programs import only `dart:` libraries and this package's own, and
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

Speed: `scanner_dump.dart --bench=N` and `scanner_dump --bench=N` scan the
corpus N times in memory and print the fastest and median round.

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
