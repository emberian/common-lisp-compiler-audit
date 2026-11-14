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

echo "=== Running ACL2_to_Z3.py + Z3 5.4.1 differential check ==="
$TIMEOUT /opt/homebrew/bin/python3 repro.py > py.out 2>&1
cat py.out
for k in equal_nil_0 equal_t_1 lt_nil_t lt_0_t plus_t_minus1_eq_0 negate_t_eq_minus1 reciprocal_t_eq_1 times_nil_nil_eq_nil; do
  grep -q "^${k}: isThm=True$" py.out
done
grep -q "^proved$" py.out

for pair in "SBCL:$SBCL_ACL2:sbcl.out" "CCL:$CCL_ACL2:ccl.out"; do
  IFS=: read -r label bin out <<< "$pair"
  echo "=== Running fv-smtlink-type-coercion on $label ==="
  $TIMEOUT "$bin" > "$out" 2>&1 <<'EOF'
(ld "repro.lisp")
:q
EOF
  if grep -q "FAILED" "$out"; then
    echo "ERROR: FAILED event in $out"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "^ ACL2-TRUTH-ALL-FALSE$|@CHECK" "$out"
  grep -q "^ ACL2-TRUTH-ALL-FALSE$" "$out"
  grep -q "@CHECK smt-interpret(('proved'))=T\|@CHECK smt-interpret('(\"proved\"))=T" "$out"
done

echo "PASS: SMTLink ACL2_to_Z3.py type/truthiness coercion confirmed on Z3 5.4.1, SBCL, and CCL."
