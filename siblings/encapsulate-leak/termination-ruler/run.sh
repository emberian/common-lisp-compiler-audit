#!/bin/bash
# NEGATIVE control: the ruler-dependence termination channel is defended by
# subversive-recursion detection (not by bogus-exported-measures).
#   run.sh /path/to/saved_acl2
# Expect: F is "subversive", its termination theorem is local, NIL-PROVED FAILED.
set -u
acl2=${1:?path to saved_acl2}
here=$(cd "$(dirname "$0")" && pwd)
nice -n 15 timeout 300 "$acl2" < "$here/test.lsp" 2>&1 \
  | grep -iE "subversive|Infected|ill-formed lemma|NIL-PROVED|FAILED|PASSED"
