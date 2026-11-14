#!/usr/bin/env bash
# Standalone reproducer for W4-KF-1 (w4-kf-term-thm-capture):
# `translate-lmi` (`history-management.lisp:14864-14872`) accepts a functional
# substitution `substn` in `(:termination-theorem fn substn)` (including
# pseudo-lambdas with free variables via `symbol-doublet-listp` +
# `translate-functional-substitution@par`), then passes the resulting alist
# straight to `sublis-fn-simple` (`history-management.lisp:11503-11511`) without
# checking for bound-variable capture (unlike `translate-lmi/functional-instance`
# at `12418-12450`). When `fn` has `:ruler-extenders :all` (or `:lambdas`) and a
# `let`-bound variable `v` governs a recursive call, substituting
# `(fn (lambda (z) v))` captures `v` and crashes with `HARD ACL2 ERROR in ASSERT$`.
set -euo pipefail

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=5s 60s"

TMPDIR_WORK="$(mktemp -d /tmp/w4-kf-term-capture.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

cat > "$TMPDIR_WORK/repro.lisp" << 'EOF'
(in-package "ACL2")

(defun rec-let (x)
  (declare (xargs :ruler-extenders :all))
  (if (consp x)
      (if (let ((v (car x)))
            (if v (rec-let (cdr x)) t))
          (rec-let (cdr x))
        0)
    0))

(thm nil
  :hints (("Goal" :use ((:termination-theorem rec-let
                          ((rec-let (lambda (z) (if z v nil)))))))))
:q
EOF

echo "=== [W4-KF-1] Testing on SBCL ($SBCL_ACL2) ==="
$TIMEOUT "$SBCL_ACL2" < "$TMPDIR_WORK/repro.lisp" > "$TMPDIR_WORK/sbcl.out" 2>&1
grep -q "HARD ACL2 ERROR in ASSERT\\$" "$TMPDIR_WORK/sbcl.out"
grep -A 2 "HARD ACL2 ERROR in ASSERT\\$" "$TMPDIR_WORK/sbcl.out"

echo "=== [W4-KF-1] Testing on CCL ($CCL_ACL2) ==="
$TIMEOUT "$CCL_ACL2" < "$TMPDIR_WORK/repro.lisp" > "$TMPDIR_WORK/ccl.out" 2>&1
grep -q "HARD ACL2 ERROR in ASSERT\\$" "$TMPDIR_WORK/ccl.out"
grep -A 2 "HARD ACL2 ERROR in ASSERT\\$" "$TMPDIR_WORK/ccl.out"

echo "PASS: W4-KF-1 (HARD ACL2 ERROR in ASSERT$ via :termination-theorem capture) reproduced on SBCL and CCL."
