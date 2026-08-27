# dartvel_cli

The `dartvel` command.

```sh
dart pub global activate dartvel_dev
dartvel --help
```

Generation, build, dev server with hot reload across Flutter *and* the Rust
backend, database and queue management, deployment, and a typed cross-platform
shell.

## Build targets

`dartvel build <target>` covers web, Linux, Android, Fire OS, Windows, macOS,
iOS, tvOS, Tizen, Sony eLinux, VS Code extensions, and Chrome and Firefox
extensions. Embedded and television targets ride the platform vendor's own
Flutter embedder rather than plain `flutter build`, each pinned in a fork.

A build checks host support and required tooling *before* doing any generation
work, so it never starts something it cannot finish, and it says which tool is
missing rather than failing partway. Licence-gated SDKs — Xcode, Visual Studio,
the Android SDK, Tizen Studio — are never installed unattended; the build
prints instructions instead.

## The name

This package is published as part of
[`dartvel_dev`](https://pub.dev/packages/dartvel_dev). `dartvel` on pub.dev was
taken on 2026-08-06 by an unrelated package, so the published identifier
carries a suffix while the command does not.
