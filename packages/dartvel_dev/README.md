# Dartvel

A full-stack application platform built around Flutter.

You write pages, data models, backend functions, UI and business logic.
Routing, the typed client, serialization, forms, the admin and the server are
generated, compiled or served for you.

`dartvel_dev` is the umbrella package: one dependency that brings the whole
framework at one coherent set of versions. The command you run is `dartvel`,
from [`dartvel_cli`](https://pub.dev/packages/dartvel_cli).

## Start a project

Install the CLI from pub.dev:

```sh
dart pub global activate dartvel_cli
```

Activate `dartvel_cli`, the command, rather than this package: this one is what
an application depends on, and it depends on Flutter, which pub does not run as
a global command. Pub puts `dartvel` in `~/.pub-cache/bin`; add that to your
PATH if your shell cannot find it.

The same CLI also comes as a self-contained binary, with no Dart or Flutter
needed to run it:

```sh
brew install Danroyal001/dartvel_dev/dartvel_dev
npm install -g dartvel_dev
```

or take one from the
[releases page](https://github.com/Danroyal001/dartvel_dev/releases). Then:

```sh
dartvel create my_app
cd my_app
dartvel dev
```

The [dartvel_cli README](https://pub.dev/packages/dartvel_cli) covers every
install route, the command reference and configuration.

## What is in it

| Package | What it carries |
|---|---|
| [`dartvel_core`](https://pub.dev/packages/dartvel_core) | Pure Dart: data models, database, cache, queues and jobs, auth, notifications, AI adapters, the annotations the generator reads. |
| [`dartvel_flutter`](https://pub.dev/packages/dartvel_flutter) | Flutter: `DVBox`, `DVText` and the `DVModifier` chain, routing, signals, `DV.Platform` native APIs, generated forms and pages. |
| [`dartvel_shelf`](https://pub.dev/packages/dartvel_shelf) | The Rust/Axum server runtime, reached over FFI, speaking HTTP/2 and HTTP/3. |
| [`dartvel_cli`](https://pub.dev/packages/dartvel_cli) | The `dartvel` command: generation, dev server, build, deploy. |

It exposes them through these libraries:

| Import | What it gives you |
|---|---|
| `package:dartvel_dev/dartvel.dart` | Everything: core, Flutter, the server's `Router`, `serve` and options, observability, Rust bindings. |
| `package:dartvel_dev/dartvel_ui.dart` | The whole of `dartvel_flutter`. |
| `package:dartvel_dev/dartvel_core.dart` | The whole of `dartvel_core`. |
| `package:dartvel_dev/dartvel_backend.dart` | `@DVBackendFunction`, `@DVBackendCron`, request and response types, and `dartvel_shelf`. |
| `package:dartvel_dev/dartvel_database.dart` | `DV.Database`, its adapters, and the cache adapters. |
| `package:dartvel_dev/dartvel_storage.dart` | `DV.FileStorage`, with its in-memory and S3 adapters. |
| `package:dartvel_dev/dartvel_auth.dart` | `DV.Auth`, providers and password hashing. |
| `package:dartvel_dev/dartvel_ai.dart` | `DV.AI` and the adapters for Claude, OpenAI, Gemini, OpenRouter, Ollama and a local one. |
| `package:dartvel_dev/dartvel_platform.dart` | `DV.Platform` and its device APIs. |
| `package:dartvel_dev/dartvel_observability.dart` | Logging and observability. |
| `package:dartvel_dev/dartvel_rust_bindings.dart` | `DVRust`, the Rust bindings. |
| `package:dartvel_dev/dartvel_cli.dart` | The CLI as a library, for tools that drive it from Dart. |

In an application, pages and widgets import the generated barrel,
`lib/dartvel_client/dartvel_client.dart`, which re-exports the framework
alongside the application's own generated routes, models and client. Data
models and backend functions, which the generator reads rather than writes,
import `package:dartvel_core/dartvel.dart`.

## The umbrella, or the individual packages

`dartvel create` writes the individual packages into the new project's
`pubspec.yaml`: `dartvel_core`, `dartvel_flutter` and `dartvel_shelf`, with
`dartvel_cli` as a dev dependency. That is the layout to start from.

Depend on the individual packages when:

- the code is pure Dart, such as a server, a worker or a command-line tool.
  `dartvel_dev` depends on Flutter, and `dartvel_core` does not;
- you want only part of the framework, or want to move one package ahead of
  the others;
- your source imports `package:dartvel_core/...` or
  `package:dartvel_flutter/...` by name, as the files `dartvel create` and
  `dartvel generate` write do. Those imports resolve through the umbrella, but
  the `depend_on_referenced_packages` lint reports each one until the package
  is declared.

Depend on `dartvel_dev` when you want one line that moves every Dartvel
package together, for a Flutter application or a Flutter package built on
Dartvel. Each release of `dartvel_dev` constrains its siblings to the
versions published beside it (0.6.0 takes `dartvel_core`, `dartvel_flutter`
and `dartvel_cli` ^0.6.0 and `dartvel_shelf` ^0.7.0), so raising that one
constraint moves the whole set.

In an application, keep backend functions importing
`package:dartvel_core/dartvel.dart`, not the umbrella. The generated server is
pure Dart and leaves out any import that reaches Flutter, and
`package:dartvel_dev` does. Declaring `dartvel_core` and `dartvel_flutter`
beside the umbrella, with no version of their own to manage, keeps the lint
quiet:

```yaml
dependencies:
  flutter:
    sdk: flutter
  dartvel_dev: ^0.6.0
  dartvel_core: any       # the umbrella decides the version
  dartvel_flutter: any

dev_dependencies:
  dartvel_cli: ^0.6.0     # to run the CLI with `dart run dartvel_cli:dartvel`
```

`dart run <package>:<executable>` is for packages the project depends on
directly, so declare `dartvel_cli` if you run the CLI that way rather than
from an installed binary.

Every Dartvel package needs Dart 3.12 and Flutter 3.44 or newer.

[example/README.md](example/README.md) shows a project on the umbrella.

Every Dartvel package needs Dart 3.12 and Flutter 3.44 or newer.

[example/README.md](example/README.md) shows a project on the umbrella.

## Why the package is `dartvel_dev`

The framework is Dartvel and the command is `dartvel`. Only the published
identifier carries a suffix, because `dartvel` on pub.dev was taken on
2026-08-06 by an unrelated package. The same name is used on pub.dev, npm and
Homebrew so that whichever way you install it, it is called the same thing.

## Status, stated plainly

Dartvel is published early. Per-section implementation status lives in
[`docs/spec-status.json`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
and is checked by a tool that fails when a section claims to be built and the
evidence it names does not exist. `dartvel spec status` summarises it.

Each entry carries two independent labels: how much the public surface can
still move, and how much is actually built. A frozen contract that is
deliberately unbuilt is marked as such rather than implied to work, and what is
absent is written down next to what is present.

Verified per-target build status lives in
[`docs/build-targets.md`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/build-targets.md),
where "verified" means the command was run and the artifact inspected, never
inferred because a sibling target works.

## Links

- [dartvel.dev](https://dartvel.dev)
- [Repository](https://github.com/Danroyal001/dartvel_dev) and
  [getting started](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/getting-started.md)
- [Changelog](CHANGELOG.md); 0.6.0 carries breaking changes in the CLI, core
  and Flutter packages, listed in their changelogs.
- [Issues](https://github.com/Danroyal001/dartvel_dev/issues)
