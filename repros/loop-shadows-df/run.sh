#!/bin/bash
# Usage: run.sh [head|ccl]  (default both).  Expected by scoping: @Y 2, @RAT 2, @LET 3, @X 2.
cd "$(dirname "$0")"
for h in ${1:-head ccl}; do
  nice -n 15 timeout 300 /Users/ember/dev/acl2-fix/$h-worktree/saved_acl2 < session.lisp > session.$h.out 2>&1
  echo "== $h"; grep -o '@[A-Z]* .*\|@END\|ACL2 Error.*' session.$h.out; grep -A5 'ACL2 Error \[Translate\] in ( DEFUN ZDF-LOOP-X' session.$h.out | head -6
done
