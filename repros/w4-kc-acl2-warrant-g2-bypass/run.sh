#!/usr/bin/env bash
# W4-KC-5: ACL2 8.7+ Kernel Soundness-Boundary & Latent Decision-Procedure Defects:
#   (5a) apply.lisp:2046-2059 & :1430-1457 (badge-table-guard1 / g2-justification):
#        Drops unproved (and refutable!) NATP-MEASURE-OF-FN proof obligation on the floor
#        when badge-table is updated directly, installing warrantp=T in :ttag nil ACL2
#        (both SBCL and CCL) for a recursive G2 function with transfinite measure >= omega^omega.
#   (5b) non-linear.lisp:143-144, :104-106, :432-433 (invert-var / varify! / inverse-vars-p):
#        Uses (eql exponent ''-1) on a cons literal (guard violation in :logic mode) and
#        calls (varify! base) stripping constant factors while inverse-vars-p unconditionally
#        returns T for EXPT, treating X as the multiplicative inverse of (EXPT (* 2 X) -1).
set -euo pipefail

ACL2_SBCL="${ACL2_SBCL:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-warrant-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== [1/2] Pure :ttag nil ACL2 8.7+ (SBCL 2.6.10): badge-table-guard1 G2 Warrant Bypass ==="
"$TIMEOUT_BIN" --kill-after=10s 60s "$ACL2_SBCL" <<'EOF' > "$TMP_DIR/warrant.out" 2>&1
;; Define a recursive G2 function (ancestrally calling apply$) justified with o<
;; and transfinite ordinal measure omega^omega + |x|, whose NATP-MEASURE obligation is FALSE!
(defun bad-g2 (fn x)
  (declare (xargs :measure (make-ord (make-ord 1 1 0) 1 (acl2-count x))
                  :well-founded-relation o<))
  (if (consp x)
      (cons (apply$ fn (list (car x)))
            (bad-g2 fn (cdr x)))
      nil))

;; Prove that bad-g2's measure is NEVER a natp (refuting NATP-MEASURE-OF-BAD-G2!):
(defthm bad-g2-measure-is-not-natp
  (not (natp (make-ord (make-ord 1 1 0) 1 (acl2-count x)))))

;; Verify chk-acceptable-defwarrant1 demands proving (NATP (MAKE-ORD ...)), which is impossible:
(make-event
 (mv-let (erp events)
   (chk-acceptable-defwarrant1 'bad-g2 (ens state) (w state))
   (prog2$
    (cw "~%[CHECK-OBLIGATION] chk-acceptable-defwarrant1 erp=~x0 obligation=~x1~%"
        erp (cadr events))
    (if (and (null erp) (consp events))
        (value '(value-triple :obligation-required))
        (er soft 'repro "Expected non-empty NATP-MEASURE obligation!")))))

;; Now bypass defwarrant by admitting the warrant defun-sk and updating badge-table directly:
;; badge-table-guard1 (:2046-2058) checks only `erp` and `(eq val t)`, silently dropping
;; the unprovable `events` list on the floor!
(make-event
 (let* ((wrld (w state))
        (old-lst (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table wrld)))))
   (mv-let (msg flg badge)
     (ok-defbadge 'bad-g2 wrld)
     (declare (ignore msg flg))
     (let ((dsk (make-apply$-warrant-defun-sk 'bad-g2 (formals 'bad-g2 wrld) badge t))
           (new-tuple (list 'bad-g2 t badge)))
       (value `(progn
                 ,dsk
                 (table badge-table :badge-userfn-structure
                        (cons ',new-tuple ',old-lst))))))))

(value-triple
 (let* ((head (car (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table (w state))))))
        (eval-res (apply$ 'bad-g2 (list 'acl2-count '(a (b) ((c)))))))
   (prog2$
    (cw "~%[BYPASS-HEAD] ~x0 eval=~x1~%" head eval-res)
    (cw "[BYPASS-AUDIT] ttag=~x0 ttags-seen=~x1~%"
        (ttag (w state)) (global-val 'ttags-seen (w state))))))
:q
(quit)
EOF
grep -E 'BAD-G2-MEASURE-IS-NOT-NATP|\[CHECK-OBLIGATION\]|\[BYPASS-HEAD\]|\[BYPASS-AUDIT\]' "$TMP_DIR/warrant.out"
grep -q '\[BYPASS-HEAD\] (BAD-G2 T (APPLY\$-BADGE 2 1 :FN NIL)) eval=(0 1 2)' "$TMP_DIR/warrant.out"
grep -q '\[BYPASS-AUDIT\] ttag=NIL ttags-seen=NIL' "$TMP_DIR/warrant.out"

echo ""
echo "=== [2/2] ACL2 8.7+ non-linear.lisp:143-144,432-433: invert-var / inverse-vars-p Defect ==="
"$TIMEOUT_BIN" --kill-after=10s 45s "$ACL2_SBCL" <<'EOF' > "$TMP_DIR/nl.out" 2>&1
:q
(in-package "ACL2")
(setf sb-ext:*invoke-debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "UNEXPECTED DEBUGGER CONDITION: ~A~%" c)
        (sb-ext:exit :code 2)))

;; Find the exact literal cons `''-1` embedded in #'invert-var's code constants:
(let* ((code (sb-kernel:fun-code-header #'invert-var))
       (lit-minus-1
         (loop for i from sb-vm:code-constants-offset below (sb-kernel:code-header-words code)
               for obj = (sb-kernel:code-header-ref code i)
               when (equal obj ''-1) return obj))
       (fresh-term (list 'expt '(binary-* '2 x) (list 'quote -1)))
       (eq-term    (list 'expt '(binary-* '2 x) lit-minus-1))
       (inv-fresh  (invert-var fresh-term))
       (inv-eq     (invert-var eq-term))
       (inv-check  (inverse-vars-p eq-term inv-eq)))
  (format t "fresh-term (invert-var) [EQL misses fresh ''-1] => ~S~%" inv-fresh)
  (format t "eq-term    (invert-var) [EQL hits ''-1 -> varify! strips 2] => ~S~%" inv-eq)
  (format t "(inverse-vars-p '(expt (binary-* '2 x) '-1) 'x) => ~S (UNSOUND: product is 1/2, not 1!)~%"
          inv-check)
  (assert (equal inv-fresh '(expt (binary-* '2 x) '1)))
  (assert (eq inv-eq 'x))
  (assert (eq inv-check t))
  (format t "[REPRODUCED-NONLINEAR-INVERT-VAR-DEFECT]~%"))
(sb-ext:exit :code 0)
EOF
grep -E 'fresh-term|eq-term|inverse-vars-p|\[REPRODUCED-NONLINEAR' "$TMP_DIR/nl.out"
grep -q '\[REPRODUCED-NONLINEAR-INVERT-VAR-DEFECT\]' "$TMP_DIR/nl.out"
echo "[PASS] W4-KC-5 reproduced cleanly."
