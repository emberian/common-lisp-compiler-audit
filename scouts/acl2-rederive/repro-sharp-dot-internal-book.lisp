(in-package "ACL2")
(defconst *inside-reader* '(1 2))
(defun inside-reader-fn () '#.*inside-reader*)
