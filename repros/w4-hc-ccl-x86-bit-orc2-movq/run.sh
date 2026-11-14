#!/usr/bin/env bash
# Reproducer: W4-HC-10 — CCL 1.14 (x86-64 ONLY) `bit-orc2` on `simple-bit-vector`
# of length >= 129 silently drops the upper 64 bits of every 128-bit SSE2 chunk
# due to a `movq` typo instead of `movaps`.
# Source: ccl/level-0/X86/x86-array.lisp:502-519 (`%boole-orc2`, line 511).
set -euo pipefail

TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 60s ssh hbox "swarm-build timeout 30s /home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64 --no-init --batch --eval '(progn
  (let* ((z1 (make-array 192 :element-type (quote bit) :initial-element 0))
         (z2 (make-array 192 :element-type (quote bit) :initial-element 0))
         (r  (bit-orc2 z1 z2))
         (dst (make-array 192 :element-type (quote bit) :initial-element 1)))
    (bit-orc2 z1 (make-array 192 :element-type (quote bit) :initial-element 1) dst)
    (let ((res (list :ones (count 1 r) :bit127 (sbit r 127) :bit128 (sbit r 128)
                     :dst127 (sbit dst 127) :dst128 (sbit dst 128))))
      (format t \"RES=~S~%\" res)
      (when (and (= (count 1 r) 128) (= (sbit r 127) 1) (= (sbit r 128) 0)
                 (= (sbit dst 127) 0) (= (sbit dst 128) 1))
        (format t \"REPRODUCED: W4-HC-10~%\"))))
  (ccl:quit 0))'" 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-10" <<<"$OUT"
