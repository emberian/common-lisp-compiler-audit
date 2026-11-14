#!/usr/bin/env bash
# W4-KC-4: SBCL 2.6.10 ARM64 ir1opt.lisp:3799-3809 (deftransform values-list)
# Single-Value & For-Effect (values-list (reverse x)) at (safety 3) Compiles Full Call to
# Non-Existent Lisp Function SB-C::REVERSE-VALUES-LIST -> UNDEFINED-FUNCTION at Runtime.
set -euo pipefail

SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
TIMEOUT_BIN="${TIMEOUT_BIN:-/opt/homebrew/bin/timeout}"

TMP_DIR="$(mktemp -d /tmp/w4-kc-sbcl-rvl-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== SBCL 2.6.10 darwin-arm64 (safety 3): (values-list (reverse x)) UNDEFINED-FUNCTION ==="
"$TIMEOUT_BIN" --kill-after=10s 30s "$SBCL_BIN" --script /dev/stdin <<'EOF' > "$TMP_DIR/sbcl.out" 2>&1
(format t "SBCL ~A (~A)~%" (lisp-implementation-version) (machine-type))

;; 1. Single-value context at (safety 3):
(let ((f1 (compile nil '(lambda (x)
                          (declare (optimize (speed 1) (safety 3) (debug 2)))
                          (values (values-list (reverse x))))))
      (err1 nil))
  (handler-case
      (funcall f1 '(10 20 30))
    (undefined-function (c)
      (setq err1 (cell-error-name c))
      (format t "Single-value context signaled UNDEFINED-FUNCTION for ~S (expected return: 30)~%" err1)))
  (assert (eq err1 'sb-c::reverse-values-list)))

;; 2. For-effect context at (safety 3):
(let ((f2 (compile nil '(lambda (x)
                          (declare (optimize (speed 1) (safety 3) (debug 2)))
                          (values-list (reverse x))
                          :ok)))
      (err2 nil))
  (handler-case
      (funcall f2 '(10 20 30))
    (undefined-function (c)
      (setq err2 (cell-error-name c))
      (format t "For-effect context signaled UNDEFINED-FUNCTION for ~S (expected return: :OK)~%" err2)))
  (assert (eq err2 'sb-c::reverse-values-list)))

(format t "[REPRODUCED-SBCL-ARM64-REVERSE-VALUES-LIST-UNDEFINED]~%")
EOF
cat "$TMP_DIR/sbcl.out"
grep -q '\[REPRODUCED-SBCL-ARM64-REVERSE-VALUES-LIST-UNDEFINED\]' "$TMP_DIR/sbcl.out"
echo "[PASS] W4-KC-4 reproduced cleanly."
