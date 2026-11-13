#!/bin/sh
# run-probe.sh SBCL_IMAGE OUTDIR [TIMEOUT_SECONDS]
# Runs independence-probe.lisp (SBCL only) and writes OUTDIR/independence.txt.
set -u
IMAGE=$1
OUT=$2
SECS=${3:-3600}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
SBCL_USER_ARGS="${SBCL_USER_ARGS:---dynamic-space-size 12000}"
export SBCL_USER_ARGS
cat > "$OUT/probe-driver.lisp" <<EOF
(defun psw-b-identity (x) (declare (xargs :guard t)) x)
(defun psw-b-let-mv (x y) (declare (xargs :guard t)) (let ((z (cons x y))) (mv z (if (consp x) (car x) y))))
(defun psw-b-rec (x) (declare (xargs :guard t)) (if (consp x) (cons 1 (psw-b-rec (cdr x))) nil))
(defun psw-b-mbe (x) (declare (xargs :guard t)) (mbe :logic (if (consp x) (car x) nil) :exec (if (consp x) (car x) nil)))
:q
(in-package "ACL2")
(defparameter *psw-outdir* "$OUT/")
(let ((*readtable* (copy-readtable nil)))
  (load "$HERE/sweep.lisp")
  (load "$HERE/independence-probe.lisp"))
(psw-probe-main)
(psw-exit 0)
EOF
nice -n 15 timeout "$SECS" "$IMAGE" < "$OUT/probe-driver.lisp" > "$OUT/probe.log" 2>&1 &
echo $! > "$OUT/probe.pid"
wait $!
