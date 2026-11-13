; Probe 12: 8.7 stobj-attachment-restrictions on the CONCRETE side.
; A stobj field typed (satisfies p) where p is a defun calling a CONSTRAINED
; function (so p can be attached later).  Does defstobj accept it, and is
; the later defattach on the constrained function refused?

(encapsulate (((constr-flg *) => *))
  (local (defun constr-flg (x) (declare (ignore x)) t)))

(defun p3 (x) (declare (xargs :guard t)) (and (natp x) (constr-flg x)))

(defstobj c3 (f3 :type (satisfies p3) :initially 0))

; if admitted: p3/constr-flg are now ancestors of C3P; a defattach on
; constr-flg should be refused.
(defun always-no (x) (declare (xargs :guard t) (ignore x)) nil)

(defattach (constr-flg always-no))

; if somehow admitted, read the recognizer on the live stobj:
(c3p c3)
(f3 c3)

(quit)
