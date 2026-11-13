; local defun-inline in encapsulate pass 1, then a different top-level defun-inline.
; Logically (g 1) = 4.
(encapsulate () (local (defun-inline f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))))
(defun-inline f (x) (declare (xargs :guard (rationalp x))) (+ x 1))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
