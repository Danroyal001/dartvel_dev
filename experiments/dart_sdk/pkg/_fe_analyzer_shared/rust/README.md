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
  and every listener event takes the store first, mutably: a listener that
  builds a tree (the analyzer's `AstBuilder`) inserts and rewrites tokens,
  which upstream does through `parser.rewriter`. Code that splits `>>` or
  inserts synthetic tokens takes `&mut TokenStore`.
- Behaviour that looks like an upstream slip is ported as is and marked with
  a comment, never fixed: the oracle would report the fix as a difference.

## Measurements

Measured 2026-11-05 on an 8-core AMD EPYC host shared with other work (load
average 6 to 10 throughout), Dart 3.13.4 (`dart compile exe`), rustc 1.99.0
(the workspace's release profile: fat LTO, one codegen unit). Every row is
Dart AOT against the Rust binary of this workspace, measured by
`tool/measure_rows.sh` (run from the SDK root; `tool/measure.sh` is the
harness), which runs the two programs alternately, Dart first on odd runs
and Rust first on even ones, and records for each run:

- the **instructions** the process executes in user space
  (`perf stat -e instructions:u`), which do not depend on host load and
  vary by less than 0.1% between runs of the same Rust binary (Dart:
  0.1–4%, from its garbage collector);
- the **wall time**, or for an in-process row the program's own fastest
  and median round;
- the **peak RSS** of the process (`/usr/bin/time -f %M`).

On this loaded host wall times vary by 5–15% (in-process rounds) and much
more for short runs; the instruction counts are the steady figure, and Rust
wins every row by them as well as by time. The scanner, parser and tree
oracles (`scanner_oracle`, `parser_oracle`, `ast_oracle`) were run on the
same binaries the same day: 0 differences.

### In process

11 processes a side. Fastest round is the fastest of all of them; median
round is the median of the 11 per-process medians; instructions and peak
RSS are the medians of the 11 processes (each whole process: reading the
corpus and every round). The scanner corpus is the scanner oracle's default
one (1178 files, 12,790,695 bytes, 1,545,787 tokens), 20 rounds, comments
included. The parser and the tree use the parser's (5152 files, 28,328,001
bytes). Each parser round scans every file first and times only `parseUnit`
with a listener that ignores every event, so the process holds the token
streams of the whole corpus. `ast_dump` (`pkg/analyzer/rust`) rows are
described in that crate's README.

| Row | Implementation | Instructions | Fastest round | Median round | Peak RSS |
|---|---|---|---|---|---|
| `scan` (UTF-8), 20 rounds | Dart AOT | 15.33 G | 157.8 ms | 226.5 ms | 80.5 MiB |
| | Rust | **9.09 G** | **81.4 ms** | **103.8 ms** | **22.7 MiB** |
| `scanString`, 20 rounds | Dart AOT | 16.03 G | 179.9 ms | 261.5 ms | 83.3 MiB |
| | Rust | **9.51 G** | **83.6 ms** | **95.9 ms** | **47.9 MiB** |
| `parseUnit`, 20 rounds | Dart AOT | 200.46 G | 666.2 ms | 834.2 ms | 484.6 MiB |
| | Rust | **59.63 G** | **362.6 ms** | **431.1 ms** | **305.9 MiB** |
| `parseString` (tree), 10 rounds | Dart AOT | 84.38 G | 2620.6 ms | 3638.9 ms | 126.4 MiB |
| | Rust | **56.42 G** | **1545.4 ms** | **1858.5 ms** | **93.2 MiB** |
| `toSource` of every unit, 10 rounds | Dart AOT | 45.04 G | 871.3 ms | 1152.3 ms | 698.6 MiB |
| | Rust | **16.42 G** | **268.7 ms** | **370.5 ms** | **485.0 MiB** |
| Whole corpus kept (`--retain`) | Dart AOT | 21.48 G | | | 640.4 MiB |
| | Rust | **7.88 G** | | | **482.7 MiB** |

Spread over the 11 processes: Dart's peak RSS ranged 448.7–564.4 MiB on
`parseUnit` and 125.0–260.5 MiB on `parseString` (its heap grows at
different points in different runs), Rust's by under 1.5% on every row.
The parser's peak RSS fell from 494.3 MiB (2026-10-30, equal to Dart's then)
to 305.9 MiB since a token takes 28 bytes instead of 52 (`43e9c5127`).

