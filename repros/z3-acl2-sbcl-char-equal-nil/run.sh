#!/bin/sh
# Proves (defthm nil-proved nil) in pure guard-verified ACL2 on SBCL 2.6.10
# with :ttag nil, :skip-proofs-seen nil, :redef-seen nil.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ACL2_BIN="${ACL2_BIN:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}"
TIMEOUT_BIN=/opt/homebrew/bin/timeout
if [ ! -x "$TIMEOUT_BIN" ]; then TIMEOUT_BIN=timeout; fi

OUT=$("$TIMEOUT_BIN" --kill-after=10s 120s "$ACL2_BIN" < "$HERE/repro.lisp")
printf "%s\n" "$OUT"

printf "%s\n" "$OUT" | grep -q "Q.E.D."
printf "%s\n" "$OUT" | grep -q "ttag:             NIL"
printf "%s\n" "$OUT" | grep -q "skip-proofs-seen: NIL"
printf "%s\n" "$OUT" | grep -q "redef-seen:       NIL"
printf "%s\n" "$OUT" | grep -q "ACL2 SOUNDNESS BUG CONFIRMED"
