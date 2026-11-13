#!/bin/bash
# Runs every divergence in this directory on both ACL2 hosts, one fresh
# session per run, and prints the lines that differ.  At most one Lisp runs at
# a time; each run is capped at 300 s by ../../scouts/lisp-run.sh.
#   ./run.sh        the three findings
#   ./run.sh all    the findings plus every file in cases/
here="$(cd "$(dirname "$0")" && pwd)"
R="$here/../../scouts/lisp-run.sh"
show() { # show DIR FILE
  ( cd "$here/$1" || exit 2
    for h in acl2-sbcl acl2-ccl; do
      "$R" $h "$2" > /dev/null
      echo "--- $1/$2 on $h"
      grep -a -E "RESULT|HARD ACL2 ERROR|ACL2 Error|ABORTING|^ CONTRADICTION$|^Error:" "$2.$h.out" \
        | grep -a -v "Error \[Failure\]" | sed 's/^ACL2 [!>p]*>//' | cut -c1-110
    done )
}
echo "##### 1. robustness, CCL only: SATISFIES predicate called on NIL while the type is parsed (F4)"
"$here/run-case.sh" c01-stub-scalar.lisp
echo
echo "##### 2. soundness, CCL only: stale type cache, NIL proved (line ' CONTRADICTION' = theorem NIL admitted)"
show stale-type-cache nil-via-local.lisp
( cd "$here/stale-type-cache" || exit 2
  for h in acl2-sbcl acl2-ccl; do
    rm -f nil-book.cert nil-book.port nil-book.*fsl nil-book.fasl nil-book@expansion.lsp
    "$R" $h certify-nil-book.lisp > /dev/null
    if [ -f nil-book.cert ]; then echo "--- certify-book nil-book on $h: CERTIFIED (book contains theorem NIL)"
    else echo "--- certify-book nil-book on $h: not certified"; fi
  done )
echo
echo "##### 3. soundness, both hosts: single-field stobj that is a string, NIL proved"
show string-stobj string-stobj.lisp
if [ "${1:-}" = all ]; then
  echo; echo "##### cases/"
  for c in "$here"/cases/c*.lisp; do "$here/run-case.sh" "$(basename "$c")"; done
fi
