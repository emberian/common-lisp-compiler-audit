#!/usr/bin/env bash
# Reproducer: W4-HC-3 — Unpatched 0-day in SBCL 2.6.10 & HEAD (`076335724`):
# `%dpb derive-type` omits `+left-shift-derive-type-cutoff+` on `related-byte-spec`
# `(byte count (- a count))`, attempting `(ash 1 (interval-high a))` at compile time
# and crashing `COMPILE` on valid `(safety 3)` Common Lisp when `a` is `fixnum`.
# Source: src/compiler/srctran.lisp:3980-3988 (`%dpb derive-type`).
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --dynamic-space-size 512 --noinform --non-interactive --eval '(progn
  ;; Interpretively, (dpb 1 (byte 4 (- 8 4)) 0) => 16 (100% well-defined ANSI CL).
  (assert (= (let ((j 1) (count 4) (a 8) (word 0))
               (when (<= count a)
                 (dpb j (byte count (- a count)) word)))
             16))
  (handler-case
      (progn
        (compile nil (quote (lambda (j count a word)
                              (declare (optimize (safety 3))
                                       (type (integer 0 64) count)
                                       (type fixnum a)
                                       (type (unsigned-byte 64) word))
                              (when (<= count a)
                                (dpb j (byte count (- a count)) word)))))
        (sb-ext:exit :code 1))
    (error (e)
      (format t "COMPILER-CRASH: ~A: ~A~%" (type-of e) e)
      (if (search "left shift" (princ-to-string e))
          (format t "REPRODUCED: W4-HC-3~%")
          (sb-ext:exit :code 1)))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-3" <<<"$OUT"
