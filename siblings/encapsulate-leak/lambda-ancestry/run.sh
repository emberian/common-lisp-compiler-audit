#!/bin/bash
# The apply$/quoted-lambda ancestry gap: the export-surface checks' ancestry
# walks stop at (fquotep ...) and do not descend into quoted lambdas, but a
# constraint-free signature fn can never be put inside one.
#   run.sh /path/to/saved_acl2
# probe1: apply$ of a lambda calling signature g -> rejected (g has no badge).
# probe4: g in a lambda :guard -> rejected; defchoose (g x) not provable;
#         defun-sk folds the dependence into g2's constraint.
set -u
acl2=${1:?path to saved_acl2}
here=$(cd "$(dirname "$0")" && pwd)
echo "=== probe1 (badge requirement blocks signature fn in apply\$ lambda) ==="
nice -n 15 timeout 300 "$acl2" < "$here/probe1.lsp" 2>&1 \
  | grep -iE "PROBEA-ERP|no badge|fully badged"
echo "=== probe4 (lambda guard, defchoose, defun-sk) ==="
nice -n 15 timeout 300 "$acl2" < "$here/probe4.lsp" 2>&1 \
  | grep -iE "PROBEE-ERP|DEFCHOOSE-G-CONSTRAINT|G-X-PROVABLE|DEFUN-SK-G2"
