#!/usr/bin/env bash
# Reproducer for Finding 6: Sharp-macro bugs in #u, #f, and #! (acl2-fns.lisp:1440-1571).
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f sharp_in.lsp sub_hpkg.acl2 sub_hpkg.lisp sub_hpkg.cert sub_hpkg.port sub_hpkg.fasl sub_hpkg.*fsl \
        top_hpkg.lisp top_hpkg.cert top_hpkg.port top_hpkg.fasl top_hpkg.*fsl \
        test_preserve.lisp test_eof.lisp test_div0.lisp test_hpkg.lisp ./*.out
}
trap cleanup EXIT
cleanup

cat > test_preserve.lisp <<'EOF'
(in-package "ACL2")
(mv-let (och state) (open-output-channel "sharp_in.lsp" :character state)
  (let* ((state (princ$ "#ub1010" och state))
         (state (close-output-channel och state)))
    (mv-let (ich state) (open-input-channel "sharp_in.lsp" :object state)
      (read-object-with-case ich :preserve state))))
EOF

cat > test_eof.lisp <<'EOF'
(in-package "ACL2")
(mv-let (och state) (open-output-channel "sharp_in.lsp" :character state)
  (let* ((state (princ$ "#uB_" och state))
         (state (close-output-channel och state)))
    (mv-let (ich state) (open-input-channel "sharp_in.lsp" :object state)
      (read-object ich state))))
EOF

cat > test_div0.lisp <<'EOF'
(in-package "ACL2")
(mv-let (och state) (open-output-channel "sharp_in.lsp" :character state)
  (let* ((state (princ$ "#u1_0/0_0" och state))
         (state (close-output-channel och state)))
    (mv-let (ich state) (open-input-channel "sharp_in.lsp" :object state)
      (read-object ich state))))
EOF

cat > sub_hpkg.acl2 <<'EOF'
(defpkg "SECRET-HIDDEN-PKG" '(nil t))
EOF

cat > sub_hpkg.lisp <<'EOF'
(in-package "ACL2")
(defun sub-hpkg-fn () 1)
EOF

cat > top_hpkg.lisp <<'EOF'
(in-package "ACL2")
(local (include-book "sub_hpkg"))
(defun top-hpkg-fn () 2)
EOF

cat > test_hpkg.lisp <<'EOF'
(in-package "ACL2")
(include-book "top_hpkg")
; SECRET-HIDDEN-PKG is a hidden-defpkg: (in-package "SECRET-HIDDEN-PKG") is rejected,
; yet #!SECRET-HIDDEN-PKG succeeds because sharp-bang-read uses raw assoc on known-package-alist:
(mv-let (och state) (open-output-channel "sharp_in.lsp" :character state)
  (let* ((state (princ$ "#!SECRET-HIDDEN-PKG (1 2 3)" och state))
         (state (close-output-channel och state)))
    (mv-let (ich state) (open-input-channel "sharp_in.lsp" :object state)
      (mv-let (eof val state) (read-object ich state)
        (declare (ignore eof))
        (let ((state (close-input-channel ich state)))
          (prog2$
           (cw "@SHARP-HIDDEN-PKG host=~x0 pkg-hidden-flag=~x1 sharp-bang-read=~x2~%"
               (@ host-lisp)
               (cadr (assoc-equal "SECRET-HIDDEN-PKG" (known-package-alist state)))
               val)
           state))))))
EOF

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  lbl="${pair%%:*}"
  bin="${pair#*:}"
  rm -f sub_hpkg.cert sub_hpkg.port sub_hpkg.fasl sub_hpkg.*fsl top_hpkg.cert top_hpkg.port top_hpkg.fasl top_hpkg.*fsl
  echo "=== $lbl ==="
  $TIMEOUT "$bin" < repro.lisp > "silent_${lbl}.out" 2>&1
  grep -a '@SHARP-SILENT' "silent_${lbl}.out"

  $TIMEOUT "$bin" < test_preserve.lisp > "pres_${lbl}.out" 2>&1 || true
  echo -n "  [#ub1010 under :preserve]: "
  grep -a -E 'Failure to read #u|not a numeral' "pres_${lbl}.out" | tr '\n' ' '
  echo ""

  $TIMEOUT "$bin" < test_eof.lisp > "eof_${lbl}.out" 2>&1 || true
  echo -n "  [#uB_ raw Lisp abort]:     "
  grep -a -E 'ABORTING from raw Lisp|Error:' "eof_${lbl}.out" | tr '\n' ' '
  echo ""

  $TIMEOUT "$bin" < test_div0.lisp > "div0_${lbl}.out" 2>&1 || true
  echo -n "  [#u1_0/0_0 raw div0 abort]: "
  grep -a -E 'ABORTING from raw Lisp|Error:' "div0_${lbl}.out" | tr '\n' ' '
  echo ""

  printf '(ld "sub_hpkg.acl2")\n(certify-book "sub_hpkg" 1 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > /dev/null 2>&1
  printf '(certify-book "top_hpkg" 0 t :ttags nil)\n(quit)\n' | $TIMEOUT "$bin" > /dev/null 2>&1
  $TIMEOUT "$bin" < test_hpkg.lisp > "hpkg_${lbl}.out" 2>&1
  grep -a '@SHARP-HIDDEN-PKG' "hpkg_${lbl}.out"
done
