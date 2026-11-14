#!/usr/bin/env bash
# Not a port: the benchmark harness of this crate, after
# experiments/flutter/engine/src/flutter/fml/rust/tool/measure.sh.
#
# measure.sh <runs> <bench> <rounds> <cxx-driver> <rust-driver>
#
# Runs `<driver> bench <bench> <rounds>` with the C++ and the Rust driver
# alternately, <runs> times each (C++ first on odd runs, Rust first on even
# runs), each run pinned to the same core (CPU, default 0) when taskset is
# there. Every run's checksum must agree between the two sides, or the harness
# fails. Writes one line per run to $OUT/<bench>.runs and prints, for the
# fastest round, the median round and the peak RSS (VmHWM) of each side, the
# minimum, median, maximum, mean and coefficient of variation over the runs.
set -u
runs=$1 bench=$2 rounds=$3 cxx=$4 rust=$5
out=${OUT:-target/measure-geometry}
mkdir -p "$out"
log=$out/$bench.runs
: > "$log"
pin=()
if command -v taskset > /dev/null; then pin=(taskset -c "${CPU:-0}"); fi
one() {
  local side=$1 bin=$2 line
  line=$("${pin[@]}" "$bin" bench "$bench" "$rounds" | grep "^$bench fastest_ns ")
  awk -v s="$side" '{printf "%s fastest_ns=%s median_ns=%s rss_kib=%s check=%s\n", s, $3, $5, $11, $9}' <<< "$line" >> "$log"
}
for i in $(seq 1 "$runs"); do
  if (( i % 2 )); then one cxx "$cxx"; one rust "$rust"; else one rust "$rust"; one cxx "$cxx"; fi
done
checks=$(grep -o 'check=[0-9a-f]*' "$log" | sort -u | wc -l)
if [ "$checks" != 1 ]; then
  echo "== $bench: checksums differ:" >&2
  cat "$log" >&2
  exit 1
fi
summ() {
  local side=$1 field=$2
  grep "^$side " "$log" | grep -o "$field=[0-9.]*" | cut -d= -f2 | sort -g |
    awk -v s="$side" -v f="$field" '{a[NR]=$1; sum+=$1; sq+=$1*$1}
      END{if(NR==0)exit; m=sum/NR; sd=sqrt(sq/NR-m*m); printf "%-4s %-10s n=%d min=%s median=%s max=%s mean=%.1f cv=%.1f%%\n", s, f, NR, a[1], a[int((NR+1)/2)], a[NR], m, (m?100*sd/m:0)}'
}
echo "== $bench ($rounds rounds, $runs runs a side)"
for f in fastest_ns median_ns rss_kib; do
  for side in cxx rust; do summ $side $f; done
done
