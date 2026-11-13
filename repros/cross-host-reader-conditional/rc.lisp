(in-package "ACL2")
(defun rc () (declare (xargs :guard t)) #+sbcl 'sbcl #+ccl 'ccl)
(defthm rc-value (equal (rc) #+sbcl 'sbcl #+ccl 'ccl) :rule-classes nil)
