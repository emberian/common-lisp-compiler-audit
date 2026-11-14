#!/usr/bin/env bash
# Standalone reproducer for W4-KF-2 (w4-kf-term-thm-fmt0):
# `translate-lmi` (`history-management.lisp:14873-14881`) omits the `(msg ...)`
# wrapper around the `~@1` sub-message when reporting an out-of-clique function
# symbol in `(:termination-theorem fn substn)`, passing the raw format string as
# `~@1` and shifting `lmi` into `#\1`. When `fmt0` splice-formats `~@1`, the
# nested `~&1` directive receives the format string instead of a true-list of
# symbols and crashes with `HARD ACL2 ERROR in FMT0: Illegal Fmt Syntax`.
set -euo pipefail

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=5s 60s"

TMPDIR_WORK="$(mktemp -d /tmp/w4-kf-term-fmt0.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

cat > "$TMPDIR_WORK/repro.lisp" << 'EOF'
(in-package "ACL2")

(defun target-rec (x)
  (if (consp x) (target-rec (cdr x)) 0))

(defun other-fn1 (x) x)
(defun other-fn2 (x) x)

(thm nil
  :hints (("Goal" :use ((:termination-theorem target-rec
                          ((other-fn1 other-fn2)))))))
:q
EOF

echo "=== [W4-KF-2] Testing on SBCL ($SBCL_ACL2) ==="
$TIMEOUT "$SBCL_ACL2" < "$TMPDIR_WORK/repro.lisp" > "$TMPDIR_WORK/sbcl.out" 2>&1
grep -q "HARD ACL2 ERROR in FMT0" "$TMPDIR_WORK/sbcl.out"
grep -q "Illegal Fmt Syntax" "$TMPDIR_WORK/sbcl.out"
grep -A 3 "HARD ACL2 ERROR in FMT0" "$TMPDIR_WORK/sbcl.out"

echo "=== [W4-KF-2] Testing on CCL ($CCL_ACL2) ==="
$TIMEOUT "$CCL_ACL2" < "$TMPDIR_WORK/repro.lisp" > "$TMPDIR_WORK/ccl.out" 2>&1
grep -q "HARD ACL2 ERROR in FMT0" "$TMPDIR_WORK/ccl.out"
grep -q "Illegal Fmt Syntax" "$TMPDIR_WORK/ccl.out"
grep -A 3 "HARD ACL2 ERROR in FMT0" "$TMPDIR_WORK/ccl.out"

echo "PASS: W4-KF-2 (HARD ACL2 ERROR in FMT0 in :termination-theorem error handler) reproduced on SBCL and CCL."
