# `kernel` in Rust

A file-by-file Rust port of this package (`pkg/kernel`), so far the part
that reads and writes the kernel binary format: the tree (as far as the
format carries it), canonical names, the binary reader `BinaryBuilder` and
the binary writer `BinaryPrinter`. It is the first piece of a drop-in Rust
replacement for the AOT compiler's global type-flow analysis and tree shaker
(`pkg/vm/lib/transformations/type_flow/`), which reads kernel, transforms it
and writes kernel that the rest of the stock pipeline consumes, so the bytes
it writes have to be upstream's.

Each file under `src/` ports the Dart library at the same path under `../lib`
and names that library in its first line; files that are not ports
(`lib.rs`, `mod.rs`, the round-trip binary, the test) say so in theirs.

Format version: 141, this checkout's (`ceea75dd2b82`, Dart 3.15.0-dev). The
installed SDK (Dart 3.13.4) writes version 138, which this crate refuses, as
upstream at this checkout does.

## The oracle

| | Upstream | Port |
|---|---|---|
| Round trip | `oracle/roundtrip.dart` | `src/bin/kernel_roundtrip.rs` |
| Input | every `.dill` in the corpus | the same |
| Output | what `BinaryPrinter.writeComponentFile` writes for the component `BinaryBuilder.readComponent` read | the same, byte for byte |

Upstream runs from source (this checkout's `pkg/kernel` on the installed Dart
VM), so its SDK hash is `0000000000`, which the port writes too. Upstream's
plain `BinaryBuilder` ignores metadata and its `BinaryPrinter` writes none
when the component has no repositories; the port does the same until the
VM's metadata repositories are ported (they belong to `pkg/vm`).

### The corpus

`target/kernel_oracle/corpus` under the SDK root (or `KERNEL_CORPUS`), every
`.dill` in it. It is built with this checkout's front end and VM tools,
running from source:

- `vm_platform.dill`, the VM's platform, with the arguments
  `runtime/vm/BUILD.gn` gives `compile_platform.dart`
  (`oracle/compile_vm_platform.dart` makes that tool's front-end calls with
  only the VM target installed: the stock tool also installs dart2js,
  dartdevc and dart2wasm, whose packages need third_party code this
  checkout lacks);
- each program under `tests/kernel_corpus/` compiled by `pkg/vm/bin/gen_kernel.dart`
  against that platform, once plain and once with `--aot` (type-flow
  analysis, tree shaking, signature shaking);
- the inputs of the type-flow analysis's own tests
  (`pkg/vm/testcases/transformations/type_flow/transformer/*.dart`),
  compiled the same two ways.

- concatenated files, which upstream's `readComponent` merges into one
  component: `hello` compiled `--no-link-platform` after the platform,
  `hello` and `json_roundtrip` (both unlinked) after the platform, and the
  linked `hello.dill` twice.

`oracle/build_corpus.dart` builds it. `GEN_KERNEL` may name `gen_kernel.dart`
compiled with `dart compile exe` from this checkout, which is faster than
running it from source for every program.

## Running it

```sh
DART=/path/to/dart cargo test --release -p kernel --test roundtrip_oracle
DART=/path/to/dart cargo test --release -p kernel --test damage_oracle -- --ignored
```

`KERNEL_WORK` moves the scratch directory (default
`target/kernel_oracle/work`). Outputs that match are deleted; outputs that
differ are kept, and the test names the first differing byte of each.

## What is ported

| Dart (`../lib/...`) | Rust (`src/...`) |
|---|---|
| `binary/tag.dart` | `binary/tag.rs` |
| `binary/ast_from_binary.dart` (`BinaryBuilder`, without lazy reading or metadata) | `binary/ast_from_binary.rs` |
| `binary/ast_to_binary.dart` (`BinaryPrinter` and its indexers, without metadata) | `binary/ast_to_binary.rs` |
| `canonical_name.dart` (the tree and `getChild`) | `canonical_name.rs` |
| `ast.dart` and `src/ast/*.dart` (the fields the format carries) | `ast.rs` |

### Conventions

- Upstream's nodes point at each other; here a node owns its children and
  the tree's cross-links are ids (canonical names, strings, URIs, constants,
  variables, type parameters, labels, switch cases, variable contexts), so
  that the tree has no shared mutable state and needs no `unsafe`.
- Names keep their Dart spelling (`readUInt30`, `fileOffset`), so the port
  reads against upstream line by line.
