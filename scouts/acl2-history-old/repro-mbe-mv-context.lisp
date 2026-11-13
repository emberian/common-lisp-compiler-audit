; NOTE-3-2.1 with an outer MV-LET supplying a two-value expected signature.
(defun f (x)
  (mv-let (a b)
          (mbe :logic (mv x x) :exec x)
    (mv a b)))
(defthm f-logic (equal (f 3) (list 3 3)) :rule-classes nil)
(defthm f-exec (equal (f 3) 3) :rule-classes nil)
(defthm bad nil :hints (("Goal" :use (f-logic f-exec))) :rule-classes nil)
(quit)
