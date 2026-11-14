#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f py.out sbcl.out ccl.out
}
trap cleanup EXIT
cleanup

echo "=== Verifying Z3 proves collapsed variable collision ==="
$TIMEOUT /opt/homebrew/bin/python3 - <<'PY' > py.out 2>&1
import sys
sys.path.insert(0, "/Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/z3_interface")
from z3 import *
from ACL2_to_Z3 import ACL22SMT
_SMT_ = ACL22SMT()
# Both |x| and X translate to Python variable `x`, and both 'FOO and 'BAR translate to `gensym_0`
x = _SMT_.Const('x', _SMT_.IntSort())
gensym_0 = _SMT_.Symbol().intern('gensym_0')
r1 = _SMT_.prove(_SMT_.equal(x, x))
r2 = _SMT_.prove(_SMT_.equal(gensym_0, gensym_0))
assert r1.isThm() and r2.isThm()
print("proved")
PY
grep -q "^proved$" py.out

for pair in "SBCL:$SBCL_ACL2:sbcl.out" "CCL:$CCL_ACL2:ccl.out"; do
  IFS=: read -r label bin out <<< "$pair"
  echo "=== Running fv-smtlink-symbol-collision-and-index on $label ==="
  $TIMEOUT "$bin" > "$out" 2>&1 <<'EOF'
(ld "repro.lisp")
:q
EOF
  if grep -q "FAILED" "$out"; then
    echo "ERROR: FAILED event in $out"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "^ (CASE-AND-PKG-COLLISIONS|QUOTED-SYMBOL-INDEX-COLLISION)$" "$out"
  grep -q "^ CASE-AND-PKG-COLLISIONS$" "$out"
  grep -q "^ QUOTED-SYMBOL-INDEX-COLLISION$" "$out"
done

echo "PASS: SMTLink symbol collisions and symbol-index bug confirmed on Z3, SBCL, and CCL."
