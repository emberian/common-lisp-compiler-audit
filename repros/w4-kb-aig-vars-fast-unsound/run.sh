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
rm -f "$WORK/books/centaur" "$WORK/books/arithmetic" "$WORK/books/kestrel" "$WORK/books/ihs" "$WORK/books/meta"
mkdir -p "$WORK/books/centaur/fty" "$WORK/books/centaur/vl/util" "$WORK/books/centaur/aig" "$WORK/books/kestrel/utilities" "$WORK/books/ihs" "$WORK/books/arithmetic" "$WORK/books/meta"
for entry in "$BOOKS_SRC/centaur"/*; do
  [ "$(basename "$entry")" = "fty" ] || [ "$(basename "$entry")" = "vl" ] || [ "$(basename "$entry")" = "aig" ] && continue
  ln -s "$entry" "$WORK/books/centaur/$(basename "$entry")"
done
for entry in "$BOOKS_SRC/centaur/aig"/*; do
  ln -s "$entry" "$WORK/books/centaur/aig/$(basename "$entry")"
done
rm -f "$WORK/books/centaur/aig/aig-vars-fast.lisp" "$WORK/books/centaur/aig/aig-vars-fast-raw.lsp"
cp "$BOOKS_SRC/centaur/aig/aig-vars-fast.lisp" "$WORK/books/centaur/aig/aig-vars-fast.lisp"
cp "$BOOKS_SRC/centaur/aig/aig-vars-fast-raw.lsp" "$WORK/books/centaur/aig/aig-vars-fast-raw.lsp"

cat > "$WORK/books/meta/pseudo-termp-lemmas.lisp" <<'EOF'
(in-package "ACL2")
(defun pseudo-term-val-alistp (x)
  (declare (xargs :guard t))
  (if (atom x) (eq x nil) (and (consp (car x)) (pseudo-termp (cdar x)) (pseudo-term-val-alistp (cdr x)))))
(defun pseudo-term-substp (x)
  (declare (xargs :guard t))
  (if (atom x) (eq x nil) (and (consp (car x)) (symbolp (caar x)) (pseudo-termp (cdar x)) (pseudo-term-substp (cdr x)))))
EOF
cat > "$WORK/books/ihs/logops-lemmas.lisp" <<'EOF'
(in-package "ACL2")
EOF
cat > "$WORK/books/ihs/quotient-remainder-lemmas.lisp" <<'EOF'
(in-package "ACL2")
EOF

cat > "$WORK/books/arithmetic/top.lisp" <<'EOF'
(in-package "ACL2")
EOF
cat > "$WORK/books/arithmetic/top-with-meta.lisp" <<'EOF'
(in-package "ACL2")
EOF
cat > "$WORK/books/kestrel/utilities/make-termination-theorem.lisp" <<'EOF'
(in-package "ACL2")
EOF
cat > "$WORK/books/ihs/basic-definitions.lisp" <<'EOF'
(in-package "ACL2")
(defun zbp (x) (declare (xargs :guard (bitp x))) (eql x 0))
(defun b-not (i) (declare (type bit i)) (if (eql i 0) 1 0))
(defun b-and (i j) (declare (type bit i j)) (if (and (eql i 1) (eql j 1)) 1 0))
(defun b-ior (i j) (declare (type bit i j)) (if (or (eql i 1) (eql j 1)) 1 0))
(defun b-xor (i j) (declare (type bit i j)) (if (eql i j) 0 1))
(defun b-eqv (i j) (declare (type bit i j)) (if (eql i j) 1 0))
(defun b-nand (i j) (declare (type bit i j)) (b-not (b-and i j)))
(defun b-nor (i j) (declare (type bit i j)) (b-not (b-ior i j)))
(defun b-andc1 (i j) (declare (type bit i j)) (b-and (b-not i) j))
(defun b-andc2 (i j) (declare (type bit i j)) (b-and i (b-not j)))
(defun b-orc1 (i j) (declare (type bit i j)) (b-ior (b-not i) j))
(defun b-orc2 (i j) (declare (type bit i j)) (b-ior i (b-not j)))
(defun b-ite (c i j) (declare (type bit c i j)) (if (eql c 1) i j))
(defun logcar (i) (declare (type integer i)) (if (oddp i) 1 0))
(defun logcdr (i) (declare (type integer i)) (ash i -1))
(defun logcons (b i) (declare (type bit b) (type integer i)) (+ b (* 2 i)))
(defun logite (c i j) (declare (type bit c) (type integer i j)) (if (eql c 1) (ifix i) (ifix j)))
(defun logbit (pos i) (declare (xargs :guard (and (natp pos) (integerp i)))) (if (logbitp pos i) 1 0))
(defun logmask (size) (declare (xargs :guard (natp size))) (1- (expt 2 (nfix size))))
(defun loghead (size i) (declare (xargs :guard (and (natp size) (integerp i)))) (mod (ifix i) (expt 2 (nfix size))))
(defun logtail (pos i) (declare (xargs :guard (and (natp pos) (integerp i)))) (ash (ifix i) (- (nfix pos))))
(defun logapp (size i j) (declare (xargs :guard (and (natp size) (integerp i) (integerp j)))) (+ (loghead size i) (* (ifix j) (expt 2 (nfix size)))))
(defun logext (size i) (declare (xargs :guard (and (posp size) (integerp i)))) (let* ((s (if (posp size) size 1)) (m (loghead s i))) (if (logbitp (1- s) m) (- m (expt 2 s)) m)))
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

assert_has() {
  local pat="$1"
  local file="$2"
  if ! grep -q "$pat" "$file"; then
    echo "MISSING PATTERN: $pat"
    grep -B1 -A5 -m3 "ACL2 Error\|Error:" "$file" || tail -n 30 "$file"
    exit 1
  fi
}

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-aig-vars-fast-unsound on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  assert_has "NIL-PROVED-AVUL-ATOM" "$out"
  assert_has "Q.E.D." "$out"
  assert_has "NIL-PROVED-AVUL-STRINGS" "$out"
  assert_has "\[AVUL-ATOM-RAW: (A)\]" "$out"
  assert_has "\[AVUL-STRINGS-RAW: (\"v\" \"v\")\]" "$out"
  assert_has "\[AIG-BAD-ATOM-CRASH:" "$out"
  grep -E "NIL-PROVED-AVUL-|Q\.E\.D\.|\[AVUL-|\[AIG-BAD-ATOM-CRASH:" "$out" | head -n 12
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-aig-vars-fast-unsound verified on SBCL and CCL"
