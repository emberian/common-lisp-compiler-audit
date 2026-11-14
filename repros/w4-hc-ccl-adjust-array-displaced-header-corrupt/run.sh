#!/usr/bin/env bash
# Reproducer: W4-HC-9 — CCL 1.14 (arm64 & x86-64) `adjust-array :displaced-to` targeting
# an adjustable/header array wipes `$arh_disp_bit`, causing `(safety 3)` open-coded `aref`
# to read raw `vectorH`/`arrayH` VM header words instead of backing elements.
# Source: ccl/lib/arrays-fry.lisp:376-385 (`%displace-array`),
#         ccl/compiler/ARM64/arm64-vinsns.lisp:7014-7025,
#         ccl/compiler/X86/X8664/x8664-vinsns.lisp:911-919 (`deref-vector-header`).
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$CCL_BIN" --no-init --batch --eval '(progn
  (let* ((fn-s3 (compile nil (quote (lambda (arr tgt)
                                      (declare (optimize (speed 3) (safety 3)))
                                      (let ((res (adjust-array arr 3 :displaced-to tgt :displaced-index-offset 0)))
                                        (declare (type (vector t) res))
                                        (list (aref res 0) (aref res 1) (aref res 2)))))))
         (fn-ni (compile nil (quote (lambda (arr tgt)
                                      (declare (optimize (speed 3) (safety 3)) (notinline aref))
                                      (let ((res (adjust-array arr 3 :displaced-to tgt :displaced-index-offset 0)))
                                        (declare (type (vector t) res))
                                        (list (aref res 0) (aref res 1) (aref res 2)))))))
         (r-s3 (funcall fn-s3 (make-array 3 :adjustable t :initial-contents (quote (1 2 3)))
                              (make-array 4 :adjustable t :initial-contents (quote (:a :b :c :d)))))
         (r-ni (funcall fn-ni (make-array 3 :adjustable t :initial-contents (quote (1 2 3)))
                              (make-array 4 :adjustable t :initial-contents (quote (:a :b :c :d))))))
    (format t "S3=~S NI=~S~%" r-s3 r-ni)
    (when (and (equal r-ni (quote (:a :b :c))) (not (equal r-s3 r-ni)))
      (format t "REPRODUCED: W4-HC-9~%")))
  (ccl:quit 0))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-9" <<<"$OUT"
