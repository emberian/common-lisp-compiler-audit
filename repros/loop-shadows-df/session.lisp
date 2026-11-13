(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment error)))
; Control 1: the loop$ variable has a different name from the df formal.
(defun zdf-loop-y (x) (declare (type double-float x) (xargs :verify-guards nil))
  (loop$ for y in (list (floor (from-df x) 1)) sum y))
(cw "@Y ~x0~%" (zdf-loop-y (to-df 5/2)))
; Control 2: the same shadowing with an ordinary (rational) formal.
(defun zrat-loop-x (x) (declare (type rational x) (xargs :verify-guards nil))
  (loop$ for x in (list (floor x 1)) sum x))
(cw "@RAT ~x0~%" (zrat-loop-x 5/2))
; Control 3: LET shadowing a df formal with an ordinary value.
(defun zdf-let-x (x) (declare (type double-float x) (xargs :verify-guards nil))
  (let ((x (floor (from-df x) 1))) (+ x 1)))
(cw "@LET ~x0~%" (zdf-let-x (to-df 5/2)))
; The case: the loop$ variable shadows the df formal; the target expression
; (evaluated outside the loop) refers to the formal.
(defun zdf-loop-x (x) (declare (type double-float x) (xargs :verify-guards nil))
  (loop$ for x in (list (floor (from-df x) 1)) sum x))
(cw "@X ~x0~%" (zdf-loop-x (to-df 5/2)))
(cw "@END~%")
