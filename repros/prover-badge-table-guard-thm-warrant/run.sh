#!/usr/bin/env bash
# Standalone reproducer for prover-badge-table-guard-thm-warrant:
# `badge-table-guard1` (`apply.lisp:1966-1972`) allows resetting
# `:badge-userfn-structure` to `NIL` post-bootstrap (`:ttag nil`), abandoning
# warrants so `(:guard-theorem fn)` drops `(apply$-warrant-g)` and proves `NIL`.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f sbcl.out ccl.out
}
trap cleanup EXIT
cleanup

echo "=== Running prover-badge-table-guard-thm-warrant on SBCL ==="
$TIMEOUT "$SBCL_ACL2" < repro.lisp > sbcl.out 2>&1
if grep -q "FAILED" sbcl.out; then echo "ERROR: FAILED event in sbcl.out"; exit 1; fi
grep -E "^ (STEP1|NIL-PROVED)$|@SOUNDNESS" sbcl.out
grep -q "@SOUNDNESS nil='NIL ttag=NIL seen=NIL skip=NIL redef=NIL" sbcl.out

echo "=== Running prover-badge-table-guard-thm-warrant on CCL ==="
$TIMEOUT "$CCL_ACL2" < repro.lisp > ccl.out 2>&1
if grep -q "FAILED" ccl.out; then echo "ERROR: FAILED event in ccl.out"; exit 1; fi
grep -E "^ (STEP1|NIL-PROVED)$|@SOUNDNESS" ccl.out
grep -q "@SOUNDNESS nil='NIL ttag=NIL seen=NIL skip=NIL redef=NIL" ccl.out

echo "PASS: NIL-PROVED verified on both SBCL and CCL with pure kernel state."
