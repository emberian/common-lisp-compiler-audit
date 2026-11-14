#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBCL_BIN="${SBCL_BIN:-sbcl}"
exec "$SBCL_BIN" --noinform --non-interactive --load "$DIR/repro.lisp"
