#!/bin/bash
# The only execution entry point for scout workers.
#   lisp-run.sh HOST SCRIPT
# HOST: acl2-sbcl | acl2-ccl | sbcl | ccl.  SCRIPT: a file inside the caller's
# current directory, fed to the Lisp on stdin (ACL2) or loaded (sbcl, ccl).
# Runs niced with a 300 second limit in the caller's directory, writes the full
# transcript to SCRIPT.HOST.out and prints at most the last 6000 bytes of it.
set -u
host=${1:?host}; script=${2:?script}
case "$script" in /*|*..*) echo "lisp-run: script must be a relative path inside the current directory" >&2; exit 2;; esac
[ -f "$script" ] || { echo "lisp-run: no such file $script" >&2; exit 2; }
out="$script.$host.out"
case "$host" in
  acl2-sbcl) nice -n 15 timeout 300 /Users/ember/dev/acl2-fix/head-worktree/saved_acl2 < "$script" > "$out" 2>&1;;
  acl2-ccl)  nice -n 15 timeout 300 /Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2 < "$script" > "$out" 2>&1;;
  sbcl)      nice -n 15 timeout 300 /opt/homebrew/bin/sbcl --noinform --disable-debugger --load "$script" --eval '(sb-ext:exit :code 0 :abort t)' > "$out" 2>&1;;
  ccl)       nice -n 15 timeout 300 /Users/ember/dev/ccl/darm64cl -n --batch --load "$script" --eval '(ccl:quit 0)' > "$out" 2>&1;;
  *) echo "lisp-run: unknown host $host" >&2; exit 2;;
esac
rc=$?
echo "[lisp-run host=$host exit=$rc transcript=$out bytes=$(wc -c < "$out" | tr -d ' ')]"
tail -c 6000 "$out"
