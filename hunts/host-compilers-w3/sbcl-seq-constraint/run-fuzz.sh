#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
COUNT="${1:-500}"
SEED="${2:-20261113}"
CCL="/Users/ember/dev/ccl/darm64cl"
TIMEOUT="/opt/homebrew/bin/timeout"

run_sbcl() {
  local mode="$1"
  local out="$2"
  "$TIMEOUT" --kill-after=10s 120s sbcl --noinform --non-interactive \
    --load "$DIR/fuzz.lisp" \
    --eval "(sbcl-fuzz:main '(\"$mode\" \"$out\" \"$COUNT\" \"$SEED\"))"
}

run_ccl() {
  local out="$1"
  "$TIMEOUT" --kill-after=10s 120s "$CCL" -n -b \
    --load "$DIR/fuzz.lisp" \
    --eval "(sbcl-fuzz:main '(\"ccl\" \"$out\" \"$COUNT\" \"$SEED\"))" \
    --eval "(ccl:quit 0)"
}

echo "Running SBCL s3-safe3 ($COUNT seq + $COUNT constraint, seed=$SEED)..."
run_sbcl "sbcl-s3-safe3" "$DIR/out-sbcl-s3-safe3.txt"

echo "Running SBCL s3-safe0..."
run_sbcl "sbcl-s3-safe0" "$DIR/out-sbcl-s3-safe0.txt"

echo "Running SBCL s0-notinline..."
run_sbcl "sbcl-s0-notinline" "$DIR/out-sbcl-s0-notinline.txt"

echo "Running CCL 1.14..."
run_ccl "$DIR/out-ccl.txt"

echo "=== Diff SBCL s3-safe3 vs SBCL s0-notinline ==="
diff -u "$DIR/out-sbcl-s3-safe3.txt" "$DIR/out-sbcl-s0-notinline.txt" | head -n 60 || true

echo "=== Diff SBCL s3-safe0 vs SBCL s0-notinline ==="
diff -u "$DIR/out-sbcl-s3-safe0.txt" "$DIR/out-sbcl-s0-notinline.txt" | head -n 60 || true

echo "=== Diff SBCL s3-safe3 vs CCL ==="
diff -u "$DIR/out-sbcl-s3-safe3.txt" "$DIR/out-ccl.txt" | head -n 60 || true
