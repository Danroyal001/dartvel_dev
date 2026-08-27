# dartvel_dev

A batteries-included, AI-native full-stack application platform built around
Flutter.

```sh
npx dartvel_dev --help
# or
npm install -g dartvel_dev
dartvel --help
```

## No SDK needed to run it

This downloads a self-contained `dartvel` binary for your platform. The Dart
runtime and the Rust server library are linked into it, so nothing has to be
installed first.

Building an application still needs Flutter, for whichever target you are
building. Running the CLI does not.

An earlier version of this package ran `dart pub global activate` instead, and
that could not work: the umbrella package depends on the Flutter SDK, and pub
refuses to run a global executable from a package that does. It activated and
then would not run.

## Platforms

Linux, macOS and Windows, on x64; Linux and macOS also on arm64. An
unsupported combination says which one rather than fetching a URL that 404s.

The download is checked against the SHA256SUMS published with the release
before it is made executable, so a truncated fetch fails as a checksum
mismatch rather than as a mysterious crash in the tool.

## Why the package is `dartvel_dev` and the command is `dartvel`

`dartvel` on pub.dev was taken on 2026-08-06 by an unrelated package, so the
published identifier carries a suffix. The command does not, and neither does
anything else you interact with. The same name is used on
[pub.dev](https://pub.dev/packages/dartvel_dev), npm and in the
[Homebrew tap](https://github.com/Danroyal001/homebrew-dartvel_dev).
