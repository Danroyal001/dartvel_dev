# The Dart and Flutter Stack in Rust — Proposal

**Status: Final draft, 29 October 2026, accepted as a side effort. Nothing
here is built.** This is the full
programme. `NEW_SPEC.md` carries a short summary as *Side Effort: The Dart and
Flutter Stack in Rust*, with the usual labels. It does not change any Dartvel
package. Everything it builds lives in `dartvel_dev` under `experiments/`: the
Rust ports, the pinned upstream Dart SDK and Flutter sources they port from,
and the Dart tooling. No component gets a repository of its own. Part 10
lists the edits the specification needs once a component ships.
Parts 11–13 give the effort, the timeline, the token cost and the prompts to
run it with.

## Contents

1. Goal
2. What "the whole stack" is, measured
3. Compatibility contracts
4. What "provable" means, claim by claim
5. The tracks
6. Method
7. Order of work
8. The test bar and the gates
9. Third-party libraries
10. How this ties into Dartvel
11. Effort
12. Timeline (optimistic)
13. Token cost (optimistic)
14. Considered and not proposed
15. Open questions
16. Appendix A — Coordinator prompt
17. Appendix B — Worker prompt
18. Appendix C — Reviewer prompt
19. Appendix D — Prior art and sources

---

## 1. Goal

A 1:1 implementation of the Dart and Flutter stack in Rust that:

- is **100% compatible**: every Dart program, package, tool, IDE integration
  and Flutter app works unchanged and passes the same tests as on Google's
  implementation of the same version;
- is **provably faster**, component by component, on published and
  reproducible benchmarks;
- **provably uses less memory**: no more peak memory than the original on any
  corpus, and less on the reference set;
- is **provably safer**: memory-safe outside a counted and verified `unsafe`
  core, with `dart:ffi` checked statically;
- **stays current**: every upstream Dart and Flutter release, new features
  included, is matched on a fixed schedule.

Subsets, mirrors and look-alikes are out of scope. A component replaces its
upstream counterpart only when it matches it.

## 2. What "the whole stack" is, measured

The stack has two kinds of code, and the difference decides what is ported.

- **Implementation**: tools, compilers, runtimes and the engine. Users never
  import it, so it can change language. **Ported.**
- **API surface written in Dart**: the Dart source of the `dart:*` libraries,
  the Flutter framework (`package:flutter`, `flutter_test`,
  `integration_test`), and Flutter's web engine (`lib/web_ui`), which is
  compiled into every web app. Apps import it, IDEs open it, debuggers step
  through it, hot reload patches it, and stack traces name it. **Stays Dart,
  byte for byte the same as upstream.** The web engine stays Dart for one more
  reason: moving it into Rust compiled to WebAssembly would put a JS/Wasm
  boundary under every `dart:ui` call a web app makes, which fails the speed
  gate.

The sizes below were measured on 29 October 2026 at `dart-lang/sdk`
`ceea75dd2b82` and `flutter/flutter` `c3f5b027df2b`, plus the current
`dart-lang/pub` and `dart-lang/dart_style`. They count non-blank lines. A file
counts as a test when its path names a test, fixture, benchmark or testing
directory. These are counts of what exists, not estimates.

### Ported

| Component | Language | Implementation | Tests |
|---|---|---|---|
| Dart VM (`runtime/vm`: object model, GC, compiler back ends, isolates, service) | C++ | 484k | 94k |
| ...of which the VM's compiler back ends (`runtime/vm/compiler`) | C++ | 235k | 45k |
| `dart:io` embedder and natives (`runtime/bin`, `runtime/lib`, `runtime/platform`) | C++ | 65k | 30k |
| Compiler front end (`pkg/front_end`) | Dart | 319k | 120k |
| Kernel (`pkg/kernel`) and VM kernel transforms (`pkg/vm`) | Dart | 124k | 17k |
| Shared front-end layer (`pkg/_fe_analyzer_shared`) | Dart | 67k | 70k |
| `frontend_server` | Dart | 4k | 8k |
| Analyzer (`pkg/analyzer`) | Dart | 291k | 1,113k |
| Analysis server (`pkg/analysis_server`) | Dart | 219k | 371k |
| Linter (`pkg/linter`) | Dart | 35k | 62k |
| Formatter (`dart_style`) | Dart | 22k | 4k |
| dart2js (`pkg/compiler`) | Dart | 146k | 104k |
| dart2wasm | Dart | 43k | 5k |
| DDC (`pkg/dev_compiler`) | Dart | 41k | 17k |
| `dart` CLI (`pkg/dartdev`), DDS, `vm_service` | Dart | 31k | 69k |
| pub | Dart | 33k | 44k |
| Flutter engine: `fml`, `runtime`, `shell` (C++ and Objective-C++), `lib/ui` natives, `flow`, `display_list`, Impeller, `txt`, Vulkan, `skwasm`, `tonic`, accessibility | C++, ObjC++ | 408k | 230k |
| `flutter` CLI (`packages/flutter_tools`, with the daemon protocol) | Dart | 190k | 277k |
| **Total ported** | | **≈ 2.52M** | **≈ 2.6M** |

