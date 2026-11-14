#!/usr/bin/env bash
# Standalone reproducer for W4-KF-3 (w4-kf-defun-sk-macro-crash):
# 1) `defun-sk-fn` (`other-events.lisp:19260, 19277`) is the macroexpander for
#    `defun-sk`, yet calls `(er hard ctx ...)` directly during macroexpansion on
#    unrecognized/duplicate keywords or non-symbol `:constrain` values (instead
#    of returning `` `(er soft ',ctx ...) `` as lines 19297/19301 do), crashing
#    with `HARD ACL2 ERROR in DEFUN-SK`.
# 2) `defun-sk-fn` (`other-events.lisp:19315-19316, 19374-19377`) collects one
#    element per `xargs` declaration via `fetch-dcl-field` and splices
#    `` `(:stobjs ,@stobjs) `` into the `:constrain t` `encapsulate` signature,
#    producing malformed odd-length `(:stobjs st1 st2)` when multiple `:stobjs`
#    (or `:dfs`) declarations are given — rejecting valid `defun-sk` forms under
#    `:constrain t` that succeed under `:constrain nil`.
set -euo pipefail

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=5s 60s"

TMPDIR_WORK="$(mktemp -d /tmp/w4-kf-defun-sk.XXXXXX)"
cleanup() {
  rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

cat > "$TMPDIR_WORK/repro.lisp" << 'EOF'
(in-package "ACL2")

;; Bug 3a: HARD ACL2 ERROR in DEFUN-SK macroexpander on unrecognized keyword
(defun-sk sk-bad-kw (x)
  (forall y (equal x y))
  :unknown-kw t)

;; Bug 3b: HARD ACL2 ERROR in DEFUN-SK macroexpander on non-symbol :constrain
(defun-sk sk-bad-constrain (x)
  (forall y (equal x y))
  :constrain 123)

;; Bug 3c: Multi-declaration :stobjs succeeds with :constrain nil, fails with :constrain t
(defstobj st1 fld1)
(defstobj st2 fld2)

(defun-sk sk-multi-ok (st1 st2)
  (declare (xargs :stobjs st1)
           (xargs :stobjs st2))
  (forall y (equal y y))
  :constrain nil)

(make-event
  (mv-let (erp val state)
    (defun-sk sk-multi-broken (st1 st2)
      (declare (xargs :stobjs st1)
               (xargs :stobjs st2))
      (forall y (equal y y))
      :constrain t)
    (declare (ignore val))
    (if erp
        (prog2$ (cw "~%W4-KF-3C-MULTI-STOBJS-REJECTED~%")
                (value '(value-triple :reproduced)))
      (value '(value-triple :unexpected-ok)))))
:q
EOF

for entry in "SBCL:$SBCL_ACL2:$TMPDIR_WORK/sbcl.out" "CCL:$CCL_ACL2:$TMPDIR_WORK/ccl.out"; do
  HOST="${entry%%:*}"
  REST="${entry#*:}"
  BIN="${REST%%:*}"
  OUT="${REST#*:}"
  echo "=== [W4-KF-3] Testing on $HOST ($BIN) ==="
  $TIMEOUT "$BIN" < "$TMPDIR_WORK/repro.lisp" > "$OUT" 2>&1
  COUNT_HARD="$(grep -c "HARD ACL2 ERROR in (DEFUN-SK" "$OUT" || true)"
  if [ "$COUNT_HARD" -lt 2 ]; then
    echo "FAIL: expected >=2 HARD ACL2 ERROR in DEFUN-SK on $HOST, got $COUNT_HARD" >&2
    exit 1
  fi
  grep -q "SK-MULTI-OK" "$OUT"
  grep -q "W4-KF-3C-MULTI-STOBJS-REJECTED" "$OUT"
  grep -A 2 "HARD ACL2 ERROR in (DEFUN-SK" "$OUT"
done

echo "PASS: W4-KF-3 (DEFUN-SK macroexpander HARD ACL2 ERRORs + multi-:stobjs :constrain t splice bug) reproduced on SBCL and CCL."
