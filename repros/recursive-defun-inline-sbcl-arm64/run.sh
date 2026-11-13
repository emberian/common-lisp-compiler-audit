#!/bin/bash
# Usage: run.sh [head|ccl] (default both).  Each file is admitted with LD in a
# fresh ACL2 session.
#   original.lisp        the generated program as the fuzz loop emitted it, up to
#                        the failing event (a list-fold function that an IR
#                        mutation turned into DEFUN-INLINE); every earlier event
#                        is admitted
#   reduced.lisp         tools/reduce.lisp output (1630 tests): one DEFUN-INLINE.
#                        The reducer also removed the termination test, so this
#                        file only shows the compile-time failure
#   recursion-kept.lisp  the reduced body with (if (endp l) acc (self (cdr l) ...)) restored
# Observed on SBCL-hosted ACL2 (arm64): the DEFUN-INLINE aborts from raw Lisp with
#   "The value -2621xx is not of type (SIGNED-BYTE 19)".
# CCL-hosted ACL2 admits all three.
cd "$(dirname "$0")"
for h in ${1:-head ccl}; do
  echo "== $h"
  for f in original reduced recursion-kept; do
    echo "(ld \"$f.lisp\")" | nice -n 15 timeout 600 /Users/ember/dev/acl2-fix/$h-worktree/saved_acl2 > $f.$h.out 2>&1
    echo "$f: aborts=$(grep -c 'ABORTING from raw Lisp' $f.$h.out) $(grep -A4 'ABORTING' $f.$h.out | grep -A3 'Error:' | tr '\n' ' ' | tr -s ' ')"
  done
done
