# rust_stack: Phase 0 measurement

Phase 0 of [the Dart and Flutter stack in Rust](../../docs/proposals/2026-10-29-dart-flutter-rust-stack.md)
starts by measuring every component before any estimate is trusted. This
package does that measurement the same way every time, so the next one can be
compared with this one.

## Running it

The upstream sources are the submodules under `experiments/upstream/`,
pinned to the commits this baseline was measured at. Fetch them from the
repository root (blobless; about 1 GB once checked out), then measure:

```sh
git submodule update --init --filter=blob:none experiments/upstream
cd experiments/rust_stack
dart pub get
dart run bin/measure.dart \
  --sdk ../upstream/sdk --flutter ../upstream/flutter \
  --pub ../upstream/pub --dart_style ../upstream/dart_style \
  --json baselines/sizes-$(date +%F).json
```

To measure a newer upstream, move the submodules to the new commits first,
so the pins and the numbers always agree.

It prints the proposal's Part 2 table and writes exact numbers, with the
commit of each checkout, to the JSON file. A checkout you leave out is listed
as not measured, never as zero.

## The rules

Defined in `lib/line_count.dart` and held still by `test/`:

- **Lines** are non-blank lines, comments included.
- **Languages** are counted by extension: Dart; C and C++ (`.cc .cpp .cxx .c
  .h .hpp`); Objective-C and Objective-C++ (`.m .mm`). Nothing else is ported,
  so nothing else is counted.
- **A file is a test** when a directory in its path is named for tests
  (`test`, `tests`, `testing`, `testcases`, `test_data`, `testdata`,
  `fixture(s)`, `benchmark(s)`), or a directory's name ends in `_test`,
  `_tests` or `_testcases`, or the file's own name ends in `_test`, `_tests`,
  `_unittest(s)` or `_benchmark(s)`. Exception: in Dart, everything under
  `lib/` ships, so `flutter_tools/lib/src/test/` is implementation.
- `.dart_tool`, `.git` and `third_party` directories are never counted, and
  `build`/`out` only at the top of a component's root.
- Each row can restrict its languages: the engine's `lib/ui` counts only the
  C++ natives, not the `dart:ui` sources, which stay Dart.

## Baseline: 29 October 2026

