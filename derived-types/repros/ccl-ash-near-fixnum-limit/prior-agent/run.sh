#!/bin/sh
# run.sh [ccl|sbcl]   -- certify ash-nil.lisp in a fresh ACL2 session and report.
# Prints REPRODUCED if the book (whose last theorem is NIL) certifies.
HOST=${1:-ccl}
case "$HOST" in
  ccl)  IMG=${ACL2_CCL:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2} ;;
  sbcl) IMG=${ACL2_SBCL:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2} ;;
  *) echo "usage: run.sh [ccl|sbcl]"; exit 2 ;;
esac
cd "$(dirname "$0")" || exit 2
rm -f ash-nil.cert ash-nil.*fsl ash-nil.fasl ash-nil.port ash-nil.cert.out ash-nil.dx64fsl ash-nil.darm64fsl
# Two fresh sessions: the bogus object the first one creates can crash a later GC.
printf '%s\n' \
  '(defun il-ash (k) (declare (xargs :guard (natp k))) (integer-length (ash 1 k)))' \
  '(cw "EVAL (il-ash 1152921504606846975) = ~x0~%" (il-ash 1152921504606846975))' \
  | nice -n 15 timeout 300 "$IMG" > "run-$HOST-eval.log" 2>&1
printf '%s\n' '(certify-book "ash-nil")' \
  | nice -n 15 timeout 300 "$IMG" > "run-$HOST.log" 2>&1
grep -hE "EVAL|Error:|can.t represent|too large" "run-$HOST-eval.log" "run-$HOST.log" | head -5
if [ -f ash-nil.cert ]; then
  echo "REPRODUCED on $HOST: ash-nil.cert written; the book proves NIL"
  exit 0
else
  echo "not reproduced on $HOST (no certificate)"
  exit 1
fi
