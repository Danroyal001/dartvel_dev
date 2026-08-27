# dartvel_dev

A batteries-included, AI-native full-stack application platform built around
Flutter.

```sh
npx dartvel_dev --help
# or
npm install -g dartvel_dev
dartvel --help
```

## Why the package is `dartvel_dev` and the command is `dartvel`

`dartvel` on pub.dev was taken on 2026-08-06 by an unrelated package, so the
published identifier carries a suffix. The command you type does not, and
neither does anything else you interact with.

The same name is used on [pub.dev](https://pub.dev/packages/dartvel_dev) and in
the [Homebrew tap](https://github.com/Danroyal001/homebrew-dartvel_dev), so
whichever way you install it, it is called the same thing.

## What this package does

It launches the real CLI rather than containing a copy of it.

Dartvel is a Dart toolchain: `dartvel` is a Dart executable published on
pub.dev. Vendoring a compiled build into an npm package would ship a second
copy that drifts from the one `dart pub global activate` installs, and would
need a release per platform before this package could exist at all.

So on first run this finds `dartvel` on your PATH, and if it is not there,
installs it with `dart pub global activate dartvel_dev` and runs it through
`dart pub global run` — which works whether or not `~/.pub-cache/bin` is on
your PATH.

If there is no Dart SDK at all, it says so and points at the Flutter installer,
rather than failing with a command-not-found from somewhere three layers down.

## Requirements

The Dart SDK, which the Flutter SDK includes. Node 18 or newer.
