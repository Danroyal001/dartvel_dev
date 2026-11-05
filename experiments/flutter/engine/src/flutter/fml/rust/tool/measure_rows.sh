#!/usr/bin/env bash
# Not a port: measures every row of the README's Benchmarks table, the C++
# driver over upstream against the Rust driver over the port, with
# tool/measure.sh.
#
# Run from experiments/flutter after `cargo test --release -p fml --test
# oracle` (which builds both drivers: target/release/fml_dump and
# target/fml_oracle/fml_dump_libc++), with perf_event_paranoid at 2 or lower
# (or INS=0):
#
#   engine/src/flutter/fml/rust/tool/measure_rows.sh [bench...]
#
# Environment: RUNS (default 11 runs a side), OUT (default target/measure),
# CXX_DRIVER, RUST_DRIVER.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cxx=${CXX_DRIVER:-target/fml_oracle/fml_dump_libc++}
rust=${RUST_DRIVER:-target/release/fml_dump}
runs=${RUNS:-11}
# name:rounds, as the README's table runs them.
rows="queues:300 dispatch:20 time:300 strings:20 hash:100 loop:10 thread:10
concurrent:200 merger:3 file:20 mapping:5 paths:50 cmdline:50 trace:50"
want=" $* "
for row in $rows; do
  name=${row%%:*} rounds=${row#*:}
  if [ $# -gt 0 ] && [[ $want != *" $name "* ]]; then continue; fi
  "$here/measure.sh" "$runs" "$name" "$rounds" "$cxx" "$rust"
done
