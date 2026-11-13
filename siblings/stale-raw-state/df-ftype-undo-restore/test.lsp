; f is integer-valued; it is redefined (redefinition enabled) to a df function, which
; proclaims the df ftype; :u restores the integer f via the *undo-stack* (setf symbol-function),
; leaving the ftype.  Logically (g 1) = 2361183241434822606850.
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
(redef!)
(defun f (x) (declare (type double-float x)) (df+ x x))
:u
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
