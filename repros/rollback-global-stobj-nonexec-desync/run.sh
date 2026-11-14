#!/usr/bin/env bash
# Reproducer for WRB-R2:
#   *user-stobj-alist* vs *non-executable-user-stobj-lst* undo desynchronization
#   triggers raw Common Lisp CL:ASSERT failure on SBCL 2.6.10 and CCL 1.14.
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
  echo "=== [$host] Running *non-executable-user-stobj-lst* undo desync repro ==="
  $TIMEOUT "$bin" < repro.lisp > "out_${host}.out" 2>&1 || true
  grep -a -E '@WRB-R2-CALLING-ADD-GLOBAL-STOBJ|RAW LISP ERROR|NON-EXECUTABLE-USER-STOBJ-LST' "out_${host}.out"
  grep -q 'NON-EXECUTABLE-USER-STOBJ-LST' "out_${host}.out"
done
