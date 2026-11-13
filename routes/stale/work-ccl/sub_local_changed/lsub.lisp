(in-package "ACL2")
(defthm lsub-lemma (equal (car (cons x y)) x) :rule-classes nil)
(defthm lsub-lemma-2 (equal (cdr (cons x y)) y) :rule-classes nil)
