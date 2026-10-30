# dartr, vendored

The Rust port of the Dart analyzer, formatter, fixer and language server that
Track A of [the Dart and Flutter stack in Rust](../../docs/proposals/2026-10-29-dart-flutter-rust-stack.md)
starts from (the proposal's open question 1, answered: start from it).

- **Source:** `Danroyal001/dartr`, a fork of `orestesgaolin/dartr`, at commit
  `5c631e2` (11 October 2026). It ports the Dart SDK 3.13.3 analyzer.
- **License:** BSD-3-Clause, `LICENSE` and `THIRD_PARTY_NOTICES.md`, unchanged.
- **Why vendored, not a submodule:** everything for the side effort lives in
  `dartvel_dev` under `experiments/`, and the fixes this effort makes are
  committed here.

## Left out

Under the One Language Rule, which refuses Python everywhere in `dartvel_dev`:

- the Python tools: `tools/*.py`, `tools/codegen/*.py`, `bench/*.py`,
  `bench/memory.sh` (it runs `python3` inline), and
  `crates/dartr_server/tests/fixtures/minimal_edits/generate.py`. The code
  the codegen scripts generated is committed and kept; regenerating it means
  porting those scripts to Dart first (no test or build regenerates them).
  The Dart comparison tools in `experiments/oracles` replace
  `format_parity.py` and `analyze_compare.py`. `lints_differential.py` and
  `lints_metadata_differential.py`, which the lint differential tests run,
  are ported to `tools/lints_differential.dart` and
  `tools/lints_metadata_differential.dart` (same output files, byte for
  byte); `experiments/rust_stack/bin/bench.dart` does `memory.sh`'s job (see
  `bench/README.md`).
- the project's website (`site/`), packaging (`packaging/`), images
  (`docs/images/`) and GitHub workflows (`.github/`).

The Dart SDK source checkout the oracles build against (`package:analyzer`
at tag 3.13.3) is `DARTR_DART_SDK_SOURCE`, else `third_party/dart-sdk`;
`tools/oracle_package.dart` prepares the oracle's pub package against it
under `target/oracle/`.

## First measurement here

`dartr format` against `dart format` (Dart 3.13.7) on `dart_style/lib` and
Flutter's `packages/flutter/lib`, first reformatted to 60 columns so that
728 of the 772 files had to change: byte-identical output on all 772, in
1.07 s against 7.41 s.

## Formatter parity: 30 October 2026

Against the formatter Dart 3.13.3 ships, `dart_style` `39edc2d946a5`
(`dart_style_rev` in the SDK's `DEPS` at tag 3.13.3):

- **dart_style's own test data**, through `tests/format_test_data.rs` with
  `DART_STYLE_DIR` set to that checkout: tall 6,469 of 6,469 cases, short
  2,233 of 2,233, benchmarks 17 of 17 in each style. Changing one expected
  output in a copy of the data makes exactly that case fail, at each
  language version it covers.
- **Real code**, reformatted to 40, 60 and 120 columns and formatted back
  with each package's own settings by `dart format` 3.13.3 and by
  `examples/format_cli.rs`: 5,768 files per width from the SDK's `pkg/`
  (analyzer, analysis server, front end, shared front end, compiler, kernel,
  linter, dart2wasm, DDC, dartdev, DDS, vm), `sdk/lib`, pub, Flutter's
  `flutter` and `flutter_tools`, and Dartvel's `packages/`. All 17,304
  compares are byte-identical, and stdout, stderr and exit codes match in
  all 75 runs.

No formatter source change was needed to get there.

## Analyzer parity: 30 October 2026

`dartr analyze` against `dart analyze` 3.13.3: identical diagnostics
(file, offset, length, code, severity and messages) and exit codes on

- `dart_style`, pub, Dartvel's pure-Dart packages and `experiments/`, with
  their own analysis options and with every lint rule plus `strict-casts`,
  `strict-inference` and `strict-raw-types`, and 78 packages from the pub
  cache with every lint;
- the 330 most downloaded pure-Dart packages on pub.dev (tagged
  `sdk:dart`, latest versions, 20,377 files), each with its own options and
  with every lint: 3,002,516 diagnostics;
- Flutter 3.47.4 (which bundles Dart 3.13.3): `packages/flutter` (410,008
  diagnostics with every lint), `flutter_test` and `flutter_tools`, and
  Dartvel's Flutter packages (`dartvel_flutter`, `dartvel_documents`,
  `dartvel_scene`, `dartvel_windowing`, `dartvel_dev`).

Every difference the comparison found is fixed, and each fix has a project
under `crates/dartr/tests/fixtures/analyze_driver/lints_parity/` that
`analyze_parity_lints_parity` compares with Dart; every one of them failed
before its fix. Not compared yet: Flutter's other packages and the rest of
pub.dev, Flutter packages included.

## Language server parity: 30 October 2026

`dartr language-server` against `dart language-server` 3.13.3, through
`tools/lsp_differential.dart` on `dart_style` and pub: the same responses on
hover, definition, references, documentHighlight, signatureHelp,
documentSymbol, formatting, codeAction, prepareRename, rename, completion
and project diagnostics. The two differences left are not analysis
differences: the server's name in `initialize`, and one cold completion Dart
marks incomplete because its not-yet-imported pass ran out of time. The
unit indexes Dart's driver builds are identical to `dartr`'s, element and
relation order included, on all 104 `dart_style` files and 547 pub files.
Speed and memory are in `../rust_stack/README.md`.
