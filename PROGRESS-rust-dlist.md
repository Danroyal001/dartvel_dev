# Rust Port: Flutter engine display_list (Track B)

**Branch:** `agent/rust-dlist` (based on `feat/rust-stack-experiments`)
**Target:** Port `experiments/flutter/engine/src/flutter/display_list` to Rust beside the C++

## Progress Log

### 2026-11-06 - Started
- Read brief and existing Rust crates (fml, impeller_geometry) for patterns
- Created this progress file
- No Rust code for display_list exists yet

### Next Steps
1. Create Rust crate structure at `experiments/flutter/engine/src/flutter/display_list/rust/`
2. Create Cargo.toml with dependencies on fml and impeller_geometry
3. Create oracle test infrastructure (C++ dump program + Rust driver)
4. Start porting core types: dl_types, dl_color, dl_blend_mode, dl_tile_mode, dl_sampling_options
5. Port op recording: dl_op_records, dl_op_flags, dl_op_receiver
6. Port builder state: dl_builder, dl_canvas
7. Port geometry helpers: dl_path, dl_path_builder, dl_region, dl_rtree (reuse impeller_geometry)
8. Port effects: color filters, color sources, image filters, mask filters, runtime effects
9. Port image handling: dl_image
10. Port vertices and text
11. Run oracle tests and verify 0 differences
12. Benchmark against C++ upstream

## Slices (per brief)
1. **Op recording + builder state first** - dl_op_records, dl_op_flags, dl_op_receiver, dl_builder, dl_canvas, core types
2. **Bounds/culling** - dl_path, dl_path_builder, dl_region, dl_rtree, geometry conversions
3. **RTree/hit regions** - dl_rtree, hit testing
4. **The rest** - effects, image, vertices, text, storage, unittests

## Oracle Results
- Not started yet

## Measurements vs Upstream
- Not started yet
### 2026-11-06 — takeover, inspection
- Read ~/AGENTS.md, repository AGENTS.md/CLAUDE.md, brief, queue Rust bar,
  proposal and existing analyzer/fml/geometry crate READMEs; skimmed recent lead conversation.
- Existing branch is `agent/rust-dlist`, as recorded by the lead; retain it.
- Inherited untracked crate has 29 placeholder modules, invalid dependency paths,
  duplicate geometry names, nonexistent root imports and a missing binary. No oracle exists.
  These are not ported features or passing evidence. Preserve inherited files;
  only commit independently verified work.
- Compiler available: clang 21.1.8 with user-space libc++ headers/runtime wrapper
  `~/.local/libcxx21/clang++`; requested clang/libc++ 18 is absent.
- Checking upstream builder compilation before implementation. Next: establish
  real-C++ differential harness, record its initial failure, then port the
  dependency-independent foundation. Full builder requires Skia dependencies.
- No benchmark, parity or completion claim yet. No push/merge/deploy/messages.

### Upstream build probe and oracle written
- Correct include paths reproduce builder failure at
  `third_party/skia/include/core/SkRefCnt.h`: third-party Skia is not checked out.
  This is the first concrete full-builder oracle blocker (not a Rust failure).
- Added a C++ foundation driver using unchanged upstream headers and
  `utils/dl_accumulation_rect.cc`; no replacement C++ algorithm or stub dependency.
- Added byte comparison corpus: enum values/layout, non-finite and signed-zero
  point inputs, seeded mixed point/rectangle/merge/reset/overlap sequences.
- Rust diagnostic driver intentionally still returns `not ported`, to establish red
  before implementation. Cargo test is waiting for the shared heavy-build slots.
- Next: observe red, implement accumulator, then rerun comparison and unit cases.

### Red gate: toolchain
- `timeout 180 ~/heavy.sh ~/.cargo/bin/cargo test --manifest-path
  experiments/flutter/Cargo.toml -p display_list --test oracle -- --nocapture`
  compiled the foundation test and failed: `clang++-18` not found.
- Explicit clang 21 override run underway (log `/tmp/rust-dlist-oracle-red.log`);
  no implicit fallback was added. Six upstream accumulator test functions plus
  a boundary/non-finite/reset/merge regression have been written before the port.

### Red gate: real comparison
- Explicit clang 21 run built and executed upstream C++ successfully. Comparison
  failed at line 0 (`enums 4 4 4 4 4 4 ...` vs `not ported`), exit 101;
  `/tmp/rust-dlist-oracle-red.log` retains the initial failing corpus.
- apt packages for clang 18/libc++ 18 are available: downloaded and extracted
  locally (no sudo or system package changes). Testing this requested toolchain next.
- Existing scaffold is preserved at
  `~/.cache/rust-dlist-inherited/scaffold-before-port.tar`; unrelated placeholder
  files remain untracked and outside the compiled/exported crate surface.
- Next: implement the accumulator and fix the enums' inherited 1-byte layout
  (real upstream enums are 4 bytes).

