#!/usr/bin/env bash
# Reproducer: W4-HC-7 — Clozure CL 1.14 ARM64 (`darm64cl`) 2D/3D `arm642-aset2` /
# `arm642-aset3` uninitialized-register silent memory corruption on valid in-bounds
# `(simple-array bit ...)` stores when linearized constant index > 32792!
# Source: /Users/ember/dev/ccl/compiler/ARM64/arm642.lisp:2040-2052, 2165-2176, 2641.
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$CCL_BIN" -n -Q -b <<'EOF' 2>&1
(declaim (notinline opaque-idx))
(defun opaque-idx (i) i)

;; 100% valid Zero-UB inputs:
;;   a is (simple-array bit (400 100)) (total size 40,000; (aref a 328 0) = element 32,800 in-bounds)
;;   x = 100, y = 200 (both in (integer 0 1000))
;; Bug: arm642-aset2 sees constidx=32800 so `(unless constidx ...)` skips initializing idx-reg (arg_y),
;; and arm642-vset1:2641 ignores constidx > 32792 and writes bit 1 to stale caller arg_y (x = 100)!
(let ((fn (compile nil '(lambda (a x y)
                          (declare (optimize (speed 3) (safety 0))
                                   (type (simple-array bit (400 100)) a)
                                   (type (integer 0 1000) x y))
                          (setf (aref a 328 0) 1)
                          (+ x y))))
      (a (make-array '(400 100) :element-type 'bit :initial-element 0)))
  (let ((sum (funcall fn a 100 200))
        (target-bit (row-major-aref a (opaque-idx 32800)))
        (corrupted-bit (row-major-aref a (opaque-idx 100))))
    (format t "sum=~S target[32800]=~S (expected 1) stale-arg_y[100]=~S (expected 0)~%"
            sum target-bit corrupted-bit)
    (if (and (= sum 300) (= target-bit 0) (= corrupted-bit 1))
        (progn
          (format t "REPRODUCED: W4-HC-7~%")
          (ccl:quit 0))
        (ccl:quit 1))))
EOF
)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-7" <<<"$OUT"
