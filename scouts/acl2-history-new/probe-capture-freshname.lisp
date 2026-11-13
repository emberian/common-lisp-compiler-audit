(in-package "ACL2")
; 8.7+ sibling of NOTE-7-4, preserved in remove-capture-in-constraint-lst.
; Tests whether the fresh-name trap still admits a proof of NIL.
(defun f (a a-renamed0)
  (declare (ignore a a-renamed0))
  3)
(defthm good (equal (f x y) 3) :rule-classes nil)
(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal"
           :use ((:instance
                  (:functional-instance good
                    (f (lambda (p q) (if (equal p q) 3 a))))
                  (x 0) (y 1) (a 4))))))
(quit)
