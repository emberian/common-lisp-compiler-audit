#!/usr/bin/env bash
# Reproducer: W4-HC-1 — SBCL 2.6.10 EQ false-branch unsoundly negates EQL/= on
# non-eq-comparable bignum constants at (safety 3).
# Source: src/compiler/constraint.lisp:891 (`constraint-propagate-if` for `eq`)
#         + src/compiler/constraint.lisp:1073-1092 (`contiguous-numeric-set-type`).
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

OUT="$("$TIMEOUT_BIN" --kill-after=5s 30s "$SBCL_BIN" --noinform --non-interactive --eval '(progn
  (let* ((id (compile nil (quote (lambda (z) z))))
         ;; Construct a fresh heap-allocated bignum equal to 2^70 + 1 (not EQ to literal)
         (fresh-big (+ (funcall id (ash 1 70)) 1))
         (f-eql (compile nil (quote (lambda (x)
                                      (declare (optimize (speed 1) (safety 3))
                                               (type integer x))
                                      (cond ((eq x 1180591620717411303425) :eq)
                                            ((eql x 1180591620717411303425) :eql)
                                            (t :neither))))))
         (f-num (compile nil (quote (lambda (x)
                                      (declare (optimize (speed 1) (safety 3))
                                               (type integer x))
                                      (cond ((eq x 1180591620717411303425) :eq)
                                            ((= x 1180591620717411303425) :num-eq)
                                            (t :neither))))))
         (got-eql (funcall f-eql fresh-big))
         (got-num (funcall f-num fresh-big)))
    (format t "BIGNUM EQL: got=~S expected=:EQL~%" got-eql)
    (format t "BIGNUM =  : got=~S expected=:NUM-EQ~%" got-num)
    (if (and (eq got-eql :neither) (eq got-num :neither))
        (format t "REPRODUCED: W4-HC-1~%")
        (sb-ext:exit :code 1))))' 2>&1)"

printf '%s\n' "$OUT"
grep -q "REPRODUCED: W4-HC-1" <<<"$OUT"