### Stays as it is

| Component | Language | Size |
|---|---|---|
| `dart:*` library sources (`sdk/lib`) | Dart | 234k |
| Flutter framework (`packages/flutter`) | Dart | 571k |
| Flutter web engine (`lib/web_ui`) | Dart | ≈ 145k |
| Android embedding public API (Java) | Java | 40k |
| iOS and macOS public headers | Objective-C | headers only |
| Third-party C/C++ (Skia, HarfBuzz, ICU, FreeType, codecs, BoringSSL, …) | C/C++ | Part 9 |

## 3. Compatibility contracts

Every component keeps its external contracts exactly.

| Contract | Who depends on it |
|---|---|
| Command lines, options, exit codes and output formats of `dart`, `flutter`, `pub` and every subcommand | Developers, CI, scripts |
| The analysis server and LSP protocols, the `flutter daemon` protocol, the `frontend_server` protocol | IDEs, the `flutter` tool, hot reload |
| The VM service protocol and DDS | DevTools, debuggers, profilers, `integration_test` |
| File formats: kernel (`.dill`), snapshots, `package_config.json`, `pubspec.lock`, shared analysis caches | Every tool that reads another's output |
| The Dart embedding API (`dart_api.h`) and the Flutter embedder API (`flutter_embedder.h`) | Custom embedders, Dartvel's included |
| `dart:ui` native entry points and the platform-embedding public APIs | Every app and plugin |
| Engine artifact names and layout, and the SDK's engine pin | The `flutter` tool |
| Observable program behaviour, within the guarantees the language specification makes | Every program |

Each component also has three levels of compatibility, and declares the one it
promises:

| Level | Promise | Proof |
|---|---|---|
| **Identical output** | The same bytes or diagnostics as the original, for the same input | Comparison against the pinned original on large corpora |
| **Identical behaviour** | The same observable behaviour of every program | Upstream test suites unmodified, plus differential runs |
| **Lossless dialect** | Source standard tools can't read, converting to and from standard Dart with nothing lost | Round-trip of the whole pub.dev corpus |

## 4. What "provable" means, claim by claim

| Claim | What counts as proof |
|---|---|
| **Compatible** | Upstream's own test suites, unmodified, pass on both implementations at the same commit with the same results. Differential runs against upstream as the oracle, on corpora no porting agent saw. This is evidence, not a mathematical proof, and is never called more. |
| **Safe** | A count of `unsafe` blocks per module, gated so it can't grow unreviewed. Every `unsafe` module runs under Miri on its tests and is fuzzed. The core pieces (the collector, Track D's free placement, the JIT's code buffers) are model-checked with Kani on the invariants their safety comments state. A sanitizer build of the whole stack runs the full test bar. |
| **Faster** | Upstream's benchmark suites (the Dart SDK's benchmarks, Flutter devicelab) and the toolchain corpora (Flutter, the top pub.dev packages, large apps). Run on named reference machines, with method, raw data and both versions published, every release. |
| **Less memory** | Peak RSS and, for runtimes, heap high-water mark, on the same runs, under the same rules. |
| **Track D's frees are sound** | A written soundness argument for the free-placement analysis, in the style of the Perceus paper; poisoned-memory sanitizer runs of the full test bars with zero traps; Kani harnesses on the runtime's free paths. |

A component replaces its upstream counterpart in a Dartvel release only when
every row that applies to it is met. A claim the proof doesn't support is not
made.

## 5. The tracks

| Track | Scope | Level |
|---|---|---|
| **A. Tools** | Analyzer, analysis server, linter, formatter, `dart fix`, LSP | Identical output |
| **B. FFI safety** | Static `dart:ffi` lifetime checks; a `no-gc` contract | Analysis only |
| **C. Compilers** | CFE, kernel, `frontend_server`; then dart2js, dart2wasm, DDC | Identical output |
| **D. Partitioned memory** | Stack, owned, acyclic-RC and traced partitions | Identical behaviour |
| **E. Flutter engine** | Everything listed for the engine in Part 2 | Identical behaviour |
| **F. Dart VM** | Everything listed for the VM in Part 2 | Identical behaviour |
| **G. CLIs** | `dartdev`, DDS, pub, `flutter_tools` | Identical behaviour |
| **H. Upstream tracking** | Every upstream change after the initial port | Each change at its component's level |
| **I. Optional semicolons** | The `.dv` dialect | Lossless dialect |

### Track A — Tools

