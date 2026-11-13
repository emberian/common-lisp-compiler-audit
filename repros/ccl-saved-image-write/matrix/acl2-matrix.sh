#!/bin/sh
# usage: acl2-matrix.sh <outfile>   (zimg must exist in cwd)
: > "$1"
run() { # name, form, readform
  printf '(%s)\n(cw "@wrote ~%%")\n(cw "@read ~x0~%%" %s)\n(value :q)\n(ccl:quit 0)\n' "$2" "$3" > acl2-case.lisp
  nice -n 15 timeout 20 ./zimg < acl2-case.lisp > acl2-case.out 2>&1; rc=$?
  case $rc in 0) res=returned;; 124) res=HANG;; *) res="rc=$rc";; esac
  echo "$1 | $res | $(grep -o '@read .*' acl2-case.out | head -1) | $(grep -c 'An interrupt or error has occurred in the process of cleaning' acl2-case.out) cleanup-note" >> "$out"
}
out=$1
for f in zu8 zbit zu16 zu32 zu64 zs8 zs32 zs64 zint zrs zt; do run $f "update-${f}i 1 1 zst" "(list (${f}i 0 zst) (${f}i 1 zst) (${f}i 2 zst) (${f}i 3 zst))"; done
run zdf "update-zdfi 1 (to-df 1) zst" "(list (zdfi 1 zst))"
run zch "update-zchi 1 #\\Z zst" "(list (zchi 0 zst) (zchi 1 zst))"
run zsc "update-zsc 6 zst" "(zsc zst)"
run zany "update-zany '(a b) zst" "(zany zst)"
run zrs-resize "resize-zrs 8 zst" "(list (zrs-length zst) (zrsi 1 zst))"
run aset1 "assign xx (aset1 'nm *arr* 1 9)" "(list (aref1 'nm (@ xx) 1) (aref1 'nm (@ xx) 2))"
run compress1 "assign xx (compress1 'nm (aset1 'nm *arr* 1 9))" "(list (aref1 'nm (@ xx) 1) (aref1 'nm (@ xx) 2))"
run memo "assign xx (list (memo-f 17) (memo-f 18) (memo-f 18))" "(@ xx)"
run hons "assign xx (list (hons 1 (hons 2 nil)) (hons-equal *hons-pre* (hons 1 (hons 2 nil))) (hons-copy '(3 4)))" "(@ xx)"
