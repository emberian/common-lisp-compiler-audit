(in-package "ACL2")
(defmacro sm (x) `(cons ,x (quote new)))
(defun-inline si (x) (declare (xargs :guard t)) (cons x (quote new)))
