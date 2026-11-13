; defconst raw value (defparameter), :u, new value.  Logically (g 1) = 2*(1+2^70).
(defconst *c* 1)
:u
(defconst *c* 1180591620717411303424)
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x *c*))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
