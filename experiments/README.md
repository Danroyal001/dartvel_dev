# Experiments

Work for side efforts that are not part of any Dartvel package yet. Nothing
here is published, nothing here is in the pub workspace, and nothing in
`packages/` may import from here. An experiment either graduates into a
package or its own repository, or is deleted.

Each experiment is its own Dart package with its own `pubspec.yaml`, so it
resolves and tests on its own:

```sh
cd experiments/<name>
dart pub get
dart test
```

The One Language Rule applies here as everywhere else in this repository:
experiments are Dart. Work that has to be in another language (the Rust ports
of the side effort below, for example) lives in its own repository, like the
embedder forks.

`.github/workflows/experiments.yml` analyzes, format-checks and tests every
experiment with a `test/` directory on each push that touches this folder.

| Experiment | Side effort | What it is |
|---|---|---|
| [`rust_stack`](rust_stack/) | *Side Effort: The Dart and Flutter Stack in Rust* in `NEW_SPEC.md`; [the proposal](../docs/proposals/2026-10-29-dart-flutter-rust-stack.md) | Phase 0: measuring what has to be ported, reproducibly |
