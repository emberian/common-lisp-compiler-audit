(defstub p (x) nil)
(defun f (x) (declare (type (or null (satisfies p)) x)) x)
(cw "RESULT ~x0~%" (f nil))
