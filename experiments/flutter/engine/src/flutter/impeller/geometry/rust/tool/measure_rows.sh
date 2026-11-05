#!/usr/bin/env bash
# Not a port: measures every row of the README's Baseline table, the C++
# driver over upstream against the Rust driver over the port, with
# tool/measure.sh.
#
# Run from experiments/flutter after
# `cargo build --profile release-lto -p impeller_geometry`:
#
#   engine/src/flutter/impeller/geometry/rust/tool/measure_rows.sh [bench...]
#
# Builds the C++ driver first (CXX, default clang++, against libc++, with the
# engine's linux-x64 flags, the oracle's sources and -fno-exceptions
# -fno-rtti), into target/geometry_bench/geometry_dump_cxx.
# Environment: RUNS (default 15 runs a side), ROUNDS (default 300), CPU (the
# core both sides are pinned to, default 0), OUT (default
# target/measure-geometry), CXX, CXX_DRIVER, RUST_DRIVER.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../../../../.." && pwd)   # engine/src
work=target/geometry_bench
mkdir -p "$work"
cxx_driver=${CXX_DRIVER:-$work/geometry_dump_cxx}
rust=${RUST_DRIVER:-target/release-lto/geometry_dump}
if [ -z "${CXX_DRIVER:-}" ]; then
  sources=$(sed -n '/^const UPSTREAM_SOURCES/,/^];/p' "$here/../tests/oracle.rs" | grep -o '"flutter/[^"]*"' | tr -d '"')
  out=$(pwd)/$cxx_driver
  (cd "$src" && ${CXX:-clang++} -std=c++20 -O2 -march=x86-64 -ffp-contract=on -fwrapv \
    -fno-exceptions -fno-rtti -DNDEBUG -w -stdlib=libc++ -I . -I flutter -o "$out" \
    flutter/impeller/geometry/rust/oracle/geometry_dump.cc $sources -lm)
fi
runs=${RUNS:-15}
rounds=${ROUNDS:-300}
rows="point matrix invert determinant decompose rect irect color rrect rse arc gradient"
if [ $# -gt 0 ]; then rows="$*"; fi
for row in $rows; do
  "$here/measure.sh" "$runs" "$row" "$rounds" "$cxx_driver" "$rust"
done
