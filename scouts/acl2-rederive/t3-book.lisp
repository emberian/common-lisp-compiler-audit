(in-package "ACL2")
(defun f (x)
  (declare (xargs :verify-guards nil))
  (loop$ for k from 0 to 3 sum (+ k x)))
