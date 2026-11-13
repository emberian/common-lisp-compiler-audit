; NOTE-3-5 original nested-FLET exploit.
(defun a (x) (list 'c x))
(defun foo1 (x y)
  (flet ((a (x) (list 'a x)))
    (flet ((b (y) (list 'b y)))
      (b (a (list x y))))))
(cw "OBSERVED-VALUE ~x0~%" (foo1 3 4))
(defthm not-true
  (equal (foo1 3 4) '(b (c (3 4))))
  :hints (("Goal" :in-theory (disable (:executable-counterpart foo1))))
  :rule-classes nil)
(defthm contradiction
  nil
  :hints (("Goal" :use not-true))
  :rule-classes nil)
(quit)
