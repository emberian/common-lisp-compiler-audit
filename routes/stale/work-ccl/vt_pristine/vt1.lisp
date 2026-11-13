(in-package "ACL2")
(defun vh (x) (declare (xargs :mode :program :guard t)) (list x 'va))
(defun vg (x) (declare (xargs :guard t :verify-guards nil)) (list x 'ga))
