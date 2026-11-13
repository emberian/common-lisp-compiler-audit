#!/bin/bash
# Usage: run.sh /path/to/saved_acl2
#
# ME1 (soundness, TRUST-TAG gated): a make-event's :EXPANSION? is TRUSTED at
# include time and never re-run (other-events.lisp make-event-fn ~34765).  That
# is sound only because certify-book records the REAL expansion in the
# certificate's expansion-alist whenever it differs from :EXPANSION? -- and that
# recording is suppressed whenever state global BOOT-STRAP-FLG is non-nil
# (make-event-fn ~34937).  BOOT-STRAP-FLG is NOT in *initial-untouchable-vars*,
# so a book that holds a trust tag can set it persistently with progn!.  The
# make-event's FORM then expands to a benign, provable event (cert succeeds),
# nothing is recorded, and at include the malicious :EXPANSION? -- an UNPROVED
# (defthm nil-proved nil) -- is installed.  No skip-proofs is recorded.
#
# Control: the same book without the boot-strap-flg mutation (control.lisp,
# with the ttag; control-nottag.lisp, without it) records the real expansion,
# which overrides :EXPANSION? at include, so nil-proved is never defined.
ACL2=${1:?path to saved_acl2}; cd "$(dirname "$0")" || exit 2
rm -f *.cert *.port *.lx64fsl *.fasl *.o 2>/dev/null
tag=$(basename "$(dirname "$ACL2")")   # head-worktree | ccl-worktree
echo "### host image: $tag"
for b in book control; do
  printf "(certify-book \"$b\" 0 nil :ttags :all)\n(quit)\n" | "$ACL2" > cert.$b.$tag.out 2>&1
  echo "$b certified: $([ -f $b.cert ] && echo yes || echo no)"
done
printf '(certify-book "control-nottag" 0 nil)\n(quit)\n' | "$ACL2" > cert.control-nottag.$tag.out 2>&1
echo "control-nottag certified: $([ -f control-nottag.cert ] && echo yes || echo no)"
echo "book.cert records a real expansion (VALUE-TRIPLE/NIL-PROVED)?  $(LC_ALL=C grep -ac 'VALUE-TRIPLE\|NIL-PROVED' book.cert) (0 = suppressed)"
echo "control.cert records a real expansion?                        $(LC_ALL=C grep -ac 'VALUE-TRIPLE\|NIL-PROVED' control.cert)"
echo "--- ANCHOR include (book): expect nil-proved installed = 'NIL ---"
"$ACL2" < check.lsp > inc.book.$tag.out 2>&1
grep -ao '@TAG.*' inc.book.$tag.out
grep -aoiE "TTAG NOTE[^\"]*|ACL2 Warning \[[^]]*\]" inc.book.$tag.out | sort -u
echo "--- CONTROL include (ttag, no bsf): expect nil-proved :UNDEFINED ---"
printf '(include-book "control")\n(cw "@TAG controlA-nil-proved ~x0~%%" (getpropc (quote nil-proved) (quote theorem) :UNDEFINED (w state)))\n(quit)\n' | "$ACL2" > inc.control.$tag.out 2>&1
grep -ao '@TAG.*' inc.control.$tag.out
echo "--- CONTROL include (no ttag): expect nil-proved :UNDEFINED ---"
printf '(include-book "control-nottag")\n(cw "@TAG controlB-nil-proved ~x0~%%" (getpropc (quote nil-proved) (quote theorem) :UNDEFINED (w state)))\n(quit)\n' | "$ACL2" > inc.control-nottag.$tag.out 2>&1
grep -ao '@TAG.*' inc.control-nottag.$tag.out
rm -f *.lx64fsl *.fasl *.o 2>/dev/null
