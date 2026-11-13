; memoize f, populate its memo table, undo both f and the memoize, define a new f with
; the same name and memoize it.  A stale memo entry would give (f 1) = 2.  Logically (g 1) = 2361183241434822606850.
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1))
(memoize 'f)
(cw "RESULT populate (f 1): ~x0~%" (f 1))
:ubt! f
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
(memoize 'f)
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
