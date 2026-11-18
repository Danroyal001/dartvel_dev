# oracles

The first oracle harness for Track A of
[the Dart and Flutter stack in Rust](../../docs/proposals/2026-10-29-dart-flutter-rust-stack.md)
(Part 6, "An oracle per unit"). It records what the **original** Dart
formatter and analyzer produce for a corpus, deterministically, so that a
Rust port can write the same dump and be checked against it byte for byte.

Not published, not in the pub workspace.

## What it records

`bin/dump.dart` walks every `.dart` file under one or more corpus
directories and writes one output file per input:

| `--tool` | Output per file | What is in it |
|---|---|---|
| `format` | `<label>/<path>.formatted` | `DartFormatter.format` output, exactly |
| `format` | `<label>/<path>.format-error` | instead, when the formatter throws: the error text |
| `analyze` | `<label>/<path>.diagnostics.jsonl` | one JSON object per diagnostic, empty file when none |
| `analyze` | `<label>/<path>.analyze-error` | instead, when the analyzer cannot produce a result |

`<label>` is the corpus root's basename (`lib`; a second root with the same
basename becomes `lib~2`), and `<path>` is the file's path below that root
with `/` separators. A failing file is recorded and the run goes on; one
bad file never ends a dump.

**Formatter settings** are the ones `dart format` would use for the file:

- language version: the lower bound of `environment: sdk:` in the nearest
  `pubspec.yaml` above the file (what pub writes into `package_config.json`),
  else the formatter's latest; `--language-version 3.6` fixes it for every
  file instead;
- page width and trailing commas: the `formatter:` section of the
  `analysis_options.yaml` that applies to the file, read through the
  analyzer as the pinned `dart format` reads it, else 80 and `automate`.

All three are recorded per file in the manifest.

**Diagnostics** come from the analyzer's public API:
`AnalysisContextCollection` over the corpus roots, then
`session.getErrors(path)` per file, using the running Dart SDK's libraries.
Each line is

```json
{"offset":7406,"code":"todo","severity":"info","length":66,"message":"TODO(rnystrom): …"}
```

in that key order: `code` is the diagnostic code's lower-case name,
`severity` the code's own severity (`error`, `warning`, `info`), and lines
are sorted by `offset`, then `code`, then the other fields. The analysis
context is whatever the corpus provides (its `analysis_options.yaml`, its
`.dart_tool/package_config.json` if it has been through `pub get`); a corpus
without one records the unresolved-import diagnostics that follow from that,
which is still a deterministic oracle.

`<out>/manifest.json` names the tool and exact versions (the version from
each package's pubspec, whether it came from the pub cache or a path, and
for a path checkout its git revision), the Dart SDK version, the settings,
the corpus root labels, the file count, the count of recorded errors, and
for each file its input's and output's sha256. `overallSha256` is the sha256
of the lines `<output path>\t<sha256>\n` over all output files in sorted
order.

## Running it

```sh
cd experiments/oracles
dart pub get
dart run bin/dump.dart <corpus-dir>... --out <dir> --tool format|analyze
dart run bin/compare.dart <dumpA> <dumpB>
```

`--out` must be absent, empty, or an earlier dump, which is replaced; any
other directory is refused rather than emptied.

`compare.dart` compares every output file of the two dumps byte for byte and
exits 0 when they are identical. Otherwise it lists each file only one dump
has and, for each file both have, the first differing line with both
versions, and exits 1 (64 on bad usage). `manifest.json` is not compared as
bytes, because a port names itself in it; differing tool versions, SDK and
settings are printed as notes. A Rust port writes the same layout and is
checked with this command.

### Which original

`pubspec.yaml` depends on the hosted `dart_style` 3.1.14 and `analyzer`
14.7.0, so the package resolves on any machine and in CI, which checks out
without submodules. To record the sources the port is actually made from —
`experiments/upstream/dart_style` and `experiments/upstream/sdk/pkg/analyzer`
at their submodule pins — initialize those submodules and use the override:

```sh
cp pubspec_overrides.pinned.yaml pubspec_overrides.yaml   # git-ignored
dart pub get
```

Every manifest says which one produced it (`"source": "path"` with a
`revision`, or `"source": "hosted"`), so the two cannot be confused. The
pinned `dart_style` (3.1.15-wip) differs from 3.1.14 in its solver and CLI
sources. On the two baseline corpora the two produce identical `format`
output, but that is a measurement on those corpora, not a guarantee.

The analysis of Flutter's `packages/flutter/lib` in `baselines/` is
unresolved: the checkout has no `package_config.json` and the plain Dart SDK
has no `dart:ui`, so most of its diagnostics follow from
`uri_does_not_exist`. It is deterministic, but it is not Flutter as it is
normally analyzed.

## Guarantees

- **Deterministic.** Two dumps of the same corpus with the same tool
  versions are byte-identical, manifest included: paths are stored relative
  to the root labels, files and diagnostics are sorted, and nothing hashed or
  written carries a timestamp, a stack trace or an absolute path. Absolute
  paths that the tools themselves put in messages are rewritten: a corpus
  root to its label, its parent to `<label>/..`, the Dart SDK to
  `<dart-sdk>`, the pub cache to `<pub-cache>`.
- **Error per file, never a crash.** A file the formatter or analyzer
  cannot handle produces an `-error` file and is counted in `errorCount`.
- **A single changed byte is found.** `compare.dart` checks every byte of
  every output file, including trailing bytes, and names the file and line.

Each of these is a test in `test/`, and each was shown to fail when the
property was deliberately broken (a timestamp in the manifest, an unsorted
walk, unsorted diagnostics, absolute paths, an uncaught formatter error, a
length-only compare, ignored analysis options).

What it does not do: walk hidden directories (`.dart_tool`, `.git`) or
follow links; record anything but `.dart` files; analyze against the pinned
SDK's own `dart:` libraries (it uses the running SDK's).

## Baselines

`baselines/` holds the manifests of real runs, as recorded baselines for a
port: counts and hashes only, no outputs. Each is named
`<corpus>-<tool>.json` and says which corpus revision it was taken from.
The dumps themselves are large and are not committed; regenerate them with
the commands in each baseline's `command` field.
