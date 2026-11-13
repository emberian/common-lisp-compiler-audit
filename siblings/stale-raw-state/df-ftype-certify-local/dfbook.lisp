(in-package "ACL2")
(local (defun f (x) (declare (type double-float x)) (df+ x x)))
(defun dfbook-marker (x) x)
