(in-package "ACL2")

(cw "~%=== H50 CONDITIONAL DEFINITION RULE IN EXPAND HINT ===~%")
(defun f50 (x) x)
(defthm f50-cond
  (implies (equal x 0) (equal (f50 x) 0))
  :rule-classes :definition)
(defthm bad50
  (equal (f50 1) 0)
  :hints (("Goal" :expand ((:with f50-cond (f50 1)))))
  :rule-classes nil)
(defthm good50
  (equal (f50 0) 0)
  :hints (("Goal" :expand ((:with f50-cond (f50 0)))))
  :rule-classes nil)

(cw "~%=== H51 CONDITIONAL DEFINITION RULE FOR DEFUN-INLINE ===~%")
(defun-inline f51 (x) x)
(defthm f51-cond
  (implies (equal x 0) (equal (f51 x) 0))
  :rule-classes :definition)
(defthm bad51
  (equal (f51 1) 0)
  :hints (("Goal" :expand ((:with f51-cond (f51 1)))))
  :rule-classes nil)
(defthm good51
  (equal (f51 0) 0)
  :hints (("Goal" :expand ((:with f51-cond (f51 0)))))
  :rule-classes nil)

(cw "~%=== H50B OPEN CONDITIONAL EXPANSION ===~%")
(defthm bad50-open
  (implies (equal x 1) (equal (f50 x) 0))
  :hints (("Goal" :expand ((:with f50-cond (f50 x)))))
  :rule-classes nil)
(defthm good50-open
  (implies (equal x 0) (equal (f50 x) 0))
  :hints (("Goal" :expand ((:with f50-cond (f50 x)))))
  :rule-classes nil)
(defthm bad51-open
  (implies (equal x 1) (equal (f51 x) 0))
  :hints (("Goal" :expand ((:with f51-cond (f51 x)))))
  :rule-classes nil)
(defthm good51-open
  (implies (equal x 0) (equal (f51 x) 0))
  :hints (("Goal" :expand ((:with f51-cond (f51 x)))))
  :rule-classes nil)

(quit)
