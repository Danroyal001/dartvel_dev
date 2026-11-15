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

- `vm_platform.dill`, the VM's platform (`pkg/front_end/tool/compile_platform.dart`
  with the arguments `runtime/vm/BUILD.gn` gives it);
- each program under `tests/kernel_corpus/` compiled by `pkg/vm/bin/gen_kernel.dart`
  against that platform, once plain and once with `--aot` (type-flow
  analysis, tree shaking, signature shaking);
- the inputs of the type-flow analysis's own tests
  (`pkg/vm/testcases/transformations/type_flow/transformer/*.dart`),
  compiled the same two ways.

`oracle/build_corpus.dart` builds it.

## Running it

```sh
DART=/path/to/dart cargo test --release -p kernel --test roundtrip_oracle
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
- The reader and the writer recurse as upstream does, so a tree nested
  deeply enough to exhaust the stack aborts the process (upstream throws a
  stack overflow). Any other damaged input is refused with a `ParseError`
  (`tests/malformed_input.rs`).
- End-to-end checks through `gen_snapshot` (programs run, snapshot sizes)
  need a VM at this checkout's version. This box runs Dart 3.13.4 and the
  fork's C++ VM is not built here, so they wait until Dartvel moves to a
  Flutter release that carries this Dart.

## Numbers

Not measured yet.
