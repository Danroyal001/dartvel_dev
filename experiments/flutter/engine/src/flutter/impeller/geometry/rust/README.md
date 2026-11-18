# Impeller `geometry` in Rust

A file-by-file Rust port of Impeller's geometry library,
`engine/src/flutter/impeller/geometry`: every header and source file in it
(points, sizes, vectors, colors and blend modes, half floats, matrices and
their decomposition, quaternions, rects of every element type, saturated
math, rationals, trig tables, sigma, shear, RSTransform, Wang's formula,
gradients, stroke parameters, rounding radii, round rects, round
superellipses, arcs and the path sources). Each file under `src/` ports the
C++ file of the same name under `..`, keeps its structure and names, and names
that file in its first line. Files that are not ports (`lib.rs`, `cxx.rs`,
`print.rs`, the driver, the oracle test) say so in their first line.
`*_unittests.rs` modules port the gtest file of the same name.

The crate is a member of the Cargo workspace at `experiments/flutter` and
uses the `fml` port for `FML_DCHECK`/`FML_UNREACHABLE`. `lib.rs` denies
`unsafe_code`; the only `unsafe` in the library is the two calls into the SSE2
code of `Matrix::invert` and `get_determinant`, and the driver exports a C
`main` (see *Unsafe code*).

## What is ported

| Upstream | Port | Upstream tests | Rust tests |
|---|---|---|---|
| `scalar.h` | `src/scalar.rs` | — | — |
| `constants.h`, `.cc` | `src/constants.rs` | — | — |
| `type_traits.h`, `.cc` | `src/type_traits.rs` | — | — |
| `saturated_math.h` | `src/saturated_math.rs` | 18 | 18 |
| `point.h`, `.cc` | `src/point.rs` | 6 | 7 (one added) |
| `size.h`, `.cc` | `src/size.rs` | 5 | 5 |
| `vector.h`, `.cc` | `src/vector.rs` | — | — |
| `color.h`, `.cc` | `src/color.rs` | — | — |
| `half.h` | `src/half.rs` | — | — |
| `shear.h`, `.cc` | `src/shear.rs` | — | — |
| `quaternion.h`, `.cc` | `src/quaternion.rs` | — | — |
| `matrix_decomposition.h`, `.cc` | `src/matrix_decomposition.rs` | — | — |
| `matrix.h`, `.cc` | `src/matrix.rs` | 22 | 24 (two added) |
| `rect.h`, `.cc` | `src/rect.rs` | 97 | 97 |
| `trig.h`, `.cc` | `src/trig.rs` | 2 | 2 |
| `sigma.h`, `.cc` | `src/sigma.rs` | — | — |
| `gradient.h`, `.cc` | `src/gradient.rs` | — | — |
| `separated_vector.h`, `.cc` | `src/separated_vector.rs` | — | — |
| `rational.h`, `.cc` | `src/rational.rs` | 11 | 12 (one added) |
| `rstransform.h`, `.cc` | `src/rstransform.rs` | 2 | 2 |
| `wangs_formula.h`, `.cc` | `src/wangs_formula.rs` | 2 | 2 |
| `stroke_parameters.h`, `.cc` | `src/stroke_parameters.rs` | — | — |
| `path_source.h`, `.cc` | `src/path_source.rs` | 11 | 11 |
| `dashed_line_path_source.h`, `.cc` | `src/dashed_line_path_source.rs` | — | — |
| `rounding_radii.h`, `.cc` | `src/rounding_radii.rs` | 12 | 12 |
| `round_rect.h`, `.cc` | `src/round_rect.rs` | 27 | 27 |
| `round_superellipse_param.h`, `.cc` | `src/round_superellipse_param.rs` | — | — |
| `round_superellipse.h`, `.cc` | `src/round_superellipse.rs` | 31 | 32 (one added) |
| `arc.h`, `.cc` | `src/arc.rs` | 12 | 12 |
| `geometry_unittests.cc` (vector, color, quaternion, half, …) | `src/geometry_unittests.rs` | 84 | 84 (one ignored, as upstream skips it off macOS/iOS) |
| `geometry_asserts.h` | `src/geometry_asserts.rs` | — | — |

