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

- the Python tools: `tools/*.py`, `tools/codegen/*.py`, `bench/*.py`, and
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
