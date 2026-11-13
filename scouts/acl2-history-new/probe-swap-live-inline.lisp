(in-package "ACL2")
; NOTE-8-7 original live-stobj swap exploit and defun-inline sibling.
(defstobj st (fld))
(defstobj st1 (fld1) :congruent-to st)
(defun st-init (st)
  (declare (xargs :stobjs (st)))
  (with-local-stobj st1
    (mv-let (st1 st) (swap-stobjs st1 st) st)))
(thm (not (equal (st-init '(1)) '(nil))))
(thm (equal (st-init '(1)) '(nil))
     :hints (("Goal" :in-theory (disable (:e st-init)))))

(defun-inline st-init-inline (st)
  (declare (xargs :stobjs (st)))
  (with-local-stobj st1
    (mv-let (st1 st) (swap-stobjs st1 st) st)))
(thm (not (equal (st-init-inline '(1)) '(nil))))
(thm (equal (st-init-inline '(1)) '(nil))
     :hints (("Goal" :in-theory (disable (:e st-init-inline)))))
(quit)
