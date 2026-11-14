#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-plev.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books/tools"
for entry in "$BOOKS_SRC"/*; do
  base="$(basename "$entry")"
  [ "$base" = "tools" ] && continue
  ln -s "$entry" "$WORK/books/$base"
done
for entry in "$BOOKS_SRC/tools"/*; do
  base="$(basename "$entry")"
  [ "$base" = "plev-ccl.lisp" ] || [ "$base" = "plev-ccl-raw.lsp" ] || \
  [ "$base" = "advise.lisp" ] || [ "$base" = "advise-raw.lsp" ] && continue
  ln -s "$entry" "$WORK/books/tools/$base"
done
cp "$BOOKS_SRC/tools/plev-ccl.lisp" "$WORK/books/tools/plev-ccl.lisp"
cp "$BOOKS_SRC/tools/plev-ccl-raw.lsp" "$WORK/books/tools/plev-ccl-raw.lsp"
cp "$BOOKS_SRC/tools/advise.lisp" "$WORK/books/tools/advise.lisp"
cp "$BOOKS_SRC/tools/advise-raw.lsp" "$WORK/books/tools/advise-raw.lsp"

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-plev-advise-oprof-raw on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  if [ "$label" = "CCL" ]; then
    if ! grep -q "\[ADVISEDP-RESULT: NIL\]" "$out"; then
      echo "MISSING [ADVISEDP-RESULT: NIL] on CCL"
      tail -n 30 "$out"
      exit 1
    fi
  else
    if ! grep -q "Raw lisp definition not installed?" "$out"; then
      echo "MISSING Raw lisp definition not installed? on SBCL"
      grep -n -A2 -m5 "ACL2 Error" "$out" || tail -n 30 "$out"
      exit 1
    fi
  fi
  if ! grep -qE "NOT-AN-INTEGER|ABORTING from raw Lisp|Error:" "$out"; then
    echo "MISSING plev printer corruption on $label"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "\[ADVISEDP-RESULT:|Raw lisp definition not installed\?|NOT-AN-INTEGER|ABORTING from raw Lisp|Error:" "$out" | head -n 8
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-plev-advise-oprof-raw verified on SBCL and CCL"
