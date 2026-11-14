#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f injected.py py.out sbcl.out ccl.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2:sbcl.out" "CCL:$CCL_ACL2:ccl.out"; do
  IFS=: read -r label bin out <<< "$pair"
  echo "=== Running fv-smtlink-python-injection-spoof on $label ==="
  $TIMEOUT "$bin" > "$out" 2>&1 <<'EOF'
(ld "repro.lisp")
:q
EOF
  if grep -q "^\*\*\*\*\*\*\*\* FAILED \*\*\*\*\*\*\*\*$" "$out"; then
    echo "ERROR: FAILED event in $out"
    tail -n 30 "$out"
    exit 1
  fi
  test -f injected.py
  $TIMEOUT /opt/homebrew/bin/python3 injected.py > py.out
  first_line=$(head -n 1 py.out)
  test "$first_line" = "proved"
  $TIMEOUT "$bin" >> "$out" 2>&1 <<EOF
(ld "repro.lisp")
(value-triple (cw "~%@INTERP ~x0~%" (smt-interpret-lines '("$first_line"))))
:q
EOF
  grep -q "@INTERP T" "$out"
  echo "$label -> injected Python printed '$first_line' and SMT-interpret returned T (False bypassed)."
done

echo "PASS: SMTLink Python injection + 'proved' spoofing confirmed on SBCL and CCL."
