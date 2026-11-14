#!/usr/bin/env bash
# Reproducer for WRB-R3:
#   redef! + :u on stobj KID deletes KID from *current-stobj-gensym-ht* instead
#   of restoring its prior gensym, wiping live stobj-table entries ((KID) 99 1 -> NIL 0 0).
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
  echo "=== [$host] Running redef! + :u stobj-table gensym wipe repro ==="
  $TIMEOUT "$bin" < repro.lisp > "out_${host}.out" 2>&1
  grep -a -E '@WRB-R3-' "out_${host}.out"
  grep -q '@WRB-R3-BEFORE .*((NIL) (KID) 99 1)' "out_${host}.out"
  grep -q '@WRB-R3-AFTER  .*((NIL) NIL 0 0)' "out_${host}.out"
done
