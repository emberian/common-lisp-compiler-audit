; attach h1 to stub h, :u the defattach, attach h2.  Logically (g 1) = 2*2^70.
(defstub h (x) t)
(defun h1 (x) (declare (xargs :guard t) (ignore x)) 1)
(defun h2 (x) (declare (xargs :guard t) (ignore x)) 1180591620717411303424)
(defattach h h1)
:u
(defattach h h2)
(defun f (x) (declare (xargs :guard (rationalp x))) (fix (h x)))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