340 upstream tests, all ported; 5 added (below), and the tests of `cxx.rs`'s
rounding: 351 in all, 350 pass and 1 is ignored. The gtest assertions become `expect_*!`
macros over a `TestEq` trait that gives C++'s mixed-type `==`; gmock's
`StrictMock` with a `Sequence` becomes a recording receiver checked in order.

Not upstream files:

- `cxx.rs`: the C++ semantics the headers rely on: `std::min`, `std::max`
  and `std::clamp` (which differ from Rust's on NaN and signed zeros), glibc's
  `lroundf`, `floor`/`ceil`/`round` computed inline, and `Num`, which carries
  the usual arithmetic conversions of the element types the templates are
  instantiated with (`TPoint<int64_t> * float` computes in float and
  converts back).
- `print.rs`: how a default `std::ostream` prints a float (`%g`, six digits)
  and `std::fixed` (`%f`), which the `operator<<` overloads use.

## The oracle

The upstream C++ stays in this checkout and is the oracle.
`oracle/geometry_dump.cc` links all 26 upstream geometry sources (and fml's
logging) listed in `tests/oracle.rs` and prints what they compute;
`src/bin/geometry_dump.rs` is the same program over the port. Both draw every
input from the same splitmix64 stream, each draw its own statement (C++
leaves argument evaluation order unspecified), so the output is a function of
the suite, the seed and the case count. Every float is printed as its bit
pattern (`%08x`, doubles `%016llx`), so equality is byte-for-byte, except
NaN: IEEE 754 leaves the sign and payload of a NaN result unspecified and
LLVM does not preserve them (clang rewrites `a - b` as `a + -b` in places),
so both drivers print any NaN as ` nan`.

| Suite | What it drives |
|---|---|
| `scalar` | the constants, `Absolute`, `ScalarNearlyZero`/`NearlyEqual`, Degrees/Radians conversions and operators, and `saturated::` `Add`, `Sub`, `AverageScalar` and `Cast` on every width (`int8_t` … `int64_t`, float, double) at the edges |
| `point` | `TPoint<Scalar>`, `TPoint<int64_t>` and `TPoint<int32_t>`: every operator and compound assignment (mixed with sizes, scalars and integers), `Min`/`Max`/`Floor`/`Ceil`/`Round`, lengths, `Normalize` (zero included), `Cross`, `Dot`, `Reflect`, `Rotate`, `AngleTo`, `Lerp`, `GetDistanceToSegment`, `GetDistanceSquared`, `IsFinite`, `IsZero` |
| `size` | `TSize` of float, `int64_t` and `int32_t`: operators, `Min`/`Max`, `IsEmpty`, `Area`, `Ceil`, `MipCount` |
| `vector` | `Vector3` and `Vector4`: operators, `Normalize`, `Cross`, `Dot`, `Combine`, `Lerp`, `Min`/`Max`/`Floor`/`Ceil`/`Round` |
| `color` | the 142 named colors, every blend mode by name, the color operators, `Blend` for all 29 modes on unit colors, `ApplyColorMatrix`, premultiplication, sRGB conversions, `ToARGB`/`ToIColor`/8-bit round trips, `Random`'s shape, and `half` conversions |
| `matrix` | every `Make*` factory, operators, `Invert`, `GetDeterminant`, `Transpose`, `Basis`, scales, `IsAligned*`, `HasPerspective*`, `Decompose` and `Matrix(MatrixDecomposition)`, `TransformHomogenous`, `GetMaxBasisLength*`, `GetScales2D`, and `Quaternion` (operators, `Slerp`, `Invert`, `Normalize`) |
| `rect` | `TRect<Scalar>` and `TRect<int64_t>`/`TRect<int32_t>`: constructors (XYWH saturating, LTRB, point bounds), `Union`, `Intersection`, `Cutout`, `Contains`, `Expand`, `Shift`, `Scale`, `Project`, `RoundOut`/`RoundIn`/`Round`, `GetNormalizingTransform`, `TransformBounds`, `TransformAndClipBounds` (with perspective clipping), `ExpandToMinTransformedSize` |
| `misc` | trig tables, `Sigma`/`Radius`, `SeparatedVector2`, `Rational` (operators, `Invert`, hash), `RSTransform` (quad, bounds, matrix), Wang's formula for quads, conics and cubics, `CreateGradientBuffer`, `StrokeParameters` |
| `round` | `RoundingRadii` (scaled, `AreAllCornersSame`, operators), `RoundRect` and `RoundSuperellipse` (`MakeRectRadii` and its variants, `Contains`, `Shift`/`Expand`, `ToApproximateRoundRect`), `RoundSuperellipseParam` (octants, `Contains`), `Arc` (`GetTightArcBounds`, `ComputeIterations`, point counts), and every path source dispatched to a printing receiver: rect, ellipse, round rect, diff round rect, round superellipse, arc and dashed line |

Inputs are drawn to cover the edges: ±0, subnormals, `FLT_MAX`, ±infinity
and NaN as well as sane values, degenerate and inverted rects, zero and
negative radii and scales, matrices with and without perspective.

The C++ is built with the engine's linux-x64 floating point flags,
`-std=c++20 -O2 -march=x86-64 -ffp-contract=on -fwrapv`, plus `-DNDEBUG`
and `-stdlib=libc++`, from `engine/src` (`FP_FLAGS` in `tests/oracle.rs`).
`-march=x86-64` has SSE2 and no FMA, so `-ffp-contract=on` fuses nothing and
every `a * b + c` rounds twice, as Rust's does; there is no `-ffast-math`
anywhere in the engine. `-fwrapv` defines the signed overflow upstream
leaves undefined (see *Differences*).

## Running it

From `experiments/flutter`, with clang and libc++ (`libc++-dev`) installed:

```sh
cargo test -p impeller_geometry              # unit tests
cargo test --release -p impeller_geometry    # unit tests and the oracle
```

The oracle runs 9 suites × 16 seeds × 2000 cases (about 90 seconds). It is
a release-only test: the drivers feed inputs that upstream's `FML_DCHECK`s
reject (NaN scales, inverted rects), which a debug build of either side
aborts on, so a debug run of it only says so.
`GEOMETRY_ORACLE_SEED_BASE`, `GEOMETRY_ORACLE_SEEDS`,
`GEOMETRY_ORACLE_CASES` and `GEOMETRY_ORACLE_SUITES` pick another corpus;
`GEOMETRY_ORACLE_CXX`, `GEOMETRY_ORACLE_STDLIB` and `GEOMETRY_ORACLE_WORK`
the compiler, the standard library and the scratch directory. The test fails
on the first differing line and prints it.

Benchmarks: `geometry_dump bench <name> <rounds>` with either driver. Each
benchmark runs the ported code only: the inputs (4096 of each kind, from the
same seed in the same order) are generated before the first round, and each
result is folded into a checksum, which the two sides must agree on. Build
the Rust side with `cargo build --profile release-lto -p impeller_geometry`;
`tool/measure_rows.sh [bench...]` (from `experiments/flutter`) builds the C++
driver with the engine's flags and runs every row with `tool/measure.sh`: the
two drivers alternately, pinned to one core (`CPU`), `RUNS` runs a side of
`ROUNDS` rounds, failing unless every checksum agrees. `invert` and
`determinant` time `Matrix::Invert` and `GetDeterminant` alone. Where
`clang++` has no libc++ headers, `CXX` (and `GEOMETRY_ORACLE_CXX`) can name a
wrapper that adds them.

## Porting conventions

- Types keep their C++ names; methods and free functions become snake case.
  An overload set becomes one name per overload, named for what tells them
  apart (`contains` and `contains_rect`, `make_ltrb`, `round_out`).
- Templates become generics over `Num` (`TPoint<T>`, `TSize<T>`,
  `TRect<T>`), and the C++ arithmetic conversions are spelled out through it,
  so `TPoint<int64_t> * Scalar` computes in float and converts back exactly
  as `static_cast<Type>(x * scale)` does.
- Table constants written as double literals in C++ (the superellipse
  tables, `kThirdNSlope`) are ported as `f64 as f32`. Unqualified float math
  resolves to the float overloads as libc++'s does (`sqrt(2)` with an int
  argument is the double one).
