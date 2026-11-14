#!/bin/sh
# Usage: run.sh [ccl|sbcl]   (default: ccl)
# Demonstrates CCL 1.14 ARM64 register-clobber bug in arm642-four-untargeted-reg-forms
# corrupting 2D (setf aref) and 3D (aref) even at (optimize (safety 3) (speed 1)).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
case "${1:-ccl}" in
  ccl)  exec timeout 60 nice /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$HERE/repro.lisp" ;;
  sbcl) exec timeout 60 nice /opt/homebrew/bin/sbcl --script "$HERE/repro.lisp" ;;
  *) echo "usage: $0 [ccl|sbcl]" >&2; exit 2 ;;
esac
