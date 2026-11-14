#!/usr/bin/env bash
# Reproducer: W4-HC-6 — Unpatched 0-day in SBCL 2.6.10 & HEAD (`076335724`) ARM64:
# `define-partial-reffer` / `define-partial-setter` call `(load-store-offset ...)`
# without passing `size` (defaulting to 64-bit scale), crashing `SB-ARM64-ASM` on
# 8-bit vector / simple-base-string constant indices `4095, 4103, ..., 32759` at
# `(safety 3)` — and crashing `:ttags nil` ACL2 8.7+ (`saved_acl2`) on inline u8 stobjs!
# Source: src/compiler/arm64/macros.lisp:45-50, 508-511, 562-565.
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
ACL2_BIN="${ACL2_BIN:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

echo "=== [1/2] Standalone SBCL 2.6.10 ARM64 (safety 3) Assembler Crash ==="
OUT1="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --noinform --non-interactive --eval '(progn
  ;; Verify interpreted / non-constant index 4095 is 100% valid in-bounds:
  (let ((arr (make-array 5000 :element-type (quote (unsigned-byte 8)) :initial-element 219))
        (f-var (compile nil (quote (lambda (a i)
                                     (declare (optimize (speed 1) (safety 3))
                                              (type (simple-array (unsigned-byte 8) (*)) a)
                                              (type fixnum i))
                                     (aref a i))))))
    (assert (= (funcall f-var arr 4095) 219)))
  ;; Constant index 4095 (byte_offset = 4095 + 1 = 4096, divisible by 8, > 4095 max uimm12 for LDRB):
  (handler-case
      (progn
        (compile nil (quote (lambda (a)
                              (declare (optimize (speed 1) (safety 3))
                                       (type (simple-array (unsigned-byte 8) (*)) a))
                              (aref a 4095))))
        (sb-ext:exit :code 1))
    (error (e)
      (format t "SBCL-ARM64-CRASH: ~A~%" e)
      (if (search "Invalid STR/LDR arguments" (princ-to-string e))
          (format t "REPRODUCED: W4-HC-6-CL~%")
          (sb-ext:exit :code 1)))))' 2>&1)"
printf '%s\n' "$OUT1"
grep -q "REPRODUCED: W4-HC-6-CL" <<<"$OUT1"

if [[ -x "$ACL2_BIN" ]]; then
  echo "=== [2/2] Pure :ttag nil ACL2 8.7+ on SBCL 2.6.10 ARM64 Raw-Lisp Abort ==="
  OUT2="$("$TIMEOUT_BIN" --kill-after=5s 30s "$ACL2_BIN" <<'EOF' 2>&1 || true
(defstobj b8st
  (arr :type (array (unsigned-byte 8) (5000)) :initially 0)
  :inline t)
(defun get-u8-4095 (b8st)
  (declare (xargs :stobjs b8st :guard t))
  (arri 4095 b8st))
:q
EOF
)"
  printf '%s\n' "$OUT2" | grep -E "ABORTING from raw Lisp|Invalid STR/LDR arguments"
  grep -q "Invalid STR/LDR arguments" <<<"$OUT2"
  echo "REPRODUCED: W4-HC-6-ACL2"
fi
