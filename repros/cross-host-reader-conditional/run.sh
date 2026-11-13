#!/bin/bash
# Usage: run.sh /path/to/certifying_saved_acl2 /path/to/including_saved_acl2   (different host Lisps)
#
# rc.lisp uses the reader conditionals #+sbcl / #+ccl.  It is certified by one
# host; the other host includes it using that certificate (certificates carry no
# record of the host or of *features*, and the book-hash of the source matches).
# The including host defines rc from the text it reads, but takes the logical
# body and the theorem from the certificate, so evaluation and logic disagree.
CERT=${1:?certifying image}; INC=${2:?including image}; cd "$(dirname "$0")" || exit 2
rm -f rc.cert rc.port rc.*fsl rc.fasl ./*.out
printf '(certify-book "rc")\n(quit)\n' | "$CERT" > certify.out 2>&1
cat > include.lsp <<'EOT'
(include-book "rc")
(cw "@R host ~x0: (rc) evaluates to ~x1; logical body ~x2; theorem ~x3~%" (@ host-lisp) (rc) (getpropc 'rc 'unnormalized-body nil (w state)) (getpropc 'rc-value 'theorem nil (w state)))
(defthm contradiction nil :rule-classes nil :hints (("Goal" :use rc-value)))
(cw "@R NIL proved: ~x0~%" (if (equal (getpropc 'contradiction 'theorem t (w state)) ''nil) :YES :no))
EOT
"$INC" < include.lsp > include.out 2>&1
echo "certified: $([ -f rc.cert ] && echo yes || echo no)"
echo "warnings: $(grep -a -o 'ACL2 Warning \[[^]]*\]' include.out | sort -u | tr '\n' ' ')"
grep -a -o '@R .*' include.out
