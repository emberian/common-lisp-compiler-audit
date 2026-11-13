(in-package "ACL2")
(defconst *k* 1)
(defun f (x) (declare (xargs :guard t)) (cons x 'old))
