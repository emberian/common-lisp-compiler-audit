(in-package "ACL2")
(make-event
 (if (getpropc '*include-marker* 'const nil (w state))
     '(defconst *me-world-value* 'rich)
   '(defconst *me-world-value* 'base)))
(defun read-me-world-value () *me-world-value*)
