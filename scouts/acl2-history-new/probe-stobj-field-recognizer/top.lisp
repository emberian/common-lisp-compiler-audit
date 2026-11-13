(in-package "ACL2")
(include-book "sub")
(defthm thm1 (hi-fldp '(nil)) :rule-classes nil
  :hints (("Goal" :in-theory (disable (:e hi-fldp)))))
(defthm thm2 (not (hi-fldp '(nil))) :rule-classes nil)
(thm nil :hints (("Goal" :use (thm1 thm2))))
; Congruent field-type sibling.
(defthm thm1-congruent (hi2-fldp '(nil)) :rule-classes nil
  :hints (("Goal" :in-theory (disable (:e hi2-fldp)))))
(defthm thm2-congruent (not (hi2-fldp '(nil))) :rule-classes nil)
(thm nil :hints (("Goal" :use (thm1-congruent thm2-congruent))))