- Functions upstream defines in a header are `#[inline]`, and functions it
  defines in a `.cc` are not, so the library's object code holds what the
  C++ objects hold and a caller can inline what a C++ caller can.
- Where the port computes a value differently for speed it gives the same
  bits, and a comment says why:
  - `floor`, `ceil` and `round` truncate through an integer and fix up the
    sign instead of calling libm (x86-64 has no SSE4.1 `roundss` in its
    baseline);
  - upstream's `1.0 / det` (in `Invert`) and `1.0 / GetWidth()` (in
    `GetNormalizingTransform`) divide in double and narrow; one division
    rounded twice equals one rounded once when the wider format has at least
    2p+2 bits (53 ≥ 2·24+2), so the port divides in float;
  - on x86-64, `Invert` and `GetDeterminant` run in SSE2 registers
    (`invert_sse2`, `get_determinant_sse2`): lane l of register g of
    `Invert` is cofactor 4g+l, and every lane adds upstream's six triple
    products in upstream's order (a subtracted product is added with its
    last factor negated, which is exact); `GetDeterminant`'s twelve minors
    are three registers of four, each lane upstream's two products and
    difference, and the final sum is taken left to right. `mulps`, `addps`
    and `xorps` round each lane as the scalar instructions do. rustc 1.99
    (LLVM 23) left the plain-array form of the same lanes scalar; it stays
    as the code for targets without SSE2 (`invert_portable`,
    `get_determinant_portable`) and as what the SSE2 code is tested against;
  - `Decompose` skips dividing by `e[3][3]` when it is 1 (exact);
  - `&&`/`||` chains with no side effects are evaluated with `&`/`|` and
    `Union`/`IntersectionOrEmpty`-style choices are selects, which avoids a
    branch per comparison on unpredictable data.

