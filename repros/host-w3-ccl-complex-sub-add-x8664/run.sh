#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-hbox}" in
  hbox)
    ssh -o BatchMode=yes hbox 'timeout 30s /home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64 --batch --no-init' < "$DIR/repro.lisp"
    ;;
  ccl)
    /opt/homebrew/bin/timeout --kill-after=10s 30s /Users/ember/dev/ccl/darm64cl --batch --no-init --load "$DIR/repro.lisp"
    ;;
  sbcl)
    /opt/homebrew/bin/timeout --kill-after=10s 30s /opt/homebrew/bin/sbcl --script "$DIR/repro.lisp"
    ;;
  *)
    echo "usage: $0 [hbox|ccl|sbcl]" >&2
    exit 2
    ;;
esac
