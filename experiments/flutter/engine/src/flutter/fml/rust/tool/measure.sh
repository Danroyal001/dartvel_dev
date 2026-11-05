#!/usr/bin/env bash
# Not a port: the benchmark harness of this crate, after
# experiments/dart_sdk/pkg/_fe_analyzer_shared/rust/tool/measure.sh.
#
# measure.sh <runs> <bench> <rounds> <cxx-driver> <rust-driver>
#
# Runs `<driver> bench <bench> <rounds>` with the C++ and the Rust driver
# alternately, <runs> times each (C++ first on odd runs, Rust first on even
# runs). Each run is two executions, with nothing between the shell and the
# driver:
#   1. plain: the driver's own report gives the fastest and median round of
#      its stopwatch and the peak RSS (VmHWM) of the process;
#   2. with FML_BENCH_INS=1: the driver counts the user-space instructions
#      retired under its stopwatch, in every thread (perf_event_open; needs
#      perf_event_paranoid <= 2, else it reports -1), and reports the median
#      round's count. Skipped with INS=0.
# Every run's check value must agree between the two sides, or the harness
# fails. Writes one line per run to $OUT/<bench>.runs and prints, for each
# measure and side, the minimum, median, maximum, mean and coefficient of
# variation.
set -u
runs=$1 bench=$2 rounds=$3 cxx=$4 rust=$5
out=${OUT:-target/measure}
mkdir -p "$out"
log=$out/$bench.runs
: > "$log"
one() {
  local side=$1 bin=$2 e=$out/.e.$$ line fast med rss check ins=-
  "$bin" bench "$bench" "$rounds" > /dev/null 2> "$e"
  line=$(grep "^bench $bench " "$e" | tail -1)
  read -r fast med rss check <<< "$(awk '{print $4, $7, $13, $16}' <<< "$line")"
  if [ "${INS:-1}" != 0 ]; then
    FML_BENCH_INS=1 "$bin" bench "$bench" "$rounds" > /dev/null 2> "$e"
    ins=$(grep "^bench $bench " "$e" | tail -1 | awk '{print $20}')
  fi
  echo "$side ins=$ins fastest_us=$fast median_us=$med rss_kib=$rss check=$check" >> "$log"
  rm -f "$e"
}
for i in $(seq 1 "$runs"); do
  if (( i % 2 )); then one cxx "$cxx"; one rust "$rust"; else one rust "$rust"; one cxx "$cxx"; fi
done
checks=$(grep -o 'check=[0-9a-f]*' "$log" | sort -u | wc -l)
if [ "$checks" != 1 ]; then
  echo "== $bench: check values differ:" >&2
  grep -o '^[a-z]* .*check=[0-9a-f]*' "$log" >&2
  exit 1
fi
summ() {
  local side=$1 field=$2
  grep "^$side " "$log" | grep -o "$field=[0-9.]*" | cut -d= -f2 | sort -g |
    awk -v s="$side" -v f="$field" '{a[NR]=$1; sum+=$1; sq+=$1*$1}
      END{if(NR==0)exit; m=sum/NR; sd=sqrt(sq/NR-m*m); printf "%-4s %-10s n=%d min=%s median=%s max=%s mean=%.1f cv=%.1f%%\n", s, f, NR, a[1], a[int((NR+1)/2)], a[NR], m, (m?100*sd/m:0)}'
}
echo "== $bench ($rounds rounds, $runs runs a side)"
for f in ins fastest_us median_us rss_kib; do
  for side in cxx rust; do summ $side $f; done
done
