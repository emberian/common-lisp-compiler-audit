; Regression control for the recently fixed memoize-partial EC-CALL capture.
(defun f-limit (n limit)
  (declare (xargs :guard (and (natp n) (natp limit)) :measure (nfix limit)))
  (if (zp limit)
      'c
    (let ((limit (1- limit)))
      (if (zp n)
          'z
        (if (equal (f-limit 0 limit) (ec-call (f-limit 0 limit)))
            'c
          'd)))))
(memoize-partial f)
(defthm f-limit-1 (equal (f-limit 1 l) 'c))
(defthm f-1-logic (equal (f 1) 'c)
  :hints (("Goal" :in-theory (disable (:e f)))) :rule-classes nil)
(defthm f-1-exec (equal (f 1) 'd) :rule-classes nil)
(defthm bad nil :hints (("Goal" :use (f-1-logic f-1-exec))) :rule-classes nil)
(quit)
