#!/bin/sh
# run-ccl.sh FILE.lisp [TIMEOUT_SECONDS]   -- as run-sbcl.sh, for the CCL-hosted ACL2 image.
IMG=${ACL2_CCL:-/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2}
F=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
CMD=$(mktemp "${TMPDIR:-/tmp}/dt-cmd.XXXXXX")
printf ':q\n(in-package "ACL2")\n(handler-bind ((warning (function muffle-warning))) (load "%s"))\n(ccl:quit 0)\n' "$F" > "$CMD"
nice -n 15 timeout "${2:-600}" "$IMG" < "$CMD" 2>&1 &
[ -n "$PIDFILE" ] && echo $! > "$PIDFILE"
wait $!
rm -f "$CMD"
