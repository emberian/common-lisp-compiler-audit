; Sibling of NOTE-3-6 encapsulate redundancy: changed default WFR.
(defun never< (x y) (declare (ignore x y)) nil)
(defun id (x) x)
(defthm never<-is-well-founded
  (and (implies (natp x) (o-p (id x)))
       (implies (and (natp x) (natp y) (never< x y))
                (o< (id x) (id y))))
  :rule-classes :well-founded-relation)
(encapsulate
 ()
 (local (encapsulate ()
          (defun f (x)
            (declare (xargs :measure (acl2-count x)))
            (if (consp x) (f (cdr x)) x))))
 (set-well-founded-relation never<)
 (encapsulate ()
   (defun f (x)
     (declare (xargs :measure (acl2-count x)))
     (if (consp x) (f (cdr x)) x))))
(defthm bad (not (consp x)) :rule-classes nil
  :hints (("Goal" :use (:termination-theorem f))))
(defthm nil-proved nil :rule-classes nil
  :hints (("Goal" :use (:instance bad (x '(1))))))
(quit)
