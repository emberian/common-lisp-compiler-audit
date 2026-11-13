#!/bin/sh
# run.sh IMAGE OUTDIR [TIMEOUT_SECONDS] [ONLY-FUNCTIONS]
#
# Runs the logical-vs-actual sweep (sweep.lisp) on one ACL2 image and writes
# results into OUTDIR.  If the image dies in the middle of a function, that
# function is recorded in OUTDIR/crashed.txt and the sweep restarts after it.
#
#   ./run.sh /path/to/saved_acl2 results/sbcl
#   ./run.sh /path/to/saved_acl2 /tmp/x 600 '(nth binary-append)'
#
# The image is always run under `nice -n 15 timeout`.  To stop a run early,
# create OUTDIR/STOP: the sweep exits before the next function.  OUTDIR/image.pid
# holds the PID of the running image process.

set -u
IMAGE=$1
OUT=$2
SECS=${3:-14400}
ONLY=${4:-nil}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# SBCL only: cap the heap so one exploding evaluation cannot take the machine.
SBCL_USER_ARGS="${SBCL_USER_ARGS:---dynamic-space-size 12000}"
export SBCL_USER_ARGS

cat > "$OUT/driver.lisp" <<EOF
(defun psw-ctl-pos-raw (x y)
  (declare (xargs :guard t))
  (if (equal x y) 1 (cons x y)))
(defun psw-ctl-pos-guarded (x)
  (declare (xargs :guard (integerp x)))
  (+ 1 x))
(defun psw-ctl-pos-star1 (x)
  (declare (xargs :guard (integerp x)))
  (if (integerp x) (- x) x))
(defun psw-ctl-neg (x y)
  (declare (xargs :guard t))
  (if (consp x) (cons y (car x)) (if (equal x y) 0 x)))
:q
(in-package "ACL2")
(setq *debugger-hook*
      (lambda (c h) (declare (ignore h))
        (format t "~&@PSW debugger entered: ~a~%" c) (finish-output)
        #+sbcl (sb-ext:exit :code 3 :abort t) #+ccl (ccl:quit 3)))
#+sbcl (setq sb-ext:*invoke-debugger-hook* *debugger-hook*)
#+ccl (let ((s (find-symbol "*BREAK-HOOK*" "CCL"))) (when s (set s *debugger-hook*)))
(defparameter *psw-outdir* "$OUT/")
(let ((*readtable* (copy-readtable nil))) (load "$HERE/sweep.lisp"))
(setq *psw-only* '$ONLY)
; Positive controls: corrupt the executable side only, after admission.
; (1) raw definition wrong at exactly one guard-satisfying tuple (index 1, 2)
(defun psw-ctl-pos-raw (x y)
  (if (and (eql x 1) (eql y -1)) 'wrong (if (equal x y) 1 (cons x y))))
; (2) raw definition wrong at exactly one guard-satisfying argument, 2^60
(defun psw-ctl-pos-guarded (x)
  (if (eql x 1152921504606846976) 0 (+ 1 x)))
; (3) *1* function wrong at exactly one guard-violating argument, "abc"
(let ((old (symbol-function (*1*-symbol 'psw-ctl-pos-star1))))
  (setf (symbol-function (*1*-symbol 'psw-ctl-pos-star1))
        (lambda (x) (if (equal x "abc") 'wrong (funcall old x)))))
(psw-main)
(psw-exit 0)
EOF

tries=0
while [ ! -f "$OUT/DONE" ] && [ $tries -lt 40 ]; do
  tries=$((tries + 1))
  rm -f "$OUT/progress"
  nice -n 15 timeout "$SECS" "$IMAGE" < "$OUT/driver.lisp" >> "$OUT/image.log" 2>&1 &
  echo $! > "$OUT/image.pid"   # the PID to signal if the image must be stopped
  wait $!
  rc=$?
  if [ -f "$OUT/STOP" ]; then echo "stopped by STOP file" >> "$OUT/attempts.log"; break; fi
  echo "attempt $tries exit $rc" >> "$OUT/attempts.log"
  if [ -f "$OUT/DONE" ]; then break; fi
  if [ $rc -eq 124 ]; then echo "overall timeout" >> "$OUT/attempts.log"; break; fi
  if [ -f "$OUT/progress" ]; then
    cat "$OUT/progress" >> "$OUT/crashed.txt"
    echo "crashed in $(cat "$OUT/progress")" >> "$OUT/attempts.log"
  else
    echo "died before the first function" >> "$OUT/attempts.log"; break
  fi
done
[ -f "$OUT/DONE" ]
