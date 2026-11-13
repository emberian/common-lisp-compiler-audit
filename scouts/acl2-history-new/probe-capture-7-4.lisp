(in-package "ACL2")
; NOTE-7-4 original capture exploit; expected to fail now.
(defun f (n) (declare (ignore n)) 3)
(defthm f-thm (equal (f x) 3) :rule-classes nil)
(defthm not-true
  (implies (equal n 3) (equal x 3))
  :hints (("Goal" :by (:functional-instance
                        f-thm
                        (f (lambda (n2) (if (equal n 3) n2 3))))))
  :rule-classes nil)
(defthm ouch
  nil
  :hints (("Goal" :use ((:instance not-true (n 3) (x 4)))))
  :rule-classes nil)
(quit)
