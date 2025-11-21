#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building Rust core (release)…"
( cd rust && cargo build --release )

echo "==> Generating C header with cbindgen…"
( cd rust && cbindgen --config cbindgen.toml -o include/dartvel_shelf.h )

echo "==> Fetching Dart deps…"
dart pub get

echo "==> Generating Dart FFI bindings with ffigen (optional; bindings.dart already included)…"
dart run ffigen || echo "ffigen failed or not installed — continuing because lib/src/ffi/bindings.dart is provided."

echo "✅ Done. Run: dart run example/server.dart"
