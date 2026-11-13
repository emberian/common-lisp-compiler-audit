(in-package "ACL2")

; CHANNEL: exported termination theorem (:termination-theorem / 'justification).
; CHECK: bogus-exported-measures (other-events.lisp ~6156-6184) inspects ONLY the
; justification's :measure, :mp and :rel for signature-function ancestors.  Unlike
; bogus-exported-compliants it never looks at the function body / the governing
; tests (rulers).  A signature function g that appears only in a ruler of a
; recursive call leaks its LOCAL property into the exported termination theorem:
; in pass 1 the local witness makes the recursive call unreachable (so the
; non-decreasing measure is fine), but the exported constraint on g says nothing.

(encapsulate (((g *) => *))
  (local (defun g (x) (declare (ignore x)) nil))   ; local witness: g is always nil
  (defun f (x)
    (declare (xargs :measure (acl2-count x)))
    (if (g x)        ; ruler mentions g; measure (acl2-count x) is NOT in g's scope
        (f x)        ; non-decreasing self-call, reachable only when (g x) is non-nil
      x)))

; What leaked: f has a 'justification, and its termination theorem mentions g.
(value-triple
 (list :f-justification (and (getpropc 'f 'justification nil (w state)) t)
       :g-constraint (getpropc 'g 'constraint-lst-etc :none (w state))
       :termination-theorem (termination-theorem 'f (w state))))

; g has no exported constraint, so functionally instantiating g := (lambda (x) t)
; turns the termination theorem into (o< (acl2-count x) (acl2-count x)), refuted by
; o<-irreflexivity -> NIL.
(defthm nil-proved nil
  :rule-classes nil
  :hints
  (("Goal"
    :use (:functional-instance
          (:termination-theorem f)
          (g (lambda (x) t))))))

(assert-event
 (and (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))
      (null (ttag (w state)))))

(value-triple
 (list :nil-proved-installed (getpropc 'nil-proved 'theorem :missing (w state))
       :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
       :ttag (ttag (w state))))
(quit)
