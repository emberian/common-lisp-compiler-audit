#!/usr/bin/env bash
# Standalone reproducer for kernel-fi-program-mode-crash:
# `translate-functional-substitution` (`history-management.lisp:11307-11314`)
# checks `(function-symbolp fn2 wrld)` and `chk-equal-arities` when `fn2` is a
# symbol, but omits `(logicp fn2 wrld)` (unlike the lambda branch right below it).
# Passing a `:program`-mode function symbol injects `:program` calls into prover
# goal clauses and crashes with `HARD ACL2 ERROR in EXPAND-ABBREVIATIONS`.
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

echo "=== Running kernel-fi-program-mode-crash on SBCL ==="
$TIMEOUT "$SBCL_ACL2" < repro.lisp > sbcl.out 2>&1
grep -q "HARD ACL2 ERROR in EXPAND-ABBREVIATIONS" sbcl.out
grep -q "encountered" sbcl.out
grep -A 1 "HARD ACL2 ERROR in EXPAND-ABBREVIATIONS" sbcl.out

echo "=== Running kernel-fi-program-mode-crash on CCL ==="
$TIMEOUT "$CCL_ACL2" < repro.lisp > ccl.out 2>&1
grep -q "HARD ACL2 ERROR in EXPAND-ABBREVIATIONS" ccl.out
grep -q "encountered" ccl.out
grep -A 1 "HARD ACL2 ERROR in EXPAND-ABBREVIATIONS" ccl.out

echo "PASS: :functional-instance :program-mode HARD ACL2 ERROR verified on SBCL and CCL."
