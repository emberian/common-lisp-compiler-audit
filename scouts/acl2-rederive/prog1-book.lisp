(in-package "ACL2")
(program)
(mutual-recursion
 (defun f (x) (g x))
 (defun g (x) (f x)))
