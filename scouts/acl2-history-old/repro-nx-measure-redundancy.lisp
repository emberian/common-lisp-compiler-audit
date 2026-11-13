; Modern sibling of NOTE-3-0-2 through DEFUN-NX.
(encapsulate
 ()
 (local (defun-nx f (x y)
          (declare (xargs :measure (acl2-count y)))
          (if (and (consp x) (consp y))
              (f (cons 1 x) (cdr y))
            (list x y))))
 (defun-nx f (x y)
   (declare (xargs :measure (acl2-count x)))
   (if (and (consp x) (consp y))
       (f (cons 1 x) (cdr y))
     (list x y))))
(defthm bad
  (not (and (consp x) (consp y)))
  :rule-classes nil
  :hints (("Goal" :use (:termination-theorem f))))
(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use (:instance bad (x '(1)) (y '(2))))))
(quit)
