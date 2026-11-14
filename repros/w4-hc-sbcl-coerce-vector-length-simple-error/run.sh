#!/usr/bin/env bash
# Reproducer: W4-HC-14 — SBCL 2.6.10 (arm64 & x86-64) `(safety 3)` `deftransform coerce`
# signals `SIMPLE-ERROR` instead of CLHS-required `TYPE-ERROR` on `(coerce seq '(vector t N))`
# length mismatch.
# Source: src/compiler/typetran.lisp:2076-2077 (`deftransform coerce`).
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --noinform --non-interactive --eval '(progn
  (let* ((s3 (compile nil (quote (lambda (x) (declare (optimize (speed 3) (safety 3)))
                                   (handler-case (coerce x (quote (vector t 2)))
                                     (type-error () :caught-type-error)
                                     (error (e) (list :uncaught (type-of e))))))))
         (ni (compile nil (quote (lambda (x) (declare (optimize (speed 3) (safety 3)) (notinline coerce))
                                   (handler-case (coerce x (quote (vector t 2)))
                                     (type-error () :caught-type-error))))))
         (r-s3 (funcall s3 (list 1 2 3)))
         (r-ni (funcall ni (list 1 2 3))))
    (format t "S3=~S NI=~S~%" r-s3 r-ni)
    (when (and (equal r-s3 (quote (:uncaught simple-error)))
               (eq r-ni :caught-type-error))
      (format t "REPRODUCED: W4-HC-14~%"))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-14" <<<"$OUT"
