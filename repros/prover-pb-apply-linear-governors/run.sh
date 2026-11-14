#!/usr/bin/env bash
# Standalone reproducer for prover-pb-apply-linear-governors:
# Proof-builder `:apply-linear` (`:al`, proof-builder-b.lisp:3226-3332) relieves
# `:linear` rule hypotheses using branch-local `(governors conc current-addr)`
# when dived into a subterm, then appends the instantiated conclusion directly
# to top-level goal `:hyps`.
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

echo "=== Running prover-pb-apply-linear-governors on SBCL ==="
$TIMEOUT "$SBCL_ACL2" < repro.lisp > sbcl.out 2>&1
if grep -q "FAILED" sbcl.out; then echo "ERROR: FAILED event in sbcl.out"; exit 1; fi
grep -E "^ (FALSE-THM|NIL-PROVED)$|@SOUNDNESS" sbcl.out
grep -q "@SOUNDNESS nil='NIL ttag=NIL seen=NIL skip=NIL redef=NIL" sbcl.out

echo "=== Running prover-pb-apply-linear-governors on CCL ==="
$TIMEOUT "$CCL_ACL2" < repro.lisp > ccl.out 2>&1
if grep -q "FAILED" ccl.out; then echo "ERROR: FAILED event in ccl.out"; exit 1; fi
grep -E "^ (FALSE-THM|NIL-PROVED)$|@SOUNDNESS" ccl.out
grep -q "@SOUNDNESS nil='NIL ttag=NIL seen=NIL skip=NIL redef=NIL" ccl.out

echo "PASS: NIL-PROVED verified on both SBCL and CCL with pure kernel state."
