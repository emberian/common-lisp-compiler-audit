#!/usr/bin/env bash
# Standalone reproducer for W4-KF-4 (w4-kf-backtrack-omitted-leak):
# Internal waterfall sentinel `:OMITTED` leaks into user `:backtrack` hints via
# two kernel bugs:
# 1) `translate-hint-expression` (`history-management.lisp:16556-16591`) ignores
#    `hint-type = 'backtrack` for 4-arg and 7-arg function-symbol hints, binding
#    `stable-under-simplificationp` even though `process-backtrack-hint`
#    (`prove.lisp:3894`) passes `:OMITTED ; unused in :backtrack hints`.
# 2) When a `:backtrack` hint returns `(:computed-hint-replacement t ...)` or a
#    replacement list mentioning `clause-list`/`processor`, `process-backtrack-hint`
#    (`prove.lisp:3905`), `eval-and-translate-hint-expression`
#    (`history-management.lisp:17720-17724`), and `waterfall0`
#    (`prove.lisp:6329-6342`) remove `:backtrack` from `pspv` and splice the
#    `'backtrack`-translated hint directly into top-of-waterfall `hints`, where
#    `find-applicable-hint-settings1` (`prove.lisp:4729-4731`) evaluates it on
#    subsequent subgoals with `clause-list = :OMITTED` and `processor = :OMITTED`!
set -euo pipefail

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=5s 60s"

TMPDIR_WORK="$(mktemp -d /tmp/w4-kf-bt-omitted.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

cat > "$TMPDIR_WORK/repro.lisp" << 'EOF'
(in-package "ACL2")

(defun p1 (x) (equal x 1))
(defun p2 (x) (equal x 2))
(in-theory (disable p1 p2))

;; Bug 4a: 4-arg symbol hint in :backtrack receives :OMITTED for stable-under-simplificationp
(defun bt4 (id clause world stable-under-simplificationp)
  (declare (xargs :guard (booleanp stable-under-simplificationp))
           (ignore id clause world))
  (prog2$ (cw "~%[W4-KF-4A] sus=~x0~%" stable-under-simplificationp)
          (if stable-under-simplificationp
              nil ; Dead-blocks! Because :OMITTED is truthy!
            '(:in-theory (enable p1)))))

(thm (implies (p1 x) (equal x 1))
  :hints (("Goal" :backtrack bt4)))

;; Bug 4b: :computed-hint-replacement t splices :backtrack hint into top-of-waterfall hints,
;; passing clause-list=:OMITTED and processor=:OMITTED and violating (true-listp clause-list)!
(defun chk-cl (cl)
  (declare (xargs :guard (true-listp cl)))
  (len cl))

(thm (and (implies (p1 x) (equal x 1))
          (implies (p2 y) (equal y 2)))
  :hints (("Goal" :backtrack
           (prog2$ (cw "~%[W4-KF-4B] cl=~x0 proc=~x1~%" clause-list processor)
                   (let ((n (with-guard-checking :all (chk-cl clause-list))))
                     (if (zp n)
                         '(:in-theory (enable p2))
                       '(:computed-hint-replacement t :in-theory (enable p1))))))))
:q
EOF

for entry in "SBCL:$SBCL_ACL2:$TMPDIR_WORK/sbcl.out" "CCL:$CCL_ACL2:$TMPDIR_WORK/ccl.out"; do
  HOST="${entry%%:*}"
  REST="${entry#*:}"
  BIN="${REST%%:*}"
  OUT="${REST#*:}"
  echo "=== [W4-KF-4] Testing on $HOST ($BIN) ==="
  $TIMEOUT "$BIN" < "$TMPDIR_WORK/repro.lisp" > "$OUT" 2>&1
  grep -q "\\[W4-KF-4A\\] sus=:OMITTED" "$OUT"
  grep -q "\\[W4-KF-4B\\] cl=:OMITTED proc=:OMITTED" "$OUT"
  grep -q "violated by the arguments in the" "$OUT"
  grep -q "(CHK-CL :OMITTED)" "$OUT"
  grep "\\[W4-KF-4" "$OUT"
done

echo "PASS: W4-KF-4 (:OMITTED sentinel leak in :backtrack 4-arg symbol hints & :computed-hint-replacement promotion) reproduced on SBCL and CCL."
