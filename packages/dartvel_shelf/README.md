# dartvel_shelf — Rust-native server (H1/H1.1/H2/H3 + SSE + WS)

A Rust-native, Shelf-replacement runtime for dartvel. The heavy lifting (HTTP, TLS/ALPN, H3/QUIC, routing, static, gzip, SSE/WS) lives in Rust. The Dart layer is a thin **FFI bridge** exposing a WinterCG-like API (`Request`, `Response`) and a small `DartvelShelf` app builder for developer ergonomics.

- Public surface is **WinterCG-first**.
- Networking is native (Rust). Dart only bridges requests/responses and hands control to your handlers when needed.
- Bindings: **cbindgen** → **ffigen**. Pre-generated bindings are included; you can regenerate if desired.

## Quickstart

```bash
# 1) Build native core
cd rust && cargo build --release
cbindgen --config cbindgen.toml -o include/dartvel_shelf.h

# 2) Dart side
cd .. && dart pub get
# optional: regenerate bindings if you changed the header
dart run ffigen || true

# 3) Run the example
dart run example/server.dart
```

### Bindings
- A complete C header is included at `rust/include/dartvel_shelf.h`.
- Pre-generated Dart FFI bindings are included at `lib/src/ffi/bindings.dart`.
- You can still run `dart run ffigen` later if you want regenerated bindings.

## Scripts
- `scripts/build_release.sh` / `scripts/build_release.ps1`: build native, generate header, run ffigen.
- `scripts/build_debug.sh`: debug build.
- `scripts/run_example.sh`: run the example server.
- `scripts/gen_cert_self_signed.sh`: create dev TLS certs for HTTP/2 and HTTP/3 tests.
- `Makefile`: convenience targets (`make release`, `make bindings`, `make example`).

## Dart SDK
- Requires Dart >= 3.4.0 (tested up to 3.9.0). The FFI structs are marked `base` to satisfy Dart 3.9 requirements.

## Loading the native library
At runtime the Dart layer needs to load the Rust shared library:

- Preferred: build once via `scripts/build_release.sh`. The CLI and examples will auto-discover the library in a monorepo (`packages/dartvel_shelf/rust/target/release/...`).
- Override: set `DARTVEL_SHELF_LIB` env var with the absolute path to the shared library, e.g.:
  - Linux: `export DARTVEL_SHELF_LIB=/path/to/libdartvel_shelf.so`
  - macOS: `export DARTVEL_SHELF_LIB=/path/to/libdartvel_shelf.dylib`
  - Windows: `set DARTVEL_SHELF_LIB=C:\\path\\to\\dartvel_shelf.dll`

If neither is found, the loader throws a helpful error when starting the dev server.

## WinterCG request bridging status

The thin bridge now populates all primary WinterCG fields for incoming requests:

- URL: the absolute URL is provided via the FFI envelope
- Method: mapped to a compact code and expanded in Dart
- Headers: all request headers (multi-value preserved)
- Params: derived in Dart from the URL query

Implementation details:

- Rust serializes URL and headers JSON into a per-request RX buffer and sets offsets/lengths on `RequestEnvelope`.
- Dart reads the RX buffer with `dv_request_metadata_read`, decodes URL/headers, and constructs a `Request`.
- RX buffers are cleared when the response envelope is submitted to avoid leaks.

## CI
A GitHub Actions workflow is included at `.github/workflows/build.yml` to build Rust and run optional ffigen.