A 1:1 port of `pkg/analyzer`, `pkg/analysis_server`, `pkg/linter`,
`_fe_analyzer_shared` and `dart_style`. Each Rust file keeps the structure and
names of the Dart file it ports and names that file in its first line, so
upstream changes can be followed file by file.

Track A is ported from the Dart SDK itself, in the same fork of
`dart-lang/sdk` as every other Dart track, not from a third-party port.
`dartr` (BSD-3-Clause) ports this slice independently; it is prior art only
and is not vendored or built on.

The memory gate applies from the first day, language server included:

- arena storage with 32-bit indices instead of pointers;
- interned names and types;
- syntax trees dropped once summaries exist;
- memory-mapped summaries.

### Track B — FFI safety and `no-gc` contracts

Analysis only, on existing Dart syntax, so no program changes meaning:

- a `Pointer` from an `Arena` must not escape its `using(...)`;
- double free and use after free on paths the analyzer can follow;
- `NativeFinalizer` rules checked rather than left to undefined behaviour: no
  Dart C API calls in the callback, no `Pointer.fromFunction` trampolines;
- ownership annotations (`@owned`, `@borrowed`) through the existing metadata
  syntax, for APIs the analysis can't infer;
- `@pragma('dartvel:no-gc')`: the build proves the function and its callees
  never allocate managed memory or enter the GC. Standard Dart ignores
  pragmas.

### Track C — Compilers

The CFE, kernel serialization, the incremental compiler and `frontend_server`
first. They share Track A's front-end crates, because the analyzer and the CFE
share `_fe_analyzer_shared` upstream. Then dart2js, dart2wasm and DDC.

The contract is byte-identical output for the same input and options. Where
byte identity is impossible, the contract is an identical canonical form, with
each difference documented and justified. Every back end passes its own tests
on Rust-produced kernel. Hot reload is tested with the `flutter` tool's own
hot-reload tests.

### Track D — Partitioned memory

The compiler sorts every allocation site into one partition:

| Partition | What the compiler proves | How memory is reclaimed |
|---|---|---|
| **None** | The value never escapes | Stack or registers |
| **Owned** | One owner, a provable last use | A compiler-placed free |
| **Acyclic RC** | The type can never lead back to itself | Precise, mostly compile-time reference counting; non-atomic for isolate-local objects |
| **Traced** | Can be in a cycle, or is visible to `WeakReference`, `Finalizer`, `NativeFinalizer` or `Expando` | The GC, scanning only this partition |

- **When the GC is linked.** If a program's traced partition is provably empty,
  no collector is linked. The decision is per program and automatic, so it is
  fully compatible. Flutter apps always have traced objects (`Element`,
  `RenderObject`, `Layer` and `FocusNode` point to their parents and children),
  so they always link a GC, and gain from it scanning only part of the heap.
- **Removing the GC for every program is not possible compatibly.** Dart
  programs build cycles freely, and `WeakReference` and `Finalizer` are
  defined by reachability. Anything that reclaims all unreachable memory,
  cycles included, is a garbage collector.
- **Phase 0 measurement.** Before anything is built, run the partition analysis
  on the Flutter framework and reference apps, run them with counting turned
  on, and report per frame how many objects and bytes go to each partition and
  what share the GC still scans. That share sets Track D's expected gains for
  Flutter, and decides whether it's worth building past the owned partition.
- **What is promised.** Lower peak memory, and lower p99 and maximum GC pauses,
  as gates. Throughput is measured and reported, not promised: Dart's nursery
  already makes short-lived objects nearly free, so a site moves out of it only
  where profile data shows that measures faster or leaner.
- **Compatibility.** AOT builds only; debug, JIT and hot reload keep upstream's
  memory model. Reachability-observed objects stay traced, so `Finalizer` and
  `WeakReference` behave as specified. DevTools' heap snapshots and memory
  views cover all four partitions in the existing protocol.
- **Soundness.** As Part 4 states. A wrong free is the one way this could make
  Dart less safe, so its gate is never waived.
