#!/usr/bin/env bash
# Standalone reproducer for prover-bad-ancestor-constrained-liar:
# `bad-ancestor1` (`apply.lisp:1242, 1262`) ignores constrained functions
# (`(body fn nil wrld)` is `NIL`), admitting `apply$-warrant-liar` +
# `(defattach apply$-warrant-liar true-apply$-warrant)` even though
# `(not (apply$-warrant-liar))` is a proved theorem — falsifying Attachment
# Consistency (`other-events.lisp:30435`) and vacuously verifying `:guard nil`.
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

echo "=== Running prover-bad-ancestor-constrained-liar on SBCL ==="
$TIMEOUT "$SBCL_ACL2" < repro.lisp > sbcl.out 2>&1
if grep -q "FAILED" sbcl.out; then echo "ERROR: FAILED event in sbcl.out"; exit 1; fi
grep -E "^ (NOT-WARRANT-LIAR|VACUOUS-GUARD-VERIFIED)$|@LIAR" sbcl.out
grep -q "@LIAR eval=T thm=T ttag=NIL skip=NIL redef=NIL" sbcl.out

echo "=== Running prover-bad-ancestor-constrained-liar on CCL ==="
$TIMEOUT "$CCL_ACL2" < repro.lisp > ccl.out 2>&1
if grep -q "FAILED" ccl.out; then echo "ERROR: FAILED event in ccl.out"; exit 1; fi
grep -E "^ (NOT-WARRANT-LIAR|VACUOUS-GUARD-VERIFIED)$|@LIAR" ccl.out
grep -q "@LIAR eval=T thm=T ttag=NIL skip=NIL redef=NIL" ccl.out

echo "PASS: Attachment-Consistency falsification & vacuous :guard nil verified on SBCL and CCL."
