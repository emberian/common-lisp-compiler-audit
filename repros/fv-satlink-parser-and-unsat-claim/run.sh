#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SBCL_ACL2="${1:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
CCL_ACL2="${2:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}"
TIMEOUT="/opt/homebrew/bin/timeout --kill-after=10s 120s"

cleanup() {
  rm -f sbcl.out ccl.out
}
trap cleanup EXIT
cleanup

for pair in "SBCL:$SBCL_ACL2:sbcl.out" "CCL:$CCL_ACL2:ccl.out"; do
  IFS=: read -r label bin out <<< "$pair"
  echo "=== Running fv-satlink-parser-and-unsat-claim on $label ==="
  $TIMEOUT "$bin" > "$out" 2>&1 <<'EOF'
(ld "repro.lisp")
:q
EOF
  if grep -q "^\*\*\*\*\*\*\*\* FAILED \*\*\*\*\*\*\*\*$" "$out"; then
    echo "ERROR: FAILED event in $out"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "^ PARSER-AND-EXITCODE-BUGS$|@CHECK" "$out"
  grep -q "^ PARSER-AND-EXITCODE-BUGS$" "$out"
  grep -q "@CHECK corrupted-prefix=:UNSAT segfault-139=:UNSAT" "$out"
done

echo "PASS: SATlink parser prefix & exit-code gaps confirmed on SBCL and CCL."
