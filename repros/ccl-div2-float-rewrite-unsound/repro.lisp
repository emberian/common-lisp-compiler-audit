;;;; CCL 1.14 cross-arch IEEE-754 soundness bug:
;;;; `acode-rewrite-div2` (compiler/acode-rewrite.lisp:369-386) and backend
;;;; `arm642-div2` (compiler/ARM64/arm642.lisp:7376-7386) / `x862-div2`
;;;; unconditionally rewrite:
;;;;
;;;;   (/ (* c1 x) c2)  ==>  (* (/ c1 c2) x)
;;;;
;;;; whenever `c1` and `c2` are constant rationals — WITHOUT checking that `x`
;;;; is `rational` and even at `(optimize (safety 3) (speed 1))`!
;;;;
;;;; When `x` is a floating-point number:
;;;;   1. `(/ (* 3 x) 3)` with `x = most-positive-double-float` rewrites to
;;;;      `(* 1 x)`, returning finite `1.7976931348623157d308` instead of
;;;;      IEEE-754 `+Inf` (on ARM64 CCL) or signalling `FLOATING-POINT-OVERFLOW`
;;;;      (on x86-64 CCL and SBCL)!
;;;;   2. `(/ (* 0 x) -3)` with `x = 0.0d0` (or `1.0d0`) rewrites to `(* 0 x)`,
;;;;      returning `+0.0d0` (`float-sign` = `+1.0d0`) instead of `-0.0d0`
;;;;      (`float-sign` = `-1.0d0`)!

(defun describe-float-outcome (thunk)
  (handler-case
      (let ((v (funcall thunk)))
        (cond
          ((not (floatp v)) (list :ok v))
          ((/= v v) (list :nan))
          ((> (abs v) most-positive-double-float)
           (list :inf (float-sign v)))
          ((zerop v)
           (list :zero :sign (float-sign v)))
          (t (list :finite v))))
    (error (c)
      (list :err (type-of c)))))

(let ((f-ovf-ref (compile nil '(lambda (x)
                                 (declare (notinline * /))
                                 (/ (* 3 x) 3))))
      (f-ovf-s3  (compile nil '(lambda (x)
                                 (declare (optimize (safety 3) (speed 1)))
                                 (/ (* 3 x) 3))))
      (f-sz-ref  (compile nil '(lambda (x)
                                 (declare (notinline * /))
                                 (/ (* 0 x) -3))))
      (f-sz-s3   (compile nil '(lambda (x)
                                 (declare (optimize (safety 3) (speed 1)))
                                 (/ (* 0 x) -3)))))
  (format t "~&[1] (/ (* 3 x) 3) at x = most-positive-double-float:~%")
  (format t "    notinline             => ~S~%"
          (describe-float-outcome (lambda () (funcall f-ovf-ref most-positive-double-float))))
  (format t "    (safety 3)(speed 1)   => ~S  (WRONG on CCL: overflow erased!)~%"
          (describe-float-outcome (lambda () (funcall f-ovf-s3 most-positive-double-float))))

  (format t "~%[2] (/ (* 0 x) -3) at x = 0.0d0 (signed zero):~%")
  (format t "    notinline             => ~S~%"
          (describe-float-outcome (lambda () (funcall f-sz-ref 0.0d0))))
  (format t "    (safety 3)(speed 1)   => ~S  (WRONG on CCL: -0.0d0 flipped to +0.0d0!)~%"
          (describe-float-outcome (lambda () (funcall f-sz-s3 0.0d0)))))

(finish-output)
#+ccl (ccl:quit)
#+sbcl (sb-ext:exit)
