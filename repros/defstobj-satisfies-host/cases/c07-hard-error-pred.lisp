(defun ph (x) (declare (xargs :guard t)) (if (null x) (hard-error 'ph "PH called on nil" nil) t))
(defstobj st (fld :type (or null (satisfies ph)) :initially nil))
(cw "RESULT ~x0~%" (fld st))
