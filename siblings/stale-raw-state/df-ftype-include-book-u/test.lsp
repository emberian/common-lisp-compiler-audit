; include-book of a certified book defining a df f, :u, then an integer-valued f.
; run.sh certifies dfbook2 first in a separate process.  Logically (g 1) = 2361183241434822606850.
(include-book "dfbook2")
:u
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
