#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_BOOKS="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT_BIN="/opt/homebrew/bin/timeout"

TMPDIR_ROOT="$(mktemp -d /tmp/acl2s-repro-1.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

SHADOW_BOOKS="$TMPDIR_ROOT/books"
mkdir -p "$SHADOW_BOOKS"

for d in acl2s xdoc misc data-structures hacking std ordinals tools arithmetic-5 make-event clause-processors system defsort; do
  cp -R "$SRC_BOOKS/$d" "$SHADOW_BOOKS/$d"
done

mkdir -p "$SHADOW_BOOKS/centaur/fty" \
         "$SHADOW_BOOKS/coi/symbol-fns" \
         "$SHADOW_BOOKS/coi/util" \
         "$SHADOW_BOOKS/ihs" \
         "$SHADOW_BOOKS/kestrel/utilities/system"

cat > "$SHADOW_BOOKS/centaur/fty/basetypes.lisp" <<'EOF'
(in-package "FTY")
(defun integerp-fix (x) (declare (xargs :guard t)) (ifix x))
EOF
cat > "$SHADOW_BOOKS/centaur/fty/fixtype.lisp" <<'EOF'
(in-package "FTY")
(defmacro deffixtype (&rest args) (declare (ignore args)) '(value-triple :fty-stub))
(defmacro deffixequiv (&rest args) (declare (ignore args)) '(value-triple :fty-stub))
EOF
cp "$SHADOW_BOOKS/centaur/fty/fixtype.lisp" "$SHADOW_BOOKS/centaur/fty/fixequiv.lisp"

cat > "$SHADOW_BOOKS/coi/symbol-fns/portcullis.acl2" <<'EOF'
(in-package "ACL2")
(defpkg "SYMBOL-FNS" (union-eq *acl2-exports* *common-lisp-symbols-from-main-lisp-package*))
EOF
cat > "$SHADOW_BOOKS/coi/symbol-fns/symbol-fns.lisp" <<'EOF'
(in-package "SYMBOL-FNS")
(defun join-symbols-lst (pkg lst)
  (declare (xargs :mode :logic :guard (symbol-listp lst)) (ignore pkg))
  (if (endp lst) ""
    (concatenate 'string (symbol-name (car lst)) (join-symbols-lst pkg (cdr lst)))))
(defun join-symbols-fn (pkg lst)
  (declare (xargs :mode :logic :guard (and (symbolp pkg) (symbol-listp lst))))
  (intern$ (join-symbols-lst pkg lst) (if (symbolp pkg) (symbol-package-name pkg) "ACL2")))
(defmacro suffix (&rest args) `(join-symbols-fn ,(car args) (list ,@args)))
(defmacro prefix (&rest args) `(let ((xs (list ,@args))) (join-symbols-fn (car (last xs)) xs)))
(defun item-to-numbered-symbol-list-rec (x k)
  (declare (xargs :mode :logic :guard (and (symbolp x) (natp k))))
  (if (zp k) nil
    (cons (intern$ (concatenate 'string (symbol-name x) (coerce (explode-atom k 10) 'string))
                   (if (symbolp x) (symbol-package-name x) "ACL2"))
          (item-to-numbered-symbol-list-rec x (1- k)))))
EOF
cat > "$SHADOW_BOOKS/coi/util/pseudo-translate.lisp" <<'EOF'
(in-package "ACL2")
(program)
(defun pseudo-translate-add-fns (fns-args wrld)
  (if (endp fns-args) wrld
    (let* ((fn (caar fns-args)) (args (cdar fns-args))
           (wrld (putprop fn 'formals args wrld))
           (wrld (putprop fn 'stobjs-in (make-list (len args)) wrld))
           (wrld (putprop fn 'stobjs-out '(nil) wrld)))
      (pseudo-translate-add-fns (cdr fns-args) wrld))))
(defun pseudo-translate (form new-fns-and-args wrld)
  (let ((wrld1 (pseudo-translate-add-fns new-fns-and-args wrld)))
    (translate-cmp form t nil t 'pseudo-translate wrld1 (default-state-vars nil))))
EOF
cat > "$SHADOW_BOOKS/ihs/basic-definitions.lisp" <<'EOF'
(in-package "ACL2")
(defun zbp (x) (declare (xargs :guard t)) (or (not (integerp x)) (= x 0)))
(defun loghead (size i) (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i)))) (mod (ifix i) (expt 2 (nfix size))))
(defun logtail (pos i) (declare (xargs :guard (and (integerp pos) (<= 0 pos) (integerp i)))) (floor (ifix i) (expt 2 (nfix pos))))
(defun logcons (b i) (declare (xargs :guard (and (bitp b) (integerp i)))) (let ((i (ifix i))) (+ (if (= b 1) 1 0) (* 2 i))))
(defthm unsigned-byte-p-loghead (implies (and (integerp size) (<= 0 size) (integerp i)) (unsigned-byte-p size (loghead size i))))
(defthm logcons-type (implies (and (bitp b) (integerp i)) (integerp (logcons b i))) :rule-classes :type-prescription)
(defthm unsigned-byte-p-logcons (implies (and (bitp b) (integerp size) (< 0 size) (unsigned-byte-p (1- size) i)) (unsigned-byte-p size (logcons b i))))
EOF
echo '(in-package "ACL2")' > "$SHADOW_BOOKS/kestrel/utilities/proof-builder-macros.lisp"
echo '(in-package "ACL2")' > "$SHADOW_BOOKS/kestrel/utilities/ubi.lisp"
cat > "$SHADOW_BOOKS/kestrel/utilities/make-termination-theorem.lisp" <<'EOF'
(in-package "ACL2")
(defun make-termination-theorem (fn wrld) (declare (xargs :mode :program) (ignore fn wrld)) 't)
EOF
cat > "$SHADOW_BOOKS/kestrel/utilities/system/terms.lisp" <<'EOF'
(in-package "ACL2")
(include-book "coi/util/pseudo-translate" :dir :system)
(verify-termination body)
(defun filter-program-fns (fns wrld)
  (declare (xargs :mode :program))
  (cond ((endp fns) nil)
        ((eq (symbol-class (car fns) wrld) :program)
         (cons (car fns) (filter-program-fns (cdr fns) wrld)))
        (t (filter-program-fns (cdr fns) wrld))))
(defun all-program-ffn-symbs (term ans wrld)
  (declare (xargs :mode :program))
  (append (filter-program-fns (all-ffn-symbs term nil) wrld) ans))
EOF

run_one() {
  local label="$1"
  local bin="$2"
  local out_file="$TMPDIR_ROOT/out-$label.log"
  echo "=== $label ==="
  ACL2_SYSTEM_BOOKS="$SHADOW_BOOKS" "$TIMEOUT_BIN" --kill-after=10s 120s "$bin" < "$HERE/repro.lisp" > "$out_file" 2>&1 || true
  if grep -q "ABORTING from raw Lisp" "$out_file"; then
    grep -A 6 "ABORTING from raw Lisp" "$out_file" | head -n 10
    echo "PASS ($label reproduced raw Lisp memory fault)"
  else
    echo "FAIL ($label did not trigger raw Lisp abort)"
    tail -n 30 "$out_file"
    exit 1
  fi
}

run_one "SBCL-2.6.10" "$SBCL_ACL2"
run_one "CCL-1.14" "$CCL_ACL2"
