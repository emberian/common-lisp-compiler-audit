#!/bin/sh
# Reproduces SBCL 2.6.10 same-arg float derive-type bugs in srctran.lisp
# (bogus full WARNING on truncate/floor/ceiling + NaN/signed-zero misfolding).
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
  *)
    echo "usage: $0 [sbcl|hbox]" >&2
    exit 2
    ;;
esac
