#!/bin/bash
# Reproduce the split-types guard-theorem leak on one host.
#   run.sh /path/to/saved_acl2
# Prints the decisive lines: the leaked :GUARD-THEOREM (G X), g's empty
# constraint, and NIL-PROVED installed as 'NIL with no skip-proofs/ttag.
set -u
acl2=${1:?path to saved_acl2}
here=$(cd "$(dirname "$0")" && pwd)
nice -n 15 timeout 300 "$acl2" < "$here/test.lsp" 2>&1 \
  | grep -iE "GUARD-THEOREM|G-CONSTRAINT|NIL-PROVED|Q.E.D|SKIP-PROOFS-SEEN|TTAG|PASSED"
