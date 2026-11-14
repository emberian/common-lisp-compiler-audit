#!/usr/bin/env bash
# Reproducer: W4-HC-4 — Unpatched 0-day in SBCL 2.6.10 & HEAD (`076335724`):
# Relational `<`/`>`/`eql` rational transform on `(< (ash x c) (* y k))` checks only
# `(plusp c)` without `(mod 4096)` shift cutoff, attempting `(ash 1 c)` at compile
# time and crashing `COMPILE` on valid `(safety 3)` CL where `(ash 0 2^60)` = `0`.
# Source: src/compiler/srctran.lisp:8089-8092, 8182-8185.
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --dynamic-space-size 512 --noinform --non-interactive --eval '(progn
  ;; At x = 0, (ash 0 1152921504606846976) => 0 and (< 0 3) => T (100% valid ANSI CL).
  (assert (eq (< (ash 0 1152921504606846976) (* 1 3)) t))
  (handler-case
      (progn
        (compile nil (quote (lambda (flag x y)
                              (declare (optimize (safety 3))
                                       (type integer x y))
                              (when flag
                                (< (ash x 1152921504606846976) (* y 3))))))
        (sb-ext:exit :code 1))
    (error (e)
      (format t "COMPILER-CRASH: ~A: ~A~%" (type-of e) e)
      (if (search "left shift" (princ-to-string e))
          (format t "REPRODUCED: W4-HC-4~%")
          (sb-ext:exit :code 1)))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-4" <<<"$OUT"