## Differences

- **Undefined behaviour upstream is defined here.** A float converted to an
  integer type that cannot hold it (NaN included) saturates, NaN to 0 as
  upstream's own `CastingNaNScalarToSignedIntProducesZero` expects; signed
  overflow wraps (the oracle pins upstream to the same with `-fwrapv`).
  The oracle does not feed upstream inputs that are undefined there: integer
  division by zero or `INT_MIN / -1`, `MipCount` of sizes below 0.5 or of
  `inf × inf`, `ToR8G8B8A8` outside [0, 1], dashed lines that never end,
  non-finite superellipse parameters, unsorted gradient stops.
- **FMA.** On arm64 clang contracts `a * b + c` into a fused multiply-add
  under `-ffp-contract=on`; Rust never fuses. The port therefore matches
  upstream's linux-x64 build, not its arm64 builds, wherever a product is
  added.
- `Color::Random` uses its own xorshift rather than `std::rand`; only its
  range is compared.
- `half.h` is ported for its Linux branch (`static_cast<uint16_t>(f)` in
  `ScalarToHalf`); the `_Float16` branch is for other targets.
- `Rational`'s ordering is built from its `<` and `==`, `std::gcd` keeps its
  semantics on negative values, and its hash zero-extends as upstream's does.
- Upstream's `ColorBufferNear`/`ColorsNear` test predicates and the
  `operator/` multiply slip in `Color` are kept as they are.
- The arc tests' `Trigs` (18 divisions, `kPrecomputedDivisions[100]`) are
  test support written by hand.

## Deliberate failures

Each rule below was broken on purpose, the tests named were run, and the
change was restored.

| Broken | Caught by |
|---|---|
| `saturated::Add` wraps | oracle `scalar` (4 of 4 seeds); `saturated_math` (3 tests) |
| `Point::GetLengthSquared` in float | oracle `point` (4 of 4) |
| ColorDodge compares in float | oracle `color` (4 of 4) |
| `Vector4(Vector3)` sets w to 0 | oracle `vector` (4 of 4) |
| `Decompose` sums the rotation in float | oracle `matrix` (4 of 4) |
| `Rect::GetWidth` not saturated | oracle `rect` (4 of 4) |
| `Rational` hash sign-extends | oracle `misc` (4 of 4) |
| `Arc` rounds iterations down | oracle `round` (4 of 4); `arc` (10 tests) |
| Superellipse `R` with `sqrt` in float | oracle `round` (4 of 4) |
| `Point::Normalize` of zero not the x axis | oracle `point` (4 of 4); **no upstream test** — `normalize_of_zero_is_the_x_axis` was added and fails |
| Superellipse rectangular corner includes its right edge | oracle `round` (4 of 4); **no upstream test** — `rectangular_corner_excludes_right_edge` was added and fails |
| `Rational ==` ignores signs | oracle `misc` (4 of 4); **no upstream test** — `negation_not_equals_different_den` was added and fails |
| `Rect::Union` | `rect` (4 tests) |
| `Matrix::Invert` | `matrix` (2 tests) |
| one cofactor lane of `Invert` with the wrong sign (SSE2 and portable code) | **no upstream test** — `invert_is_upstreams_bit_for_bit` was added and fails |
| `GetDeterminant`'s sum reassociated (SSE2 and portable code) | **no upstream test** — `determinant_is_upstreams_bit_for_bit` was added and fails |
| `RoundingRadii::Scaled` | `rounding_radii` (8 tests) |
| `RectPathSource` close line | `path_source` (2 tests) |
| Trig rotation | `trig` (9 tests across files) |
| Wang's formula precision | `wangs_formula` (2 tests) |
| `Size::IsEmpty` | `size` (2 tests) |
| `RSTransform` quad | `rstransform` (2 tests) |
| `Color::Premultiply` | `geometry` (2 tests) |
| Dash gaps | `path_source` (1 test) |
| inline `floor` loses the sign of −0 | `f32_rounding_matches_libm`, `f64_rounding_matches_libm` |
| inline `round` rounds halves to even | `f32_rounding_matches_libm`, `f64_rounding_matches_libm` |

