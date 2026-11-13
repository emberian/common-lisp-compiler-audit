#!/bin/bash
# neg-run.sh SEED COUNT HOST WORKDIR : known-outcome guard-obligation tests (see neg.lisp).
# Exit 0 iff every BAD twin stays :IDEAL, every BAD obligation is NIL at its
# witness, no BAD call returns under guard checking :ALL, and every GOOD
# obligation is T at every query input.
SEED=$1; N=$2; HOST=$3; W=$4
ACL2=/Users/ember/dev/acl2-fix/$HOST-worktree/saved_acl2
mkdir -p "$W" && cd "$W" || exit 2
timeout 600 /opt/homebrew/bin/sbcl --script /Users/ember/dev/compiler-audit/synth/neg.lisp "$SEED" "$N" "$W/" | tail -1
{ echo "(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment error)))"
  echo '(ld "neg.lisp" :ld-error-action :continue)'; } > n1.lisp
nice -n 15 timeout ${NT:-3000} "$ACL2" < n1.lisp > n1.$HOST.out 2>&1
grep -o '@[A-Z]* .*\|@NEND' n1.$HOST.out > neg.$HOST.rec
R=neg.$HOST.rec
n=$(grep -c '^@N ' $R)
nv_ideal=$(grep -c '^@NV [0-9]* :IDEAL' $R); nv_bug=$(grep '^@NV' $R | grep -vc ':IDEAL')
no_nil=$(grep -c '^@NO [0-9]* NIL$' $R); no_other=$(grep '^@NO' $R | grep -vc ' NIL$')
nx=$(grep -c '^@NX' $R)
po_t=$(grep -c '^@PO [0-9]* T$' $R); po_other=$(grep '^@PO' $R | grep -vc ' T$')
pv=$(grep -c '^@PV [0-9]* :COMMON-LISP-COMPLIANT' $R)
end=$(grep -c '^@NEND' $R)
echo "planted=$n  BAD: verify-guards failed $nv_ideal, VERIFIED $nv_bug; obligation NIL at witness $no_nil, other $no_other; returned under :all $nx"
echo "GOOD: obligation T $po_t, other $po_other; guards proved $pv/$n   end=$end"
[ "$end" = 1 ] && [ "$nv_ideal" = "$n" ] && [ "$nv_bug" = 0 ] && [ "$no_nil" = "$n" ] && [ "$no_other" = 0 ] && [ "$nx" = 0 ] && [ "$po_other" = 0 ] && [ "$po_t" -gt 0 ]
