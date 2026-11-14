# Rust that ships in the `dartvel` CLI

Ports of the Dart SDK to Rust that a released Dartvel build uses. Today that
is one thing: the syntax check `dartvel build` and `dartvel doctor` run
before anything is generated.

| Crate | What it is | Lines |
|---|---|---|
| `fe_analyzer_shared/` | Port of `pkg/_fe_analyzer_shared`: the scanner and the parser | about 36,000 |
| `analyzer/` | Port of `pkg/analyzer`, only what `parseString` runs: the AST, the `AstBuilder`, the diagnostics | about 65,000 (47,000 generated) |
| `dartvel_syntax/` | Ours: the helper program the CLI runs, and its tests | about 300 |

No crate depends on anything outside this folder, and all three forbid
`unsafe` code.

## Where the ports come from

- Upstream: `dart-lang/sdk` at commit `ceea75dd2b82` (Dart 3.15.0-dev,
  `analyzer` 14.7.0-dev, `_fe_analyzer_shared` 110.0.0). BSD-3-Clause; its
  licence is `LICENSE.dart-sdk`.
- Ported in: branch `feat/rust-stack-experiments` of this repository (pull
  request #180), where each Rust file sits beside the Dart file it ports
  under `experiments/dart_sdk/pkg/<package>/rust`. Copied from commit
  `6c0b612480cc7be491cc6f00c416a8f5afe878e6` of that branch.
- Each ported file names the Dart library it ports in its first line and
  keeps that library's structure and names, upstream's short ones included,
  so it can be read against the Dart line by line. A file that is not a
  port says so in its first line.

What was left on the branch, because nothing shipped uses it yet: the
visitors, `toSource`'s callers, `NodeLocator2`, the element model, the
resolver and type analysis of `analyzer`; the dump programs; and the oracle
tests. `analyzer/src/lib.rs` lists exactly the modules taken.

## What the ports are proven to do

On the branch, the Dart code being ported stays in the checkout as the
oracle, and three tests compare the two byte for byte:

| Oracle | Compares | Corpus | Result |
|---|---|---|---|
| `scanner_oracle` | every token (type, offset, lexeme, error) | the scanner's own test inputs, `_fe_analyzer_shared/lib`, `analyzer/lib`: 1,178 files | identical |
| `parser_oracle` | every parser event with its arguments, errors included | the two `lib` folders and `tests/language`: 5,152 files | identical |
| `ast_oracle` | the tree `parseString` builds and every diagnostic (code, offset, length, message, correction) | the analyzer's AST and recovery test inputs, the two `lib` folders, `tests/language` | identical |

`tests/language` is the Dart language's own test suite, including its
files of deliberate syntax errors. So the parser is a port of the whole
language's syntax as of that commit, not of a subset.

Those oracles need the SDK fork and stay with it. What runs here, in this
repository, on every change (`.github/workflows/rust-check.yml`):

- `cargo test` in this folder: the ported unit tests, the helper's own
  tests, 40,000 seeded mutations and every prefix of two sources that use
  most of the language's syntax (none may escape as a panic), and nesting
  20,000 deep in fourteen shapes through the helper program.
- `packages/dartvel_cli/test/syntax_differential_test.dart`: the helper
  against `package:analyzer` over every Dart file in this repository, over
  malformed files, over 3,000 seeded mutations of repository files and over
  nesting up to 400,000 deep. For every file the helper calls clean the
  analyzer must report nothing, and for every file it flags the diagnostics
  must be the analyzer's exactly.

## What the port does not cover, and what the CLI does about it

- **Dart newer than the port.** The port knows the syntax of its upstream
  commit. Syntax added later would be flagged by it.
- **Panics.** Where upstream throws, the port panics, in about 2,400
  places; a slip in the port would look the same.
- **Stack.** The parser is recursive. Upstream stops at 500 nested
  expressions or statements with a `stack_overflow` diagnostic, and the port
  does the same, but other shapes (type arguments, conditionals, prefix
  operators) recurse without that guard. The Dart VM turns running out of
  stack into an error the analyzer survives; a Rust process just dies.
- **Time on hostile nesting.** Some shapes make upstream's parser search
  in time that grows faster than the file: type arguments nested 5,000
  deep take the helper 3.5 s, 50,000 deep more than two minutes. Dart stops
  on those at about 3,000 levels, when its stack runs out; this parser has
  a larger stack and keeps going. The stall timeout below bounds what it
  costs. Every other shape measured, at 50,000 deep, took under 7 s.
- **Encodings.** Dart decides what a byte order mark or a byte sequence
  that is not UTF-8 means.

So the CLI never takes the helper's word that a file is wrong:

1. The helper answers each file `clean`, `flagged` or `deferred`. It defers
   a file that is not plain UTF-8, is larger than 16 MiB, made the parser
   panic, or parsed into a tree more than 500 nodes deep.
2. A `clean` file is done. **Every other file is parsed by
   `package:analyzer`**, and only what the analyzer reports is shown. A
   helper that dies, or answers nothing for 10 seconds, is killed: its
   answers so far stand, the file it was on goes to Dart, and it is started
   again after that file, up to three times. A helper that breaks its
   protocol is not believed about anything in that run.
3. The helper is a separate process, so nothing it does can take the CLI
   down.

The cost of a gap in the port is therefore time, never a wrong verdict. The
one way the helper's answer is final is `clean`, which is the direction the
differential test checks on every file it has.

## How it ships

The CLI is released as one file (npm, the GitHub release binaries, Homebrew)
built by `dart build cli`, which cannot attach a second program. Three ways
to carry the helper were considered:

| | One file | Survives a parser crash | `dart pub global activate` |
|---|---|---|---|
| A dynamic library loaded over FFI (a native asset, as `dartvel_shelf` does for applications) | no: a `lib/` folder beside the binary, so the npm launcher, the tap and the release would all change | no: a panic can be caught, a stack overflow kills the CLI | only with `cargo` on the developer's machine |
| A second download on first use | yes | yes | yes, but a tool that fetches a program at run time, offline failures, and a second thing to sign |
| **The helper inside the executable** | yes | yes | falls back to Dart |

The third is what is built. Before a release binary is compiled,
`packages/dartvel_cli/tool/embed_syntax_helper.dart` builds this workspace
with `cargo build --release --locked` and writes the helper, gzipped and
base64-encoded, into `lib/src/analysis/syntax_helper_carried.g.dart`, which
is compiled into the executable. The first time the CLI needs it, it writes
the helper to `~/.dartvel/native/dartvel_syntax-<digest>`, and before every
use it checks that file against the SHA-256 compiled into the CLI, so a file
somebody else put there is replaced, never run. If the helper cannot be
written or run, the CLI parses in Dart.

In the repository the carried file is empty, so `dart run`, `dart pub global
activate dartvel_cli` and the package on pub.dev carry no helper and parse
every file with `package:analyzer`: the same findings, more slowly.
`DARTVEL_SYNTAX_ENGINE=dart` turns the helper off in a binary that has one.

## The helper's protocol

`dartvel_syntax` reads file paths from standard input, one a line, and
answers in order on standard output, flushing after each file:

```text
dartvel_syntax	1                  greeting: the protocol version
clean	0
flagged	1	2                      two diagnostics in file 1
deferred	2	byte-order-mark        or not-utf8, too-large, parser-panic, deeply-nested, unreadable
```

Fields are separated by tabs. With `--diagnostics` each flagged file is
followed by `diagnostic <file> <code> <offset> <length> <message>` lines,
which is what the differential test reads.

## Working on it

```sh
cd rust
cargo test --release -- --nocapture          # prints how many inputs were answered by a caught panic
cargo build --release                        # target/release/dartvel_syntax

cd ../packages/dartvel_cli
dart test test/syntax_check_test.dart test/syntax_differential_test.dart
DARTVEL_SYNTAX_CORPUS=/path/to/an/app dart test test/syntax_differential_test.dart
```

To take a newer port from the branch: copy the files `analyzer/src/lib.rs`
names, and all of `fe_analyzer_shared/src` but `bin/`, from the same commit;
update the commit above; run both test commands. Do not edit a ported file
here: fix it on the branch, where the oracle can check the fix, and copy it.

