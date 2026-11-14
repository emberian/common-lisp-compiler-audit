(in-package "ACL2")

(defstobj st (fld :type integer :initially 0))

(encapsulate
  (((my-st-fn * st) => st
    :formals (x st)
    :guard (and (integerp x) (stp st))))
  (local (defun my-st-fn (x st)
           (declare (xargs :stobjs st :guard (integerp x)))
           (update-fld x st))))

(defun my-st-impl (x st)
  (declare (xargs :stobjs st :guard (integerp x)))
  (update-fld x st))

(defattach my-st-fn my-st-impl)

(defun corrupt (st)
  (declare (xargs :mode :program :stobjs st))
  (my-st-fn 'not-an-integer st))

(value-triple (list :fn-risk (getpropc 'my-st-fn 'invariant-risk nil (w state))
                    :impl-risk (getpropc 'my-st-impl 'invariant-risk nil (w state))
                    :corrupt-risk (getpropc 'corrupt 'invariant-risk nil (w state))))

(defevaluator my-ev my-ev-lst ((if x y z)))

(defun my-cp (clause hint st)
  (declare (xargs :stobjs st :guard t) (ignore hint))
  (if (or (not (stp st)) (integerp (fld st)))
      (mv nil (list clause))
    (mv nil nil)))

(defthm my-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (my-ev (conjoin-clauses (clauses-result (my-cp clause hint st))) a))
           (my-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(corrupt st)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause nil st)))
  :rule-classes nil)

(value-triple
 (list :theorem (getpropc 'nil-proved 'theorem nil (w state))
       :ttag (ttag (w state))
       :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
       :redef-seen (global-val 'redef-seen (w state))))
