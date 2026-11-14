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
  echo "=== Running fv-sulfa-eriks-ht-mismatch on $label ==="
  $TIMEOUT "$bin" < repro.lisp > "$out" 2>&1
  if grep -q "FAILED" "$out"; then
    echo "ERROR: FAILED event in $out"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "^ (SULFA-LEMMA-EXEC|SULFA-LEMMA-LOGIC|NIL-PROVED)$" "$out"
  grep -q "^ NIL-PROVED$" "$out"
done

echo "PASS: SULFA eriks-ht-set mismatch proved NIL on SBCL and CCL."