- **Where it lands.** The owned partition first, as a patch to the upstream C++
  VM (a free entry point in the allocator, as in Go's `runtime.freegc`). The
  other partitions in the Rust VM (Track F), whose object model is designed for
  them.

### Track E — Flutter engine

- **Replace module by module inside one binary.** C++ and Rust are linked
  together through typed bridges, so every build during the port is a
  shippable mixed engine. Rust is added to the engine's GN and Ninja build.
- **The upstream C++ stays in the build as the oracle**, behind a switch. A
  Rust module replaces the C++ one only when outputs match: display lists to
  pixels, paragraphs to metrics, task-runner traces, semantics trees, platform
  message sequences.
- **Rulebooks:** `PORTING.md` and `LIFETIMES.tsv` (the ownership of every
  pointer field). The C++ conventions map as follows:
  - `fml::RefPtr` and `std::shared_ptr` → `Arc`, with thread-safety audited per type;
  - `fml::WeakPtr` → a weak handle that keeps the thread check;
  - virtual interfaces → traits;
  - task runners → the same types on the same platform loops, never `tokio`;
  - Objective-C++ → `objc2`;
  - JNI C++ → the `jni` crate;
  - `Dart_Handle` → a small audited `unsafe` core with typed wrappers.
- **Order:** embedders, `fml`, runtime and `dart:ui` natives, shell, display
  lists and layers, Impeller (geometry, entities, renderer, then each HAL
  backend: Vulkan, Metal, GLES), the text wrapper, then build-time tools.
- **Gates:** Flutter's full test bar and devicelab, with frame time,
  start-up, memory and size within budget of Google's engine at the same
  commit.

### Track F — Dart VM

- **Order:** the object model, designed for Track D's partitions; the GC; the
  AOT back ends and `gen_snapshot`; isolates; `dart:io` and `dart:ffi`; the VM
  service; last the JIT and hot reload.
- **Contract:** the VM tests and co19 pass unmodified; snapshots are
  interchangeable with the C++ VM's at the same version; the VM service
  protocol is byte for byte.
- **Safety claim:** "memory-safe outside a counted, audited core" (the
  collector and the JIT). Never "memory-safe".

### Track G — CLIs

`dartdev`, DDS, pub and `flutter_tools`, with their command lines, outputs,
exit codes and the `flutter daemon` and DDS protocols kept identical, and
tested with their own suites. pub's resolver must produce identical
`pubspec.lock` files on the same inputs, checked against the top pub.dev
packages and their dependency graphs.

### Track H — Upstream tracking (permanent)

- **Every commit** to `dart-lang/sdk`, `flutter/flutter`, `dart-lang/pub` and
  `dart-lang/dart_style` that touches ported code is ported as a diff. An
  agent applies the commit's intent to the Rust counterpart under the same
  rulebook, and the differential harness checks it, with upstream as oracle.
- **New language and framework features arrive with their tests** (co19,
  language tests, engine and framework tests). A feature is ported when its
  tests pass on both implementations.
- **Release window:** each upstream stable release is matched within two
  weeks to start, shrinking as the loop matures, with same-day as the aim.
- **The oracle is never deleted.** Upstream keeps building in CI for as long
  as the project exists.

### Track I — Optional semicolons

- Files use the `.dv` extension, so no standard tool misreads one and no
  package published to pub.dev contains one.
- **Insertion rule (Go-style):** at a newline, a semicolon is inserted when
  the line's last token could end a statement (an identifier, a literal, `)`,
  `]`, `}`, `return`, `break`, `continue`, `rethrow`, postfix `++`/`--`, `!`).
- **Continuation rule:** no semicolon is inserted when the next line starts
  with a token that can only continue the expression: `.`, `..`, `?.`, `?..`,
  a binary operator, `?`, `:`, `)`, `]`, `}`, `=>`. Dot shorthands don't
  conflict, because a bare statement has no context type, so a line starting
  with `.` is always a continuation.
- **Dart's known ambiguities**, which standard Dart parked in
  `dart-lang/language#69`:
  - `{` attaches to the line before, and the formatter enforces it;
  - a line starting with `(` or `[` is a new statement, with a warning;
  - generic `<` is resolved by the normal parser, because insertion runs after
    tokenizing.
- **Tools:** the formatter converts `--to-dart` and `--to-dialect`.
  `dartvel build` and publishing emit standard Dart, so every other tool only
  ever sees standard Dart.
- **Freeze rule:** the rule set is frozen when the whole pub.dev corpus
  round-trips: remove semicolons, insert them back, and get an identical token
  stream. Every file that fails is either a new rule or a construct the
  dialect refuses with a named error.

## 6. Method

1. **Pin a version** for the initial port; Track H takes over afterwards.
2. **An oracle per unit.** Each unit has a dump mode that both the original and
   the port write: tokens, AST, element models, kernel, display lists, heap
   graphs, protocol traffic. A unit is done when it matches **on a corpus its
   worker didn't see**, re-run by the coordinator.
3. **Prove every test can fail.** Each worker breaks one rule on purpose and
   shows the failure.
4. **Rulebooks:** `PORTING.md` for Dart to Rust and for C++ to Rust, plus
   ownership tables.
5. **One coordinator per track** that plans, verifies and merges, and never
   ports. Workers each get one unit, one worktree and one build directory.
6. **Standing rules,** taken from the incident logs of earlier agent ports:
   - every command has a time limit;
   - reference tools get isolated caches;
   - no two agents own the same feature;
   - the full suite runs after every merge;
   - workers commit after every step.
7. **Speed and memory are measured on every merge** against committed
   baselines. A regression past budget is refused like a failing test.

