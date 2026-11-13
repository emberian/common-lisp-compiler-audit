(in-package "ACL2")
(defun mbe-choice ()
  (mbe :logic 'logical :exec 'executive))
(defconst *mbe-choice-value* (mbe-choice))
(defconst *mbe-direct-value*
  (mbe :logic 'direct-logic :exec 'direct-exec))
(defun read-mbe-choices ()
  (list *mbe-choice-value* *mbe-direct-value*))
