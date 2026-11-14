#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-sframe.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books"
for entry in "$BOOKS_SRC"/*; do
  ln -s "$entry" "$WORK/books/$(basename "$entry")"
done

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-stobj-frame-v-collision on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  if ! grep -q "ACL2 Error \[Failure\] in ( DEFTHM NTH-MY-STOBJ-OF-SET-SLOT0-V" "$out"; then
    echo "MISSING DEFTHM NTH-MY-STOBJ-OF-SET-SLOT0-V failure on $label"
    grep -n -A2 -m5 "ACL2 Error" "$out" || tail -n 30 "$out"
    exit 1
  fi
  grep -A2 "ACL2 Error \[Failure\] in ( DEFTHM NTH-MY-STOBJ-OF-SET-SLOT0-V" "$out" | head -n 6
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-stobj-frame-v-collision verified on SBCL and CCL"
