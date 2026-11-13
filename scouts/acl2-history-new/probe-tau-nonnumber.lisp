(in-package "ACL2")
; NOTE-8-1 tau non-strict-to-strict conversion on non-numbers.
(thm (or (< x 0) (= x 0) (> x 0)))
(thm (implies (and (not (equal x 0)) (<= x 0)) (< x 0)))
; Correct controls: explicit numeric hypothesis, and evaluation at counterexample.
(thm (implies (acl2-numberp x) (or (< x 0) (= x 0) (> x 0))))
(assert-event (not (or (< t 0) (= t 0) (> t 0))))
(quit)
