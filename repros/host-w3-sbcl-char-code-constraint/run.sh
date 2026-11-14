#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SBCL_BIN="${SBCL_BIN:-/opt/homebrew/bin/sbcl}"
ACL2_BIN="${ACL2_BIN:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"

echo "=== 1. Running Common Lisp repro on $SBCL_BIN ==="
/opt/homebrew/bin/timeout --kill-after=10s 30s "$SBCL_BIN" --script "$DIR/repro.lisp" || true

if [[ -x "$ACL2_BIN" ]]; then
  echo "=== 2. Running guard-verified ACL2 nil-proved check ==="
  /opt/homebrew/bin/timeout --kill-after=10s 30s "$ACL2_BIN" < "$DIR/acl2-nil-proved.lisp"
fi
