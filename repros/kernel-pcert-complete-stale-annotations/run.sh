#!/usr/bin/env bash
# Standalone reproducer for kernel-pcert-complete-stale-annotations:
# `certify-book-finish-complete` -> `include-book-alist-uncertified-books`
# (`other-events.lisp:16180-16207, 16307-16370`) only checks file-write-dates
# before renaming `.pcert1` -> `.cert`. If `sub1` (unchanged `.lisp` mtime,
# e.g. reading `payload.lsp` via `make-event`) is re-certified with
# `:skip-proofs-okp t` (or `:defaxioms-okp t` / `:ttags :all`) after `top`
# created `top.pcert1`, `(certify-book "top" 0 nil :pcert :complete)` promotes
# `top.pcert1` to `top.cert` without checking sub1's cert annotations or hash.
# Moreover, when `sub1` was included locally, `(include-book "top" :ttags nil)`
# loads `top.cert` cleanly with `skip-proofs-seen = NIL` and no warning.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f payload.lsp sub1.cert sub1.port top.cert top.port top.pcert0 top.pcert1 \
        *.fasl *.dx64fsl *.da64fsl sbcl-*.out ccl-*.out
}
trap cleanup EXIT

for label_bin in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  label="${label_bin%%:*}"
  bin="${label_bin#*:}"
  tag="$(echo "$label" | tr A-Z a-z)"
  cleanup
  echo "=== Running kernel-pcert-complete-stale-annotations on $label ==="

  printf '(defun sub1-ok (x) x)\n' > payload.lsp
  $TIMEOUT "$bin" > "${tag}-1.out" 2>&1 <<'EOF'
(certify-book "sub1" 0 nil)
EOF
  $TIMEOUT "$bin" > "${tag}-2a.out" 2>&1 <<'EOF'
(certify-book "top" 0 nil :pcert :create)
EOF
  $TIMEOUT "$bin" > "${tag}-2b.out" 2>&1 <<'EOF'
(certify-book "top" 0 nil :pcert :convert)
EOF
  test -f top.pcert1

  sleep 1
  printf '(skip-proofs (defthm bogus nil :rule-classes nil))\n' > payload.lsp
  $TIMEOUT "$bin" > "${tag}-3.out" 2>&1 <<'EOF'
(certify-book "sub1" 0 nil :skip-proofs-okp t)
EOF
  $TIMEOUT "$bin" > "${tag}-4.out" 2>&1 <<'EOF'
(certify-book "top" 0 nil :pcert :complete)
EOF
  test -f top.cert

  $TIMEOUT "$bin" > "${tag}-5.out" 2>&1 <<'EOF'
(include-book "top" :ttags nil)
(cw "CHECK ttag=~x0 ttags-seen=~x1 skip=~x2~%"
    (ttag (w state))
    (global-val 'ttags-seen (w state))
    (global-val 'skip-proofs-seen (w state)))
EOF
  grep -q "CHECK ttag=NIL ttags-seen=NIL skip=NIL" "${tag}-5.out"
  grep "CHECK ttag=" "${tag}-5.out"
  echo "[$label] top.cert created despite stale :skip-proofs-okp sub1.cert; clean load verified."
done

echo "PASS: pcert :complete stale sub-book certificate promotion verified on SBCL and CCL."
