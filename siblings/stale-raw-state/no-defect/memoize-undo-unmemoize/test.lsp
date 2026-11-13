; memoize f, populate, unmemoize, :u (restores memoization via the undo stack's memoize-fn),
; then f is unchanged so values must stay 4; also checks the restored table is fresh vs stale is harmless here.
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1))
(memoize 'f)
(cw "RESULT populate (f 1): ~x0~%" (f 1))
(unmemoize 'f)
:u
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
