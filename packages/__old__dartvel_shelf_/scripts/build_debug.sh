#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

( cd rust && cargo build )

( cd rust && cbindgen --config cbindgen.toml -o include/dartvel_shelf.h )

dart pub get
dart run ffigen || echo "ffigen optional; using pre-generated bindings.dart"
