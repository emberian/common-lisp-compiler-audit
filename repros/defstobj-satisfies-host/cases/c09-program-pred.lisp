(defun pp (x) (declare (xargs :mode :program)) (prog2$ (cw "CALLED pp ~x0~%" x) (if (null x) (er hard 'pp "PP on nil") t)))
(defun f (x) (declare (xargs :mode :program) (type (or null (satisfies pp)) x)) x)
(cw "RESULT ~x0~%" (f nil))
