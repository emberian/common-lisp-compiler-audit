#!/usr/bin/env bash
# Reproducer: W4-HC-5 — SBCL 2.6.10 `convert-more-call` marks local keyword call
# as `:error` on non-symbol keyword even when `:allow-other-keys t` suppresses
# keyword checking (CLHS 3.4.1.4.1), crashing `COMPILE` with `NIL is not SB-C::NODE`.
# Source: src/compiler/locall.lisp:865-868 (`convert-more-call`).
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --noinform --non-interactive --eval '(progn
  ;; Non-inline reference call with :allow-other-keys t is 100% valid per CLHS 3.4.1.4.1:
  (let ((ref (compile nil (quote (lambda (v)
                                   (flet ((g (&key k) (values k v)))
                                     (declare (notinline g))
                                     (multiple-value-list (g 1 2 :allow-other-keys t))))))))
    (assert (equal (funcall ref :ok) (quote (nil :ok)))))
  (handler-case
      (progn
        (compile nil (quote (lambda (v)
                              (declare (optimize (debug 2) (safety 3)))
                              (labels ((g (&key k)
                                         (g :k 1)
                                         (values k v)))
                                (declare (inline g))
                                (g 1 2 :allow-other-keys t)))))
        (sb-ext:exit :code 1))
    (type-error (e)
      (format t "COMPILER-ICE: ~A~%" e)
      (if (eq (type-error-expected-type e) (quote sb-c::node))
          (format t "REPRODUCED: W4-HC-5~%")
          (sb-ext:exit :code 1)))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-5" <<<"$OUT"
