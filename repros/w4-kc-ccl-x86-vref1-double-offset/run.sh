#!/usr/bin/env bash
# W4-KC-3: Clozure CL 1.14 x86-64 x862-vref1 (x862.lisp:2093,2116,2136,2148,2159,2172)
# Double misc-data-offset (-5 + -5 = -10) Unaligned Cross-Element Read + Bogus fulltag-misc
# Pointer Tag in GC-Traced Node Register at (optimize (speed 1) (safety 3)).
set -euo pipefail

HBOX_HOST="${HBOX_HOST:-hbox}"
LX86CL64="${LX86CL64:-/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-x86-vref1-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== Clozure CL 1.14 x86-64-linux (safety 3): x862-vref1 Double misc-data-offset ==="
ssh "$HBOX_HOST" "swarm-build timeout 60s $LX86CL64 -R 8G -n -Q -b" <<'EOF' > "$TMP_DIR/x86.out" 2>&1
(let* ((idx #x10000000) ; 2^28 = target-max-64-bit-constant-index + 1 (2 GiB u64 vector)
       (f-const (compile nil `(lambda (v)
                                (declare (optimize (speed 1) (safety 3))
                                         (type (simple-array (unsigned-byte 64) (*)) v))
                                (aref v ,idx))))
       (f-var   (compile nil '(lambda (v i)
                                (declare (optimize (speed 1) (safety 3))
                                         (type (simple-array (unsigned-byte 64) (*)) v))
                                (aref v i))))
       ;; Use variable-index writer so CCL does not constant-propagate `idx` into x862-vset1:
       (s-var   (compile nil '(lambda (v i val)
                                (declare (optimize (speed 1) (safety 3))
                                         (type (simple-array (unsigned-byte 64) (*)) v))
                                (setf (aref v i) val)))))
  (disassemble f-const)
  (let ((arr (make-array (+ idx 2) :element-type '(unsigned-byte 64) :initial-element 0)))
    (funcall s-var arr (1- idx) #x1122334455667788)
    (funcall s-var arr idx      #xAABBCCDDEEFF0099)
    (let ((got-const (funcall f-const arr))
          (got-var   (funcall f-var arr idx)))
      (format t "(safety 3) var-index   = #x~16,'0X~%" got-var)
      (format t "(safety 3) const-index = #x~16,'0X (expected #x~16,'0X)~%" got-const got-var)
      ;; Reading 5 bytes early on little-endian x86-64 splices the top 5 bytes of arr[idx-1]
      ;; (#x1122334455) into the low 5 bytes and the low 3 bytes of arr[idx] (#xFF0099) into
      ;; the high 3 bytes => #xFF00991122334455!
      (assert (= got-var   #xAABBCCDDEEFF0099))
      (assert (= got-const #xFF00991122334455))
      (format t "[REPRODUCED-CCL-X86-VREF1-DOUBLE-OFFSET]~%"))))
(quit 0)
EOF
cat "$TMP_DIR/x86.out"
grep -q '\[REPRODUCED-CCL-X86-VREF1-DOUBLE-OFFSET\]' "$TMP_DIR/x86.out"
echo "[PASS] W4-KC-3 reproduced cleanly."
