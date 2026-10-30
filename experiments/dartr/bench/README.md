# Benchmarks

- `compare.sh`: `dartr analyze` against `dart analyze` (one command line run per project).
- `baseline.sh`: earlier baseline of `dart analyze`.
- `lsp_bench.py`: `dartr language-server` against `dart language-server` for editor use
  (upstream only: Python is not vendored into `dartvel_dev`, see `VENDORED.md`).
- `setup_corpus.sh`: gets the corpus projects into `corpus/`.

Results go to `results/` (git-ignored).

## Memory

Upstream's `memory.sh` (median peak RSS of 3 runs of `dart analyze` and `dartr analyze` per
corpus project) is not vendored: it ran `python3` inline. `experiments/rust_stack/bin/bench.dart`
does its job, with a warm-up run first (which also warms `dart analyze`'s disk cache, as
`memory.sh` did) and the median of the counted runs:

```sh
cd experiments/rust_stack
dart run bin/bench.dart --runs 3 --label "dart analyze: flutter_tools" -- \
  dart analyze <corpus>/flutter_tools
dart run bin/bench.dart --runs 3 --label "dartr analyze: flutter_tools" -- \
  <target>/release/dartr analyze <corpus>/flutter_tools
```

It reports the peak of the summed RSS of the whole process tree, sampled from `/proc` every 50 ms
(`dart analyze` works in a child analysis-server process); `memory.sh` read `ru_maxrss` from
`/usr/bin/time -l` on macOS, the peak of the largest single process.

## Language server (`lsp_bench.py`)

The harness starts the server like VS Code with Dart-Code does (the `initialize` parameters of
`crates/dartr/tests/lsp_fixtures/dart_code_initialize.json`, with `workspaceFolders`) and measures:

1. Startup: from `initialize` to the end of the initial analysis (the last `$/progress` end of
   token `ANALYZING`, or `$/analyzerStatus` `isAnalyzing: false`, followed by 2 s without a new
   analysis). Cold Dart runs use an empty temporary `--cache` directory; warm runs use the
   benchmark's persistent `--dart-cache` directory (default `$TMPDIR/dartr-lsp-bench-cache`, not
   `~/.dartServer`), warmed by the first uncounted start. dartr has no disk cache.
2. Edits, 5 times each, after the initial analysis: (a) a statement with a type error in a method
   body of a file with few importers, (b) the rename of a public member that many files use. Both
   are undone. The time to the `publishDiagnostics` that shows the change (for (b): of the first
   and of the last other file) and to the end of the analysis.
3. Requests on the warm server: completion after `.` and at statement start, hover, definition,
   references. Median and p95.
4. RSS and CPU time of the server process and its children (`ps`).

The edits are overlays (`didOpen`/`didChange`/`didClose`): the projects on disk do not change.
The edit targets of each project are in `TARGETS` at the top of the script.

```sh
# one server, one project (JSON with all raw numbers in --out, summary on stdout)
tools/heavy.sh python3 -I bench/lsp_bench.py --server dart \
  --dart ~/fvm/default/bin/cache/dart-sdk/bin/dart --project bench/corpus/analyzer-9.0.0 \
  --cold-runs 3 --warm-runs 3 --full-runs 1 --out bench/results/lsp-analyzer-dart.json
tools/heavy.sh python3 -I bench/lsp_bench.py --server dartr \
  --project bench/corpus/analyzer-9.0.0 --cold-runs 3 --full-runs 1 \
  --out bench/results/lsp-analyzer-dartr.json
```

Use the SDK `dart` binary (not the Flutter wrapper script), so that the measured process tree is
the server. `--trace` prints every message to stderr. On a busy machine, compare CPU time and
repeat the runs: wall times change with the load average, which the script records.
