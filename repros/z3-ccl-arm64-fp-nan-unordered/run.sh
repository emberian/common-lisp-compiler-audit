#!/bin/sh
# Reproduces CCL 1.14 ARM64 FCMP unordered NaN condition-code miscompilation
# under default FPU mode at (optimize (speed 1) (safety 3)).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TIMEOUT_BIN=/opt/homebrew/bin/timeout
if [ ! -x "$TIMEOUT_BIN" ]; then TIMEOUT_BIN=timeout; fi

case "${1:-ccl}" in
  ccl)
    exec "$TIMEOUT_BIN" --kill-after=10s 60s /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$HERE/repro.lisp"
    ;;
  sbcl)
    exec "$TIMEOUT_BIN" --kill-after=10s 60s /opt/homebrew/bin/sbcl --script "$HERE/repro.lisp"
    ;;
  *)
    echo "usage: $0 [ccl|sbcl]" >&2
    exit 2
    ;;
esac
