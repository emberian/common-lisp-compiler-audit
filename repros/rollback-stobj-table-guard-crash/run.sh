#!/usr/bin/env bash
# Reproducer for WRB-R1:
#   Guard-verified tbl-boundp / tbl-remove crashes in raw Common Lisp
#   (current-stobj-gensym CL:ERROR) after key stobj KID is rolled back.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f ./*.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  host="${pair%%:*}"
  bin="${pair#*:}"
  echo "=== [$host] Running guard-verified tbl-boundp across stobj rollback ==="
  $TIMEOUT "$bin" < repro.lisp > "out_${host}.out" 2>&1 || true
  grep -a -E '@WRB-R1-BEFORE-ROLLBACK|RAW LISP ERROR|Attempted to access a stobj-table entry for KID' "out_${host}.out"
  grep -q '@WRB-R1-BEFORE-ROLLBACK erp=NIL' "out_${host}.out"
  grep -q 'Attempted to access a stobj-table entry for KID' "out_${host}.out"
done
