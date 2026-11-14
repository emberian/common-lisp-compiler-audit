#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-tmc.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books/kestrel/utilities" "$WORK/books/centaur/fty"
for entry in "$BOOKS_SRC"/*; do
  base="$(basename "$entry")"
  [ "$base" = "kestrel" ] || [ "$base" = "centaur" ] && continue
  ln -s "$entry" "$WORK/books/$base"
done
for entry in "$BOOKS_SRC/centaur"/*; do
  base="$(basename "$entry")"
  [ "$base" = "fty" ] && continue
  ln -s "$entry" "$WORK/books/centaur/$base"
done
printf '(in-package "ACL2")\n' > "$WORK/books/kestrel/utilities/make-termination-theorem.lisp"
printf '(in-package "ACL2")\n' > "$WORK/books/centaur/fty/basetypes.lisp"
cat > "$WORK/books/centaur/fty/fixtype.lisp" <<'EOF'
(in-package "FTY")
(defmacro deffixtype (&rest args) (declare (ignore args)) '(value-triple :stub))
(defmacro deffixequiv (&rest args) (declare (ignore args)) '(value-triple :stub))
(defmacro deffixcong (&rest args) (declare (ignore args)) '(value-triple :stub))
EOF

assert_has() {
  local pat="$1"
  local file="$2"
  local label="$3"
  if ! grep -q "$pat" "$file"; then
    echo "MISSING PATTERN on $label: $pat"
    grep -n -A2 -m8 "ACL2 Error" "$file" || tail -n 30 "$file"
    exit 1
  fi
}

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-tools-macro-contracts on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  assert_has "IMPL-ST\$GUARD-VERIFIED" "$out" "$label"
  assert_has "DEFUN STR-ENUM-P" "$out" "$label"
  assert_has "RETURN-TYPE-OF-BAD-DEFAULT-FIX" "$out" "$label"
  assert_has "REWRITE\$-TRANSLATE-HINTS-FN" "$out" "$label"
  assert_has "DEFTHM NEW-THM" "$out" "$label"
  echo "[$label] All 5 contract/macro bugs observed."
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-tools-macro-contracts verified on SBCL and CCL"
