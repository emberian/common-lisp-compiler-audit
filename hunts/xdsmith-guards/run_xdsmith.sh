#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

TIMEOUT_BIN="/opt/homebrew/bin/timeout"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

python3 gen_xdsmith_guards.py "$@"

echo "=== Running suite_bug_probes.lisp on SBCL ==="
nice -n 15 "$TIMEOUT_BIN" --kill-after=15s 180s "$SBCL_ACL2" < suite_bug_probes.lisp > sbcl_probes.log 2>&1
grep -E 'XDS-(CONFIRMED-BUG|PROBE-MISSED)|ACL2 Error|ABORTING' sbcl_probes.log || true

echo "=== Running suite_bug_probes.lisp on CCL ==="
nice -n 15 "$TIMEOUT_BIN" --kill-after=15s 180s "$CCL_ACL2" < suite_bug_probes.lisp > ccl_probes.log 2>&1
grep -E 'XDS-(CONFIRMED-BUG|PROBE-MISSED)|ACL2 Error|ABORTING' ccl_probes.log || true

echo "=== Running suite_negative.lisp on SBCL ==="
nice -n 15 "$TIMEOUT_BIN" --kill-after=15s 180s "$SBCL_ACL2" < suite_negative.lisp > sbcl_negative.log 2>&1

echo "=== Running suite_negative.lisp on CCL ==="
nice -n 15 "$TIMEOUT_BIN" --kill-after=15s 180s "$CCL_ACL2" < suite_negative.lisp > ccl_negative.log 2>&1

for host in sbcl ccl; do
  log="${host}_negative.log"
  echo "=== Summary: $host ($log) ==="
  echo "  XDS-PASS-NEG:           $(grep -c 'XDS-PASS-NEG|' "$log" || true)"
  echo "  XDS-PASS-DIFF:          $(grep -c 'XDS-PASS-DIFF|' "$log" || true)"
  echo "  XDS-SURVIVOR-SOUNDNESS: $(grep -c 'XDS-SURVIVOR-SOUNDNESS|' "$log" || true)"
  echo "  XDS-BUG-LAMBDA-CRASH:   $(grep -c 'XDS-BUG-LAMBDA-ALIST-CRASH|' "$log" || true)"
  echo "  XDS-ANOMALY:            $(grep -c 'XDS-ANOMALY|' "$log" || true)"
  echo "  ABORTING raw Lisp:      $(grep -c 'ABORTING from raw Lisp' "$log" || true)"
  echo "  Completed cleanly:      $(grep -c 'XDS-SUITE-COMPLETE' "$log" || true)"
done
