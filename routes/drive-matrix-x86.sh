#!/bin/bash
# Runs the x86 route matrix over a seed range, parallelism P, saving one summary
# line and the session-route residues per seed, reclaiming each workdir after.
set -u
BASE=/home/hbox/ca-x86-sbcl
MX=$BASE/common-lisp-compiler-audit/routes/run-matrix-x86.sh
RES=${RES:-$BASE/results-matrix}
N=${N:-8}
P=${P:-4}
LO=${LO:-1}; HI=${HI:-30}
mkdir -p "$RES"
run_seed() {
  local s=$1 w rc
  w=$BASE/work/seed-$s
  rm -rf "$w"; mkdir -p "$w"
  if timeout 1200 "$MX" "$s" "$N" head "$w" > "$RES/seed-$s.log" 2>&1; then rc=PASS; else rc="FAIL_$?"; fi
  grep "^@Q" "$w/session.rec" 2>/dev/null | sort > "$RES/seed-$s.residue" || true
  local df; df=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
  echo "seed $s N=$N $rc routes=$(grep -c "^[a-z].* yes$\|^[a-z].* NO$" "$RES/seed-$s.log" 2>/dev/null) freeGB=$df" >> "$RES/summary.txt"
  rm -rf "$w"
}
export -f run_seed; export BASE MX RES N
echo "START $(date) seeds $LO-$HI N=$N P=$P" > "$RES/summary.txt"
seq "$LO" "$HI" | xargs -P "$P" -I{} bash -c "run_seed {}"
echo "DONE $(date)" >> "$RES/summary.txt"
