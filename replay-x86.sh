#!/bin/bash
# Replay the confirmed ACL2 findings on the prebuilt x86-64 ACL2 8.7 image
# (SBCL 2.2.9.debian) and print the decisive lines, so the disposition can be
# compared to the arm64 (SBCL 2.6.10 / CCL 1.14) results in ACL2-BUG-REPORT.md.
# Single SBCL host: cross-host (S2) and CCL-only robustness cases are N/A.
set -u
IMG=/home/hbox/acl2-8.7/saved_acl2
REPO=/home/hbox/ca-x86-sbcl/common-lisp-compiler-audit
sb() { nice -n 15 timeout 300 "$IMG" "$@"; }
sep() { echo; echo "================= $* ================="; }

sep "S1 stale-compiled-file (arm64: NIL proved, 0 warnings, both hosts)"
( cd "$REPO/repros/stale-compiled-file" && bash run.sh "$IMG" )

sep "S3 stale-type-cache f8-min (arm64: CCL proves NIL; SBCL REJECTS g-is-nil)"
( cd "$REPO/repros/defstobj-satisfies-host/stale-type-cache"
  printf '(in-package "ACL2")\n' > /tmp/s3.lsp; cat f8-min.lisp >> /tmp/s3.lsp; printf '\n(quit)\n' >> /tmp/s3.lsp
  sb < /tmp/s3.lsp > /tmp/s3.out 2>&1
  echo "g-is-nil admitted? $(grep -ac 'G-IS-NIL' /tmp/s3.out) ; contradiction/NIL admitted? (last form)"
  grep -aE 'ACL2 Error|rejected|not of type|G-IS-T|G-IS-NIL|CONTRADICTION|Form:' /tmp/s3.out | tail -20 )

sep "S4 string-stobj f9-min (arm64: NIL proved, both hosts)"
( cd "$REPO/repros/defstobj-satisfies-host/string-stobj"
  printf '(in-package "ACL2")\n' > /tmp/s4.lsp; cat f9-min.lisp >> /tmp/s4.lsp; printf '\n(quit)\n' >> /tmp/s4.lsp
  sb < /tmp/s4.lsp > /tmp/s4.out 2>&1
  echo "contradiction admitted (NIL proved)? last events:"; grep -aE 'Form:.*CONTRADICTION|ACL2 Error| CONTRADICTION$' /tmp/s4.out | tail -4 )

sep "S5 count eql-vs-equal (arm64: gv=0, nogv=1, both hosts)"
( cd "$REPO/derived-types/repros/count-eql-vs-equal" && ACL2_SBCL="$IMG" bash run.sh sbcl )

sep "S6 stale-df-ftype (arm64: SBCL CORRECT on both paths; CCL garbage 1.0E-323)"
( cd "$REPO/derived-types/repros/stale-df-ftype" && ACL2_SBCL="$IMG" bash run.sh sbcl )

sep "S7? uncertified-top-stale-compiled (arm64: NIL proved, Uncertified warning)"
( cd "$REPO/repros/uncertified-top-stale-compiled" && bash run.sh "$IMG" )

sep "R1 loop-ignore-ok (arm64: session (f 1)=6; after include-book Implementation error)"
( cd "$REPO/repros/loop-ignore-ok" && bash run.sh "$IMG" )

sep "R2 lambda-ignore-ok (arm64: ld (g 7)=7; certify-book Implementation error)"
( cd "$REPO/repros/lambda-ignore-ok" && bash run.sh "$IMG" )

sep "R3 portcullis-book-changed-raw-abort (arm64: ABORTING from raw Lisp, forms discarded)"
( cd "$REPO/repros/portcullis-book-changed-raw-abort" && bash run.sh "$IMG" )

sep "R4 defun-ground-call-assert (arm64: f rejected HARD ACL2 ERROR in ASSERT$; g admitted)"
( cd "$REPO/primitives/repros"
  sb < defun-ground-call-assert.lisp > /tmp/r4.out 2>&1
  echo "HARD ASSERT\$ errors: $(grep -ac 'HARD ACL2 ERROR in ASSERT' /tmp/r4.out)"
  grep -aE 'HARD ACL2 ERROR|ASSERT|admitted|G has been' /tmp/r4.out | head -6 )

sep "R5 ev-fncall-rec-logical binary-* (arm64: host TYPE-ERROR on (#\\a 0), 0 on (0 #\\a))"
( cd "$REPO/primitives/repros"
  sb < ev-fncall-rec-logical-binary-star.lisp > /tmp/r5.out 2>&1
  grep -aE '@R ' /tmp/r5.out | head -6 )

sep "R6 flush-compress-raw-error (arm64: thm proved; (flush-compress 0) raw error)"
( cd "$REPO/primitives/repros"
  sb < flush-compress-raw-error.lisp > /tmp/r6.out 2>&1
  grep -aE 'Proof succeeded|is not of type SYMBOL|Error|flush|NIL| A ' /tmp/r6.out | head -8
  echo "raw type errors on SYMBOL: $(grep -ac 'not of type\|SYMBOL' /tmp/r6.out)" )

sep "R7a df-tail-multiple-values (arm64 SBCL: @TAIL replaced by raw return-type error)"
( cd "$REPO/repros/df-tail-multiple-values"
  sb < session.lisp > /tmp/r7a.out 2>&1
  grep -aoE '@[A-Z]+ .*|not of the declared return type.*|ABORTING from raw Lisp|Q\.E\.D\.' /tmp/r7a.out | head -12 )

sep "R7b loop-shadows-df (arm64: scoping result @Y 2 @RAT 2 @LET 3 @X 2; or Translate error)"
( cd "$REPO/repros/loop-shadows-df"
  sb < session.lisp > /tmp/r7b.out 2>&1
  grep -aoE '@[A-Z]+ .*|ACL2 Error.*' /tmp/r7b.out | head -12 )

sep "H1 defstobj (satisfies p) (arm64: SBCL ADMITS; CCL rejects)"
( printf '(in-package "ACL2")\n(defstub p (x) nil)\n(defstobj st (fld :type (or null (satisfies p)) :initially nil))\n(cw "@R stobj admitted: ~x0~%%" (if (getpropc (quote st) (quote stobj) nil (w state)) :YES :NO))\n(quit)\n' > /tmp/h1.lsp
  sb < /tmp/h1.lsp > /tmp/h1.out 2>&1
  grep -aE '@R stobj admitted|ACL2 Error|cannot ev the call of non-executable' /tmp/h1.out | head -6 )

echo; echo "================= DONE ================="; df -h / | tail -1
