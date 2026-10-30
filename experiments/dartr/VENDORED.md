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
  porting those scripts to Dart first. The Dart comparison tools in
  `experiments/oracles` replace `format_parity.py` and `analyze_compare.py`.
- the project's website (`site/`), packaging (`packaging/`), images
  (`docs/images/`) and GitHub workflows (`.github/`).

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
  `examples/format_cli.rs`: 6,153 files per width from the SDK's `pkg/`
  (analyzer, analysis server, front end, shared front end, compiler, kernel,
  linter, dart2wasm, DDC, dartdev, DDS, vm), `sdk/lib`, pub, Flutter's
  `flutter` and `flutter_tools`, and Dartvel's `packages/`. All 18,459
  compares are byte-identical, and stdout, stderr and exit codes match in
  all 75 runs.

No formatter source change was needed to get there.
