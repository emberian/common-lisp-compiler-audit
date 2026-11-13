; NOTE-3-2.1 MBE/multiple-value signature mismatch must be rejected.
(defun f (x)
  (mbe :logic (mv x x) :exec x))
(defthm f-logic (equal (f 3) (list 3 3)) :rule-classes nil)
(defthm f-exec (equal (f 3) 3) :rule-classes nil)
(defthm bad nil :hints (("Goal" :use (f-logic f-exec))) :rule-classes nil)
(quit)
