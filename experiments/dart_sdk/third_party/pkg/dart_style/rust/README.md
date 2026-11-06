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
`tests/code_oracle.rs` builds the same 256 trees and compares the output as
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
(0 differences). Seven additional native tests pass, including raw UTF-16
surrogates; all seven also pass under nightly Miri. This covers output building,
not debug rendering or the remaining formatter. No performance measurements yet.
