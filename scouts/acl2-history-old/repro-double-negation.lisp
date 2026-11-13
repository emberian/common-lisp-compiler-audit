; NOTE-2-8 tautology checker controls.  The EQUAL formula is actually false
; for generalized Boolean Q (e.g. Q=5), so rejecting it is the desired control.
(defthm double-negation-equal-rejected
  (equal (and p q) (not (or (not p) (not q))))
  :rule-classes nil)
(defthm double-negation-negated-also-rejected
  (not (equal (and p q) (not (or (not p) (not q)))))
  :rule-classes nil)
; The valid Boolean-equivalence statement is the positive control.
(defthm double-negation-iff
  (iff (and p q) (not (or (not p) (not q))))
  :rule-classes nil)
(quit)
