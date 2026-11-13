(in-package "ACL2")
; NOTE-8-1 original implicit functional instantiation of O<'s termination theorem.
(defun bad (x y)
  (declare (xargs :measure (acl2-count x)
                  :hints (("Goal" :use (:termination-theorem o<)))))
  (if (or (o-finp x)
          (o-finp y)
          (equal (o-first-expt x) (o-first-expt y)))
      nil
    (if (bad (acl2-count (o-first-expt x)) (acl2-count x))
        nil
      (+ 1 (bad x y)))))
(defthm bad-1-4 (not (bad 1 4)))
(in-theory (disable bad (:e bad)))
(defthmd bad-lemma
  (equal (bad '((1 . 1)) '((2 . 2)))
         (+ 1 (bad '((1 . 1)) '((2 . 2)))))
  :instructions ((:dv 1) :x :top :s))
(defthm bad-thm nil :rule-classes nil
  :hints (("Goal" :use (:instance bad-lemma))))
(quit)
