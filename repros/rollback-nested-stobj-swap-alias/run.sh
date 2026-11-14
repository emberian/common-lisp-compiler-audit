#!/usr/bin/env bash
# Reproducer for WRB-S1:
#   Shallow *user-stobj-alist* undo snapshot + trans-eval functional spine copy
#   + nested swap-stobjs aliases parent.k1 and parent.k2 (EQ), violating Stobj
#   Evaluation Invariant (C1) and proving (defthm nil-proved nil) with :ttags nil
#   on BOTH SBCL 2.6.10 and CCL 1.14 (both session and certify-book).
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f repro.cert repro.port repro.fasl repro.da64fsl repro.lx64fsl ./*.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  host="${pair%%:*}"
  bin="${pair#*:}"
  echo "=== [$host] Session run ==="
  $TIMEOUT "$bin" < repro.lisp > "session_${host}.out" 2>&1
  grep -a -E '@WRB-S1|^Q\.E\.D\.$' "session_${host}.out" | tail -n 5
  grep -q 'def=T thm='\''NIL ttag=NIL seen=NIL skip=NIL redef=NIL' "session_${host}.out"

  cleanup
  echo "=== [$host] certify-book (:ttags nil) ==="
  printf '(certify-book "repro" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > "cert_${host}.out" 2>&1
  test -f repro.cert
  echo "repro.cert certified with :ttags nil on $host: YES"
  cleanup
done
