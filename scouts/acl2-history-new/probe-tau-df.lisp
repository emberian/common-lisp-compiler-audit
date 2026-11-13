(in-package "ACL2")
; NOTE-8-1 nonnumeric inequality invariant through the newer df domain.
(thm (implies (dfp x) (acl2-numberp x)))
(thm (implies (dfp x) (or (< x 0) (= x 0) (> x 0))))
(thm (implies (and (dfp x) (not (equal x 0)) (<= x 0)) (< x 0)))
; Sound control: the numeric hypothesis is sufficient without ruling out df.
(thm (implies (acl2-numberp x) (or (< x 0) (= x 0) (> x 0))))
(quit)
