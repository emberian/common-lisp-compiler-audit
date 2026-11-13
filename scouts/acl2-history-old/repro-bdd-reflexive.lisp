; NOTE-2-7 BDD commutative-p1: a reflexive rule is not commutativity.
(defun f (x y) (and x (not y)))
(defthm f-reflexive (equal (f x x) (f x x)))
(defthm bdd-commutativity-bad
  (equal (f a b) (f b a))
  :hints (("Goal" :bdd (:vars (a b))))
  :rule-classes nil)
(defthm contradiction nil
  :hints (("Goal" :use ((:instance bdd-commutativity-bad (a t) (b nil)))))
  :rule-classes nil)
(quit)