### Implementation step: accumulator
- Ported `utils/dl_accumulation_rect.h/.cc` using the existing Impeller `Rect`
  and `Point` types: point/rectangle/accumulator overloads, reset, conservative
  overlap, bounds and emptiness. Own crate forbids unsafe code.
- Preserve strict comparisons (signed zero), reject non-finite points, retain
  infinite rectangle edges and do not inherit a merged accumulator's overlap flag.
- Corrected six foundational enum layouts to match upstream's 32-bit enums.
- Requested toolchain now works locally: clang 18.1.8 + libc++ 18 from Ubuntu
  packages, wrapper `~/.cache/rust-dlist-toolchain18/clang++`.
- Running foundation suite against that wrapper; log
  `/tmp/rust-dlist-foundation-green.log`. Next: inspect results, add exact upstream
  test-case inputs to the oracle, deliberate mutation, release/workspace checks.

### Foundation green on requested toolchain
- clang 18.1.8 + libc++ 18: 6 enum tests, all 6 upstream accumulator tests
  (including their subcases), 1 added regression and 1 real-C++ oracle pass.
- Oracle: 16 seeds × 16 sequences × 64 operations = 16,384 operations,
  plus 196 non-finite/signed-zero/edge point pairs; byte differences = 0.
- Full default command still requires clang++-18 on PATH or explicit DL_ORACLE_CXX.
- Downloaded only pinned Skia headers (revision from experiments/flutter/DEPS)
  to an external cache; retrying upstream builder syntax probe without stubs.
- Next: deliberate accumulator mutation and restore, release/Miri checks,
  document precisely what remains, atomic foundation commit.

### Mutation check queued
- Deliberately changed the point upper-X comparison `<` to `<=`.
  Correct source is saved at `/tmp/rust-dlist-accumulator-correct.rs`.
  Restore it before committing; current mutation run is waiting on heavy slots.
- Pinned Skia public headers downloaded successfully; adding their include roots
  gets past the missing header. A 15-second builder syntax probe now times out
  (rather than reporting a missing header); no full builder or Skia library has
  been built. The initial dependency blocker is therefore partly resolved, not
  evidence that a full oracle can never be built.

### Mutation unit test result
- Deliberate `<` → `<=` point-edge mutation fails 3 of 7 accumulator tests:
  `two_points`, `three_points`, `edge_nonfinite_reset_and_merge`.
- Oracle-only mutation run is underway; a shell EXIT trap restores the exact
  correct source after the run, even on timeout. Log:
  `/tmp/rust-dlist-oracle-mutation.log`.
- Added upstream's explicit subcases to the oracle input, not just to Rust tests.
- Added crate README with run commands, scope, safety limits and every unmeasured
  gate. Next: inspect oracle mutation, restore, release/Miri/workspace runs.

### Mutation oracle result and restore
- Real-C++ oracle also fails the upper-X mutation (first mismatch in upstream
  unit-case corpus); exit 101. Correct source restored and byte-checked against
  saved copy before moving it to `src/utils/dl_accumulation_rect.rs`.
- Unused inherited placeholder/unverified modules moved intact to
  `~/.cache/rust-dlist-inherited/unverified-modules/`; none will enter the commit.
  Their earlier source archive remains available too.
- Formatted only this crate. Starting release + held-out-seed checks, then Miri
  and the existing Flutter Rust workspace tests.

### Builder object probe resolved; mutation correction
- With pinned Skia public headers and all three include roots, clang 18 compiles
  real `dl_builder.cc` to `/tmp/rust-dlist-builder.o` (298,616 bytes). The original
  missing-header problem is resolved for this translation unit. Full link still
  needs Skia and the other display-list/engine objects; no full-list oracle yet.
- Inspection of the first mutation shows the broad substitution also changed
  `is_not_empty`'s comparison, not just point overlap. Its oracle mismatch was
  the emptiness flag, so it cannot be claimed as an overlap-only oracle check.
  Correct source is restored. Next run will target only the point `if` line.

### Release green and pinned Skia source available
- Full foundation release suite passes on clang/libc++ 18: 13 unit tests,
  real-C++ oracle (including explicit upstream subcases), zero byte differences.
  Log `/tmp/rust-dlist-release.log`.
- Downloaded pinned Skia's complete source archive (77 MiB) to external cache,
  not to tracked experiments or production packages. No Skia library has been
  built yet. Investigating build tooling/dependencies for the full oracle.
- Exact overlap-only mutation is running under an EXIT restore trap; it changes
  only `if x >= self.min_x && x < self.max_x ...`, not emptiness predicates.

### Exact overlap mutation caught
- Restricted `<` → `<=` mutation to the point overlap `if` line only.
  Real-C++ oracle fails on overlap (no emptiness predicate changed), exit 101;
  log `/tmp/rust-dlist-overlap-only-mutation.log`.
- Restored correct formatted source and verified exact equality with saved copy.
- Next: Miri (own unit tests), held-out seed base 1001, complete Flutter Rust
  release workspace suite. Any pre-existing failures will be reported unchanged.