Narrowing `Invert`'s reciprocal from double to float is not a break: it
gives the same bits (see *Porting conventions*), which is why the port does
it.

## Baseline

Measured 2026-11-06 with `tool/measure_rows.sh` on a shared 8-core AMD EPYC
whose load average stood at 5–7 from other work throughout. C++: clang
21.1.8 against libc++ 21 headers (libc++ 22 runtime), the engine's flags
(`-O2 -march=x86-64 -ffp-contract=on -fwrapv -fno-exceptions -fno-rtti
-DNDEBUG`). Rust: rustc 1.99.0 (LLVM 23), `--profile release-lto` (fat LTO,
one codegen unit, `panic = "abort"`). The harness runs the two drivers
alternately, 15 runs a side of 300 rounds of 4096 elements, both pinned to
the same core; every run's checksum agreed between the sides. *Fastest* is
the fastest round of all runs and *median* the median of the runs' medians,
in µs; peak RSS is the whole process (`VmHWM`), the largest of the runs.
The coefficient of variation between runs was 1–7% for the medians and
2–15% for the fastest rounds. Instruction counts are not given: this host
has `perf_event_paranoid` at 4, which refuses the counter to user space.

| Benchmark | C++ fastest | Rust fastest | C++ median | Rust median | C++ RSS | Rust RSS | Rust faster (fastest / median) |
|---|---|---|---|---|---|---|---|
| `point` (6 ops) | 206 | **168** | 292 | **250** | 5.27 MiB | **4.54 MiB** | 1.23× / 1.17× |
| `matrix` (7 ops) | 450 | **352** | 618 | **462** | 5.20 MiB | **4.50 MiB** | 1.28× / 1.34× |
| `invert` (`Invert` alone) | 174 | **93** | 259 | **139** | 5.16 MiB | **4.54 MiB** | 1.87× / 1.86× |
| `determinant` (`GetDeterminant` alone) | 39 | **29** | 55 | **39** | 5.13 MiB | **4.58 MiB** | 1.32× / 1.40× |
| `decompose` | 678 | **664** | 849 | **763** | 5.19 MiB | **4.52 MiB** | 1.02× / 1.11× |
| `rect` (10 ops) | 274 | **258** | 359 | **336** | 5.19 MiB | **4.50 MiB** | 1.06× / 1.07× |
| `irect` (6 ops) | 189 | **101** | 246 | **131** | 5.27 MiB | **4.51 MiB** | 1.88× / 1.88× |
| `color` (29 blends, sRGB, `ToIColor`) | 1626 | **1404** | 2401 | **2154** | 5.18 MiB | **4.62 MiB** | 1.16× / 1.11× |
| `rrect` (make, contains, dispatch) | 473 | **364** | 668 | **485** | 5.19 MiB | **4.59 MiB** | 1.30× / 1.38× |
| `rse` (make, contains, dispatch) | 7191 | **6870** | 9182 | **8785** | 5.27 MiB | **4.61 MiB** | 1.05× / 1.05× |
| `arc` (bounds, iterations) | 429 | **380** | 598 | **502** | 5.18 MiB | **4.59 MiB** | 1.13× / 1.19× |
| `gradient` | 849 | **440** | 1447 | **777** | 5.22 MiB | **4.60 MiB** | 1.93× / 1.86× |