## 7. Order of work

1. **Phase 0, every track:** measure, build each oracle harness, commit speed
   and memory baselines, and run the Track D partition measurement.
2. **A**: tools.
3. **B**: FFI checks, alongside A.
4. **I**: the dialect, alongside A, since it's scanner and formatter work.
5. **C**: the compiler front end, then dart2js, dart2wasm and DDC.
6. **G**: `dartdev`, DDS, pub and `flutter_tools`.
7. **D, owned partition**, in the upstream C++ VM.
8. **E**: the Flutter engine.
9. **F**: the Dart VM, with the rest of D.
10. **H**: starts the day the first component ships and never stops.

## 8. The test bar and the gates

| Track | Correctness | Speed and memory |
|---|---|---|
| A, B, I | The analyzer's own tests; differential corpora; the pub.dev round-trip for I | Wall time and peak RSS ≤ Dart on every corpus, language server included |
| C | Every back end's tests on Rust kernel; hot-reload tests | Compile time and peak RSS ≤ the CFE |
| D | Full Dart and Flutter bars; zero sanitizer traps | Peak memory lower; p99 and maximum pause lower; throughput reported |
| E | Flutter's framework, golden, embedder, integration, plugin and devicelab tests | Frame time, start-up, memory and size within budget of Google's engine |
| F | VM tests, co19, VM service tests, Flutter's full bar | Dart benchmarks and pause times ≤ the C++ VM |
| G | Each CLI's own tests; identical `pubspec.lock` and protocol traffic | Command latency and peak RSS ≤ upstream |

## 9. Third-party libraries

A third-party library is replaced only when the Rust replacement is proven
identical on the differential corpus. Otherwise it stays linked, and the
safety claim names it as C/C++. Compatibility outranks "100% Rust" wherever the
two conflict.

| Library | Candidate | Bar |
|---|---|---|
| zlib, PNG, JPEG and WebP decoders | `zlib-rs`, `png`, `zune-jpeg`, `image-webp` | Identical bytes and pixels |
| HarfBuzz | `rustybuzz` | Identical glyph runs on HarfBuzz's tests and a multilingual corpus |
| ICU | ICU4X | Identical line breaks and BiDi; otherwise ICU stays |
| BoringSSL | `rustls`, `ring` | `dart:io` TLS tests and interoperability |
| Skia, SkParagraph, FreeType | None identical today | Stay, until a separate proposal |

## 10. How this ties into Dartvel

- **Everything lives in `dartvel_dev`, under `experiments/`.** The Rust ports,
  one Cargo workspace per track, sit beside the Dart tooling; the pinned
  upstream sources (`dart-lang/sdk`, `flutter/flutter`, `dart-lang/pub`,
  `dart-lang/dart_style`) are git submodules there, at the commits the work is
  measured and ported against. No component gets its own repository.
  `experiments/` is the one exception to the One Language Rule: Rust is
  allowed there and nowhere else, and nothing in `packages/` may depend on it
  until a component graduates.
- **The Dartvel CLI gets the Rust stack behind its existing commands**, with
  `dartvel doctor` reporting which implementation runs each step. Upstream
  stays selectable per component until that component meets its proof bar.
- **One memory analysis** serves Track D and the memory tiers of the MCU and
  Lite targets (`2026-10-27-mcu-memory.md`).
- **The engine artifacts** reach every Dartvel target through the SDK's engine
  pin and a storage mirror. The vendor forks (Tizen, webOS, tvOS, Sony eLinux)
  switch per target, each with its own evidence in `docs/build-targets.md`.
- **Spec edits when a component ships:**
  - the project rule that vendor and embedded targets download a prebuilt
    Google engine becomes "a prebuilt engine per version: Google's, or the
    Rust port's at the same version, recorded per target";
  - every safety, speed and memory claim goes into the spec per component,
    with its numbers and its proof, under Part 4's rules.

## 11. Effort

### What has to be written

| Track | Source lines to port | Rust to write, implementation (≈ 1.2× source) | Unit tests to port | Difficulty weight |
|---|---|---|---|---|
| A. Tools | 634k Dart | 760k | 243k (15% of 1.62M; the oracle covers the rest) | 1.0 |
| C. Compilers | 677k Dart | 812k | 41k | 1.2 |
| G. CLIs | 254k Dart | 305k | 59k | 0.8 |
| E. Engine | 408k C++/ObjC++ | 490k | 115k (50% of 230k; internals have no external oracle) | 2.0 |
| F. VM | 549k C++ | 660k | 62k | 2.5 |
| B, D, I (new code) | — | ≈ 120k | — | 1.0–2.0 |
| **Total** | **≈ 2.52M** | **≈ 3.15M** | **≈ 0.52M** | |