- Where upstream's writer and reader disagree (`ConstantPattern` and
  `RelationalPattern` write optional types that are read as required), the
  writer follows upstream's writer.
- `#![forbid(unsafe_code)]`.

## Limits

- Metadata is dropped on read and not written, as upstream's plain reader
  and writer do; the VM's repositories come with the type-flow port.
- An instance member reference whose target is not in the component (an
  unlinked component) keeps the member-signature origin that was read;
  upstream cannot write such a component at all.
- **Damaged input is not yet fully 1:1** (`tests/damage_oracle.rs`, numbers
  below). Matched: the header, the component index, the string, link,
  source and constant tables, references, the library and class indexes,
  string decoding (upstream's trusting WTF-8 decoder, re-encoded as its
  writer does), URIs (`Uri.parse` and `"$uri"`, through the port of
  `sdk/lib/core/uri.dart` in `../../../sdk/lib/core/rust`), allocation
  failures and deep nesting. Not matched yet:
  - Name binding: upstream's writer recomputes every canonical name from
    the tree and binds it (`Cannot bind ... to ..., target is already bound
    to ...`, `... is not bound to an AST node`), and its reader casts the
    nodes a reference is bound to (`type 'Library' is not a subtype of type
    'ExtensionTypeDeclaration?'`). The port keeps the names it read.
  - Upstream reads class members and function bodies lazily, when its
    writer reaches them; the port reads them in file order. For one
    damaged place the error is the same; for several, which comes first can
    differ.
  - Two kinds of upstream error depend on its environment, not its input:
    `Out of Memory` (the oracle runs with a 256 MB heap; the port models a
    single allocation of more than 248 MiB, and objects made before they
    are read with estimated sizes) and `Stack Overflow` (at 4205 levels of
    nesting, measured on chains of `!`; upstream's real limit depends on the
    kinds of node). Near those limits the port is approximate, and some
    `already bound` messages print identity hash codes, which differ from
    run to run even upstream.
- Not a pipeline stage on its own. The reader and writer are the first part
  of the type-flow port: they become a stage in `gen_kernel --aot` when the
  analysis itself is ported (Dart passes before, Rust type flow, Dart passes
  after, stock `gen_snapshot`). Nothing in a build calls this crate yet.
- End-to-end checks through `gen_snapshot` (programs run, snapshot sizes)
  need a VM at this checkout's version. This box runs Dart 3.13.4 and the
  fork's C++ VM is not built here, so they wait until Dartvel moves to a
  Flutter release that carries this Dart.

## Numbers

