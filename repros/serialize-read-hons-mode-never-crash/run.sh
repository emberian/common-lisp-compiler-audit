#!/usr/bin/env bash
# Usage: run.sh [head|ccl] (default both)
set -euo pipefail
cd "$(dirname "$0")"
for h in ${1:-head ccl}; do
  rm -f sample.sao
  nice -n 15 /opt/homebrew/bin/timeout --kill-after=15s 60s "/Users/ember/dev/acl2-fix/$h-worktree/saved_acl2" < session.lisp > "session.$h.out" 2>&1 || true
  echo "== $h"
  grep -E '@SMART-READ|@NEVER-READ|ABORTING from raw Lisp|magic number incorrect|@END' "session.$h.out"
  rm -f sample.sao
done
