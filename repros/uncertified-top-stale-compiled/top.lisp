(in-package "ACL2")
(include-book "sub")
(defun tf (x) (declare (xargs :guard t)) (si x))
(defconst *tc* (sm 1))
