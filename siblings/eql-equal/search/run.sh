#!/bin/sh
# run.sh [ccl|sbcl]  -- evaluate test.lsp in a fresh ACL2 session on the given host and
# print the two RESULT lines (or the error the host raised instead).
HOST=${1:-ccl}
case "$HOST" in
  ccl)  IMG=${ACL2_CCL:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2} ;;
  sbcl) IMG=${ACL2_SBCL:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2} ;;
  *) echo "usage: run.sh [ccl|sbcl]"; exit 2 ;;
esac
cd "$(dirname "$0")" || exit 2
nice -n 15 timeout 300 "$IMG" < test.lsp > "run-$HOST.log" 2>&1
grep -E "RESULT|HARD ACL2 ERROR|Error:|can.t represent|too large|Fatal" "run-$HOST.log" | cut -c1-200 | head -20
