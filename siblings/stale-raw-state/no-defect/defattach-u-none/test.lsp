; attach h1 to stub h, :u the defattach; no attachment remains, so both callers must fail.
(defstub h (x) t)
(defun h1 (x) (declare (xargs :guard t) (ignore x)) 1)
(defattach h h1)
:u
(defun f (x) (declare (xargs :guard (rationalp x))) (fix (h x)))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
