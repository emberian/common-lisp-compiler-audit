#!/bin/sh
# drive.sh IMPL START END OUT CRASHLOG
# Runs a fuzz worker over [START,END); on crash/hang (worker exits nonzero or stops
# early) records the offending seed in CRASHLOG and resumes just past it.
IMPL=$1; START=$2; END=$3; OUT=$4; CRASH=$5
CCL=/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64
SBCL=/home/hbox/sbcl-2.6.8-x86-64-linux/run-sbcl.sh
FUZZ=/home/hbox/ca-x86-ccl/fuzz.lisp
: > "$OUT"
cur=$START
while [ "$cur" -lt "$END" ]; do
  if [ "$IMPL" = ccl ]; then
    START=$cur END=$END timeout -k 5 1800 "$CCL" --batch --no-init --load "$FUZZ" >> "$OUT" 2>/dev/null
  else
    START=$cur END=$END timeout -k 5 1800 "$SBCL" --noinform --non-interactive --load "$FUZZ" >> "$OUT" 2>/dev/null
  fi
  rc=$?
  last=$(awk -F'\t' '/^[0-9]+\t/{s=$1} END{print s}' "$OUT")
  if [ "$rc" = 0 ] && [ -n "$last" ] && [ "$last" -ge "$((END-1))" ]; then
    break
  fi
  if [ -z "$last" ] || [ "$last" -lt "$cur" ]; then
    crashseed=$cur
  else
    crashseed=$((last+1))
  fi
  echo "$IMPL seed=$crashseed rc=$rc (resuming at $((crashseed+1)))" >> "$CRASH"
  cur=$((crashseed+1))
done
