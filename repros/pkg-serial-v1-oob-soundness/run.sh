#!/usr/bin/env bash
# Reproducer for Finding 1:
#   1) Single-host pure :logic-mode OOB (svref arr -1) in serialize-read on CCL arm64
#      producing #<BOGUS object @ #xBE> outside ACL2's universe and crashing guard-verified
#      (lexorder x x) with :ttags nil.
#   2) Full (defthm nil-proved nil :rule-classes nil) soundness escalation (SBCL certify ->
#      CCL include) via #Y<13-byte-v1-zero> with ZERO #+/#- reader conditionals and :ttags nil,
#      exploiting (svref arr -1) + chk-bad-lisp-object skip in include-book (axioms.lisp:23384).
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f v1-zero.sao v1_book.lisp v1_book.cert v1_book.port v1_book.fasl v1_book.*fsl \
        include_ccl.lisp ./*.out
}
trap cleanup EXIT
cleanup

echo "=== [Part 1] Single-host pure :logic serialize-read OOB (zero books, :ttags nil) ==="
$TIMEOUT "$SBCL_ACL2" < repro.lisp > single_sbcl.out 2>&1 || true
$TIMEOUT "$CCL_ACL2"  < repro.lisp > single_ccl.out  2>&1 || true

grep -a -E '@V1-|RAW LISP ERROR|Error: .* is not of the expected type SYMBOL' single_sbcl.out || true
grep -a -E '@V1-|RAW LISP ERROR|Error: .* is not of the expected type SYMBOL' single_ccl.out  || true

echo ""
echo "=== [Part 2] Full (defthm nil-proved nil) escalation (zero #+/#-, :ttags nil) ==="
python3 - <<'PY'
v1_zero = bytes([0xAC, 0x12, 0x0B, 0xC7, 0, 0, 0, 0, 0, 0, 0, 0, 0xAC, 0x12, 0x0B, 0xC7])
book = (
    b'(in-package "ACL2")\n'
    b'(defun v1z () \'#Y' + v1_zero + b')\n'
    b'(defthm v1z-is-0 (equal (v1z) 0) :rule-classes nil)\n'
)
with open("v1_book.lisp", "wb") as f:
    f.write(book)
PY

printf '(certify-book "v1_book" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$SBCL_ACL2" > cert_sbcl.out 2>&1

cat > include_ccl.lisp <<'EOF'
(in-package "ACL2")
(include-book "v1_book" :ttags nil)
(defthm v1z-not-0 (not (equal (v1z) 0)) :rule-classes nil)
(defthm nil-proved nil
  :rule-classes nil
  :hints (("Goal" :use (v1z-is-0 v1z-not-0))))
(cw "@V1-SOUNDNESS host=~x0 nil-thm=~x1 ttags=~x2~%"
    (@ host-lisp)
    (getpropc 'nil-proved 'theorem t (w state))
    (global-val 'ttags-seen (w state)))
(quit)
EOF

$TIMEOUT "$CCL_ACL2" < include_ccl.lisp > inc_ccl.out 2>&1

echo "v1_book.cert created on SBCL (:ttags nil): $([ -f v1_book.cert ] && echo YES || echo NO)"
grep -a -E '@V1-SOUNDNESS|^Q\.E\.D\.$' inc_ccl.out
