#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-2darr.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books/ihs" "$WORK/books/arithmetic" "$WORK/books/std/basic" "$WORK/books/std/strings" "$WORK/books/xdoc" "$WORK/books/kestrel/utilities"
for entry in "$BOOKS_SRC"/*; do
  base="$(basename "$entry")"
  [ "$base" = "ihs" ] || [ "$base" = "arithmetic" ] || [ "$base" = "std" ] || [ "$base" = "xdoc" ] || [ "$base" = "kestrel" ] && continue
  ln -s "$entry" "$WORK/books/$base"
done
for entry in "$BOOKS_SRC/xdoc"/*; do
  base="$(basename "$entry")"
  [ "$base" = "str.lisp" ] && continue
  ln -s "$entry" "$WORK/books/xdoc/$base"
done
for entry in "$BOOKS_SRC/std"/*; do
  base="$(basename "$entry")"
  [ "$base" = "basic" ] || [ "$base" = "strings" ] && continue
  ln -s "$entry" "$WORK/books/std/$base"
done
for entry in "$BOOKS_SRC/std/basic"/*; do
  base="$(basename "$entry")"
  [ "$base" = "arith-equivs.lisp" ] && continue
  ln -s "$entry" "$WORK/books/std/basic/$base"
done
for entry in "$BOOKS_SRC/std/strings"/*; do
  base="$(basename "$entry")"
  [ "$base" = "substrp.lisp" ] || [ "$base" = "strsubst.lisp" ] && continue
  ln -s "$entry" "$WORK/books/std/strings/$base"
done
printf '(in-package "ACL2")\n' > "$WORK/books/kestrel/utilities/make-termination-theorem.lisp"
printf '(in-package "ACL2")\n' > "$WORK/books/ihs/quotient-remainder-lemmas.lisp"
printf '(in-package "ACL2")\n' > "$WORK/books/arithmetic/top-with-meta.lisp"
cat > "$WORK/books/std/basic/arith-equivs.lisp" <<'EOF'
(in-package "ACL2")
(include-book "tools/rulesets" :dir :system)
(include-book "std/lists/list-fix" :dir :system)
(include-book "std/lists/mfc-utils" :dir :system)
(def-ruleset arith-equiv-forwarding nil)
(defun nat-equiv (x y)
  (declare (xargs :guard t))
  (equal (nfix x) (nfix y)))
(defequiv nat-equiv)
EOF
cat > "$WORK/books/std/strings/substrp.lisp" <<'EOF'
(in-package "STR")
(defun substrp (x y)
  (declare (xargs :mode :logic :guard t))
  (if (and (stringp x) (stringp y) (search x y)) t nil))
EOF
cat > "$WORK/books/xdoc/str.lisp" <<'EOF'
(in-package "XDOC")
(defmacro str::cat (&rest args) (declare (ignore args)) "")
EOF
cat > "$WORK/books/std/strings/strsubst.lisp" <<'EOF'
(in-package "STR")
(defun strsubst (old new x)
  (declare (xargs :mode :logic :guard t :measure (if (stringp x) (length x) 0)))
  (let ((pos (if (and (stringp old) (stringp x)) (search old x) nil)))
    (if (or (not (stringp x)) (not (stringp old)) (not (stringp new))
            (zp (length old)) (not (natp pos)) (>= pos (length x)))
        x
      (string-append (subseq x 0 pos)
                     (string-append new
                                    (strsubst old new (subseq x (+ pos (length old)) nil)))))))
EOF

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-2d-arr-ec-call-crash on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  if ! grep -q "ANY2D-RESIZE-ROWS\$G" "$out"; then
    echo "MISSING ANY2D-RESIZE-ROWS\$G error on $label"
    grep -n -A2 -m5 "ACL2 Error" "$out" || tail -n 30 "$out"
    exit 1
  fi
  grep -A3 "ANY2D-RESIZE-ROWS\$G" "$out" | head -n 6
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-2d-arr-ec-call-crash verified on SBCL and CCL"