So about **3.7 million lines of Rust**, implementation and tests together.
That is about 3.5 times Bun's port (about 1 million lines of Rust, from
535,496 lines of Zig) and about 5 times dartr's (about 685,000 lines). The
1.2× ratio sits between dartr's measured 1.1× and Bun's 1.9×.

The difficulty weight reflects how hard the oracle is to build and how long
the parity tail is:

- the analyzer is pure, deterministic Dart with a perfect oracle (1.0);
- the engine has GPUs, threads and platforms (2.0);
- the VM has a GC, a JIT, four CPU architectures and hot reload (2.5).

### People

Agents write the code. People own:

- the rulebooks and ownership tables;
- every `unsafe` block and its safety argument;
- the Kani and Miri work;
- performance analysis;
- devices and reference machines;
- merge decisions on the hard tracks.

The optimistic plan assumes **four to six engineers**:

- one per hard track (engine, VM);
- one for the tools and compilers;
- one for infrastructure (CI, devices, benchmarks);
- and the owner.

This is the largest programme Dartvel would run, larger than everything else
in the specification together.

### Costs that are not tokens

Expect **CI and devices to cost more than tokens**:

- the full Flutter test bar and devicelab on physical Android and iOS devices;
- macOS runners for Apple targets;
- GPU machines for Impeller's backends;
- reference machines for benchmarks.

Part 13 doesn't price these: they depend on what Dartvel already runs and on
hosting choices.

## 12. Timeline (optimistic)

Assumptions:

- about 50 agent workflows in parallel, at Bun's scale;
- four to six engineers;
- rate limits that allow that throughput;
- no upstream rewrite of a major component during the port;
- Phase 0's harnesses working first time.

For calibration, the two earlier agent ports ran at about 90,000 lines a day
(Bun, 50 workflows, 11 days) and about 230,000 lines a day (dartr's
deterministic analyzer, a handful of agents).

| Months from start | Track | Milestone |
|---|---|---|
| 0–0.75 | Phase 0 | Sizes, oracles, baselines for every track; the Track D partition measurement |
| 0.5–1.5 | A, B, I | Tools at parity and under the memory gate; FFI checks; the dialect with pub.dev round-trip |
| 1–3.5 | C | CFE, kernel and `frontend_server` at parity (month 2); dart2js, dart2wasm and DDC (month 3.5) |
| 2–3.5 | G | `dartdev`, DDS, pub and `flutter_tools` |
| 2–3 | D (owned) | Owned partition in the C++ VM, sanitizer-clean |
| 2–9 | E | Embedders and `fml` (month 3), `dart:ui` and shell (month 5), display lists and Impeller on Vulkan (month 7), Metal and GLES and text (month 9) |
| 3–12 | F | Object model and GC (month 5), AOT back ends and `gen_snapshot` for x64 and ARM64 (month 8), isolates, I/O and FFI (month 9), VM service (month 10), JIT and hot reload (month 12) |
| from 1.5 | H | Running continuously from the first shipped component |

**Optimistic total: about 12 months to full-stack parity.** Tools ship in about
6 weeks, compilers in about 3.5 months, the engine in about 9 months, and the
VM in about 12.

The realistic range is **two to three years**, because the parity tail on the
engine and VM (GPU drivers, timing, platform differences, the last 1% of
tests) is where every large port has spent most of its time.

## 13. Token cost (optimistic)

### Prices used

Anthropic first-party API prices, per million tokens, as listed on
2026-10-06:

| Model | Input | Output | Cache read | Cache write (5 min) |
|---|---|---|---|---|
| Claude Fable 5.1 | $10.00 | $50.00 | $0.25 | ≈ $12.50 (1.25×) |
| Claude Opus 5.5 | $4.00 | $20.00 | $0.20 | ≈ $5.00 |
| Claude Sonnet 5.5 | $2.00 | $10.00 | $0.20 | ≈ $2.50 |
| Claude Haiku 5.5 | $0.10 | $0.50 | — | — |

The Batch API halves prices but suits only asynchronous work (reviews, test
triage), so the estimate leaves it out.

### Assumptions

- **Per line of finished Rust at difficulty 1.0**, implementer and two
  reviewers together:
  - about **6,000 input tokens**: re-read context, source files, compiler and
    test output;
  - about **80 output tokens**, thinking included.

  This matches a 1,000-line file taking about 40 turns at about 80,000 tokens
  of context.
- **Input mix:** 90% cache reads, 8% cache writes, 2% uncached. Agent loops
  with stable prefixes reach this when caching is set up properly.
