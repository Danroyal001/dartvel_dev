# dart_style in Rust — initial backend work

This is an incomplete, file-by-file port of the formatter pinned by the Dart
SDK's DEPS. The unchanged upstream source is in the parent directory; see
`../README.dartvel.md` for provenance. Rust source files name the upstream file
on line one. The crate forbids unsafe Rust and has no dependencies.

There is no Rust Dart formatter executable yet. The AST-to-piece visitor,
piece classes, solver, declarations, statements, expressions and comments are
not ported. A successful backend test does not establish formatter parity.

## Oracle

`oracle/code.dart` imports and executes the original `GroupCode` implementation.
`tests/code_oracle.rs` builds the same 260 trees and compares the output as
UTF-16 code units and selection offsets. Cases exercise nested groups, suppressed
leading newlines, blank lines, indentation above the upstream small-indent cache,
non-BMP Unicode, CRLF, and nested/unclosed disabled-format regions. Tests require
an explicit `DART` binary and reject a version other than 3.13.3.

Run from this directory:

```sh
DART=/path/to/dart-3.13.3/bin/dart ~/heavy.sh ~/.cargo/bin/cargo test
```

## Remaining acceptance gates

- Port and test the complete piece/solver core.
- Build the AST-to-piece formatter using the existing scanner/analyzer crates.
- Run a real `dart format` CLI differential oracle over all upstream `.unit`
  and `.stmt` cases (including options, language versions and selection markers).
- Run large corpora: `tests/language`, `sdk/lib`, `pkg/*/lib`; report parse errors
  separately rather than silently excluding files.
- Measure fastest/median time, peak RSS, stripped/unstripped binary size,
  compilation/cold start and instructions using the existing measurement harnesses.
- Run Miri and record coverage. No compatibility, speed, memory or size wins
  are claimed by this initial backend work.

Verified 2026-11-06 with Dart 3.13.3: 260/260 generated Code tree rows match
(0 differences). Two differential tests pass, covering output building (260 rows) and debug
rendering (128 trees). Ten focused native tests pass, including raw UTF-16
surrogates and signed selection offsets; all ten also pass under nightly Miri.
This does not cover the remaining formatter. No performance measurements yet.

## Piece primitives

`src/src/piece/piece.rs` ports `State` and `Shape`; the abstract `Piece` class
is still unported. `State::canonical(value, cost)` models a Dart const state,
while `State::new(value, cost)` models a non-const allocation. Equality follows
object identity, but `compare_to()` compares numeric values independently of
cost. It deliberately does not implement Rust `Ord`, whose equality contract
would conflate these two relations. Clones retain allocation identity.

`oracle/piece.dart` imports the original upstream Piece library and compares
442 output rows: 20 states, 400 pair comparisons, every shape merge and the
allowed-shape sets. Resolving the upstream package is required before this test:

```sh
cd ..
/path/to/dart-3.13.3/bin/dart pub get
cd rust
DART=/path/to/dart-3.13.3/bin/dart ~/heavy.sh ~/.cargo/bin/cargo test
~/heavy.sh ~/.cargo/bin/cargo +nightly miri test --test piece_test
```

The process deadline is 300 seconds: importing Piece also compiles the upstream
formatter/analyzer, which exceeded the previous 60-second deadline on this
shared host. Version checks and exact-output comparisons apply to every oracle.
The primitive oracle passed with zero differences on 2026-11-06, along with all
four focused tests. Both native and real-upstream comparisons were observed
failing before implementation. This is not solver or formatter compatibility.

Safety/coverage evidence for the current two source files (2026-11-06): all
14 focused tests passed under nightly Miri. A full native test run built with
`RUSTFLAGS='-C instrument-coverage'` passed, and the matching stable LLVM
`llvm-profdata`/`llvm-cov report` tools report 265/265 lines and 356/356 regions
covered (`code.rs`: 215 lines/302 regions; `piece.rs`: 50 lines/54 regions).
Branch coverage was not collected. Coverage describes only the ported files,
not any of the unported formatter. Raw local logs/profiles are under
`/tmp/rust-dstyle-coverage*`; regenerate them rather than treating `/tmp` as a
durable artifact.
