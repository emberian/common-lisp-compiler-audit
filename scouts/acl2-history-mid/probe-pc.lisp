(in-package "ACL2")
(program)
(set-state-ok t)

(cw "~%=== H52 USER-DEFINED PROOF-BUILDER PRIMITIVE ORIGINAL ===~%")
(define-pc-primitive foo52 (&rest rest-args)
  (declare (ignore rest-args))
  (mv (change-pc-state pc-state :goals (cdr goals)) state))

(cw "~%=== H53 MAKE-EVENT-GENERATED PROOF-BUILDER PRIMITIVE ===~%")
(make-event
 '(define-pc-primitive bar53 (&rest rest-args)
    (declare (ignore rest-args))
    (mv (change-pc-state pc-state :goals (cdr goals)) state)))

(logic)
(defthm bug52 nil :instructions (:foo52) :rule-classes nil)
(defthm bug53 nil :instructions (:bar53) :rule-classes nil)

(quit)
