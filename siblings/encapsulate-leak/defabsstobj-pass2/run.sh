#!/bin/bash
# ISSUE B18 (fixed before ACL2 8.8): a signature fn as the :EXEC of a defabsstobj
# export with LOCAL supporting theorems.  This TREE is post-fix.
#   run.sh /path/to/saved_acl2
# Expect: pass-2 REJECTION ("must be admitted ... defabsstobj"), erp T, and
# stp/fld/h NOT installed.
set -u
acl2=${1:?path to saved_acl2}
here=$(cd "$(dirname "$0")" && pwd)
nice -n 15 timeout 300 "$acl2" < "$here/test.lsp" 2>&1 \
  | grep -iE "B18A-ENCAPSULATE-ERP|must be admitted|STP-IS-FUNCTION|FLD-IS-FUNCTION|H-IS-FUNCTION"
