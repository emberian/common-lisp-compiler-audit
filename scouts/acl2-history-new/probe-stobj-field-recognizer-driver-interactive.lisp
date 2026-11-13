(in-package "ACL2")
; Run interactively so an expected failed theorem does not stop later variants.
(include-book "probe-stobj-field-recognizer/sub")
(defthm thm1 (hi-fldp '(nil)) :rule-classes nil
  :hints (("Goal" :in-theory (disable (:e hi-fldp)))))
(defthm thm2 (not (hi-fldp '(nil))) :rule-classes nil)
(defthm nil-proved nil :rule-classes nil
  :hints (("Goal" :use (thm1 thm2))))
(defthm thm1-congruent (hi2-fldp '(nil)) :rule-classes nil
  :hints (("Goal" :in-theory (disable (:e hi2-fldp)))))
(defthm thm2-congruent (not (hi2-fldp '(nil))) :rule-classes nil)
(defthm nil-proved-congruent nil :rule-classes nil
  :hints (("Goal" :use (thm1-congruent thm2-congruent))))
(quit)
