; A guard-verified function with a double-float (df) formal whose body ends in
; a call of FLOOR.  Logically (zdf-floor (to-df 5/2)) = 2.
(in-package "ACL2")
(defun zdf-floor (x)
  (declare (type double-float x))
  (floor (from-df x) 1))
; Control: the same body, value forced to a single value by a LET.
(defun zdf-floor-let (x)
  (declare (type double-float x))
  (let ((r (floor (from-df x) 1))) r))
; Control: the same tail call with a rational formal instead of a df formal.
(defun zrat-floor (x)
  (declare (type rational x))
  (floor x 1))
