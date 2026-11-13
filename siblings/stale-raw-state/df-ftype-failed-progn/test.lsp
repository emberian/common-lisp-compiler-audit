; proclaim-dfs ftype from a defun inside a PROGN that fails (rolled back).
; No undo command, no redefinition.  Logically (g 1) = 2361183241434822606850.
(progn (defun f (x) (declare (type double-float x)) (df+ x x))
       (defthm bogus (equal (car (cons 1 2)) 2)))
(defun f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
