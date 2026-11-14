#!/bin/sh
# Reproduces SBCL 2.6.10 cross-arch equality-constraints.lisp soundness bugs
# at (optimize (speed 1) (safety 3)) under default FPU mode.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TIMEOUT_BIN=/opt/homebrew/bin/timeout
if [ ! -x "$TIMEOUT_BIN" ]; then TIMEOUT_BIN=timeout; fi

case "${1:-sbcl}" in
  sbcl)
    exec "$TIMEOUT_BIN" --kill-after=10s 60s /opt/homebrew/bin/sbcl --script "$HERE/repro.lisp"
    ;;
  hbox)
    exec "$TIMEOUT_BIN" --kill-after=10s 60s ssh hbox \
      '/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh --script' < "$HERE/repro.lisp"
    ;;
  ccl)
    exec "$TIMEOUT_BIN" --kill-after=10s 60s /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$HERE/repro.lisp"
    ;;
  *)
    echo "usage: $0 [sbcl|hbox|ccl]" >&2
    exit 2
    ;;
esac
