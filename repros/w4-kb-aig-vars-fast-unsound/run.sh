#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-aig-vars-fast.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books"
for entry in "$BOOKS_SRC"/*; do
  ln -s "$entry" "$WORK/books/$(basename "$entry")"
done
rm "$WORK/books/centaur" "$WORK/books/arithmetic"
rm -f "$WORK/books/kestrel" "$WORK/books/ihs"
mkdir -p "$WORK/books/centaur/fty" "$WORK/books/centaur/vl/util" "$WORK/books/kestrel/utilities" "$WORK/books/ihs" "$WORK/books/arithmetic"
for entry in "$BOOKS_SRC/centaur"/*; do
  [ "$(basename "$entry")" = "fty" ] || [ "$(basename "$entry")" = "vl" ] && continue
  ln -s "$entry" "$WORK/books/centaur/$(basename "$entry")"
done
for entry in "$BOOKS_SRC/arithmetic"/*; do
  ln -s "$entry" "$WORK/books/arithmetic/$(basename "$entry")"
done

cat > "$WORK/books/arithmetic/top-with-meta.lisp" <<'EOF'
(in-package "ACL2")
(include-book "top" :dir :system :uncertified-okp t)
EOF
cat > "$WORK/books/kestrel/utilities/make-termination-theorem.lisp" <<'EOF'
(in-package "ACL2")
EOF
cat > "$WORK/books/ihs/basic-definitions.lisp" <<'EOF'
(in-package "ACL2")
EOF
cat > "$WORK/books/centaur/vl/util/cwtime.lisp" <<'EOF'
(in-package "ACL2")
(defmacro cwtime (form &rest args) (declare (ignore args)) form)
(defmacro xf-cwtime (form &rest args) (declare (ignore args)) form)
EOF
cat > "$WORK/books/centaur/fty/fixequiv.lisp" <<'EOF'
(in-package "ACL2")
(defmacro fty::deffixequiv (&rest args) (declare (ignore args)) '(value-triple :deffixequiv))
(defmacro fty::deffixequiv-mutual (&rest args) (declare (ignore args)) '(value-triple :deffixequiv-mutual))
(defmacro fty::deffixcong (&rest args) (declare (ignore args)) '(value-triple :deffixcong))
(defmacro fty::deffixtype (name &key fix equiv define &allow-other-keys)
  (declare (ignore name))
  (if define
      `(progn (defun ,equiv (x y) (declare (xargs :guard t)) (equal (,fix x) (,fix y)))
              (defequiv ,equiv))
    '(value-triple :deffixtype)))
EOF
cat > "$WORK/books/centaur/fty/fixtype.lisp" <<'EOF'
(in-package "ACL2")
(include-book "centaur/fty/fixequiv" :dir :system :uncertified-okp t)
EOF
cat > "$WORK/books/centaur/fty/basetypes.lisp" <<'EOF'
(in-package "ACL2")
(include-book "centaur/fty/fixtype" :dir :system :uncertified-okp t)
(defun int-equiv (a b) (declare (xargs :guard t)) (equal (ifix a) (ifix b))) (defequiv int-equiv)
(defthm ifix-under-int-equiv (int-equiv (ifix a) a)) (defcong int-equiv equal (ifix a) 1)
(defun nat-equiv (a b) (declare (xargs :guard t)) (equal (nfix a) (nfix b))) (defequiv nat-equiv)
(defthm nfix-under-nat-equiv (nat-equiv (nfix a) a)) (defcong nat-equiv equal (nfix a) 1)
(defun bit-equiv (x y) (declare (xargs :guard t)) (equal (bfix x) (bfix y))) (defequiv bit-equiv)
(defcong bit-equiv equal (bfix x) 1)
EOF

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-aig-vars-fast-unsound on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  grep -q "NIL-PROVED-AVUL-ATOM" "$out"
  grep -q "Q.E.D." "$out"
  grep -q "NIL-PROVED-AVUL-STRINGS" "$out"
  grep -q "\[AVUL-ATOM-RAW: (A)\]" "$out"
  grep -q "\[AVUL-STRINGS-RAW: (\"v\" \"v\")\]" "$out"
  grep -q "\[AIG-BAD-ATOM-CRASH:" "$out"
  grep -q "\[AIGTAB-EMPTY-QUEUE-CRASH:" "$out"
  grep -E "NIL-PROVED-AVUL-|Q\.E\.D\.|\[AVUL-|\[AIG-BAD-ATOM-CRASH:|\[AIGTAB-EMPTY-QUEUE-CRASH:" "$out" | head -n 12
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-aig-vars-fast-unsound verified on SBCL and CCL"
