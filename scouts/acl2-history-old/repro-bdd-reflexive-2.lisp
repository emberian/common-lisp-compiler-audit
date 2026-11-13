; Reach the BDD proof with Boolean hypotheses; the trivial reflexive rule is
; separately rejected by add-rewrite-rule before commutative-p1 could use it.
(defun f (x y) (and x (not y)))
(defthm f-reflexive (equal (f x x) (f x x)) :rule-classes nil)
(defthm bdd-commutativity-bad
  (implies (and (booleanp a) (booleanp b))
           (equal (f a b) (f b a)))
  :hints (("Goal" :bdd (:vars (a b))))
  :rule-classes nil)
(defthm contradiction nil
  :hints (("Goal" :use ((:instance bdd-commutativity-bad (a t) (b nil)))))
  :rule-classes nil)
(quit)