- **Model mix:**
  - 10% Claude Fable 5.1 for the hardest units (GC, JIT, Impeller HALs,
    Track D's analysis);
  - 40% Claude Opus 5.5 for complex porting;
  - 50% Claude Sonnet 5.5 for wiring, tests and simpler units.
- **Weighted volume:** about 5.5 million difficulty-weighted lines (Part 11).

### Result

| | Tokens | Effective price | Cost |
|---|---|---|---|
| Input | ≈ 33 billion | ≈ $0.62 per million (blended, cached) | ≈ $20,500 |
| Output | ≈ 0.44 billion | ≈ $18 per million (blended) | ≈ $8,000 |
| **Initial port, optimistic** | | | **≈ $28,500** |

Ongoing:

- **Upstream tracking (Track H):** about 10% of the ported code is touched by
  upstream each year. At the same rates that is about **$3,000–5,000 a year**.
- **Realistic multiplier:** three to five times for the parity tail on the
  engine and VM. That gives **$90,000–150,000** for the initial port.

The token bill is not the main cost. Engineers, CI and devices (Part 11) will
cost more than tokens even in the optimistic case.

## 14. Considered and not proposed

- **Subsets and mirrors** (dartc and similar).
- **Rewriting the Dart sources of `dart:*`, the Flutter framework or the web
  engine.** It's API surface (Part 2).
- **Removing the GC for every program.** Incompatible by Dart's semantics; done
  per program only when proven.
- **Optional semicolons in `.dart` files.** Only in `.dv`, always converted.
- **A greenfield Rust engine "inspired by" Flutter, or replacing Impeller with
  wgpu or Vello.** Different output; fails the golden tests.
- **`tokio` or `winit` for the engine shell.** Different scheduling and
  lifecycle semantics.
- **Calling compatibility evidence a "proof"** beyond Part 4's definitions.

## 15. Open questions

1. **dartr for Track A:** answered on 30 October 2026: no. The port is of
   the Dart SDK and Flutter themselves, done in forks of `dart-lang/sdk` and
   `flutter/flutter`; dartr and dartc stay prior art.
2. **The upstream window:** two weeks per stable release to start, or tighter?
3. **The Dart and Flutter teams:** offer them the differential harnesses?
4. **Licensing and distribution:** BSD-3-Clause like upstream? Free, or part
   of Dartvel's paid offering?
5. **The dialect's extension and name.**
6. **Budget sign-off:** Part 13 is optimistic. Approve a Phase 0 budget first:
   its measurements replace these estimates before the large spend starts.

---

## Appendix A — Coordinator prompt

One coordinator session per track. Run it on Claude Opus 5.5 at effort `high`
(`xhigh` for Tracks E and F), with adaptive thinking and caching on. Replace
the bracketed fields.

```text
You coordinate Track [LETTER: NAME] of the Dart and Flutter Rust port. The
proposal is docs/proposals/2026-10-29-dart-flutter-rust-stack.md in
Danroyal001/dartvel_dev; read Parts 2-8 for your track before anything else.

Your job is to plan, assign, verify and merge. You never port code yourself.

The upstream reference is pinned:
- dart-lang/sdk at [COMMIT], flutter/flutter at [COMMIT],
  dart-lang/pub at [COMMIT], dart-lang/dart_style at [COMMIT].
- It is checked out as the git submodules under experiments/upstream/ in
  Danroyal001/dartvel_dev. It must build and pass its own tests before you
  assign any unit.

The port lives in Danroyal001/dartvel_dev under experiments/[TRACK DIR], one
Cargo workspace. Nothing outside experiments/ may depend on it. Each Rust file names the
upstream file it ports in its first line and keeps that file's structure and
names, so upstream changes can be followed file by file.

How a unit gets done:
1. Split the track into units small enough for one worker to finish in one
   session, each with a clear oracle: a dump mode both upstream and the port
   write (tokens, AST, elements, kernel, display lists, heap graphs, protocol
   traffic). Build the oracle before assigning the unit.
2. Give each unit to one worker, in its own git worktree and its own build
   directory, using the worker prompt (Appendix B). Name the owner of every
   neighbouring feature in the task, so two workers never build the same
   thing.
3. When a worker reports done, re-run its differential test yourself on a
   corpus the worker did not use. Check that the worker showed one deliberate
   failure. Send the diff to two reviewers (Appendix C).
4. Merge only when the oracle matches on unseen input, both reviewers have no
   blocking findings, the full workspace test suite passes in release mode,
   and the speed and memory measurements are within budget of the committed
   baseline. A regression past budget is a failing test.
5. Record every merge in docs/TIMELINE.md: time, commit, unit, agent, and the
   evidence you checked. Record every incident and its lesson in the same
   file.

Standing rules:
- Every command you or a worker runs has a time limit.
- Reference tools run with isolated caches.
- Workers commit after each step.
- Count `unsafe` blocks per crate on every merge; a rise needs a human
  reviewer's sign-off recorded in the merge entry.
- Nothing is called done, compatible, faster, leaner or safe unless Part 4's
  proof for that claim exists. Report what was measured, not what was hoped.

Escalate to a human, and stop assigning work on the affected units, when:
- an upstream behaviour looks like a bug (port the behaviour, file the
  question);
- a unit needs new `unsafe` code outside the crates the rulebook allows;
- the oracle and upstream's own tests disagree;
- a gate cannot be met without changing a contract in Part 3.
```

## Appendix B — Worker prompt

Run implementers on Claude Opus 5.5 at effort `high` for complex units and
Claude Sonnet 5.5 at `medium` for wiring and tests. Use Claude Fable 5.1 for
the GC, the JIT, Impeller's backends and Track D's analysis.

```text
You are porting one unit of the Dart and Flutter stack to Rust, 1:1.

Unit: [UNIT NAME]
Upstream files: [PATHS at the pinned commit]
Target crate and files: [PATHS]
Oracle: [COMMAND that dumps upstream's output] and
        [COMMAND that dumps the port's output], compared by [COMMAND].
Corpus you may use: [PATHS]. The coordinator checks your work on a different
corpus, so don't tune for this one.
Neighbouring features and their owners: [LIST]. Don't build them; call their
interfaces, or ask the coordinator if they're missing.
Rulebook: PORTING.md (and LIFETIMES.tsv for pointer ownership). Follow it; if
it doesn't cover a case, propose an addition in your report instead of
improvising.

What done means:
- The oracle comparison shows no differences on your corpus.
- Every upstream unit test for these files that has no oracle equivalent is
  ported, and the Rust and Dart/C++ test counts per file are reported.
- You broke one rule on purpose, showed the test that caught it, and
  restored it.
- The full workspace tests pass in release mode.
- Speed and peak memory for the unit's benchmark are reported against the
  baseline.
- No new `unsafe` unless the rulebook allows it in this crate; each `unsafe`
  block has a SAFETY comment stating the invariant it relies on.

Work in your own worktree and build directory. Put a time limit on every
command. Commit after every step. Keep each Rust file's structure and names
close to the upstream file it ports, and name that file in the first line.

Report: what you ported, the oracle result, test counts, the deliberate
failure, speed and memory numbers, any `unsafe` added, and anything you
couldn't port and why. Report failures and differences plainly; don't call a
unit done while a difference remains.
```

## Appendix C — Reviewer prompt

Two independent reviewers per unit. Run them on Claude Opus 5.5 at `high`.
Reviews may run through the Batch API when they don't block a merge.

```text
Review a unit of the Dart and Flutter Rust port for correctness against
upstream, not for style.

Unit: [UNIT NAME]. Upstream files: [PATHS at the pinned commit]. Diff: [REF].
The worker's report is attached; treat its claims as claims to check.

Look for, in this order:
1. Behaviour that differs from upstream on some input the oracle corpus
   might not cover: error paths, edge cases, ordering, numeric edge values,
   platform differences, concurrency. Name a concrete input for each.
2. Ownership and lifetime mistakes: anything LIFETIMES.tsv would classify
   differently, and every `unsafe` block whose SAFETY comment doesn't
   establish what it claims.
3. Speed or memory regressions visible in the code: extra allocation, extra
   copies, lost parallelism, data structures larger than upstream's.
4. Rulebook violations.

For each finding give the file and line, the concrete failing input or
scenario, and whether it blocks the merge. If you find nothing that blocks,
say so plainly; don't invent findings.
```

## Appendix D — Prior art and sources

- `orestesgaolin/dartr`: a Rust port of the Dart analyzer, formatter, fixer and
  language server, at parity on large corpora; its `docs/TIMELINE.md` is the
  incident log this proposal's method draws on.
  <https://github.com/orestesgaolin/dartr>
- `medz/dartc`: an independent native Dart compiler written in Dart; a subset,
  explicitly not compatible with kernel, snapshots, the VM or Flutter. Not
  used. <https://github.com/medz/dartc>
- Bun's port from Zig to Rust: <https://bun.com/blog/bun-in-rust>,
  <https://www.infoq.com/news/2026/09/bun-AI-rewrite-zig-rust-4-months/>
- TypeScript 7, a structure-preserving port of the TypeScript compiler to Go:
  <https://infoq.com/news/2026/08/typescript-7-released/>
- Perceus: Garbage Free Reference Counting with Reuse:
  <https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse/>
- Lobster's compile-time memory management: <https://strlen.com/lobster>
- Go's `runtime.freegc`: <https://github.com/golang/go/issues/74299>
- Optional semicolons in Dart, on hold:
  <https://github.com/dart-lang/language/issues/69>
- Hertz and Berger, *Quantifying the Performance of Garbage Collection vs.
  Explicit Memory Management*, OOPSLA 2005.
- `dart:ffi` and `NativeFinalizer`: <https://api.flutter.dev/flutter/dart-ffi/>