`baselines/sizes-2026-10-29.json`, at `dart-lang/sdk` `ceea75dd2b82` and
`flutter/flutter` `c3f5b027df2b` (the proposal's pins), `dart-lang/pub`
`1df594373b77` and `dart-lang/dart_style` `81042caf2e54`:

| Component | Language | Implementation | Tests |
|---|---|---|---|
| Dart VM | C++ | 483k | 93k |
| ...of which VM compiler back ends | C++ | 235k | 44k |
| dart:io embedder and natives | C++ | 63k | 30k |
| Compiler front end | Dart | 218k | 221k |
| Kernel and VM transforms | Dart | 116k | 25k |
| Shared front-end layer | Dart | 70k | 67k |
| frontend_server | Dart | 4k | 8k |
| Analyzer | Dart | 296k | 1,108k |
| Analysis server | Dart | 205k | 371k |
| Linter | Dart | 35k | 62k |
| Formatter | Dart | 22k | 3k |
| dart2js | Dart | 147k | 102k |
| dart2wasm | Dart | 42k | 5k |
| DDC | Dart | 39k | 17k |
| dart CLI, DDS and vm_service | Dart | 32k | 54k |
| pub | Dart | 33k | 44k |
| Flutter engine | C++, ObjC++ | 387k | 228k |
| flutter CLI | Dart | 189k | 265k |
| **Total ported** | | **2,382k** | **2,703k** |

| Stays as it is | Language | Size |
|---|---|---|
| dart:* library sources | Dart | 232k |
| Flutter framework | Dart | 572k |
| Flutter web engine | Dart | 120k |

### Where this differs from the proposal's Part 2

The proposal's table was counted by hand on the same pins. Total ported
implementation here is **2.38M lines, against the proposal's 2.52M**:

- **Compiler front end: 218k, not 319k.** `pkg/front_end/testcases` (95k
  lines) and `parser_testcases` (10k) are test inputs. The hand count filed
  them as implementation; the rule above files them as tests. The front end's
  total (439k) is the same either way.
- **Flutter engine: 387k, not 408k.** The same directories, with nested
  `third_party` directories (such as `impeller/third_party`) left out as
  vendored code. The remaining 21k is not yet traced to a directory.
- **Analysis server: 205k, not 219k.** Directories whose names end in
  `_test` or `_tests` are tests under the rule above.
- **Flutter web engine: 120k, not about 145k.** The proposal's figure was
  marked approximate; this one is counted, implementation only.

None of these changes the proposal's conclusions. They lower Part 11's
"Rust to write" by about 5%, and Part 13's token estimate with it, which is
the kind of correction Phase 0 exists to make before money is spent.

## Speed and memory baseline: 30 October 2026

`baselines/speed-memory-2026-10-30.json`, from `bin/bench.dart`: one
warm-up run, then five measured runs; the median wall time and the median of
each run's peak memory. Memory is the summed resident set of the whole
process tree (`dart analyze` works in a separate analysis server), sampled
from `/proc` every 50 ms, so it is a floor on the true peak. Dart SDK 3.13.7
on a 4-core Intel Xeon 2.1 GHz cloud container with nothing else running.
That is not one of the proposal's named reference machines, so these numbers
are provisional.

| Tool and corpus | Median wall | Median peak memory |
|---|---|---|
| `dart format -o none`, Flutter `packages/flutter/lib` (695 files) | 6.06 s | 199 MB |
| `dart format -o none`, SDK `pkg/analyzer/lib` | 3.63 s | 255 MB |
| `dart analyze`, `dart_style`, cold (empty analysis cache each run) | 7.05 s | 630 MB |
| `dart analyze`, `pub`, cold | 10.48 s | 586 MB |
| `dart analyze`, `dart_style`, warm (cache kept) | 0.66 s | 183 MB |
| `dart analyze`, `pub`, warm | 0.97 s | 203 MB |

The cold runs are the comparison for a port: a warm `dart analyze` mostly
reads its previous results back from `~/.dartServer`, which is a test of the
cache, not of analysis. Each cold run gets a fresh, empty `HOME`, so nothing
is deleted to make it cold.

## dartr against Dart: 30 October 2026

`baselines/dartr-vs-dart-2026-10-30.json`, the same method against the Dart
`dartr` ports, 3.13.3, on the same container, with `dartr` from
`experiments/dartr` at `10fd666` (release build). Both tools give identical
output on these inputs (`../dartr/VENDORED.md`).

| Tool and corpus | Dart 3.13.3 | dartr | Faster | Memory |
|---|---|---|---|---|
| format, Flutter `packages/flutter/lib` (695 files) | 6.73 s, 207 MB | 0.86 s, 127 MB | 7.8× | 61% |
| format, SDK `pkg/analyzer/lib` | 4.10 s, 262 MB | 0.53 s, 182 MB | 7.7× | 69% |
| analyze, `dart_style`, cold | 7.49 s, 633 MB | 1.38 s, 399 MB | 5.4× | 63% |
| analyze, `pub`, cold | 10.29 s, 600 MB | 1.65 s, 461 MB | 6.2× | 77% |

Memory is `dartr`'s median peak as a share of Dart's. On these four corpora
`dartr` passes Part 8's gate for Track A (wall time and peak memory no more
than Dart's). The gate is every corpus and the language server too; the
language server and Flutter code are measured below, and the gate is not a
pass until every corpus the proposal names is.

### Flutter code

`baselines/dartr-vs-dart-flutter-2026-10-30.json`, cold, three runs, Flutter
3.47.4 (Dart 3.13.3):

| Corpus | Dart 3.13.3 | dartr | Faster | Memory |
|---|---|---|---|---|
| analyze Flutter `packages/flutter` | 54.53 s, 1,462 MB | 13.74 s, 1,296 MB | 4.0× | 89% |
| analyze Dartvel's 5 Flutter packages, one after another | 103.31 s, 1,369 MB | 14.39 s, 1,085 MB | 7.2× | 79% |
| analyze `dartvel_flutter` | 28.98 s, 1,382 MB | 7.73 s, 1,077 MB | 3.7× | 78% |

`dartr`'s runs on `packages/flutter` ranged from 9.4 s to 16.1 s while
another build shared the four cores, so its speed-up there is a floor.

### Language server

`baselines/dartr-vs-dart-lsp-2026-10-30.json`: one scripted LSP session per
project (three files, 12 probes each, every request repeated five times),
cold, three runs, with `dartr` at `dcc962c`. The driver is
`../dartr/tools/lsp_differential.dart`; its `diff` mode compares the two
servers' normalized responses.

| | `dart_style` Dart | `dart_style` dartr | pub Dart | pub dartr |
|---|---|---|---|---|
| Analysis complete | 8.64 s | 1.85 s | 11.87 s | 2.75 s |
| Peak memory | 834 MB | 787 MB | 828 MB | 763 MB |
| Memory after analysis | 595 MB | 402 MB | 587 MB | 468 MB |
| completion (median) | 12.1 ms | 9.0 ms | 10.0 ms | 6.9 ms |
| references | 5.5 ms | 2.4 ms | 3.9 ms | 2.2 ms |
| rename | 7.9 ms | 3.1 ms | 18.7 ms | 6.7 ms |

`dartr` is faster on every request kind the session makes (the JSON has all
eleven) and peaks lower on both projects. Its responses match Dart's on
every request kind but two, neither an analysis difference: `initialize`
names the server `dartr LSP Analysis Server`, and one cold completion on pub
is `isIncomplete` in Dart only, because Dart's not-yet-imported pass ran
out of its time budget; the items are identical.
