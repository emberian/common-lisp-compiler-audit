#!/bin/bash
# Usage: run.sh [head|ccl]   (default: both).  Fresh ACL2 session per host.
# Expected (logic): @RAT 2, @LET 2, @TAIL 2, and the THM proved.
# Observed on SBCL-hosted ACL2: @TAIL is replaced by a raw Lisp error
#   "Values [2 1/2] from (FLOOR (FROM-DF X) 1) ... is not of the declared
#    return type of the function (VALUES T &OPTIONAL)".
cd "$(dirname "$0")"
for h in ${1:-head ccl}; do
  nice -n 15 timeout 300 /Users/ember/dev/acl2-fix/$h-worktree/saved_acl2 < session.lisp > session.$h.out 2>&1
  echo "== $h"; grep -o '@[A-Z]* .*\|@END\|Q\.E\.D\.\|ABORTING from raw Lisp\|is not of the declared return type.*\|Values$\|\[2 1/2\]' session.$h.out
done
