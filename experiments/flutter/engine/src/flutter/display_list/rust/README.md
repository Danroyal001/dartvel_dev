# Display list Rust foundation (partial)

This is an experimental, incomplete port beside Flutter's
`engine/src/flutter/display_list`. It is a Cargo workspace member at
`experiments/flutter`. Nothing under `packages/` depends on it.

## Implemented and checked

- `dl_types.h`: clip, point and source-rectangle-constraint enums.
- `dl_sampling_options.h`: filter and image-sampling enums.
- `dl_tile_mode.h`: tiling enum.
- `utils/dl_accumulation_rect.h/.cc`: finite point accumulation, rectangle and
  accumulator accumulation, bounds, reset and conservative overlap detection.
  Geometry uses the existing `impeller_geometry` crate's `Rect` and `Point`.

Methods retain upstream semantics, including exclusive upper edges, degenerate
point bounds, rejecting non-finite points but accepting infinite rectangle
edges, and not copying a merged accumulator's overlap flag. The enums use
32-bit representations, matching the C++ oracle's layout on Linux x64.

## Oracle and tests

From `experiments/flutter`:

```sh
cargo test -p display_list
cargo test --release -p display_list
```

The oracle requires `clang++-18` and libc++ 18 headers/runtime. If those are
installed outside PATH, explicitly select a compiler wrapper:

```sh
DL_ORACLE_CXX=/path/to/clang18-libcxx18-wrapper cargo test --release -p display_list
DL_ORACLE_SEED_BASE=1001 DL_ORACLE_CXX=/path/to/wrapper cargo test --release -p display_list --test oracle
```

The compiler receives `-std=c++20 -O2 -march=x86-64 -ffp-contract=on -fwrapv
-DNDEBUG -stdlib=libc++ -fno-exceptions -fno-rtti`. The harness builds unchanged
upstream `utils/dl_accumulation_rect.cc` and fml logging, links them to
`oracle/foundation_dump.cc`, and compares stdout byte-for-byte against
`display_list_dump` on identical input. It checks exit status and stderr too;
an unavailable compiler or failed build fails the test, with no silent skip.
Each invocation recompiles the reference so edits cannot leave a stale oracle.
Outer command timeouts are required, as with the existing engine harnesses.

The corpus contains the six upstream accumulator unit-test cases and their
subcases, 196 pairs drawn from floating-point edges (signed zero, NaN,
infinities, subnormals, extremes), and 16 seeds × 16 sequences × 64 mixed
operations, checking bounds bits and flags after every operation. Enum layout
and representative discriminants are also compared. Six upstream accumulator
test functions are ported as Rust tests, with an additional boundary/reset/
non-finite/merge regression. Existing enum tests bring the unit total to 13.

The initial comparison failed against an intentionally unimplemented Rust
driver. Changing the point upper-X comparison from `<` to `<=` is the deliberate
mutation used to check that the tests reject changed overlap behavior. Results
and exact commands are recorded in `PROGRESS-rust-dlist.md` at the repo root.

The crate and its driver/tests forbid unsafe code. This does not make the
transitive geometry/fml dependencies free of unsafe code; see their READMEs.

## Remaining work and measurements

`DisplayList`, `DisplayListBuilder`, op recording/dispatch/serialization,
paint, paths, effects, images, text, vertices, culling, region and R-tree are
not implemented here. There is no full-list equality/hash or op-stream oracle.
No placeholder modules are exported or counted as tests. The inherited
unverified scaffold is not part of this crate's supported implementation.

| Required gate | Status |
|---|---|
| Foundation byte comparison | See progress log; not full-list parity |
| Full C++ display list build/link | Pending Skia dependency/build setup |
| Op streams, bounds/culling, R-tree, equality/hash | Not measured |
| Upstream display-list benchmarks, fastest/median | Not measured |
| Peak RSS, stripped/unstripped size, compile/cold-start | Not measured |
| Instruction counts | Not measured |
| Miri / workspace release tests | See progress log |

The benchmark cases under upstream `benchmarking/` require the actual builder
and dispatch path. A small accumulator microbenchmark would not satisfy that
bar, so no substitute performance claim is made. This foundation does not
meet the brief's whole-component completion or performance gates.
