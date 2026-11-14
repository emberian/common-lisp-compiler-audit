#!/usr/bin/env bash
# Reproducer for WRB-S3:
#   Failed include-book leaves poisoned redundant-raw-lisp-discriminator (:creator)
#   on *the-live-kid*, proving (defthm nil-proved nil) with ZERO memoize, ZERO
#   :clause-processor, ZERO apply$, ZERO defattach, and :ttags nil on SBCL & CCL.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f bad_kid_book.cert bad_kid_book.port bad_kid_book.fasl bad_kid_book.da64fsl bad_kid_book.lx64fsl ./*.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  host="${pair%%:*}"
  bin="${pair#*:}"
  cleanup
  echo "=== [$host] Certifying helper bad_kid_book (:ttags nil) and running repro ==="
  printf '(certify-book "bad_kid_book" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > "cert_${host}.out" 2>&1
  test -f bad_kid_book.cert
  $TIMEOUT "$bin" < repro.lisp > "repro_${host}.out" 2>&1
  grep -a -E '@WRB-S3|^Q\.E\.D\.$' "repro_${host}.out" | tail -n 5
  grep -q 'def=T thm='\''NIL ttag=NIL seen=NIL skip=NIL redef=NIL' "repro_${host}.out"
  cleanup
done
