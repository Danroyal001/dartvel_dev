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

## Building all six from one Linux machine

Every copy in `lib/native/` must be built from the same source, so build them
together, from one checkout, after any change under `rust/`. All six
cross-compile from Linux x64; none needs a Mac or a Windows machine:

```sh
rustup target add aarch64-unknown-linux-gnu aarch64-apple-darwin \
  x86_64-apple-darwin x86_64-pc-windows-msvc aarch64-pc-windows-msvc
cargo install --locked cargo-zigbuild cargo-xwin   # plus zig on the PATH, clang, lld

cd rust
cargo build --release --locked --target x86_64-unknown-linux-gnu
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar \
  cargo build --release --locked --target aarch64-unknown-linux-gnu
MACOSX_DEPLOYMENT_TARGET=11.0 \
  cargo zigbuild --release --locked --target aarch64-apple-darwin
MACOSX_DEPLOYMENT_TARGET=10.12 \
  cargo zigbuild --release --locked --target x86_64-apple-darwin
cargo xwin build --release --locked --target x86_64-pc-windows-msvc
PATH="$PWD/../tool/clang-imsvc:$PATH" \
  cargo xwin build --release --locked --target aarch64-pc-windows-msvc
```

Then copy each `target/<triple>/release/` library over its row in the table
above.

- **macOS.** zig links the dylib and signs it ad hoc, which is all Apple
  silicon needs to load a library. The warning that `xcrun` was not found is
  expected: zig carries its own macOS libSystem stubs.
- **windows-arm64.** `ring` compiles its ARM64 assembly with plain `clang`
  rather than `clang-cl`, and cargo-xwin's C flags are written for `clang-cl`
  (`/imsvc <dir>`), which plain clang reads as file names.
  `tool/clang-imsvc/clang` is a small Dart script that rewrites that one flag
  and runs the real clang; put it
  first on the `PATH` for this target only. cargo-xwin's
  `--cross-compiler clang` mode is not a way round it: it puts MSVC's
  `arm_neon.h` ahead of clang's, and zstd then calls MSVC-only intrinsics
  (`neon_ld1m_8`) that do not link.

### The source revision

`build.rs` stamps each library with a hash of the files it was built from
(`Cargo.toml`, `Cargo.lock`, `build.rs` and everything under `src/`), readable
as `aw_source_revision()` and present in the binary as the plain text
`dartvel_shelf source revision <16 hex digits>`.
`test/prebuilt_source_revision_test.dart` hashes `rust/` the same way and
reads the stamp out of all six copies without loading them, so it checks the
macOS and Windows libraries on Linux too. It fails when any copy was built
from a different source than the one in the tree, which is what a partial
rebuild looks like: 3.47.4 rebuilt three of the six after a TLS fix, and the
macOS and windows-arm64 copies kept the bug.
