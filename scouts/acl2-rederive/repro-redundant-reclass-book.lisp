(in-package "ACL2")
(defun redundant-f (x) (cons x x))
(defun redundant-g (x) (redundant-f x))
