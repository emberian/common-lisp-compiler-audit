#!/usr/bin/env bash
# Reproducer: W4-HC-11 — CCL 1.14 (arm64 & x86-64) `:test 'equalp` hash-tables fail
# lookup and insert duplicate keys for `equalp` `ratio` vs `float` values (`1/2` vs `0.5d0`).
# Source: ccl/level-0/l0-hash.lisp:1769-1780 (`%%equalphash`).
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$CCL_BIN" --no-init --batch --eval '(progn
  (let ((ht (make-hash-table :test (quote equalp))))
    (setf (gethash 1/2 ht) :first)
    (multiple-value-bind (val foundp) (gethash 0.5d0 ht)
      (setf (gethash 0.5d0 ht) :second)
      (format t "EQUALP=~S FOUND=~S VAL=~S COUNT=~S~%"
              (equalp 1/2 0.5d0) foundp val (hash-table-count ht))
      (when (and (equalp 1/2 0.5d0) (not foundp) (= (hash-table-count ht) 2))
        (format t "REPRODUCED: W4-HC-11~%"))))
  (ccl:quit 0))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-11" <<<"$OUT"
