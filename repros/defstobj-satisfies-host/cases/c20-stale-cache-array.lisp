; CCL-hosted ACL2 returns a wrong value from a stobj array read after the
; SATISFIES predicate in the element type was undone and redefined, and
; proves NIL from it.  SBCL-hosted ACL2 returns NIL from (g) and the second
; theorem fails there.
(defun p (x) (declare (xargs :guard t)) (integerp x))
(defstobj st1
  (ar1 :type (array (and (or null (integer 0 1)) (satisfies p)) (4))
       :initially 0))
(ubt! 'p)
(defun p (x) (declare (xargs :guard t)) (or (null x) (integerp x)))
(defstobj st2
  (ar2 :type (array (and (or null (integer 0 1)) (satisfies p)) (4))
       :initially 0))
(defun g ()
  (declare (xargs :guard t))
  (with-local-stobj st2
    (mv-let (v st2)
      (let ((st2 (update-ar2i 0 nil st2)))
        (mv (ar2i 0 st2) st2))
      v)))
(cw "RESULT g = ~x0~%" (g))
(defthm g-is-nil (equal (g) nil)
  :hints (("Goal" :in-theory (disable (:e g)))))
(defthm g-is-not-nil (not (equal (g) nil))
  :hints (("Goal" :in-theory '((:e g) (:e equal) (:e not)))))
(defthm contradiction nil
  :rule-classes nil
  :hints (("Goal" :use (g-is-nil g-is-not-nil)
           :in-theory nil)))
