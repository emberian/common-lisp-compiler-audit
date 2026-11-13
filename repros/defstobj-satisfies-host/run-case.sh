#!/bin/bash
# run-case.sh CASE.lisp : run one case on both ACL2 hosts in fresh sessions and
# print each host's marker lines, then their diff.
cd "$(dirname "$0")/cases" || exit 2
c=${1:?case file name inside cases/}
R=../../../scouts/lisp-run.sh
for h in acl2-sbcl acl2-ccl; do
  $R $h "$c" > /dev/null
  grep -a -E "RESULT|CALLED|Error|HARD|FAILED|aborting|ABORTING|doesn't match|guard for|Time: +[1-9]" "$c.$h.out" \
    | grep -a -v "Error \[Failure\]" | sed "s/^ACL2 [!>p]*>//" | cut -c1-150 | uniq -c | sed "s/^ *1 //" > "$c.$h.sum"
done
echo "=== $c"
if cmp -s "$c.acl2-sbcl.sum" "$c.acl2-ccl.sum"; then echo "SAME ($(wc -l < "$c.acl2-sbcl.sum" | tr -d ' ') marker lines)"
else echo "DIFFERENT (< sbcl-hosted, > ccl-hosted)"; diff "$c.acl2-sbcl.sum" "$c.acl2-ccl.sum"; fi
