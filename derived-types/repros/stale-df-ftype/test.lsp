; Step 1: a function with a double-float (df) signature.  ACL2 proclaims
;   (ftype (function (double-float &optional) (values double-float &optional)) f)
; for it (proclaim-dfs, interface-raw.lisp).
(defun f (x) (declare (type double-float x)) (df+ x x))
; Step 2: undo it and define an ordinary function of the same name.
:u
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
; Step 3: a caller.  Logically (g 1) = 2 * (1 + 2^70) = 2361183241434822606850.
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
