#!/usr/bin/env bash
# Usage: run.sh [head|ccl] (default both)
set -euo pipefail
cd "$(dirname "$0")"
for h in ${1:-head ccl}; do
  nice -n 15 /opt/homebrew/bin/timeout --kill-after=15s 120s "/Users/ember/dev/acl2-fix/$h-worktree/saved_acl2" < session.lisp > "session.$h.out" 2>&1
  echo "== $h"
  grep -E '@[A-Z0-9-]+|^ NIL-PROVED$' "session.$h.out"
done
