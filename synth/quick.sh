#!/bin/bash
# quick.sh DIR [HOST]: session route only for an already generated program.
# Prints unverified count, query totals, control, and the first error lines.
D=$1; HOST=${2:-head}
ACL2=/Users/ember/dev/acl2-fix/$HOST-worktree/saved_acl2
cd "$D" || exit 2
{ echo "(set-inhibit-output-lst (remove1 'comment (remove1 'error *valid-output-names*)))"
  [ -f portcullis.lisp ] && echo '(ld "portcullis.lisp")'
  echo '(ld "book.lisp")'
  echo '(ld "queries.lisp" :ld-error-action :continue)'; } > q1.lisp
nice -n 15 timeout ${QT:-600} "$ACL2" < q1.lisp > q1.$HOST.out 2>&1
rc=$?
grep -o '@[A-Z]* .*\|@END' q1.$HOST.out > q.$HOST.rec
R=q.$HOST.rec
echo "exit=$rc G=$(grep '^@G' $R | cut -d' ' -f2) Q=$(grep -c '^@Q' $R)/$(grep -c '"@Q ' queries.lisp) ok=$(grep -c '^@Q.*:OK$' $R) diff=$(grep -c '^@Q.*:DIFF$' $R) ctl=$(grep '^@C' $R | cut -d' ' -f2) end=$(grep -c '^@END' $R)"
grep -n -A${ERRL:-6} 'ACL2 Error\|HARD ACL2 ERROR\|Implementation error\|debugger invoked\|Error:' q1.$HOST.out | head -${ERRN:-14} | cut -c1-260
