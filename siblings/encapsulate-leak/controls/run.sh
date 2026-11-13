#!/bin/bash
# NEGATIVE controls for the guard channel.  run.sh /path/to/saved_acl2
# Expect all three encapsulates REJECTED (erp T): split-types nil (B),
# (the (satisfies g) ...) in body (E), and a redundant local+exported defun (D).
set -u
acl2=${1:?path to saved_acl2}
here=$(cd "$(dirname "$0")" && pwd)
nice -n 15 timeout 300 "$acl2" < "$here/test.lsp" 2>&1 \
  | grep -iE "PROBE-[BED].*ERP|FD-CLASS|guard verification may"
