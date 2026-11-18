# rust_stack: Phase 0 measurement

Phase 0 of [the Dart and Flutter stack in Rust](../../docs/proposals/2026-10-29-dart-flutter-rust-stack.md)
starts by measuring every component before any estimate is trusted. This
package does that measurement the same way every time, so the next one can be
compared with this one.

## Running it

The Dart SDK and Flutter are the in-tree forks at `experiments/dart_sdk` and
`experiments/flutter`; pub and dart_style are the submodules under
`experiments/upstream/`. All four are pinned to the commits this baseline was
measured at. Fetch the submodules from the repository root, then measure:

```sh
git submodule update --init --filter=blob:none experiments/upstream
cd experiments/rust_stack
dart pub get
dart run bin/measure.dart \
  --sdk ../dart_sdk --flutter ../flutter \
  --pub ../upstream/pub --dart_style ../upstream/dart_style \
  --json baselines/sizes-$(date +%F).json
```

To measure a newer upstream, merge it into the forks and move the submodules
first, so the pins and the numbers always agree.

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
