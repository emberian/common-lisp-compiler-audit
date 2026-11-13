; NOTE-3-0-2 original measure-redundancy exploit.
(encapsulate
 ()
 (local (defun foo (x y)
          (declare (xargs :measure (acl2-count y)))
          (if (and (consp x) (consp y))
              (foo (cons x x) (cdr y))
            y)))
 (defun foo (x y)
   (if (and (consp x) (consp y))
       (foo (cons x x) (cdr y))
     y)))
(defthm bad
  (atom x)
  :rule-classes nil
  :hints (("Goal" :induct (foo x '(3)))))
(defthm contradiction
  nil
  :rule-classes nil
  :hints (("Goal" :use ((:instance bad (x '(7)))))))
(quit)
