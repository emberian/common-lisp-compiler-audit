(in-package "ACL2")
; Isolated defun-inline sibling of NOTE-8-7.
(defstobj st (fld))
(defstobj st1 (fld1) :congruent-to st)
(defun-inline st-init-inline (st)
  (declare (xargs :stobjs (st)))
  (with-local-stobj st1
    (mv-let (st1 st) (swap-stobjs st1 st) st)))
(thm (equal (st-init-inline '(1)) '(nil))
     :hints (("Goal" :in-theory (disable (:e st-init-inline)))))
(thm (not (equal (st-init-inline '(1)) '(nil))))
(quit)
