; defun-inline: f$inline is proclaimed inline and the host records its inline expansion.
; Redefine it (redefinition enabled) to a different body, then :u.  The undo-stack restores
; symbol-function of f$inline (v1) but not the host's recorded inline expansion (v2).
; Logically (g 1) = (1+1)+(1+1) = 4.
(defun-inline f (x) (declare (xargs :guard (rationalp x))) (+ x 1))
(redef!)
(defun-inline f (x) (declare (xargs :guard (rationalp x))) (+ x 1180591620717411303424))
:u
(defun g-gv (x) (declare (xargs :guard (rationalp x))) (+ (f x) (f x)))
(defun g-nogv (x) (declare (xargs :guard (rationalp x) :verify-guards nil)) (+ (f x) (f x)))
(cw "RESULT guard-verified: ~x0~%" (g-gv 1))
(cw "RESULT not guard-verified: ~x0~%" (g-nogv 1))
