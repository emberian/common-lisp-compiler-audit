(in-package "ACL2")
; NOTE-7-4 capture invariant using the newer lambda$ spelling.
(defun f (n) (declare (ignore n)) 3)
(defthm f-thm (equal (f x) 3) :rule-classes nil)
(defthm not-true-lambda$
  (implies (equal n 3) (equal x 3))
  :hints (("Goal" :by (:functional-instance
                        f-thm
                        (f (lambda$ (n2) (if (equal n 3) n2 3))))))
  :rule-classes nil)
(quit)
