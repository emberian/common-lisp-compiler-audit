(defstub p (x) nil)
(defun f (x) (declare (xargs :guard (null x))) (let ((y x)) (declare (type (or null (satisfies p)) y)) y))
(cw "RESULT ~x0~%" (f nil))
