#!/usr/bin/env bash
# W4-KC-7: SBCL 2.6.10 array-tran.lisp:2354-2364 (transform-%with-array-data/mumble)
# Simple multidimensional %WITH-ARRAY-DATA / %WITH-ARRAY-DATA/FP silently replaces `start`
# with constant `0` in BOTH bounds-checked (safety 3) and unchecked paths!
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-sbcl-wad-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== SBCL 2.6.10 (safety 3, speed 3, space 0): simple 2D with-array-data drops START ==="
"$TIMEOUT_BIN" --kill-after=10s 30s "$SBCL_BIN" --script /dev/stdin <<'EOF' > "$TMP_DIR/sbcl.out" 2>&1
(format t "SBCL ~A (~A)~%" (lisp-implementation-version) (machine-type))
(let* ((f (compile nil '(lambda (a)
                          (declare (type (simple-array (unsigned-byte 8) (2 2)) a)
                                   (optimize (speed 3) (space 0) (safety 3)))
                          (sb-kernel:with-array-data ((data a) (start 1) (end 4))
                            (list (aref data start) start end)))))
       (arr (make-array '(2 2) :element-type '(unsigned-byte 8)
                               :initial-contents '((10 20) (30 40))))
       (got (funcall f arr)))
  (format t "with-array-data(start=1, end=4) => ~S (expected (20 1 4))~%" got)
  (assert (equal got '(10 0 4)))
  (format t "[REPRODUCED-SBCL-WITH-ARRAY-DATA-DROPS-START]~%"))
EOF
cat "$TMP_DIR/sbcl.out"
grep -q '\[REPRODUCED-SBCL-WITH-ARRAY-DATA-DROPS-START\]' "$TMP_DIR/sbcl.out"
echo "[PASS] W4-KC-7 reproduced cleanly."
