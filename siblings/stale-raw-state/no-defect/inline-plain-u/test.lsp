; defun-inline, plain :u, then a defun-inline of the same name with a different arity
; and body.  Logically (g 1) = 2*(1*2^70 + 1) = 2361183241434822606850.
(defun-inline f (x) (declare (xargs :guard (rationalp x))) (+ x 1))
:u
(defun-inline f (x y) (declare (xargs :guard (and (rationalp x) (rationalp y)))) (+ (* x 1180591620717411303424) y))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x 1) (f x 1)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x 1) (f x 1)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
