#!/bin/sh
# Usage: run.sh [ccl|sbcl]   (default: ccl)
# CCL (speed 3)(safety 0): each form leaks the operand's extra value(s); wrong.
# SBCL: one value each (correct).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
case "${1:-ccl}" in
  ccl)  exec timeout 120 nice /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$HERE/repro.lisp" ;;
  sbcl) exec timeout 120 nice /opt/homebrew/bin/sbcl --script "$HERE/repro.lisp" ;;
  *) echo "usage: $0 [ccl|sbcl]" >&2; exit 2 ;;
esac