### Single-file cold start

31 runs a side, each a new process that reads one file and writes its dump;
every Rust dump is byte-identical to the Dart one. The small file is
`_fe_analyzer_shared/lib/src/util/link.dart` (5,659 bytes), the medium one
`analyzer/lib/src/dart/element/type_system.dart` (77,769 bytes), the large
one `analyzer/lib/src/dart/ast/ast.dart` (1,765,016 bytes), each in a folder
of its own. Instructions and peak RSS are medians.

| Program | File | Dart AOT instructions | Rust instructions | Dart AOT wall fastest / median | Rust wall fastest / median | Dart AOT peak RSS | Rust peak RSS |
|---|---|---|---|---|---|---|---|
| `scanner_dump` | small | 20.9 M | **1.66 M** | 14.2 / 22.9 ms | **2.6 / 6.0 ms** | 8.9 MiB | **2.6 MiB** |
| `scanner_dump` | medium | 145.7 M | **12.0 M** | 47.1 / 82.6 ms | **5.8 / 13.4 ms** | 15.8 MiB | **3.5 MiB** |
| `scanner_dump` | large | 4,380.6 M | **336.3 M** | 1114.5 / 1494.4 ms | **86.5 / 120.0 ms** | 148.4 MiB | **27.0 MiB** |
| `parser_dump` | small | 28.1 M | **2.92 M** | 16.7 / 25.7 ms | **3.2 / 6.0 ms** | 9.7 MiB | **3.2 MiB** |
| `parser_dump` | medium | 166.1 M | **19.5 M** | 61.0 / 102.8 ms | **8.0 / 13.9 ms** | 19.3 MiB | **4.2 MiB** |
| `parser_dump` | large | 5,107.6 M | **582.0 M** | 1541.3 / 1957.6 ms | **155.5 / 238.8 ms** | 173.2 MiB | **38.3 MiB** |
| `ast_dump` (analyzer) | small | 40.3 M | **3.80 M** | 28.5 / 47.7 ms | **4.2 / 8.5 ms** | 12.8 MiB | **4.6 MiB** |
| `ast_dump` (analyzer) | medium | 220.3 M | **25.3 M** | 64.7 / 114.8 ms | **10.6 / 16.3 ms** | 22.4 MiB | **6.1 MiB** |
| `ast_dump` (analyzer) | large | 6,012.3 M | **726.9 M** | 1609.9 / 2058.7 ms | **223.5 / 336.5 ms** | 151.5 MiB | **54.0 MiB** |

Rust runs 8–13× fewer instructions, is 5–13× faster on the fastest run and
4–12× on the median, and peaks at 2.8–5.5× less memory, on every row. The
slow-end loss once reported for cold start (Rust 4–31 ms against Dart AOT
8–23 ms) is not reproduced by time (2026-11-03) or by instructions
(2026-11-04, `9531c64c5`), and the slowest runs of both sides on this host
are set by its load, not by the programs.

### Binary size

| Program | Dart AOT (`dart compile exe`) | Rust unstripped | Rust stripped |
|---|---|---|---|
| `scanner_dump` | 6,853,080 bytes | **671,184 bytes** | **557,144 bytes** |
| `parser_dump` | 7,705,512 bytes | **1,373,312 bytes** | **1,071,744 bytes** |
| `ast_dump` | 10,472,152 bytes | **4,788,688 bytes** | **3,801,624 bytes** |

A Dart AOT executable cannot be stripped: `strip` drops the appended
snapshot and the result no longer runs, so its one size is both columns.

### Earlier measurements

2026-10-30 (4-core Xeon, Dart 3.13.3, rustc 1.97.0, 20 rounds, one process
each): `scan` 94.6 / 100.0 ms and 71.5 MiB (Dart AOT) against 48.5 / 50.8 ms
and 28.6 MiB (Rust); `scanString` 101.7 / 109.8 ms, 86.7 MiB against
49.1 / 51.9 ms, 53.3 MiB; `parseUnit` 312.4 / 400.2 ms, 496.5 MiB against
164.0 / 186.4 ms, 494.3 MiB. Dart JIT was slower than Dart AOT on every
median and took 2–4× the memory, so it is no longer measured.
