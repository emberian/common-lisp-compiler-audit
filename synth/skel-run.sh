#!/bin/bash
# skel-run.sh ROOT HOST [CONTEXT...] : run context directories under ROOT (written
# by skel.lisp; default all) through the route matrix on HOST.  The base context
# gets all eight routes, the others the session and book routes.  One summary
# line each in ROOT/summary-HOST.txt.
ROOT=$1; H=$2; shift 2
M=/Users/ember/dev/compiler-audit/routes/run-matrix.sh
if [ $# -gt 0 ]; then LIST="$*"; else LIST=$(cd "$ROOT" && ls -d */ | tr -d /); fi
for c in $LIST; do
  d="$ROOT/$c"; W="$ROOT/$c/$H"; mkdir -p "$W"
  cp "$d"/*.lisp "$d"/prog.sexp "$d"/manifest.txt "$W"/ 2>/dev/null
  if [ "$c" = base ]; then PREGEN=1 "$M" 0 0 "$H" "$W" > "$W.txt" 2>&1; else PREGEN=1 FAST=1 "$M" 0 0 "$H" "$W" > "$W.txt" 2>&1; fi
  rc=$?
  echo "$c $H exit=$rc $(grep -E '^(session|book) ' "$W.txt" | awk '{printf "%s:%s ok=%s diff=%s ctl=%s unv=%s same=%s  ", $1,$2,$3,$4,$5,$7,$8}')" >> "$ROOT/summary-$H.txt"
  ls "$W"/zimg* >> "$ROOT/summary-$H.txt" 2>/dev/null
done
echo DONE >> "$ROOT/summary-$H.txt"
