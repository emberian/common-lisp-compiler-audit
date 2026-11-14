#!/usr/bin/env bash
# Reproducer: W4-HC-15 — CCL 1.14 (arm64 & x86-64) stdlib semantic bugs:
# (a) 0D adjustable `adjust-array :initial-contents` silently ignored (`arrays-fry.lisp:318-321`)
# (b) `(signum -0.0f0)` / `(signum -0.0d0)` loses `-0.0` sign (`numbers.lisp:616`).
set -euo pipefail

CCL_BIN="${CCL_BIN:-/Users/ember/dev/ccl/darm64cl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$CCL_BIN" --no-init --batch --eval '(progn
  (let* ((a (make-array nil :adjustable t :initial-element (quote old)))
         (b (make-array nil :initial-element (quote old)))
         (adj (aref (adjust-array a nil :initial-contents (quote new))))
         (nonadj (aref (adjust-array b nil :initial-contents (quote new))))
         (sf (float-sign (signum -0.0f0)))
         (sd (float-sign (signum -0.0d0))))
    (format t "0D-ADJ=~S 0D-NONADJ=~S SIGNUM-F=~S SIGNUM-D=~S~%" adj nonadj sf sd)
    (when (and (eq adj (quote old)) (eq nonadj (quote new))
               (> sf 0.0f0) (> sd 0.0d0))
      (format t "REPRODUCED: W4-HC-15~%")))
  (ccl:quit 0))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-15" <<<"$OUT"
