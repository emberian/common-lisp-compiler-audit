#!/usr/bin/env bash
# Reproducer for Fast-Alist Deserialization Bugs (Finding 4 & Finding 5):
#   Bug A: Valid `(make-fast-alist '(only-atom-1 only-atom-2))` aborts in raw Lisp under
#          `(serialize-read ... :hons-mode :never)` and `#Y` (`print-object$` + `read-object`).
#   Bug B: Valid `(make-fast-alist (hons-copy '((a . 1))))` drops into raw Lisp `BREAK$-RAW`
#          on `serialize-read` under ACL2's default `slow-alist-action` (`:break`).
#   Bug C: Untrusted V3 `.sao` (:ttags nil) corrupts Hons `faltable` invariants (binding atom
#          `T` and leaving `slot1` with `key=NIL, val=#<HASH-TABLE>`) and triggers raw error on
#          bignum `count`.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f atom_fal.sao atom_fal_y.lsp normed_fal.sao bad_fal_t.sao bad_fal_nil.sao \
        sharp_y_test.lisp b_break.lisp c_inv.lisp ./*.out
}
trap cleanup EXIT
cleanup

cat > sharp_y_test.lisp <<'EOF'
(in-package "ACL2")
(with-serialize-character
 #\Y
 (mv-let (ch state)
   (open-output-channel "atom_fal_y.lsp" :object state)
   (let* ((fal (make-fast-alist '(only-atom-1 only-atom-2)))
          (state (print-object$ fal ch state))
          (state (close-output-channel ch state)))
     (mv-let (ich state)
       (open-input-channel "atom_fal_y.lsp" :object state)
       (mv-let (eof val state)
         (read-object ich state)
         (declare (ignore eof))
         (let ((state (close-input-channel ich state)))
           (value val)))))))
EOF

cat > b_break.lisp <<'EOF'
(in-package "ACL2")
(let* ((x (make-fast-alist (hons-copy '((a . 1) (b . 2)))))
       (state (serialize-write "normed_fal.sao" x)))
  (serialize-read "normed_fal.sao"))
EOF

python3 - <<'PY'
# V3 stream with size/idx=1 (arr[1]=T) and FAL entry (index=1, count=5) -> binds atom T in faltable!
with open("bad_fal_t.sao", "wb") as f:
    f.write(bytes([0xAC, 0x12, 0x0B, 0xC9, 1, 0,0,0,0,0,0,0, 1, 5, 0, 0xAC, 0x12, 0x0B, 0xC9]))
# V3 stream with size/idx=2, arr[2]=ACL2::NIL=NIL, FAL entry (index=2, count=5) -> slot1 key=NIL, val=HT!
with open("bad_fal_nil.sao", "wb") as f:
    f.write(bytes([
        0xAC, 0x12, 0x0B, 0xC9,
        2,
        0, 0, 0, 0, 0,
        1, 8, *b"ACL2", 1, 6, *b"NIL",
        0,
        2, 5, 0,
        0xAC, 0x12, 0x0B, 0xC9,
    ]))
PY

cat > c_inv.lisp <<'EOF'
(in-package "ACL2")
(set-slow-alist-action :warning)
:q
(#+sbcl sb-ext:without-package-locks #-sbcl progn
  (serialize-read-fn "bad_fal_t.sao" :smart nil *the-live-state*)
  (let ((s1 (hl-faltable-slot1 (hl-hspace-faltable *default-hs*))))
    (format t "@FAL-CORRUPT-ATOM slot1-key=~s atomp=~s slot1-has-ht=~s~%"
            (hl-falslot-key s1) (atom (hl-falslot-key s1)) (not (null (hl-falslot-val s1)))))
  (serialize-read-fn "bad_fal_nil.sao" :smart nil *the-live-state*)
  (let ((s2 (hl-faltable-slot2 (hl-hspace-faltable *default-hs*))))
    (format t "@FAL-CORRUPT-NIL  slot2-key=~s slot2-has-ht=~s~%"
            (hl-falslot-key s2) (not (null (hl-falslot-val s2))))))
(quit)
EOF

for pair in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  lbl="${pair%%:*}"
  bin="${pair#*:}"
  echo "=== $lbl ==="
  $TIMEOUT "$bin" < repro.lisp > "a1_${lbl}.out" 2>&1 || true
  grep -a -E '@FAL-SMART-OK|magic number incorrect' "a1_${lbl}.out"

  $TIMEOUT "$bin" < sharp_y_test.lisp > "a2_${lbl}.out" 2>&1 || true
  echo -n "  [#Y read-object]: "
  grep -a -o 'Invalid serialized object, magic number incorrect: [^"]*' "a2_${lbl}.out" | head -n 1

  $TIMEOUT "$bin" < b_break.lisp > "b_${lbl}.out" 2>&1 || true
  echo -n "  [normed-spine FAL]: "
  grep -a -E 'Fast alist stolen by HL-HSPACE-RESTORE-FAL-FOR-SERIALIZE|BREAK\$-RAW' "b_${lbl}.out" | tr '\n' ' '
  echo ""

  $TIMEOUT "$bin" < c_inv.lisp > "c_${lbl}.out" 2>&1 || true
  grep -a '@FAL-CORRUPT' "c_${lbl}.out"
done
