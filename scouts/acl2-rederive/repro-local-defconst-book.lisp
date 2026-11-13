(in-package "ACL2")
(encapsulate ()
  (local (defun local-choice () 'local-logical))
  (defconst *local-choice-value* (local-choice)))
