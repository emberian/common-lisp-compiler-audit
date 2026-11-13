; NOTE-3-5 type-set inequality database must not follow rebinding into LAMBDA.
; This formula is false at x=-1: the lambda result is (< 1 0) = NIL.
(defthm lambda-inequality-bad
  (implies (and (rationalp x) (< x 0))
           (equal ((lambda (x) (< x 0)) (- x)) t))
  :rule-classes nil)
; A positive control with the correct result.
(defthm lambda-inequality-good
  (implies (and (rationalp x) (< x 0))
           (equal ((lambda (x) (< x 0)) (- x)) nil))
  :rule-classes nil)
(quit)
