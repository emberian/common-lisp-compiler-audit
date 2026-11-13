; CCL-hosted ACL2 proves NIL; SBCL-hosted ACL2 rejects the second theorem.
; No undo, no trust tag, no raw Lisp, no redefinition: P is first defined
; locally inside an encapsulate (where a type declaration naming it gets
; compiled), then defined differently at the top level.
(encapsulate ()
  (local (defun p (x) (declare (xargs :guard t)) (integerp x)))
  (local (defun f1 (x)
           (declare (type (and (or null (integer 0 1)) (satisfies p)) x))
           x)))
(defun p (x) (declare (xargs :guard t)) (or (null x) (integerp x)))
(defstobj st
  (ar :type (array (and (or null (integer 0 1)) (satisfies p)) (4))
      :initially 1)
  (other :initially 7))
(defun g ()
  (declare (xargs :guard t))
  (with-local-stobj st
    (mv-let (v st)
      (mv (equal (ari 0 st) 1) st)
      v)))
(cw "RESULT (g) = ~x0~%" (g))
(defthm g-is-t (equal (g) t)
  :hints (("Goal" :in-theory (disable (:e g)))))
(defthm g-is-nil (equal (g) nil)
  :hints (("Goal" :in-theory '((:e g)))))
(defthm contradiction nil
  :rule-classes nil
  :hints (("Goal" :use (g-is-t g-is-nil) :in-theory nil)))
(cw "RESULT end of script~%")
