#!/usr/bin/env bash
# Not a port: the benchmark harness of this crate and pkg/analyzer/rust.
#
# measure.sh <runs> <name> <dart-cmd> <rust-cmd>
#
# Runs the two commands alternately <runs> times each (Dart first on odd
# runs, Rust first on even runs). Each run is three executions of the
# command, with nothing between the shell and the program:
#   1. plain, timed with $EPOCHREALTIME (wall time, and the program's own
#      "min_us=... median_us=... delta=..." line, if it prints one);
#   2. under `perf stat -e instructions:u` (user-space instructions);
#   3. under `/usr/bin/time -f %M` (peak RSS of the program, KiB).
# Writes one line per run to $OUT/<name>.runs and prints a summary: for
# each measure the minimum, median, maximum, mean and coefficient of
# variation.
set -u
runs=$1 name=$2 dart=$3 rust=$4
out=${OUT:-target/measure}
mkdir -p "$out"
log=$out/$name.runs
: > "$log"
one() {
  local side=$1 cmd=$2 t=$out/.t.$$ p=$out/.p.$$ o=$out/.o.$$
  local t0 t1 wall ins rss min med dl
  t0=$EPOCHREALTIME
  $cmd > "$o" 2>/dev/null
  t1=$EPOCHREALTIME
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", (b-a)*1000}')
  min=$(grep -o 'min_us=[0-9]*' "$o" | head -1 | cut -d= -f2)
  med=$(grep -o 'median_us=[0-9]*' "$o" | head -1 | cut -d= -f2)
  dl=$(grep -o 'delta=[0-9]*' "$o" | head -1 | cut -d= -f2)
  perf stat -x, -e instructions:u -o "$p" -- $cmd > /dev/null 2>&1
  ins=$(awk -F, '/instructions/{print $1}' "$p")
  /usr/bin/time -f "%M" -o "$t" $cmd > /dev/null 2>&1
  rss=$(tail -1 "$t")
  echo "$side ins=$ins wall_ms=$wall rss_kib=$rss min_us=${min:--} median_us=${med:--} delta=${dl:--}" >> "$log"
  rm -f "$t" "$p" "$o"
}
for i in $(seq 1 "$runs"); do
  if (( i % 2 )); then one dart "$dart"; one rust "$rust"; else one rust "$rust"; one dart "$dart"; fi
done
summ() {
  local side=$1 field=$2
  grep "^$side " "$log" | grep -o "$field=[0-9.]*" | cut -d= -f2 | sort -g |
    awk -v s="$side" -v f="$field" '{a[NR]=$1; sum+=$1; sq+=$1*$1}
      END{if(NR==0)exit; m=sum/NR; sd=sqrt(sq/NR-m*m); printf "%s %s: n=%d min=%s median=%s max=%s mean=%.1f cv=%.1f%%\n", s, f, NR, a[1], a[int((NR+1)/2)], a[NR], m, (m?100*sd/m:0)}'
}
echo "== $name"
for side in dart rust; do
  for f in ins wall_ms rss_kib min_us median_us delta; do summ $side $f; done
done
