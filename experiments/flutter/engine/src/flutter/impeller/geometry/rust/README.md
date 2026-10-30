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
uses the `fml` port for `FML_DCHECK`/`FML_UNREACHABLE`. It has no `unsafe`:
`lib.rs` declares `#![forbid(unsafe_code)]`.

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
| `matrix.h`, `.cc` | `src/matrix.rs` | 22 | 22 |
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

340 upstream tests, all ported; 3 added (below), and 3 for `cxx.rs`'s
rounding: 347 pass, 1 is ignored. The gtest assertions become `expect_*!`
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
the Rust side with `cargo build --profile release-lto -p impeller_geometry`.

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
  - `GetDeterminant`'s twelve minors are computed a row pair at a time, each
    with its own two products and difference;
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

Measured 2026-10-30 on a 4-core Intel Xeon at 2.10 GHz shared with other
builds (load average 7–10, so every figure is the best of 7 interleaved runs
of 300 rounds, pinned to one core). C++: clang 18.1.3, libc++ 18, the
engine's flags (`-O2 -march=x86-64 -ffp-contract=on -fwrapv -fno-exceptions
-fno-rtti -DNDEBUG`). Rust: rustc 1.97.0, `--profile release-lto` (fat LTO,
one codegen unit, `panic = "abort"`). Times are per round of 4096 elements,
in µs; peak RSS is the whole process (`VmHWM`). The checksums agree on every
benchmark.

| Benchmark | C++ fastest | C++ median | C++ slowest | Rust fastest | Rust median | Rust slowest | C++ RSS | Rust RSS |
|---|---|---|---|---|---|---|---|---|
| `point` (6 ops) | 194 | 212 | 546 | **176** | **188** | 475 | 4.8 MiB | **4.3 MiB** |
| `matrix` (7 ops) | **425–441** | 463–549 | 765–1065 | 436–446 | 485–513 | 921–1337 | 4.8 MiB | **4.3 MiB** |
| `decompose` | 585 | 637 | 918 | **581** | **627** | 985 | 4.8 MiB | **4.2 MiB** |
| `rect` (10 ops) | **200–212** | **218–227** | 307–405 | 213–220 | 225–228 | 313–1142 | 4.8 MiB | **4.3 MiB** |
| `irect` (6 ops) | 146 | 155 | 286 | **60** | **67** | 144 | 4.8 MiB | **4.2 MiB** |
| `color` (29 blends, sRGB, `ToIColor`) | 887–1004 | 1090–1163 | 1853–3703 | 997–1040 | **1070–1105** | 2036–2458 | 4.9 MiB | **4.3 MiB** |
| `rrect` (make, contains, dispatch) | 339 | 373 | 591 | **223** | **236** | 412 | 4.8 MiB | **4.3 MiB** |
| `rse` (make, contains, dispatch) | 4321–4922 | 4983–6129 | 8562–18507 | **4025–4519** | **4975–5875** | 8613–12326 | 4.8 MiB | **4.3 MiB** |
| `arc` (bounds, iterations) | 331 | 348 | 517 | **261** | **290** | 434 | 4.8 MiB | **4.3 MiB** |
| `gradient` | 369 | 402 | 760 | **329** | **345** | 432 | 4.8 MiB | **4.3 MiB** |

Ranges are over three such measurements where the result was close.
Rust is faster on `point`, `irect`, `rrect`, `rse`, `arc` and `gradient`,
level on `decompose` and `color` (each side wins some runs), and **slower on
`matrix` (by 1–3 %) and `rect` (by 3–7 %)**; it uses about 0.5 MiB less
memory on every benchmark. In `matrix` the gap is `Invert` and
`GetDeterminant`, each about 10 % slower than clang 18's code in isolation:
rustc's LLVM 22 vectorizes the cofactor sums with more shuffles, and four
bit-identical reformulations (a term table, column groups, row pairs, minor
pairs) did not beat it. In `rect` it is `Union`, `IntersectionOrEmpty`,
`RoundOut` and `TransformBounds`, which clang inlines and LLVM 22, given the
same hints, does not.

Size, unstripped and stripped (`llvm-strip --strip-unneeded`):

| | C++ | Rust |
|---|---|---|
| library, archive of the objects | 123,320 B | **93,294 B** |
| library, stripped | 120,264 B | **92,950 B** |
| library, code and data (`size`) | 43,772 B | **39,249 B** |
| `geometry_dump` driver | **265,880 B** (+ 1,300,112 B of `libc++`, `libc++abi` and `libunwind` it loads) | 799,096 B (std linked in) |
| `geometry_dump` driver, stripped | **240,456 B** (+ the same) | 709,016 B |

The library is the 26 upstream `.cc` files compiled with the engine's flags
against the Rust crate's object code in a release build (one codegen unit,
which the workspace sets for this crate: with the default 16 the archive is
129,970 B). The drivers are not like for like: Rust's carries its standard
library, C++'s loads libc++ at run time; with its runtime, the C++ driver is
the larger.

Safety: the crate has no `unsafe` (`#![forbid(unsafe_code)]`). Under Miri
(`cargo +nightly miri test -p impeller_geometry --lib`, one module at a time,
nightly 2026-10) 344 of the 347 tests ran and Miri reported no undefined
behaviour. Seven of them fail under Miri's default, which perturbs the
results of `sin`, `cos`, `log2` and the like by a few ULP on purpose, because
upstream compares those exactly (`trig` `multiply_by_scalar_radius`,
`rstransform` `compare_to_matrix`, `matrix` `is_aligned`, `is_aligned_2d`,
`min_max_scales_2d`, `geometry` `can_generate_mip_counts`,
`test_decomposition2`); all seven pass with
`MIRIFLAGS=-Zmiri-deterministic-floats`. The three `arc` tests that sweep
thousands of angles (`various_start_angles`, `various_end_angles`,
`various_tiny_arcs_near_quadrant_axis`) did not finish in 25 minutes each
under the interpreter and were stopped.

Coverage of the library by the unit tests and the oracle (4 seeds),
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
- `matrix` and `rect` are not yet faster than upstream (see *Baseline*).
