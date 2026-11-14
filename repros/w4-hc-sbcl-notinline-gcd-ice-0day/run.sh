#!/usr/bin/env bash
# Reproducer: W4-HC-13 — UNPATCHED 0-DAY on SBCL 2.6.10 & HEAD (arm64 & x86-64):
# `(locally (declare (notinline gcd)) (gcd))` aborts `COMPILE` at `(safety 3)` with
# unhandled `TYPE-ERROR: The value NIL is not of type NUMBER`.
# Source: src/compiler/srctran.lisp:8306-8354 (`derive-gcd` evaluates `(abs min)` when `args=NIL`).
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --noinform --non-interactive --eval '(progn
  (assert (= (gcd) 0))
  (handler-case
      (progn
        (compile nil (quote (lambda () (declare (optimize (speed 3) (safety 3)) (notinline gcd)) (gcd))))
        (sb-ext:exit :code 1))
    (error (e)
      (format t "COMPILER-ICE: ~A: ~A~%" (type-of e) e)
      (when (search "NIL" (princ-to-string e))
        (format t "REPRODUCED: W4-HC-13~%")))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-13" <<<"$OUT"
