(in-package "ACL2")
(defun rc (x) (declare (xargs :guard t)) (list x #+sbcl 'sbcl #+ccl 'ccl))
(defthm rc-thm (equal (rc 1) '(1 #+sbcl sbcl #+ccl ccl)) :rule-classes nil)
