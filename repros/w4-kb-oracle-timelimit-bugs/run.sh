#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BOOKS_SRC="/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2="/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2="/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

WORK="$(mktemp -d /tmp/w4-kb-otl.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/books/tools" "$WORK/books/quicklisp"
for entry in "$BOOKS_SRC"/*; do
  base="$(basename "$entry")"
  [ "$base" = "tools" ] || [ "$base" = "quicklisp" ] && continue
  ln -s "$entry" "$WORK/books/$base"
done
for entry in "$BOOKS_SRC/tools"/*; do
  base="$(basename "$entry")"
  [ "$base" = "oracle-timelimit.lisp" ] || [ "$base" = "oracle-timelimit-raw.lsp" ] && continue
  ln -s "$entry" "$WORK/books/tools/$base"
done
cp "$BOOKS_SRC/tools/oracle-timelimit.lisp" "$WORK/books/tools/oracle-timelimit.lisp"
cp "$BOOKS_SRC/tools/oracle-timelimit-raw.lsp" "$WORK/books/tools/oracle-timelimit-raw.lsp"

cat > "$WORK/books/quicklisp/bordeaux.lisp" <<'EOF'
(in-package "ACL2")
(include-book "tools/include-raw" :dir :system)
(defttag :bordeaux)
(include-raw "bordeaux-raw.lsp")
EOF

cat > "$WORK/books/quicklisp/bordeaux-raw.lsp" <<'EOF'
(defpackage :bordeaux-threads
  (:nicknames :bt)
  (:use :cl)
  (:export :current-thread :make-lock :with-lock-held :make-thread :interrupt-thread))
(in-package :bordeaux-threads)
(defun current-thread ()
  #+sbcl sb-thread:*current-thread*
  #+ccl ccl:*current-process*)
(defun make-lock (&optional name)
  #+sbcl (sb-thread:make-mutex :name name)
  #+ccl (ccl:make-lock name))
(defmacro with-lock-held ((place) &body body)
  #+sbcl `(sb-thread:with-mutex (,place) ,@body)
  #+ccl `(ccl:with-lock-grabbed (,place) ,@body))
(defun make-thread (fn &key name)
  #+sbcl (sb-thread:make-thread fn :name name)
  #+ccl (ccl:process-run-function (or name "bt-thread") fn))
(defun interrupt-thread (thread fn)
  #+sbcl (sb-thread:interrupt-thread thread fn)
  #+ccl (ccl:process-interrupt thread fn))
EOF

run_host() {
  local label="$1"
  local bin="$2"
  local out="$WORK/out_${label}.txt"
  echo "=== Running w4-kb-oracle-timelimit-bugs on $label ==="
  ACL2_SYSTEM_BOOKS="$WORK/books" /opt/homebrew/bin/timeout --kill-after=10s 120s "$bin" < "$DIR/repro.lisp" > "$out" 2>&1 || true
  if ! grep -q "\[OTL-SUPPRESS-BUG: okp=NIL ans=NIL\]" "$out"; then
    echo "MISSING OTL-SUPPRESS-BUG on $label"
    grep -n -A2 -m5 "ACL2 Error" "$out" || true
    tail -n 25 "$out"
    exit 1
  fi
  if ! grep -q "\[OTL-NEG-LIMIT-BUG: okp=T ans=3\]" "$out"; then
    echo "MISSING OTL-NEG-LIMIT-BUG on $label"
    tail -n 30 "$out"
    exit 1
  fi
  if ! grep -qE "ABORTING from raw Lisp|A live state is required" "$out"; then
    echo "MISSING :ret (mv ans state) crash on $label"
    tail -n 30 "$out"
    exit 1
  fi
  grep -E "\[OTL-SUPPRESS-BUG:|\[OTL-NEG-LIMIT-BUG:|ABORTING from raw Lisp|A live state is required|Error:" "$out" | head -n 8
}

run_host "SBCL" "$SBCL_ACL2"
run_host "CCL" "$CCL_ACL2"
echo "PASS: w4-kb-oracle-timelimit-bugs verified on SBCL and CCL"
