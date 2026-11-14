(in-package "ACL2")

(defstobj parent (tbl :type (stobj-table)))

;; Route A: Rollback route — KID is a genuine stobj during admission of
;; CHECK-KID, then KID is rolled back via local encapsulate (or :u).
;; In a fresh session or logically, (tbl-boundp 'kid parent) is NIL, and
;; (:verify-guards nil) returns NIL; guard-verified execution aborts in raw Lisp!
(encapsulate ()
  (local (defstobj kid fld))
  (defun check-kid-unverified (parent)
    (declare (xargs :stobjs parent :verify-guards nil))
    (tbl-boundp 'kid parent))
  (defun check-kid-verified (parent)
    (declare (xargs :stobjs parent :verify-guards t))
    (tbl-boundp 'kid parent)))

(make-event
 (mv-let (erp val state)
   (trans-eval '(check-kid-unverified parent) 'unverified state t)
   (prog2$
    (cw "~%@R UNVERIFIED-AFTER-ROLLBACK erp=~x0 val=~x1~%" erp val)
    (value '(value-triple :ok)))))

;; Calling the 100% guard-verified function CHECK-KID-VERIFIED on live PARENT
;; triggers raw CL:ERROR inside CURRENT-STOBJ-GENSYM!
(check-kid-verified parent)
