#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
# Certifies loop-ignore-ok.lisp, then evaluates (f 1) in two fresh sessions:
# one that loads the source with LD, one that includes the certified book.
ACL2=$1; cd "$(dirname "$0")" || exit 2
rm -f loop-ignore-ok.cert loop-ignore-ok.port loop-ignore-ok.*fsl loop-ignore-ok.fasl
printf '(certify-book "loop-ignore-ok")\n(quit)\n' | "$ACL2" > certify.out 2>&1
printf '(ld "loop-ignore-ok.lisp")\n(f 1)\n(quit)\n' | "$ACL2" > session.out 2>&1
printf '(include-book "loop-ignore-ok")\n(f 1)\n(quit)\n' | "$ACL2" > book.out 2>&1
echo "certified: $([ -f loop-ignore-ok.cert ] && echo yes || echo no)"
for r in session book; do
  echo "$r: implementation errors=$(grep -c 'Implementation error' $r.out)  value printed=$(grep -c '^ACL2 !>6$' $r.out)"
done
