(defun fib (n) (declare (xargs :guard (natp n))) (if (zp n) 0 (if (eql n 1) 1 (+ (fib (- n 1)) (fib (- n 2))))))
(defun pslow (x) (declare (xargs :guard t)) (if (null x) (< (fib 36) 0) t))
(defun f (x) (declare (type (or null (satisfies pslow)) x)) x)
(cw "RESULT ~x0~%" (f 3))
