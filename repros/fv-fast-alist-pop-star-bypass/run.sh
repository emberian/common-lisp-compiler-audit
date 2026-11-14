#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
BOOKS_DIR="/Users/ember/dev/acl2-fix/head-worktree/books"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f sbcl.out ccl.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2:sbcl.out" "CCL:$CCL_ACL2:ccl.out"; do
  IFS=: read -r label bin out <<< "$pair"
  echo "=== Running fv-fast-alist-pop-star-bypass on $label ==="
  ACL2_SYSTEM_BOOKS="$BOOKS_DIR" $TIMEOUT "$bin" > "$out" 2>&1 <<'EOF'
(ld "std/package.lsp" :dir :system)
(ld "repro.lisp")
:q
EOF
  if grep -q "^\*\*\*\*\*\*\*\* FAILED \*\*\*\*\*\*\*\*$" "$out"; then
    echo "ERROR: FAILED event in $out"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "@CHECK|^ NIL-PROVED$" "$out"
  grep -q "@CHECK fast-alist-pop-inv=FAST-ALIST-POP fast-alist-pop\*-inv=NIL" "$out"
  grep -q "^ NIL-PROVED$" "$out"
done

echo "PASS: fast-alist-pop* invariant-risk bypass proved NIL on SBCL and CCL."
