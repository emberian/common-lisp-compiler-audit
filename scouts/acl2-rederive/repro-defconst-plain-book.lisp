(in-package "ACL2")
(defun dc-two () 2)
(defconst *dc-two-value* (dc-two))
(defun dc-read-two () *dc-two-value*)
