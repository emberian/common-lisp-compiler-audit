#!/usr/bin/env bash
# Standalone reproducer for kernel-elided-defconst-wrapper-desync:
# `hcomp-elided-defconst-alist2` (`other-events.lisp:12181-12204`) and
# `subst-by-position-eliding-defconst2` (`other-events.lisp:15093-15115`)
# desync on `with-output`, `with-prover-step-limit`, and `with-guard-checking-event`:
#   1) `with-output` / `with-prover-step-limit` call `hcomp-elided-defconst-alist2-lst`
#      (expecting a list of forms) on a single form, missing the elided `defconst`.
#   2) `hcomp-elided-defconst-alist2` matches `with-guard-checking-event` while
#      `subst-by-position-eliding-defconst2` matches `with-guard-checking`.
# Result: `include-book ... :load-compiled-file t` aborts with a raw Lisp error
# in `acl2::elided-defconst` (`acl2.lisp:1006-1016`) and `HARD ACL2 ERROR`.
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f book.cert book.port book.fasl book.dx64fsl book.da64fsl sbcl-cert.out sbcl-inc.out ccl-cert.out ccl-inc.out
}
trap cleanup EXIT

for label_bin in "SBCL:$SBCL_ACL2" "CCL:$CCL_ACL2"; do
  label="${label_bin%%:*}"
  bin="${label_bin#*:}"
  cleanup
  echo "=== Running kernel-elided-defconst-wrapper-desync on $label ==="
  $TIMEOUT "$bin" > "$(echo "$label" | tr A-Z a-z)-cert.out" 2>&1 <<'EOF'
(certify-book "book" 0 t)
EOF
  test -f book.cert
  $TIMEOUT "$bin" > "$(echo "$label" | tr A-Z a-z)-inc.out" 2>&1 <<'EOF'
(include-book "book" :load-compiled-file t)
EOF
  inc_out="$(echo "$label" | tr A-Z a-z)-inc.out"
  grep -q "An unexpected error was encountered when trying to obtain a" "$inc_out"
  grep -q "HARD ACL2 ERROR in ( INCLUDE-BOOK" "$inc_out"
  grep -E "value for the constant|HARD ACL2 ERROR in \( INCLUDE-BOOK" "$inc_out"
done

echo "PASS: elided-defconst wrapper desync raw Lisp error + HARD ACL2 ERROR verified on SBCL and CCL."
