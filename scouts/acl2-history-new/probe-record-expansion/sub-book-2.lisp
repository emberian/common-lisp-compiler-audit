(in-package "ACL2")
(encapsulate ()
  (defun f () 2))
(defthm f-is-2 (equal (f) 2))
