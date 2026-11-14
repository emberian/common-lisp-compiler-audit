#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-bstar.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books"
for entry in "$BOOKS_SRC"/*; do
  ln -s "$entry" "$WORK/books/$(basename "$entry")"
done

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-bstar-decomp-capture on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  if ! grep -q "\[BSTAR-DECOMP-CAPTURE: (1 (1 \. 2))\]" "$out"; then
    echo "MISSING BSTAR-DECOMP-CAPTURE on $label"
    grep -n -A2 -m5 "ACL2 Error" "$out" || tail -n 30 "$out"
    exit 1
  fi
  local eval_count
  eval_count="$(grep -c "\[ACCESS-RHS-EVAL\]" "$out" || true)"
  if [ "$eval_count" != "2" ]; then
    echo "EXPECTED 2 [ACCESS-RHS-EVAL] lines on $label, got $eval_count"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "\[BSTAR-DECOMP-CAPTURE:|\[ACCESS-RHS-EVAL\]|\[BSTAR-ACCESS-DUP:" "$out"
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-bstar-decomp-capture verified on SBCL and CCL"
