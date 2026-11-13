(in-package "ACL2")
; NOTE-8-5 original non-trivial predicate guard.
(defstobj s (field :type (satisfies evenp) :initially 4))
(defthm bad nil :rule-classes nil
  :hints (("Goal" :use (:instance (:guard-theorem fieldp) (x t)))))
; Newer non-executable definition route, same violated invariant.
(defun-nx nx-evenp (x)
  (declare (xargs :guard (integerp x)))
  (evenp x))
(defstobj s-nx (field-nx :type (or null (satisfies nx-evenp)) :initially nil))
(quit)
