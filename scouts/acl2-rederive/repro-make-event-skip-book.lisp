(in-package "ACL2")
(make-event
 (if (ld-skip-proofsp state)
     '(defconst *me-skip-value* 'include)
   '(defconst *me-skip-value* 'certify)))
(defun read-me-skip-value () *me-skip-value*)
