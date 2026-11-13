; NOTE-2-7 original normalized-body guard-verification exploit.
(defun bar (x) (zp x))
(defthm zp-false-on-negatives
  (implies (< x 0) (bar x))
  :rule-classes :type-prescription)
(defun foo (x)
  (declare (xargs :guard (rationalp x) :verify-guards nil))
  (if (< x 0)
      (if (bar x) 0 1)
    17))
(defthm foo-of-minus-3-is-0
  (equal (foo -3) 0)
  :rule-classes nil)
(verify-guards foo)
(defthm foo-of-minus-3-is-1
  (equal (foo -3) 1)
  :rule-classes nil)
(defthm bug
  nil
  :rule-classes nil
  :hints (("Goal" :use (foo-of-minus-3-is-0 foo-of-minus-3-is-1))))
(quit)
