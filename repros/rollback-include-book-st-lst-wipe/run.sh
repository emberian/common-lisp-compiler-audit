#!/usr/bin/env bash
# Reproducer for WRB-S4:
#   Compiled raw defstobj emits unconditional (defg ,(st-lst name) nil)
#   (basis-a.lisp:9567), wiping memoize-flush tracking on ST across rolled-back
#   (encapsulate () (local (include-book ...))) or failed include-book, and
#   proving (defthm nil-proved nil) with :ttags nil on SBCL 2.6.10 and CCL 1.14.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f st_lst_helper_book.cert st_lst_helper_book.port st_lst_helper_book.fasl st_lst_helper_book.da64fsl st_lst_helper_book.lx64fsl \
        repro.cert repro.port repro.fasl repro.da64fsl repro.lx64fsl ./*.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  host="${pair%%:*}"
  bin="${pair#*:}"
  cleanup
  printf '(certify-book "st_lst_helper_book" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > "helper_${host}.out" 2>&1
  test -f st_lst_helper_book.cert

  echo "=== [$host] Session run ==="
  $TIMEOUT "$bin" < repro.lisp > "session_${host}.out" 2>&1
  grep -a -E '@WRB-S4|^Q\.E\.D\.$' "session_${host}.out" | tail -n 5
  grep -q 'def=T thm='\''NIL ttag=NIL seen=NIL skip=NIL redef=NIL' "session_${host}.out"

  echo "=== [$host] certify-book (:ttags nil) ==="
  printf '(certify-book "repro" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > "cert_${host}.out" 2>&1
  test -f repro.cert
  echo "repro.cert certified with :ttags nil on $host: YES"
  cleanup
done
