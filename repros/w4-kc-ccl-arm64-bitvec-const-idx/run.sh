#!/usr/bin/env bash
# W4-KC-2: Clozure CL 1.14 ARM64 arm642-vref1 / arm642-vset1 (arm642.lisp:1883, :2641)
# 1-Bit Vector Constant-Index Miscompilation at (safety 3), COMPILE Crash at (safety 0),
# and Pure :ttag nil (defthm nil-proved nil) in ACL2 8.7+ via Inline Bit-Array Stobj.
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
ACL2_CCL="${ACL2_CCL:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-arm64-bv-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== [1/2] Standalone Clozure CL 1.14 ARM64: (safety 3) Wrong-Code & (safety 0) COMPILE Crash ==="
"$TIMEOUT_BIN" --kill-after=10s 30s "$CCL_BIN" -n -Q -b <<'EOF' > "$TMP_DIR/ccl.out" 2>&1
;; Part A: (safety 3) wrong-code on constant bit index > 131040 (e.g. 131105)
(let* ((bv (make-array 200000 :element-type 'bit :initial-element 0))
       (reader-const (compile nil '(lambda (v)
                                     (declare (optimize (speed 1) (safety 3))
                                              (type simple-bit-vector v))
                                     (sbit v 131105))))
       (reader-var   (compile nil '(lambda (v i)
                                     (declare (optimize (speed 1) (safety 3))
                                              (type simple-bit-vector v))
                                     (sbit v i)))))
  (setf (sbit bv 131105) 1)
  (let ((got-const (funcall reader-const bv))
        (got-var   (funcall reader-var bv 131105)))
    (format t "(safety 3) const-index (sbit bv 131105) => ~S (expected ~S)~%" got-const got-var)
    (assert (eql got-var 1))
    (assert (eql got-const 0))
    ;; Also demonstrate silent aliasing with bit index (32776 + 1) = 32777?
    ;; Actually offset used is (-6 + 4097) = +4091 bytes from tagged pointer = byte 4097 of data
    ;; (word 1024 + 1 byte, unaligned!), reading bit 1 of byte 4097 = bit (4097*8 + 1) = 32777!
    (setf (sbit bv 32777) 1)
    (let ((aliased (funcall reader-const bv)))
      (format t "(safety 3) after setting bit 32777, (sbit bv 131105) => ~S (confirms 1/4 unaligned byte offset!)~%"
              aliased)
      (assert (eql aliased 1)))))

;; Part B: (safety 0) COMPILE crash ("bad regspec: NIL") in arm642-vset1 (:2641)
(let ((crashed nil))
  (handler-case
      (compile nil '(lambda (v)
                      (declare (optimize (speed 3) (safety 0))
                               (type simple-bit-vector v))
                      (setf (sbit v 131105) 1)))
    (error (e)
      (setq crashed (princ-to-string e))
      (format t "(safety 0) COMPILE (setf (sbit v 131105) 1) crashed as expected: ~A~%" crashed)))
  (assert crashed))
(format t "[REPRODUCED-CCL-ARM64-BITVEC-CONST-INDEX-BUGS]~%")
(quit 0)
EOF
cat "$TMP_DIR/ccl.out"
grep -q '\[REPRODUCED-CCL-ARM64-BITVEC-CONST-INDEX-BUGS\]' "$TMP_DIR/ccl.out"

echo ""
echo "=== [2/2] Pure :ttag nil ACL2 8.7+ on CCL 1.14: (defthm nil-proved nil) via Bit-Array Stobj ==="
"$TIMEOUT_BIN" --kill-after=10s 60s "$ACL2_CCL" <<'EOF' > "$TMP_DIR/acl2.out" 2>&1
(defstobj bv-st
  (bv :type (array bit (200000)) :initially 0)
  :inline t)

;; Pass `idx` as a variable to `update-bvi` (otherwise inline `update-bvi` with constant
;; 131105 crashes ACL2's raw-Lisp compiler with `Error: bad regspec: NIL` via arm642-vset1!),
;; and read back with constant index `(bvi 131105 bv-st)` to trigger arm642-vref1 (:1883):
(defun write-var-then-read-131105 (idx bv-st)
  (declare (xargs :stobjs bv-st
                  :guard (and (natp idx) (< idx 200000))))
  (let ((bv-st (update-bvi idx 1 bv-st)))
    (mv (bvi 131105 bv-st) bv-st)))

(defun run-bv-bug ()
  (declare (xargs :guard t))
  (with-local-stobj
    bv-st
    (mv-let (ans bv-st)
      (write-var-then-read-131105 131105 bv-st)
      ans)))

(defthm run-bv-bug-is-1-by-logic
  (equal (run-bv-bug) 1)
  :hints (("Goal" :in-theory (e/d (run-bv-bug write-var-then-read-131105)
                                  ((run-bv-bug))))))

(defthm run-bv-bug-is-0-by-exec
  (equal (run-bv-bug) 0)
  :hints (("Goal" :in-theory (disable run-bv-bug))))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal"
           :in-theory (disable run-bv-bug (run-bv-bug))
           :use (run-bv-bug-is-1-by-logic run-bv-bug-is-0-by-exec))))

(value-triple
 (prog2$
  (cw "~%[AUDIT-TTAG] ttag=~x0 ttags-seen=~x1~%"
      (ttag (w state))
      (global-val 'ttags-seen (w state)))
  (cw "[AUDIT-FLAGS] skip-proofs=~x0 redef=~x1~%"
      (global-val 'skip-proofs-seen (w state))
      (global-val 'redef-seen (w state)))))
:q
(quit 0)
EOF
grep -E 'Q\.E\.D\.|^ NIL-PROVED$|\[AUDIT-TTAG\]|\[AUDIT-FLAGS\]' "$TMP_DIR/acl2.out"
grep -q '^ NIL-PROVED$' "$TMP_DIR/acl2.out"
grep -q '\[AUDIT-TTAG\] ttag=NIL ttags-seen=NIL' "$TMP_DIR/acl2.out"
grep -q '\[AUDIT-FLAGS\] skip-proofs=NIL redef=NIL' "$TMP_DIR/acl2.out"
echo "[PASS] W4-KC-2 reproduced cleanly."
