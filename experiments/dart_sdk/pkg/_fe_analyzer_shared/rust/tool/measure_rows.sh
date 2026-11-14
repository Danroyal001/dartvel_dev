#!/usr/bin/env bash
# Not a port: measures every README row of the scanner, the parser and the
# syntax tree, Dart AOT against Rust, with tool/measure.sh.
#
# Run from the SDK root (experiments/dart_sdk), after
# `cargo build --release --bins` and after the ast oracle has run once
# (it writes the analyzer's package config under target/ast_oracle), with
# `perf_event_paranoid` at 2 or lower:
#
#   pkg/_fe_analyzer_shared/rust/tool/measure_rows.sh [inproc] [single]
#
# Environment: DART (default dart), N_INPROC (default 11 processes a side),
# N_SINGLE (default 31), OUT (default target/measure).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
measure=$here/measure.sh
dart=${DART:-dart}
out=${OUT:-target/measure}
aot=$out/aot
mkdir -p "$aot"
export OUT=$out

shared=pkg/_fe_analyzer_shared/rust/oracle
[ -x "$aot/scanner_dump" ] || "$dart" compile exe --packages=$shared/package_config.json \
  $shared/scanner_dump.dart -o "$aot/scanner_dump"
[ -x "$aot/parser_dump" ] || "$dart" compile exe --packages=$shared/package_config.json \
  $shared/parser_dump.dart -o "$aot/parser_dump"
[ -x "$aot/ast_dump" ] || "$dart" compile exe --packages=target/ast_oracle/ast/package_config.json \
  pkg/analyzer/rust/oracle/ast_dump.dart -o "$aot/ast_dump"
rust=target/release

# The scanner's default corpus (the scanner oracle extracts its test
# inputs) and the parser's, which the tree benchmarks use too.
scan_corpus="target/scanner_oracle/scanner_test_inputs pkg/_fe_analyzer_shared/lib pkg/analyzer/lib"
parse_corpus="pkg/_fe_analyzer_shared/lib pkg/analyzer/lib tests/language"

inproc() {
  local n=${N_INPROC:-11}
  "$measure" $n scan_utf8 "$aot/scanner_dump --scanner=utf8 --bench=20 $scan_corpus" \
    "$rust/scanner_dump --scanner=utf8 --bench=20 $scan_corpus"
  "$measure" $n scan_string "$aot/scanner_dump --scanner=string --bench=20 $scan_corpus" \
    "$rust/scanner_dump --scanner=string --bench=20 $scan_corpus"
  "$measure" $n parse "$aot/parser_dump --bench=20 $parse_corpus" \
    "$rust/parser_dump --bench=20 $parse_corpus"
  "$measure" $n ast "$aot/ast_dump --bench=10 $parse_corpus" \
    "$rust/ast_dump --bench=10 $parse_corpus"
  "$measure" $n tosource "$aot/ast_dump --api --bench=10 $parse_corpus" \
    "$rust/ast_dump --api --bench=10 $parse_corpus"
  "$measure" $n retain "$aot/ast_dump --retain $parse_corpus" \
    "$rust/ast_dump --retain $parse_corpus"
}

# Each single-file input sits in a folder of its own.
single() {
  local n=${N_SINGLE:-31} files=$out/files
  mkdir -p $files/small $files/medium $files/large
  cp pkg/_fe_analyzer_shared/lib/src/util/link.dart $files/small/
  cp pkg/analyzer/lib/src/dart/element/type_system.dart $files/medium/
  cp pkg/analyzer/lib/src/dart/ast/ast.dart $files/large/
  for program in scanner_dump parser_dump ast_dump; do
    for size in small medium large; do
      rm -rf $out/dumps && mkdir -p $out/dumps/dart $out/dumps/rust
      "$measure" $n single_${program}_$size "$aot/$program --out $out/dumps/dart $files/$size" \
        "$rust/$program --out $out/dumps/rust $files/$size"
      if diff -r $out/dumps/dart $out/dumps/rust > /dev/null; then
        echo "identical: $program $size"
      else
        echo "DIFFERENT: $program $size"
      fi
    done
  done
}

for part in "${@:-inproc single}"; do
  for p in $part; do $p; done
done

for program in scanner_dump parser_dump ast_dump; do
  strip -o "$out/$program.stripped" "$rust/$program"
  echo "size $program: rust $(stat -c%s "$rust/$program") unstripped," \
    "$(stat -c%s "$out/$program.stripped") stripped; dart AOT $(stat -c%s "$aot/$program")"
done
