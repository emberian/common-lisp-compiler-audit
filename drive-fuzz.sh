#!/bin/bash
# Differential non-integer SBCL codegen fuzz: W workers x SECS seconds per SBCL,
# (speed 3)(safety 0) vs (speed 0)(safety 3), FP traps masked identically.
# Each worker writes a PID file and a summary; we aggregate HARD/soft counts.
set -u
BASE=/home/hbox/ca-x86-sbcl
FZ=$BASE/fuzz-nonint.lisp
SECS=${SECS:-120}
W=${W:-8}
run_version() {
  local tag=$1 sbcl=$2 out=$BASE/fuzz-$1
  rm -rf "$out"; mkdir -p "$out"
  local pids=()
  for w in $(seq 1 "$W"); do
    nice -n 15 timeout $((SECS+40)) "$sbcl" --dynamic-space-size 2500 --script "$FZ" \
         "$w" "$SECS" "$out" 28 > "$out/w$w.log" 2>&1 &
    echo $! > "$out/w$w.pid"
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  { echo "=== $tag ($sbcl) ==="
    echo "workers: $(ls "$out"/summary-w* 2>/dev/null | wc -l)"
    echo "total functions: $(grep -ho "nfn=[0-9]*" "$out"/summary-w* 2>/dev/null | cut -d= -f2 | paste -sd+ | bc)"
    echo "HARD value-diffs (all-finite inputs): $(grep -ho "HARD=[0-9]*" "$out"/summary-w* 2>/dev/null | cut -d= -f2 | paste -sd+ | bc)"
    echo "value-diffs total: $(grep -ho "value-diffs=[0-9]*" "$out"/summary-w* 2>/dev/null | cut -d= -f2 | paste -sd+ | bc)"
    echo "asym: $(grep -ho "asym=[0-9]*" "$out"/summary-w* 2>/dev/null | cut -d= -f2 | paste -sd+ | bc)"
    echo "compile-skips: $(grep -ho "compile-skips=[0-9]*" "$out"/summary-w* 2>/dev/null | cut -d= -f2 | paste -sd+ | bc)"
    echo "hard finding files: $(ls "$out"/findings-hard.lisp-w* 2>/dev/null | wc -l)"
  } | tee "$out/AGG.txt"
}
run_version sbcl268 /home/hbox/sbcl-2.6.8-x86-64-linux/run-sbcl.sh
run_version sbcl229 /usr/bin/sbcl
echo "FUZZ-ALL-DONE"
