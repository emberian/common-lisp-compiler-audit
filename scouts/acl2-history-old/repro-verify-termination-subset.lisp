; Exact NOTE-3-5 measured-subset VERIFY-TERMINATION exploit from its documentation.
(encapsulate
 ()
 (defun foo (x y)
   (declare (xargs :mode :program))
   (if (or (zp x) (zp y))
       (list x y)
     (foo (1+ x) (1- y))))
 (local (defun foo (x y)
          (declare (xargs :measure (acl2-count y)))
          (if (or (zp x) (zp y))
              (list x y)
            (foo (1+ x) (1- y)))))
 (verify-termination foo))
(defthm bad-lemma
  (zp x)
  :hints (("Goal" :induct (foo x 1)))
  :rule-classes nil)
(defthm contradiction nil
  :hints (("Goal" :use ((:instance bad-lemma (x -1)))))
  :rule-classes nil)
(quit)
