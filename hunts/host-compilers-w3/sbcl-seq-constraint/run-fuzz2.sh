#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
COUNT="${1:-1000}"
SEED="${2:-777111}"
CCL="/Users/ember/dev/ccl/darm64cl"
TIMEOUT="/opt/homebrew/bin/timeout"

run_sbcl() {
  local mode="$1"
  local out="$2"
  "$TIMEOUT" --kill-after=10s 180s sbcl --noinform --non-interactive \
    --load "$DIR/fuzz2.lisp" \
    --eval "(sbcl-fuzz2:main '(\"$mode\" \"$out\" \"$COUNT\" \"$SEED\"))"
}

run_ccl() {
  local out="$1"
  "$TIMEOUT" --kill-after=10s 180s "$CCL" -n -b \
    --load "$DIR/fuzz2.lisp" \
    --eval "(sbcl-fuzz2:main '(\"ccl\" \"$out\" \"$COUNT\" \"$SEED\"))" \
    --eval "(ccl:quit 0)"
}

echo "Running SBCL s3-safe3 ($COUNT + $COUNT, seed=$SEED)..."
run_sbcl "sbcl-s3-safe3" "$DIR/out2-sbcl-s3-safe3.txt"

echo "Running SBCL s3-safe0..."
run_sbcl "sbcl-s3-safe0" "$DIR/out2-sbcl-s3-safe0.txt"

echo "Running SBCL s0-notinline..."
run_sbcl "sbcl-s0-notinline" "$DIR/out2-sbcl-s0-notinline.txt"

echo "Running CCL 1.14..."
run_ccl "$DIR/out2-ccl.txt"

echo "=== Diff SBCL s3-safe3 vs SBCL s0-notinline ==="
diff -u "$DIR/out2-sbcl-s3-safe3.txt" "$DIR/out2-sbcl-s0-notinline.txt" | head -n 80 || true

echo "=== Diff SBCL s3-safe0 vs SBCL s0-notinline ==="
diff -u "$DIR/out2-sbcl-s3-safe0.txt" "$DIR/out2-sbcl-s0-notinline.txt" | head -n 80 || true

echo "=== Diff SBCL s3-safe3 vs CCL ==="
diff -u "$DIR/out2-sbcl-s3-safe3.txt" "$DIR/out2-ccl.txt" | head -n 80 || true
