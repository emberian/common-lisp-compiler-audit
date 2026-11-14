#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-fcm.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books"
for entry in "$BOOKS_SRC"/*; do
  ln -s "$entry" "$WORK/books/$(basename "$entry")"
done
rm "$WORK/books/centaur"
mkdir -p "$WORK/books/centaur/vl/util"
for entry in "$BOOKS_SRC/centaur"/*; do
  [ "$(basename "$entry")" = "vl" ] && continue
  ln -s "$entry" "$WORK/books/centaur/$(basename "$entry")"
done
cat > "$WORK/books/centaur/vl/util/cwtime.lisp" <<'EOF'
(in-package "ACL2")
(defmacro cwtime (form &rest args) (declare (ignore args)) form)
(defmacro xf-cwtime (form &rest args) (declare (ignore args)) form)
EOF

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-fast-cons-memo-nesting on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  grep -q "\[FCM-AFTER-NESTED: (:SMASHED-MEMO FCM-MARKER)\]" "$out"
  grep "\[FCM-AFTER-NESTED:" "$out"
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-fast-cons-memo-nesting verified on SBCL and CCL"
