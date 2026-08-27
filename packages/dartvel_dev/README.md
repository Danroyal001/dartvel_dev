# Dartvel

A batteries-included, AI-native full-stack application platform built around
Flutter.

You write pages, models, backend functions, UI and business logic. Everything
else — routing, clients, serialization, forms, admin, the server — is
generated, compiled or served.

```sh
dart pub global activate dartvel_dev
dartvel new my_app
cd my_app && dartvel dev
```

Or through npm, if that is closer to hand:

```sh
npx dartvel_dev new my_app
```

Or Homebrew:

```sh
brew install Danroyal001/dartvel_dev/dartvel_dev
```

## Why the package is `dartvel_dev`

The framework is Dartvel and the command is `dartvel`. Only the published
identifier carries a suffix, because `dartvel` on pub.dev was taken on
2026-08-06 by an unrelated package. The same name is used on pub.dev, npm and
Homebrew so that whichever way you install it, it is called the same thing.

## What is in it

This package is the umbrella. It brings together
[`dartvel_core`](https://pub.dev/packages/dartvel_core) (models, database,
cache, queues, auth, notifications, AI),
[`dartvel_flutter`](https://pub.dev/packages/dartvel_flutter) (UI primitives,
routing, signals, native platform APIs),
[`dartvel_shelf`](https://pub.dev/packages/dartvel_shelf) (the Rust/Axum
runtime, reached over FFI, speaking HTTP/2 and HTTP/3), and
[`dartvel_cli`](https://pub.dev/packages/dartvel_cli) (the `dartvel` command).

## Status, stated plainly

Dartvel is published early. Per-section implementation status lives in
[`docs/spec-status.json`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
and is checked by a tool that fails when a section claims to be built and the
evidence it names does not exist.

Each entry carries two independent labels: how much the public surface can
still move, and how much is actually built. A frozen contract that is
deliberately unbuilt is marked as such rather than implied to work, and what is
absent is written down next to what is present.

Verified per-target build status lives in
[`docs/build-targets.md`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/build-targets.md),
where "verified" means the command was run and the artifact inspected — never
inferred because a sibling target works.
