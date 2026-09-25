# Building the native library from source

You do not need this to use `dartvel_shelf`. The package ships a prebuilt
library for each supported platform in `lib/native/`, and `serve()` loads
that. This page is for working on the Rust side, or for rebuilding the
library yourself rather than using the shipped binary.

## Why the build hook is off by default

`dartvel_shelf` declares a native-assets build hook (`hook/build.dart`). Every
Dartvel application depends on this package through `dartvel_dev`, whether or
not it ever serves anything, so a hook that always built would put a full
HTTP server into client applications that never listen. It therefore does
nothing unless the application asks for it.

## Turning it on

In the pubspec of the application being built:

```yaml
hooks:
  user_defines:
    dartvel_shelf:
      embed_server: true
```

`true`, or the strings `true`, `1` or `yes`. Anything else, including
`false`, leaves it off.

It then needs, on the `PATH`:

- `cargo` (a Rust toolchain from <https://rustup.rs>);
- `cbindgen` (`cargo install cbindgen`);
- `rustup`, when building for an architecture other than the host's; the hook
  runs `rustup target add` for the target triple if it is missing.

If `cargo` or `cbindgen` is missing, the hook prints a message and skips,
and the shipped library is used as before. If they are present and the build
fails, the hook fails the build.

## What it does

For the platform being built (Linux, macOS or Windows, x64 or arm64):

1. `cargo build --release --target <triple>` in the package's `rust/`
   directory, with a 30 minute limit. A cold build compiles close to two
   hundred crates.
2. `cbindgen` regenerates `rust/include/dartvel_shelf.h`.
3. `dart run ffigen` regenerates `lib/src/generated/bindings.dart`.
4. The built library is copied over `lib/native/<platform>/` and reported to
   the Dart build as a bundled code asset.

Steps 2 to 4 write into the `dartvel_shelf` package directory itself, so only
turn this on for a path or git dependency you have checked out, not for a
copy in the pub cache.

`serve()` loads the library from `lib/native/<platform>/` under `dart run`,
and from `embedNativeServerLibrary()` in a compiled executable. It does not
look for the copy a `dart build cli` bundle places in `bundle/lib/`, so a
compiled server still needs the step in [deployment.md](deployment.md).

## Building by hand

The same result without the hook, from the package root:

```sh
cd rust
cargo build --release --target x86_64-unknown-linux-gnu
cp target/x86_64-unknown-linux-gnu/release/libdartvel_shelf.so \
   ../lib/native/linux-x64/libdartvel_shelf.so
```

| Platform | Target triple | File |
|---|---|---|
| `linux-x64` | `x86_64-unknown-linux-gnu` | `libdartvel_shelf.so` |
| `linux-arm64` | `aarch64-unknown-linux-gnu` | `libdartvel_shelf.so` |
| `macos-arm64` | `aarch64-apple-darwin` | `libdartvel_shelf.dylib` |
| `macos-x64` | `x86_64-apple-darwin` | `libdartvel_shelf.dylib` |
| `windows-x64` | `x86_64-pc-windows-msvc` | `dartvel_shelf.dll` |
| `windows-arm64` | `aarch64-pc-windows-msvc` | `dartvel_shelf.dll` |

The Dart side checks what it loads. A library built from an older Rust source
is refused with a message naming the file, rather than being called with the
wrong arguments.
