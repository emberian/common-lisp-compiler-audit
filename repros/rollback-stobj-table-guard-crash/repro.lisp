;; WRB-R1: Guard-verified stobj-table boundp / remove raw Lisp crash after
;; rolling back the key stobj (or on any non-stobj / non-symbol key).
;;
;; Root cause:
;;   other-events.lisp:20675-20685 defines common-guard for tbl-boundp / tbl-remove
;;   as ONLY `(,recog ,stobj-name) with `:verify-guards t`, omitting both `(symbolp k)`
;;   and stobj-ness of `k`. Yet raw tbl-boundp / tbl-remove (basis-a.lisp:8821)
;;   unconditionally calls `(current-stobj-gensym k)` (basis-a.lisp:8620-8639),
;;   which invokes raw `(error "Attempted to access a stobj-table entry for ~s,
;;   which is not currently the name of a stobj." st)` once `k` is rolled back!
(in-package "ACL2")

(defstobj parent (tbl :type (stobj-table)))

(encapsulate ()
  (local (defstobj kid fld))
  (defun check-kid-verified (parent)
    (declare (xargs :stobjs parent :verify-guards t))
    (tbl-boundp 'kid parent))
  (local
   (make-event
    (mv-let (erp val state)
      (trans-eval '(check-kid-verified parent) 'inside-encap state t)
      (prog2$
       (cw "@WRB-R1-BEFORE-ROLLBACK erp=~x0 val=~x1~%" erp val)
       (value '(value-triple :ok)))))))

;; KID has now been rolled back by encapsulate pass-2, while guard-verified
;; CHECK-KID-VERIFIED remains admitted in the world with :ttags nil.
;; Calling (check-kid-verified parent) now aborts in raw Common Lisp!
(check-kid-verified parent)
(quit)
