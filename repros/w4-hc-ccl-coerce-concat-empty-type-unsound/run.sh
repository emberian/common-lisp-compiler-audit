#!/usr/bin/env bash
# Reproducer: W4-HC-12 — CCL 1.14 (arm64 & x86-64) `(safety 3)` `concatenate` & `coerce`
# compiler macros (`optimizers.lisp`) and runtime (`sequences.lisp`) drop length/range bounds
# and return values claiming to inhabit the empty type `NIL`.
# Source: ccl/compiler/optimizers.lisp:2412-2441, 2649-2653; ccl/lib/sequences.lisp:106, 851-908.
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$CCL_BIN" --no-init --batch --eval '(progn
  (let* ((c-s3 (compile nil (quote (lambda (a b) (declare (optimize (speed 3) (safety 3)))
                                     (concatenate (quote (string 2)) a b)))))
         (c-ni (compile nil (quote (lambda (a b) (declare (optimize (speed 3) (safety 3)) (notinline concatenate))
                                     (handler-case (concatenate (quote (string 2)) a b)
                                       (type-error () :type-error))))))
         (k-s3 (compile nil (quote (lambda (x) (declare (optimize (speed 3) (safety 3)))
                                     (coerce x nil)))))
         (k-ni (compile nil (quote (lambda (x) (declare (optimize (speed 3) (safety 3)) (notinline coerce))
                                     (handler-case (coerce x nil)
                                       (type-error () :type-error))))))
         (r1 (funcall c-s3 "abc" "def"))
         (r2 (funcall c-ni "abc" "def"))
         (r3 (funcall k-s3 5))
         (r4 (funcall k-ni 5))
         (r5 (funcall k-ni #\a)))
    (format t "CONCAT-S3=~S CONCAT-NI=~S COERCE5-S3=~S COERCE5-NI=~S COERCEA-NI=~S~%"
            r1 r2 r3 r4 r5)
    (when (and (equal r1 "abcdef") (eq r2 :type-error)
               (eql r3 5.0f0) (eq r4 :type-error) (eql r5 #\a))
      (format t "REPRODUCED: W4-HC-12~%")))
  (ccl:quit 0))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-12" <<<"$OUT"
