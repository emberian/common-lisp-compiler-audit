#!/bin/sh
out=$1; : > "$out"
run() { # name, form, readform
  printf '%s\n' "($2)" '(cw "@wrote~%")' "(cw \"@read ~x0~%\" $3)" '(value :q)' '(ccl:quit 0)' > acl2-case.lisp
  nice -n 15 timeout 20 ./zimg < acl2-case.lisp > acl2-case.out 2>&1; rc=$?
  case $rc in 0) res=returned;; 124) res=HANG;; *) res="rc=$rc";; esac
  pred=$(grep -i "@field a$1 " acl2-probe2.out | awk '{for(i=1;i<=NF;i++){if($i ~ /^page=/)p=substr($i,6); if($i ~ /^upd-code-page=/)c=substr($i,15)}; print (p==c)?"same-page=YES":"same-page=no"}')
  printf '%s\n' "$1 | ${pred:-n/a} | $res | $(grep -o '@read .*' acl2-case.out | head -1) | cleanup-note=$(grep -c 'process of cleaning' acl2-case.out)" >> "$out"
}
for f in u8 bt u16 u32 u64 s8 s32 s64 int t rs il; do run $f "update-a${f}i 1 1 s$f" "(list (a${f}i 0 s$f) (a${f}i 1 s$f) (a${f}i 2 s$f) (a${f}i 3 s$f))"; done
run df "update-adfi 1 (to-df 1) sdf" "(list (from-df (adfi 1 sdf)))"
run ch "update-achi 1 #\\Z sch" "(list (achi 0 sch) (achi 1 sch))"
run u8-scalar "update-cu8 6 su8" "(cu8 su8)"
run u8-read "cw \"~x0~%\" (au8i 1 su8)" "(au8i 0 su8)"
