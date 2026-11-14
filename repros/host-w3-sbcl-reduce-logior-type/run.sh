#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
/opt/homebrew/bin/timeout --kill-after=10s 30s "$SBCL_BIN" --script "$DIR/repro.lisp"