Rust is ahead on every row on all three measures. The closest rows were
measured again at 31 runs a side and stayed ahead: `decompose` 646 against
674 fastest, 743 against 825 median; `rect` 260 against 273, 340 against
353; `rse` 7019 against 7091, 8749 against 9198. Against a C++ driver with
libc++ linked statically, which does not map the shared libraries, Rust's
peak RSS is still lower on every row (largest of 5 runs: 4.41–4.58 MiB
against 4.64–4.82 MiB).

Before this measurement `matrix` was 1–3 % behind on an Intel Xeon with
clang 18 and rustc 1.97, and on this host with rustc 1.99 level (437 against
442 µs fastest, 596 against 607 median), with `invert` level and
`determinant` behind on its fastest round (36 against 31 µs): LLVM 23 left
`Invert`'s lanes scalar (136 `mulss`, 480 instructions against clang's
496), and `GetDeterminant` was the same 76 instructions as clang's. The
SSE2 lanes (*Porting conventions*) are 187 and 51 instructions, with the
same bits. `rect` was 3–7 % behind on rustc 1.97 because `Union`,
`IntersectionOrEmpty`, `RoundOut` and `TransformBounds` were not inlined;
rustc 1.99 inlines all four (none is a symbol of the driver), and the row is
ahead with no change to the code.

Size, unstripped and stripped (`llvm-strip --strip-unneeded`):

| | C++ | Rust |
|---|---|---|
| library, archive of the objects | 113,762 B | **87,640 B** |
| library, stripped | 111,786 B | **87,336 B** |
| library, code and data (`size`) | 41,578 B | **37,033 B** |
| `geometry_dump` driver, libc++ shared | **269,568 B** (+ 1,347,432 B of `libc++.so.1` and `libc++abi.so.1` it loads) | 761,920 B (std linked in) |
| `geometry_dump` driver, libc++ shared, stripped | **244,552 B** (+ the same) | 673,192 B |
| `geometry_dump` driver, libc++ linked in | 1,360,544 B | **761,920 B** |
| `geometry_dump` driver, libc++ linked in, stripped | 1,040,408 B | **673,192 B** |

