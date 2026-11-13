(defstub p (x) nil)
(defun f (x) (declare (xargs :guard (null x))) (the (or null (satisfies p)) x))
(cw "RESULT ~x0~%" (f nil))
