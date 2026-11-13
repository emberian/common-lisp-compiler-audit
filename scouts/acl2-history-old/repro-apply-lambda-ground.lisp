; Ground APPLY$/LAMBDA$ evaluation controls for variable rebinding.
(defthm apply-lambda-ground-bad
  (equal (apply$ (lambda$ (y) (< y 0)) (list (- -1))) t)
  :rule-classes nil)
(defthm apply-lambda-ground-good
  (equal (apply$ (lambda$ (y) (< y 0)) (list (- -1))) nil)
  :rule-classes nil)
(cw "APPLY-LAMBDA-GROUND ~x0~%"
    (apply$ (lambda$ (y) (< y 0)) (list (- -1))))
(quit)
