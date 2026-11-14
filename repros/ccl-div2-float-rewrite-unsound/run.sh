#!/bin/sh
# Usage: run.sh [ccl|sbcl]   (default: ccl)
# Demonstrates CCL 1.14 unsound (/ (* c1 x) c2) -> (* (/ c1 c2) x) rewrite
# on floating-point inputs at (optimize (safety 3) (speed 1)).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
case "${1:-ccl}" in
  ccl)  exec timeout 60 nice /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$HERE/repro.lisp" ;;
  sbcl) exec timeout 60 nice /opt/homebrew/bin/sbcl --script "$HERE/repro.lisp" ;;
  *) echo "usage: $0 [ccl|sbcl]" >&2; exit 2 ;;
esac
