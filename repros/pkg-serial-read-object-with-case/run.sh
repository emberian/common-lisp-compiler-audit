#!/usr/bin/env bash
# Reproducer for Finding 3: read-object-with-case ignores :downcase and :invert modes.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f case_input.lsp ./*.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  lbl="${pair%%:*}"
  bin="${pair#*:}"
  echo "=== $lbl ==="
  $TIMEOUT "$bin" < repro.lisp > "case_${lbl}.out" 2>&1
  grep -a -A 6 '@READ-CASE' "case_${lbl}.out"
done
