#!/bin/bash
# Usage: run.sh [head|ccl] (default both).  Expected: @LOGIC 1 and @RAW 1.
cd "$(dirname "$0")"
for h in ${1:-head ccl}; do
  nice -n 15 timeout 300 /Users/ember/dev/acl2-fix/$h-worktree/saved_acl2 < session.lisp > session.$h.out 2>&1
  echo "== $h"; grep -o '@[A-Z]* .*\|@END\|Fault during read.*\|ABORTING from raw Lisp\|ACL2 Error.*' session.$h.out
done
