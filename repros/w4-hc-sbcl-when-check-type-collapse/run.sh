#!/usr/bin/env bash
# Reproducer: W4-HC-2 — SBCL 2.6.10 `type-from-constraints` collapses non-NIL
# variable ref in IF test to `(member t)` despite `lvar-annotations` (`check-type`),
# throwing bogus runtime `SIMPLE-TYPE-ERROR` on valid CONS input at (safety 3).
# Source: src/compiler/constraint.lisp:1166-1172 (`type-from-constraints`).
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --noinform --non-interactive --eval '(progn
  (let* ((f (compile nil (quote (lambda (y)
                                  (declare (optimize (safety 3))
                                           (type list y))
                                  (when y
                                    (check-type y cons)
                                    (car y))))))
         (input (list 42)))
    (handler-case
        (let ((res (funcall f input)))
          (format t "UNEXPECTED-OK: ~S~%" res)
          (sb-ext:exit :code 1))
      (type-error (e)
        (format t "CAUGHT-BOGUS-TYPE-ERROR: ~A~%" e)
        (if (and (consp input)
                 (eql (type-error-datum e) t)
                 (eq (type-error-expected-type e) (quote cons)))
            (format t "REPRODUCED: W4-HC-2~%")
            (sb-ext:exit :code 1))))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-2" <<<"$OUT"