The library is the 26 upstream geometry `.cc` files compiled with the
engine's flags against the Rust crate's object code in a release build
(one codegen unit, which the workspace sets for this crate; emitted without
LTO, since the LTO build's object is bitcode). The drivers are like for like
when both carry their standard library: Rust's links std in, so the C++
driver that loads libc++ at run time is smaller on disk and larger with its
runtime.

Compile time, the library alone, one process at a time on the same loaded
host (3 builds each): the 26 C++ files took 92.9–98.5 s (each pulls in
libc++'s headers), the Rust crate in a release build (`-j1`, `fml`
already built) 2.0–9.5 s.

Cold start, the driver started and exiting at once (its usage error), timed
over 15 interleaved blocks of 200 executions pinned to one core, twice on
8 Nov: Rust 1.70 and 1.54 ms fastest block, 1.96 and 2.03 ms median; C++ with
libc++ linked in 1.86 and 1.60 ms, 2.08 and 1.97 ms; C++ with libc++ shared
2.32 ms fastest block and 2.92 ms median (one run of 9 blocks). Rust is ahead on the fastest block both times;
the medians change sides within 3%, this host's noise. The two drivers now make
the same 49 system calls to start, one for one. Until 8 Nov the Rust driver
made 73: std's `fn main` reads /proc/self/maps, installs SIGSEGV and SIGBUS
handlers on an alternate stack, ignores SIGPIPE and polls fds 0–2 before
`main` runs, and `std::env::args` set up the heap for the usage error. With
that start-up it was 1.95–2.13 ms fastest and 2.23–2.31 ms median in two
runs of the same blocks, behind the linked-in C++. The driver now enters through C's
`main` and counts its arguments from `argc` (`tests/cold_start.rs` fails if
either comes back), which also took 10.8 KB off the binary.

### Unsafe code

`lib.rs` denies `unsafe_code`. Calling a `#[target_feature]` function takes
`unsafe` even on a target that has the feature, so the SSE2 lanes are
entered through two `unsafe` blocks, the only ones in the library; inside
them the intrinsics are safe calls. The driver (`src/bin/geometry_dump.rs`,
not part of the library) is `#![no_main]` and exports C's `main` with
`#[unsafe(no_mangle)]`, so that std's runtime set-up does not run before it
(see *Baseline*, cold start). `tests/unsafe_audit.rs` (after
fml's) fails when an `unsafe` has no `SAFETY:` comment above it, tests its
checker on a failing sample, and pins the number of lines with `unsafe` at 6
(the `deny`, an `allow` and a block on each function, and the export).

| File | What | Why it is sound | Verified by |
|---|---|---|---|
| `matrix.rs`, `Matrix::invert` | `unsafe { self.invert_sse2() }` | compiled only under `cfg(all(target_arch = "x86_64", target_feature = "sse2"))`, so the CPU running it has the SSE2 that `#[target_feature(enable = "sse2")]` asks for; no pointers, the matrix goes in and out by value | `invert_is_upstreams_bit_for_bit`, the `matrix` tests and oracle `matrix`; under Miri |
| `matrix.rs`, `Matrix::get_determinant` | `unsafe { self.get_determinant_sse2() }` | as above | `determinant_is_upstreams_bit_for_bit`, oracle `matrix`; under Miri |
| `bin/geometry_dump.rs`, `main` | `#[unsafe(no_mangle)]` | the binary is `#![no_main]`, so nothing else defines `main`, and the function has the `int main(int, char **)` signature the C runtime calls it with | `tests/cold_start.rs`, the oracle (every suite runs through it) |

Safety: under Miri (`cargo +nightly miri test -p impeller_geometry --lib`,
one module or test at a time; rustc 1.101 nightly, Miri of 2026-11-04 since
6 Nov, nightly 2026-10 before), no test has reported undefined behaviour.
On 30 Oct 344 of the 347 tests then in the crate ran. Seven of them fail
under Miri's default, which perturbs the results of `sin`, `cos`, `log2` and
the like by a few ULP on purpose, because upstream compares those exactly
(`trig` `multiply_by_scalar_radius`, `rstransform` `compare_to_matrix`,
`matrix` `is_aligned`, `is_aligned_2d`, `min_max_scales_2d`, `geometry`
`can_generate_mip_counts`, `test_decomposition2`); all seven pass with
`MIRIFLAGS=-Zmiri-deterministic-floats`. On 6 Nov the three `arc` tests that
sweep thousands of angles, which had been stopped after 25 minutes each, ran
to the end with `-Zmiri-deterministic-floats`:
`arc_iterations_various_tiny_arcs_near_quadrant_axis` passed in 137 s and
`arc_iterations_various_start_angles_near_quadrant_axis` in 643 s;
`arc_iterations_various_end_angles_near_quadrant_axis` (36,000 arcs, ten
times the others) in 10,743 s; Miri reported no undefined behaviour in any. The `matrix` module with the SSE2 code,
under Miri's default flags: `determinant_is_upstreams_bit_for_bit` (40,000
matrices through the SSE2 lanes) passed, and the 22
other tests, which call `invert` and `get_determinant` through the SSE2 code,
pass (the three listed above need `-Zmiri-deterministic-floats` here too);
`invert_is_upstreams_bit_for_bit` was stopped after it had run for more than an
hour in the interpreter (it runs three inversions of each of 40,000 matrices, and passes
natively).


Coverage of the library by the unit tests and the oracle (4 seeds; measured
2026-10-30, before the SSE2 lanes),
measured with `-C instrument-coverage -Zcoverage-options=branch` and LLVM 22's
`llvm-cov`: **94.6 % of lines (4186 of 4424) and 93.9 % of branches (682 of
726)**; the unit tests alone cover 71.6 % of lines and 78.5 % of branches.
Below 90 % of lines: `half.rs` (63 %: upstream's own half test is skipped
off macOS/iOS, and the oracle drives the Linux conversions only),
`type_traits.rs` (compile-time only), `arc.rs` (78 %: the debug-only
checks and the precomputed-trig cache paths), `rstransform.rs` (85 %),
`cxx.rs` (87 %: conversions for element types upstream never instantiates)
and `print.rs` (86 %).

## Not ported yet

- `geometry_benchmarks.cc`: it benchmarks the tessellator and shadow
  vertices (`impeller/tessellator`, `impeller/entity`), which are not part
  of this library; the drivers' `bench` mode benchmarks the library itself.
