# Experiments

Work for side efforts that are not part of any Dartvel package yet. Nothing
here is published, nothing here is in the pub workspace, and nothing in
`packages/` may import from here. An experiment either graduates into a
package or is deleted.

Everything a side effort needs lives here, in this repository: its code in
any language the effort calls for, the upstream sources it works against, and
its tooling. A side effort does not get repositories of its own.

## The One Language Rule here

`experiments/` is the rule's single exception: Rust is allowed here, because
the Rust stack side effort ports the Dart and Flutter implementation to Rust.
Python still is not, and Dart tooling is still Dart. Rust anywhere outside
`experiments/` is still refused.

## Layout

| Path | What it is |
|---|---|
| [`rust_stack/`](rust_stack/) | Phase 0: measuring what has to be ported, reproducibly |
| [`dv_dialect/`](dv_dialect/) | Track I: the optional-semicolon `.dv` dialect, converted losslessly to and from Dart |
| [`dart_sdk/`](dart_sdk/) | The fork of `dart-lang/sdk` (at `ceea75dd2b82`) the Dart side is ported in: each Rust file sits beside the Dart or C++ file it ports, starting with `pkg/_fe_analyzer_shared/rust` |
| [`flutter/`](flutter/) | The fork of `flutter/flutter` (at `c3f5b027df2b`, engine included) the Flutter side is ported in, the same way |
| [`oracles/`](oracles/) | Track A's oracle: deterministic dumps of the formatter's output and the analyzer's diagnostics, and the byte-for-byte compare a port is checked with |
| [`upstream/`](upstream/) | `dart-lang/pub` and `dart-lang/dart_style` as git submodules at pinned commits |

Dartvel's public forks are here too, as git submodules on each repository's
default branch, so a checkout of this repository reaches every public part of
Dartvel from one place: the embedder and package forks (`dartvel_tizen`,
`dartvel_elinux`, `dartvel_webos`, `dartvel_fuchsia`, `dartvel_tvos`,
`dartvel_vscode`, `dartvel_cli_flt`, `dartvel_mix`, `dartvel-passepartout`)
and `homebrew-dartvel_dev`. They are pointers, not copies: each keeps its own
history, issues and releases, and the build still uses the forks as
`NEW_SPEC.md` describes. Private repositories are never added here.

Every Dart experiment is its own package with its own `pubspec.yaml`:

```sh
cd experiments/<name>
dart pub get
dart test
```

The Dart SDK and Flutter forks are part of this repository and come with a
clone. pub and dart_style are submodules, fetched on demand:

```sh
git submodule update --init --filter=blob:none experiments/upstream
```

`.github/workflows/experiments.yml` analyzes, format-checks and tests every
Dart experiment with a `test/` directory on each push that touches this
folder.

Side effort: *Side Effort: The Dart and Flutter Stack in Rust* in
`NEW_SPEC.md`, and [the proposal](../docs/proposals/2026-10-29-dart-flutter-rust-stack.md).
