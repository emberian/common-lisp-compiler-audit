#!/bin/sh
# usage: matrix.sh <outfile> <writers...>   (img must exist in cwd)
out=$1; shift
: > "$out"
for t in bit u8 u16 u32 u64 s8 s16 s32 s64 fix sf df ch bch gv; do
  for w in "$@"; do
    CASE=$w:$t nice -n 15 timeout 6 ${RUNIMG:-./img} --batch --no-init --load mtest.lisp > t.out 2>&1; rc=$?
    sp=$(grep -o 'same-page=[A-Za-z]*' t.out | head -1); area=$(grep -o 'area=[A-Z-]*' t.out | head -1)
    rb=$(grep -o 'readback=[A-Z]*' t.out | head -1); gc=$(grep -o '@after-gc [A-Z]*' t.out | head -1)
    case $rc in 0) res=returned;; 124) res=HANG;; *) res="rc=$rc";; esac
    echo "$w:$t | $area | ${sp:-same-page=n/a} | $res | ${rb:--} | ${gc:--}" >> "$out"
  done
done
