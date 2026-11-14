#!/bin/sh
# Usage: run.sh [ccl|sbcl]   (default: ccl)
# Demonstrates CCL 1.14 bug in nx1-expand-inline-call (compiler/nx0.lisp:2453)
# where (space 0) overwrites (safety 3) with (safety 0) inside all inlined functions.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
case "${1:-ccl}" in
  ccl)  exec timeout 60 nice /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$HERE/repro.lisp" ;;
  sbcl) exec timeout 60 nice /opt/homebrew/bin/sbcl --script "$HERE/repro.lisp" ;;
  *) echo "usage: $0 [ccl|sbcl]" >&2; exit 2 ;;
esac
