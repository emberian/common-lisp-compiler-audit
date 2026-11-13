#!/bin/bash
# NEGATIVE probes for the remaining task-listed channels.
#   run.sh /path/to/saved_acl2
# test.lsp:  defattach to a same-encapsulate signature fn is illegal (C);
#            auto type-prescription foiled by the guard check (T).
# test2.lsp: type-prescription is RECOMPUTED in pass 2, local rule does not
#            leak (T2); bogus-exported-measures DOES reject a measure that
#            mentions a signature fn (M, positive control).
set -u
acl2=${1:?path to saved_acl2}
here=$(cd "$(dirname "$0")" && pwd)
echo "=== test.lsp (C: defattach, T: type-prescription via guard) ==="
nice -n 15 timeout 300 "$acl2" < "$here/test.lsp" 2>&1 \
  | grep -iE "PROBE-[CT]|illegal to attach|ATTACHMENT|EVAL-G-ERP|FT-TPS|NATP-FT|guard verification may"
echo "=== test2.lsp (T2: type-prescription recompute, M: measure positive control) ==="
nice -n 15 timeout 300 "$acl2" < "$here/test2.lsp" 2>&1 \
  | grep -iE "PROBE-(T2|M)|FT-TPS|NATP-FT|ENCAPSULATE-ERP|termination-theorem may"
