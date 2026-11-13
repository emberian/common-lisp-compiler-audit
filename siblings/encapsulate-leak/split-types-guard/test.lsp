(in-package "ACL2")

; CHANNEL: exported guard theorem.  CHECK: bogus-exported-compliants
; (other-events.lisp ~6105-6154) inspects (guard f) and the body's ancestors,
; but NOT the 'split-types-term property, which guard-clauses-for-fn1
; (history-management.lisp ~14266-14286) conjoins into the guard obligation.
; So a (satisfies g) split type on a signature function g leaks "(g x)" into
; f's EXPORTED :guard-theorem while g has no exported constraint.

(encapsulate (((g *) => *))
  (local (defun g (x)
           (declare (xargs :guard t :verify-guards t))
           (declare (ignore x))
           t))
  (defun f (x)
    (declare (type (satisfies g) x)
             (xargs :guard t :split-types t))
    x))

; The leaked obligation: f is common-lisp-compliant and its guard theorem is (g x).
(value-triple
 (list :f-symbol-class (symbol-class 'f (w state))
       :guard-of-f (guard 'f nil (w state))
       :split-types-term (getpropc 'f 'split-types-term :none (w state))
       :g-constraint (getpropc 'g 'constraint-lst-etc :none (w state))
       :guard-theorem (guard-theorem 'f nil nil (w state) state)))

; Functionally instantiate the leaked guard theorem (g x) with g := (lambda (x) nil).
; g has no exported constraint, so there are no functional-instantiation obligations.
(defthm nil-proved nil
  :rule-classes nil
  :hints
  (("Goal"
    :use (:functional-instance
          (:guard-theorem f)
          (g (lambda (x) nil))))))

; Decisive markers: a real theorem NIL is installed, with no skip-proofs, no
; redefinition, and no trust tag.
(assert-event
 (and (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))
      (null (ttag (w state)))))

(value-triple
 (list :nil-proved-installed (getpropc 'nil-proved 'theorem :missing (w state))
       :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
       :ttag (ttag (w state))))
(quit)
