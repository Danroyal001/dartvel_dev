# dartvel_dev

The `dartvel` command for [Dartvel](https://dartvel.dev), a full-stack
application platform built around Flutter: code generation, a dev server with
hot reload across the app and its backend, builds for web, mobile, desktop, TV
and embedded targets, and deployment.

```sh
npm install -g dartvel_dev
dartvel --help

# or without installing
npx dartvel_dev --help
```

Installing puts two names on your PATH, `dartvel` and `dartvel_dev`, for the
same program. [`dartvel_cli`](https://www.npmjs.com/package/dartvel_cli) is an
alias package that installs this one.

## What this package does

It is a launcher. The first time it runs, it downloads the self-contained
`dartvel` binary for your platform from the
[GitHub release](https://github.com/Danroyal001/dartvel_dev/releases) with the
same version as this package, checks it against the `SHA256SUMS` published
with that release, and keeps it in `vendor/` inside the package. Later runs
start that binary directly. Arguments, output and the exit code pass through
unchanged.

The Dart runtime and the Rust server library are linked into the binary, so
nothing has to be installed first. Building an application still needs
Flutter, for whichever target you are building. Running the CLI does not.

A release without a `SHA256SUMS` file still installs, with a message saying the
download was not verified. A checksum that does not match is an error, and
nothing is kept.

## Platforms

| Platform | Release asset |
|---|---|
| Linux x64 | `dartvel-linux-amd64` |
| Linux arm64 | `dartvel-linux-arm64` |
| macOS Intel | `dartvel-darwin-amd64` |
| macOS Apple silicon | `dartvel-darwin-arm64` |
| Windows x64 | `dartvel-windows-amd64.exe` |

Windows on ARM has no build yet; the launcher says so rather than fetching a
URL that does not exist. The x64 binary runs there under emulation if you
download it yourself. Node 18 or newer.

**For 0.6.0, only the Linux binaries are attached until the CI release
workflow has run.** Until then, on macOS or Windows the first run fails with
`HTTP 404` and prints the release page. Use `dartvel_dev@0.5.0` there, or run
the CLI from a project's dependencies with `dart run dartvel_cli:dartvel` (see
the [dartvel_cli README](https://pub.dev/packages/dartvel_cli)).

## First steps

```sh
dartvel create my_app
cd my_app
dartvel dev
```

`dartvel doctor` checks your Dart, Flutter and project setup, and
`dartvel doctor --target <target>` checks one build target's toolchain. The
command reference, configuration and troubleshooting are in the
[dartvel_cli README](https://pub.dev/packages/dartvel_cli).

## Why not `dart pub global activate`

An earlier version of this package ran `dart pub global activate dartvel_dev`
and then the activated command. That cannot work: the `dartvel_dev` package on
pub.dev depends on the Flutter SDK, and pub refuses to run a global executable
from such a package. It activated, and then every run failed with:

```text
dartvel_dev as globally activated requires the Flutter SDK, which is unsupported for global executables.
```

Downloading the compiled binary avoids pub altogether.

## Why the package is `dartvel_dev` and the command is `dartvel`

`dartvel` on pub.dev was taken on 2026-08-06 by an unrelated package, so the
published identifier carries a suffix. The command does not, and neither does
anything else you interact with. The same name is used on
[pub.dev](https://pub.dev/packages/dartvel_dev), npm and in the
[Homebrew tap](https://github.com/Danroyal001/homebrew-dartvel_dev).

## Links

- [dartvel.dev](https://dartvel.dev)
- [Repository](https://github.com/Danroyal001/dartvel_dev)
- [Releases](https://github.com/Danroyal001/dartvel_dev/releases)
- [Issues](https://github.com/Danroyal001/dartvel_dev/issues)
