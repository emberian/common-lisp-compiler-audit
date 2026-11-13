#!/bin/bash
# launch.sh NAME [BACKEND]  -- start a headless scout (BACKEND: claude-kimi default, or claude-glm) in scouts/NAME using scouts/NAME/brief.md.
# The worker may read anywhere, write only inside its own directory, and execute
# only lisp-run.sh and read-only git on the SBCL and CCL checkouts.
set -eu
M=/Users/ember/dev/compiler-audit/scouts; name=$1; backend=${2:-claude-kimi}; d=$M/$name
[ -f "$d/brief.md" ] || { echo "no brief at $d/brief.md" >&2; exit 2; }
cd "$d"
nohup "$backend" -p "$(cat brief.md)" \
  --allowedTools "Read" "Grep" "Glob" \
    "Edit(/$d/**)" \
    "Bash($M/lisp-run.sh:*)" \
    "Bash(git -C /Users/ember/dev/sbcl log:*)" "Bash(git -C /Users/ember/dev/sbcl show:*)" \
    "Bash(git -C /Users/ember/dev/ccl log:*)" "Bash(git -C /Users/ember/dev/ccl show:*)" \
  > "$d/worker.log" 2>&1 &
echo $! > "$d/worker.pid"
echo "$backend" > "$d/worker.backend"; echo "started $name on $backend pid $(cat "$d/worker.pid")"
