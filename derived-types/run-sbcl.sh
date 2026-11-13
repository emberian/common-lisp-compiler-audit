#!/bin/sh
# run-sbcl.sh FILE.lisp [TIMEOUT_SECONDS]
# Load FILE in raw Lisp (after :q, package ACL2) of the SBCL-hosted ACL2 image, under
# nice and timeout.  If PIDFILE is set, the PID of the timeout process is written there;
# `kill $(cat $PIDFILE)` stops the run (timeout forwards the signal to the image).
IMG=${ACL2_SBCL:-/Users/ember/dev/acl2-fix/head-worktree/saved_acl2}
F=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
SBCL_USER_ARGS="${SBCL_USER_ARGS:---dynamic-space-size 8000}"; export SBCL_USER_ARGS
CMD=$(mktemp "${TMPDIR:-/tmp}/dt-cmd.XXXXXX")
printf ':q\n(in-package "ACL2")\n(handler-bind ((warning (function muffle-warning))) (load "%s"))\n(sb-ext:exit :abort t)\n' "$F" > "$CMD"
nice -n 15 timeout "${2:-600}" "$IMG" < "$CMD" 2>&1 &
[ -n "$PIDFILE" ] && echo $! > "$PIDFILE"
wait $!
rm -f "$CMD"
