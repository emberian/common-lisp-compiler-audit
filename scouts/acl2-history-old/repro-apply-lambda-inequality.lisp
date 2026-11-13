; Modern LAMBDA$/APPLY$ sibling of lambda-scoped inequality handling.
(defthm apply-lambda-inequality-bad
  (implies (and (rationalp x) (< x 0))
           (equal (apply$ (lambda$ (y) (< y 0)) (list (- x))) t))
  :rule-classes nil)
(defthm apply-lambda-inequality-good
  (implies (and (rationalp x) (< x 0))
           (equal (apply$ (lambda$ (y) (< y 0)) (list (- x))) nil))
  :rule-classes nil)
(quit)
