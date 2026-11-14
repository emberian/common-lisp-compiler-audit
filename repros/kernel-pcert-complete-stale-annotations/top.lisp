(in-package "ACL2")
(local (include-book "sub1"))
(defthm top-ok (equal (car (cons x y)) x))