18 Nov 2026, on the shared server (load average 10 to 20 during the runs,
so medians are noisy; fastest runs are the steadier figure). Upstream is
`oracle/roundtrip.dart` compiled with `dart compile exe` (Dart
3.15.0-145.0.dev, running this checkout's `pkg/kernel`); the port is
`kernel_roundtrip`, built with the workspace's release profile (fat LTO)
unless a row says otherwise. Harness:
`../../_fe_analyzer_shared/rust/tool/measure.sh` (alternating runs; in each
process the read and write is repeated 10 times and the fastest and median
are printed).

### Byte identity

| Corpus | Components | Differences |
|---|---|---|
| `vm_platform.dill`, 5 programs plain and `--aot`, every runnable type-flow test input (110 of 120; the other 10 are libraries those import) plain and `--aot` | 227 | 0 |
| Concatenated files: platform + program, platform + two programs, a whole program twice | 3 | 0 |

Before this round, all three concatenated files were refused (the port
read only single-component files; upstream's `readComponent` merges them).

### Damaged input

`tests/damage_oracle.rs`: every truncation and every byte flipped four ways
(masks 0x01, 0x40, 0x80, 0xFF); upstream (`oracle/damage.dart`, Dart
3.15.0-145.0.dev JIT, 256 MB heap) and the port must write the same bytes or
throw the same thing.

| Base file | Damaged inputs | Differ, before | Differ, now |
|---|---|---|---|
| `tests/fixtures/empty.dill` (88 bytes) | 440 | 273 | 0 |
| `tests/fixtures/hello-unlinked.dill` (616 bytes) | 3,080 | not run (the harness died: upstream ran out of memory inside the test's scope) | 344 |

Of the 344: 267 are name binding (`Cannot bind ...`), the rest index errors
the port does not hit or hits elsewhere (bodies read in file order instead
of lazily), Out of Memory near the modelled limit, and node casts. Steps:
upstream's errors for header, index and tables, 860; library indexes, 843;
`Uri.parse`, 354; library URIs, 344.

After these changes the platform round trip's fastest run is 142.3 ms
against 127.4 ms before them (20 alternating runs each, server load
about 14): 12% slower, still 2.2x faster than upstream's 314.7 ms. Reading
and writing timed alone did not move; the cost is in merging strings and
constants by value and parsing every URI, which only damaged files need.
To be won back. `tests/deep_nesting.rs`: upstream writes a chain 4202
deep and throws `Stack Overflow` at 4203; so does the port (it aborted
before).

### Speed and memory (7 runs each)

| Input | Measure | Upstream | Rust | |
|---|---|---|---|---|
| `vm_platform.dill` (8.2 MB) | fastest read+write | 314.7 ms | 128.8 ms | 2.4x |
| | median of medians | 676.7 ms | 151.1 ms | 4.5x |
| | peak RSS (median) | 240.6 MB | 98.3 MB | 0.41x |
| `hello-aot.dill` (6.3 MB, tree-shaken) | fastest | 96.8 ms | 48.9 ms | 2.0x |
| | median of medians | 205.4 ms | 62.5 ms | 3.3x |
| | peak RSS (median) | 167.9 MB | 51.9 MB | 0.31x |
| platform + two programs, concatenated | fastest | 369.2 ms | 140.8 ms | 2.6x |
| | median of medians | 696.8 ms | 172.0 ms | 4.1x |
| | peak RSS (median) | 228.9 MB | 99.9 MB | 0.44x |
| 88-byte empty component, one round trip per process (21 runs) | wall, fastest | 13.0 ms | 1.9 ms | 6.8x |
| | wall, median | 29.5 ms | 3.3 ms | 8.9x |
| | peak RSS | 8.3 MB | 2.5 MB | 0.30x |

Peak memory was a loss at first (112.5 MB against upstream's 107.5 MB for
one round trip of the platform): every `Expression` took 296 bytes and every
`DartType` 88, the size of the largest variant. Boxing the large payloads
brought them to 112 and 40 bytes, and one round trip to 80.6 MB.

### Size and build time

| Measure | Upstream | Rust (fat LTO) | Rust (`--profile thin`) |
|---|---|---|---|
| executable | 8,306,576 B (`dart compile exe`; the AOT snapshot alone is 2,539,392 B) | 986,552 B | 1,192,320 B |
| stripped | stripping breaks it (the snapshot is lost) | 830,896 B | 950,600 B |
| clean build | 23.0 s, 25.2 s (`dart compile exe`) | 28.9 s | 13.9 s |
| platform round trip, fastest | 314.7 ms | 130.0 ms | 145.2 ms |

Speed and memory were measured before the last commit (bounds on scope, type parameter and switch case counts: one comparison each, outside the hot loops).

With fat LTO the build is **slower** than `dart compile exe`, so the release
profile does not win every measure. The `thin` profile does: it builds in
13.9 s and keeps the speed (2.2x), memory and size leads.

### Safety

- `#![forbid(unsafe_code)]` in the library and the binary; no dependencies.
- No `panic!`, `unreachable!` or `todo!`; two `unwrap()`s, both on values
  just shown to be present. Every list length read from the input is capped
  by the bytes left (`cap`), so a damaged length cannot allocate more than
  the input could describe.
- `tests/malformed_input.rs`: every truncation and every byte flipped
  (four ways) of the empty component and of a real program
  (`tests/fixtures/hello-unlinked.dill`) is read or refused without a panic,
  and whatever is read is written without one. This found one abort: a flipped byte gave a scope size of 2^29 and the reader allocated 4 GiB for it (type parameter and switch case counts had the same shape). Counts the input cannot hold are now refused before anything is allocated, and the id counters use checked addition.
- Miri (nightly 2026-11-04): all 9 tests of `tests/malformed_input.rs` and `tests/small_components.rs` pass, including both damage sweeps over the real program (778 s). The oracle test runs subprocesses, so it runs natively only.
- Not covered: inputs nested deeply enough to exhaust the stack (abort, as
  above), and CPU time: a damaged index can point many classes at the same
  bytes, which upstream reads as many times too. Coverage not recorded this
  round. No threads, so no sanitizer run applies.
