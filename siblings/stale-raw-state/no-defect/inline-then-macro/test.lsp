; defun-inline f, :u, then f$inline defined as a macro.  Logically (g 1) = 4.
(defun-inline f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
:u
(defmacro f$inline (x) (list 'binary-+ x 1))
(defmacro f (x) (list 'f$inline x))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
