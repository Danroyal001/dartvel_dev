# Deploying a dartvel_shelf server

Under `dart run`, `serve()` finds the native library inside the resolved
`dartvel_shelf` package (`lib/native/<platform>/`). A compiled executable has
no package configuration to resolve against, so that lookup has nothing to
find. Before 0.7.0 this failed with a null check; now `serve()` throws a
`StateError` saying the library is missing.

The fix is to hand the process the library's bytes with
`embedNativeServerLibrary(bytes)` before the first `serve()`. Where those
bytes come from is up to you. This page uses the simplest arrangement: the
library file sits next to the executable.

## What to ship

| Host | Files |
|---|---|
| Linux | `server`, `libdartvel_shelf.so` |
| macOS | `server`, `libdartvel_shelf.dylib` |
| Windows | `server.exe`, `dartvel_shelf.dll` |

Plus whatever your program reads at runtime: a `staticDir`, TLS certificates.
Nothing else from the Dart SDK or the pub cache is needed.

The library must be the one for the machine the server runs on, and from the
same `dartvel_shelf` version the executable was compiled against. A library
from an older version is refused by name (`speaks ABI 1 and this package
speaks 2`, or `cannot limit a request body`), never loaded and misread.

## Step by step

1. Load the library in `main` before serving. From
   [example/compiled.dart](../example/compiled.dart):

   ```dart
   String get nativeLibraryName => Platform.isWindows
       ? 'dartvel_shelf.dll'
       : Platform.isMacOS
           ? 'libdartvel_shelf.dylib'
           : 'libdartvel_shelf.so';

   Future<void> main() async {
     final beside = File.fromUri(File(Platform.resolvedExecutable)
         .parent
         .uri
         .resolve(nativeLibraryName));
     // Under `dart run`, resolvedExecutable is the Dart VM and the package's
     // own copy is used instead, so this program works both ways.
     if (beside.existsSync()) {
       embedNativeServerLibrary(beside.readAsBytesSync());
     }
     // ... serve() as usual
   }
   ```

2. Compile. Either command works; `dart build cli` puts the result in a
   `bundle/` directory meant to be shipped as a whole.

   ```sh
   dart build cli                     # build/cli/<os>_<arch>/bundle/bin/server
   # or
   dart compile exe bin/server.dart -o build/server
   ```

   No Rust toolchain is involved. The package's build hook runs and skips
   (see [building-from-source.md](building-from-source.md)).

3. Copy the library next to the executable.
   [example/copy_native_library.dart](../example/copy_native_library.dart)
   finds it in your project's resolved `dartvel_shelf` and copies it; put it
   in your project (say `tool/copy_native_library.dart`) and run:

   ```sh
   dart run tool/copy_native_library.dart build/cli/linux_x64/bundle/bin
   ```

   Or copy it by hand from `lib/native/<platform>/` of the `dartvel_shelf`
   directory that `.dart_tool/package_config.json` points at.

4. Run it from anywhere:

   ```sh
   PORT=8080 build/cli/linux_x64/bundle/bin/server
   ```

This sequence was run for this release on Linux x64: `dart build cli` of
`example/compiled.dart`, the library copied beside it, the `bundle/` directory
moved elsewhere, then started, requested with `curl`, and stopped with
`SIGTERM`.

## How the library is loaded

On Linux the bytes are written to an anonymous in-memory file (`memfd_create`)
and loaded from there, so nothing is written to disk. If the kernel refuses
that, and on macOS and Windows, they are written to a new directory created
with `Directory.systemTemp.createTempSync`, which only the current user can
enter, and loaded from there. That directory is not removed when the process
exits.

## Cross-compiling

`dart build cli` accepts `--target-os` and `--target-arch`; the library you
ship must then be the one for the target, taken from
`lib/native/<os>-<arch>/`. `copy_native_library.dart` copies the one for the
machine it runs on, so for a cross build copy the file yourself.

## Containers

The Linux libraries link against glibc 2.34 or newer and `libgcc_s`, so the
runtime image has to provide both. Debian 12 (`debian:bookworm-slim`) and
Ubuntu 22.04 or later do; Alpine (musl) does not. A starting point, not
something this package's CI builds:

```dockerfile
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart build cli -o out \
 && dart run tool/copy_native_library.dart out/bundle/bin

FROM debian:bookworm-slim
COPY --from=build /app/out/bundle /app
EXPOSE 8080
CMD ["/app/bin/server"]
```

Inside a container, listen on `0.0.0.0`, not the default `127.0.0.1`, or
nothing outside the container can connect.

## Stopping cleanly

Orchestrators send `SIGTERM` and wait before killing. `ServerHandle.stop()`
blocks the isolate while the native side closes, so a request whose handler is
still awaiting something cannot finish during it and is answered 504 or cut
off. Count running requests in a middleware and wait for zero before calling
`stop()`; answer `/health` with 503 while you wait so the load balancer stops
sending traffic. [example/graceful_shutdown.dart](../example/graceful_shutdown.dart)
does both.

`ProcessSignal.sigterm.watch()` throws on Windows, so guard it with
`Platform.isWindows` as the examples do.
